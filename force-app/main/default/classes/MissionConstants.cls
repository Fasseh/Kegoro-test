/**
 * Valeurs de la picklist Account.MissionStatus__c.
 * Centralisées ici pour éviter les chaînes écrites en dur dans le code et les fautes de frappe.
 */
public with sharing class MissionConstants {
    public static final String STATUS_ACTIVE = 'active';
    public static final String STATUS_CANCELED = 'canceled';

    // Classe utilitaire : elle ne doit jamais être instanciée.
    private MissionConstants() {}
}
