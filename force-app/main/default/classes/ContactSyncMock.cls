/**
 * Faux serveur HTTP pour les tests : Salesforce interdit les vrais callouts en test.
 * Il répond avec le code voulu et mémorise la dernière requête reçue (méthode, URL, header,
 * corps) dans des variables statiques que les tests peuvent vérifier.
 */
@IsTest
public class ContactSyncMock implements HttpCalloutMock {
    // Nombre d'appels reçus (remis à 0 à chaque création du mock).
    public static Integer callCount = 0;
    public static String lastMethod;
    public static String lastEndpoint;
    public static String lastAuth;
    public static List<Object> lastPayload;

    private final Integer statusCode;

    /** Mock avec la taille de lot par défaut (1000). */
    public ContactSyncMock(Integer statusCode) {
        this(statusCode, 1000);
    }

    /** Injecte aussi une configuration de test : aucune dépendance aux données de l'org. */
    public ContactSyncMock(Integer statusCode, Integer chunkSize) {
        this.statusCode = statusCode;
        callCount = 0;
        ContactSyncClient.configOverride = new ApiConfig__mdt(
            ChunkSize__c = chunkSize,
            TimeoutMs__c = 5000
        );
    }

    /** Appelée par Salesforce à la place de l'envoi réel de la requête. */
    public HttpResponse respond(HttpRequest req) {
        callCount++;
        lastMethod = req.getMethod();
        lastEndpoint = req.getEndpoint();
        lastAuth = req.getHeader('Authorization');
        lastPayload = (List<Object>) JSON.deserializeUntyped(req.getBody());

        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(statusCode == 200 ? 'OK' : 'Error');
        return res;
    }
}
