@IsTest
public class ContactSyncMock implements HttpCalloutMock {
    public static Integer callCount = 0;
    public static String lastMethod;
    public static String lastEndpoint;
    public static String lastAuth;
    public static List<Object> lastPayload;

    private final Integer statusCode;

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
