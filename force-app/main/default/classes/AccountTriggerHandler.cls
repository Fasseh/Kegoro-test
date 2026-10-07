public with sharing class AccountTriggerHandler {

    /** a) Date d'annulation : en before, aucun DML nécessaire. */
    public static void beforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        for (Account acc : getNewlyCanceled(newAccounts, oldMap)) {
            acc.MissionCanceledDate__c = Date.today();
        }
    }

    /** b) + c) Désactivation des contacts puis synchronisation asynchrone. */
    public static void afterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        Map<Id, Account> canceledAccounts = new Map<Id, Account>(getNewlyCanceled(newAccounts, oldMap));
        if (canceledAccounts.isEmpty()) {
            return;
        }

        List<Contact> deactivated =
            ContactStatusService.deactivateContactsWithoutActiveMission(canceledAccounts.keySet());

        if (!deactivated.isEmpty()) {
            System.enqueueJob(new ContactSyncQueueable(deactivated));
        }
    }

    /** Comptes qui PASSENT à "canceled" (ignore ceux déjà annulés). */
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