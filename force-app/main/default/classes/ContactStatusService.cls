/**
 * Règle métier : un contact dont l'entreprise passe en mission annulée devient inactif.
 * Contournement : l'org ne dispose pas de AccountContactRelation (voir README), donc seul
 * le compte principal (Contact.AccountId) est pris en compte, pas les comptes secondaires.
 * "without sharing" : règle d'intégrité exécutée par un trigger, elle ne doit pas
 * dépendre des droits de visibilité de l'utilisateur qui modifie le compte.
 */
public without sharing class ContactStatusService {

    /** Retourne uniquement les contacts effectivement passés à inactif. */
    public static List<Contact> deactivateContactsWithoutActiveMission(Set<Id> canceledAccountIds) {
        List<Contact> toDeactivate = new List<Contact>();
        for (Contact c : [
            SELECT Id, IsActive__c
            FROM Contact
            WHERE AccountId IN :canceledAccountIds
            AND IsActive__c = true
        ]) {
            c.IsActive__c = false;
            toDeactivate.add(c);
        }

        return updateAndKeepSucceeded(toDeactivate);
    }

    // DML partielle : une erreur sur un contact ne bloque pas les autres.
    private static List<Contact> updateAndKeepSucceeded(List<Contact> contacts) {
        List<Contact> succeeded = new List<Contact>();
        if (contacts.isEmpty()) {
            return succeeded;
        }
        List<Database.SaveResult> results = Database.update(contacts, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                succeeded.add(contacts[i]);
            } else {
                System.debug(LoggingLevel.ERROR,
                    'Échec mise à jour contact ' + contacts[i].Id + ' : ' + results[i].getErrors()[0].getMessage());
            }
        }
        return succeeded;
    }
}