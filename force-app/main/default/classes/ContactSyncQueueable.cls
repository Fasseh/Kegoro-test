/**
 * Envoie les statuts des contacts à l'API de façon asynchrone.
 * Asynchrone car un callout est impossible après un DML dans la transaction du trigger,
 * et pour ne pas ralentir ni faire échouer l'enregistrement du compte si l'API est lente.
 * Database.AllowsCallouts : indispensable pour qu'un Queueable puisse appeler une API externe.
 */
public with sharing class ContactSyncQueueable implements Queueable, Database.AllowsCallouts {

    // On ne garde que ce que l'API attend (Id + statut), pas les contacts entiers.
    private final List<ContactSyncClient.ContactStatus> statuses = new List<ContactSyncClient.ContactStatus>();

    public ContactSyncQueueable(List<Contact> contacts) {
        for (Contact c : contacts) {
            statuses.add(new ContactSyncClient.ContactStatus(c.Id, c.IsActive__c));
        }
    }

    public void execute(QueueableContext ctx) {
        // Le finalizer est attaché avant l'appel : il sera exécuté même si l'appel plante.
        System.attachFinalizer(new SyncFinalizer(statuses.size()));
        ContactSyncClient.sync(statuses);
    }

    /**
     * Trace l'échec même si le job plante (API en erreur, timeout...).
     * Sans lui, l'exception resterait visible uniquement dans la liste des Apex Jobs.
     */
    private class SyncFinalizer implements Finalizer {
        private final Integer contactCount;

        SyncFinalizer(Integer contactCount) {
            this.contactCount = contactCount;
        }

        public void execute(FinalizerContext ctx) {
            if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
                System.debug(LoggingLevel.ERROR,
                    'Sync de ' + contactCount + ' contacts en échec : ' + ctx.getException().getMessage());
            }
        }
    }
}
