/**
 * Orchestre la réaction à l'annulation d'une mission (Account.MissionStatus__c -> 'canceled').
 * Chaque méthode reçoit des listes pour traiter jusqu'à 200 comptes en une seule exécution.
 */
public with sharing class AccountTriggerHandler {

    /**
     * a) Renseigne la date d'annulation.
     * Appelé en "before update" : on modifie directement les comptes en mémoire,
     * Salesforce les enregistre ensuite, donc aucun DML n'est nécessaire.
     */
    public static void beforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        for (Account acc : getNewlyCanceled(newAccounts, oldMap)) {
            acc.MissionCanceledDate__c = Date.today();
        }
    }

    /**
     * b) Désactive les contacts concernés, puis c) lance leur synchronisation avec l'API.
     * Appelé en "after update" : les comptes sont enregistrés, on peut modifier les contacts.
     */
    public static void afterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        // Map construite depuis la liste : on obtient les Id des comptes sans boucle supplémentaire.
        Map<Id, Account> canceledAccounts = new Map<Id, Account>(getNewlyCanceled(newAccounts, oldMap));
        if (canceledAccounts.isEmpty()) {
            return;
        }

        // Une seule requête et un seul DML pour tous les comptes du lot (pas de SOQL/DML en boucle).
        List<Contact> deactivated =
            ContactStatusService.deactivateContactsWithoutActiveMission(canceledAccounts.keySet());

        // Le callout est fait en asynchrone : Salesforce interdit un callout juste après un DML
        // dans la même transaction. On n'envoie que les contacts réellement modifiés.
        if (!deactivated.isEmpty()) {
            System.enqueueJob(new ContactSyncQueueable(deactivated));
        }
    }

    /**
     * Retourne les comptes qui PASSENT à "canceled" lors de cette mise à jour.
     * On compare l'ancienne et la nouvelle valeur : un compte déjà annulé qui est simplement
     * modifié (ex : renommé) est ignoré, sa date d'annulation n'est donc pas réécrite.
     */
    private static List<Account> getNewlyCanceled(List<Account> newAccounts, Map<Id, Account> oldMap) {
        List<Account> result = new List<Account>();
        for (Account acc : newAccounts) {
            Account oldAcc = oldMap.get(acc.Id);
            if (acc.MissionStatus__c == MissionConstants.STATUS_CANCELED
                && oldAcc.MissionStatus__c != MissionConstants.STATUS_CANCELED) {
                result.add(acc);
            }
        }
        return result;
    }
}
