/**
 * Règle métier : un contact dont l'entreprise passe en mission annulée devient inactif.
 *
 * LIMITATION : l'énoncé demande de désactiver un contact seulement si TOUTES ses entreprises
 * sont annulées (via AccountContactRelation). Cet objet n'existe pas dans l'org de développement
 * (voir README), donc seul le compte principal (Contact.AccountId) est pris en compte.
 * Un contact rattaché à plusieurs comptes n'est pas géré.
 *
 * "without sharing" : règle d'intégrité exécutée par un trigger, elle ne doit pas
 * dépendre des droits de visibilité de l'utilisateur qui modifie le compte.
 */
public without sharing class ContactStatusService {

    /**
     * Désactive les contacts actifs des comptes annulés.
     * @param canceledAccountIds Id des comptes qui viennent de passer à "canceled"
     * @return uniquement les contacts effectivement passés à inactif (ceux à synchroniser avec l'API)
     */
    public static List<Contact> deactivateContactsWithoutActiveMission(Set<Id> canceledAccountIds) {
        List<Contact> toDeactivate = new List<Contact>();
        // Une seule requête pour tous les comptes. On ignore les contacts déjà inactifs :
        // inutile de les mettre à jour ou de les renvoyer à l'API.
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

    /**
     * Met à jour les contacts en DML partielle : une erreur sur un contact ne bloque pas les autres.
     * Seuls les contacts réellement enregistrés sont retournés, pour ne synchroniser avec l'API
     * que des statuts qui existent vraiment dans Salesforce.
     */
    private static List<Contact> updateAndKeepSucceeded(List<Contact> contacts) {
        List<Contact> succeeded = new List<Contact>();
        if (contacts.isEmpty()) {
            return succeeded;
        }
        // allOrNone = false : on récupère un résultat par contact au lieu d'une exception globale.
        List<Database.SaveResult> results = Database.update(contacts, false);
        // results est dans le même ordre que contacts : on utilise l'index pour les associer.
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
