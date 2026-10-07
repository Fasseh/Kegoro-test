/**
 * Point d'entrée : aucune logique métier ici, tout est délégué à AccountTriggerHandler.
 *
 * - before update : on modifie les comptes en cours d'enregistrement (date d'annulation),
 *   ce qui ne demande aucun DML supplémentaire.
 * - after update  : les comptes sont enregistrés, on peut modifier d'autres objets (contacts)
 *   et lancer la synchronisation asynchrone.
 *
 * Les handlers reçoivent des listes : le trigger est bulkifié (200 comptes par lot Salesforce).
 */
trigger AccountTrigger on Account (before update, after update) {
    if (Trigger.isBefore) {
        AccountTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter) {
        AccountTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
