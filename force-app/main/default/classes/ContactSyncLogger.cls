/**
 * Trace chaque synchronisation avec l'API dans l'objet ContactSyncLog__c, consultable dans
 * Salesforce (onglet / rapport) : contrairement à System.debug, la trace est conservée et
 * visible sans ouvrir les logs Apex.
 */
public with sharing class ContactSyncLogger {

    public static final String SUCCESS = 'SUCCESS';
    // Échec, mais une nouvelle tentative est planifiée.
    public static final String RETRY = 'RETRY';
    // Échec définitif : toutes les tentatives sont épuisées, une intervention est nécessaire.
    public static final String FAILED = 'FAILED';

    /**
     * Enregistre une ligne de log.
     * Database.insert(..., false) : un problème d'écriture du log ne doit jamais faire
     * échouer ou masquer la synchronisation elle-même.
     */
    public static void log(String status, Integer contactCount, Integer attempt, String errorMessage) {
        Database.insert(new ContactSyncLog__c(
            Status__c = status,
            ContactCount__c = contactCount,
            Attempt__c = attempt,
            // Le champ est limité à 5000 caractères.
            ErrorMessage__c = errorMessage == null ? null : errorMessage.abbreviate(5000)
        ), false);
    }
}
