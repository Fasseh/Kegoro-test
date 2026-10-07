/**
 * Envoie les statuts des contacts à l'API de façon asynchrone.
 *
 * Pourquoi asynchrone : un callout est impossible après un DML dans la transaction du trigger,
 * et l'enregistrement du compte ne doit pas dépendre de la lenteur de l'API.
 * Database.AllowsCallouts : indispensable pour qu'un Queueable puisse appeler une API externe.
 *
 * Bulkification : Salesforce limite à 100 callouts par transaction. Un job envoie au plus
 * MAX_CALLOUTS_PER_JOB appels, puis se ré-enfile pour le reste des contacts (chaînage).
 *
 * Fiabilité : si l'API échoue, le job est relancé (MAX_ATTEMPTS fois, avec une minute d'attente).
 * Chaque issue est tracée dans ContactSyncLog__c (méthode log).
 * Relancer un envoi est sans danger : l'API fixe un statut, elle ne l'incrémente pas.
 */
public with sharing class ContactSyncQueueable implements Queueable, Database.AllowsCallouts {

    // Limite Salesforce : 100 callouts par transaction. On garde une marge de sécurité.
    @TestVisible private static final Integer MAX_CALLOUTS_PER_JOB = 90;
    // Nombre total d'essais avant de déclarer l'échec définitif.
    @TestVisible private static final Integer MAX_ATTEMPTS = 3;
    // Attente avant une nouvelle tentative, pour laisser l'API se rétablir.
    private static final Integer RETRY_DELAY_MINUTES = 1;

    // Valeurs de ContactSyncLog__c.Status__c.
    @TestVisible private static final String SUCCESS = 'SUCCESS';
    // Échec, mais une nouvelle tentative est planifiée.
    @TestVisible private static final String RETRY = 'RETRY';
    // Échec définitif : toutes les tentatives sont épuisées, une intervention est nécessaire.
    @TestVisible private static final String FAILED = 'FAILED';

    // On ne garde que ce que l'API attend (Id + statut), pas les contacts entiers.
    private final List<ContactSyncClient.ContactStatus> statuses;
    // Numéro de la tentative en cours (1 = premier essai).
    private final Integer attempt;

    /** Constructeur public : premier essai pour des contacts qui viennent d'être modifiés. */
    public ContactSyncQueueable(List<Contact> contacts) {
        this(toStatuses(contacts), 1);
    }

    /** Constructeur interne : utilisé pour le chaînage (suite) et pour les nouvelles tentatives. */
    private ContactSyncQueueable(List<ContactSyncClient.ContactStatus> statuses, Integer attempt) {
        this.statuses = statuses;
        this.attempt = attempt;
    }

    public void execute(QueueableContext ctx) {
        // Le finalizer est attaché avant l'appel : il s'exécute même si l'appel plante.
        System.attachFinalizer(new SyncFinalizer(statuses, attempt));

        List<ContactSyncClient.ContactStatus> remaining = sendWithinLimits(statuses);
        // Les callouts sont terminés : on peut maintenant écrire en base (DML après callout autorisé).
        log(SUCCESS, statuses.size() - remaining.size(), attempt, null);

        // Il reste des contacts : un nouveau job prend la suite (nouvelle transaction, nouveaux quotas).
        if (!remaining.isEmpty()) {
            System.enqueueJob(new ContactSyncQueueable(remaining, 1));
        }
    }

    /**
     * Envoie le plus possible sans dépasser la limite de callouts.
     * @return les statuts qui n'ont pas pu être envoyés (liste vide si tout est parti)
     */
    @TestVisible
    private static List<ContactSyncClient.ContactStatus> sendWithinLimits(
        List<ContactSyncClient.ContactStatus> statuses
    ) {
        Integer sent = ContactSyncClient.sync(statuses, MAX_CALLOUTS_PER_JOB);
        List<ContactSyncClient.ContactStatus> remaining = new List<ContactSyncClient.ContactStatus>();
        for (Integer i = sent; i < statuses.size(); i++) {
            remaining.add(statuses[i]);
        }
        return remaining;
    }

    /**
     * Enregistre une ligne dans ContactSyncLog__c, consultable dans Salesforce (contrairement à
     * System.debug, la trace est conservée).
     * Database.insert(..., false) : un problème d'écriture du log ne doit jamais faire
     * échouer ou masquer la synchronisation elle-même.
     */
    @TestVisible
    private static void log(String status, Integer contactCount, Integer attempt, String errorMessage) {
        Database.insert(new ContactSyncLog__c(
            Status__c = status,
            ContactCount__c = contactCount,
            Attempt__c = attempt,
            // Le champ est limité à 5000 caractères.
            ErrorMessage__c = errorMessage == null ? null : errorMessage.abbreviate(5000)
        ), false);
    }

    private static List<ContactSyncClient.ContactStatus> toStatuses(List<Contact> contacts) {
        List<ContactSyncClient.ContactStatus> result = new List<ContactSyncClient.ContactStatus>();
        for (Contact c : contacts) {
            result.add(new ContactSyncClient.ContactStatus(c.Id, c.IsActive__c));
        }
        return result;
    }

    /**
     * Exécuté après le job, même en cas d'exception non gérée (API en erreur, timeout...).
     * C'est ici qu'on trace l'échec et qu'on planifie la nouvelle tentative : dans le job lui-même,
     * l'exception annulerait l'écriture du log.
     */
    private class SyncFinalizer implements Finalizer {
        private final List<ContactSyncClient.ContactStatus> statuses;
        private final Integer attempt;

        SyncFinalizer(List<ContactSyncClient.ContactStatus> statuses, Integer attempt) {
            this.statuses = statuses;
            this.attempt = attempt;
        }

        public void execute(FinalizerContext ctx) {
            if (ctx.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
                return; // Succès : déjà tracé par le job.
            }
            String error = ctx.getException().getMessage();

            if (attempt < MAX_ATTEMPTS) {
                log(RETRY, statuses.size(), attempt, error);
                // Nouvelle tentative avec les mêmes contacts, après une minute d'attente.
                AsyncOptions options = new AsyncOptions();
                options.MinimumQueueableDelayInMinutes = RETRY_DELAY_MINUTES;
                System.enqueueJob(new ContactSyncQueueable(statuses, attempt + 1), options);
            } else {
                log(FAILED, statuses.size(), attempt, error);
            }
        }
    }
}
