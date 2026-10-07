/**
 * Client HTTP : ne connaît que l'API.
 * URL et secret : Named Credential. Lots et timeout : ApiConfig__mdt.
 */
public with sharing class ContactSyncClient {

    public class SyncException extends Exception {}

    public class ContactStatus {
        public String id;
        public Boolean is_active;
        public ContactStatus(String id, Boolean isActive) {
            this.id = id;
            this.is_active = isActive;
        }
    }

    // Référence au Named Credential : ni URL ni token dans le code.
    private static final String NAMED_CREDENTIAL = 'callout:ContactSyncApi';
    private static final String CONFIG_NAME = 'ContactSync';

    // Permet aux tests d'injecter une configuration sans dépendre des données de l'org.
    @TestVisible private static ApiConfig__mdt configOverride;

    /** Envoie les statuts par lots ; lève SyncException si l'API ne répond pas 200. */
    public static void sync(List<ContactStatus> statuses) {
        if (statuses.isEmpty()) {
            return;
        }
        ApiConfig__mdt config = getConfig();
        Integer chunkSize = Integer.valueOf(config.ChunkSize__c);

        for (Integer i = 0; i < statuses.size(); i += chunkSize) {
            List<ContactStatus> chunk = new List<ContactStatus>();
            Integer upperBound = Math.min(i + chunkSize, statuses.size());
            for (Integer j = i; j < upperBound; j++) {
                chunk.add(statuses[j]);
            }
            send(chunk, config);
        }
    }

    private static void send(List<ContactStatus> chunk, ApiConfig__mdt config) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        // Le header Authorization est ajouté par le Named Credential.
        req.setTimeout(Integer.valueOf(config.TimeoutMs__c));
        req.setBody(JSON.serialize(chunk));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new SyncException('API sync contacts : HTTP ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }

    private static ApiConfig__mdt getConfig() {
        ApiConfig__mdt config = configOverride != null
            ? configOverride
            : ApiConfig__mdt.getInstance(CONFIG_NAME);

        if (config == null) {
            throw new SyncException('Configuration introuvable : ApiConfig__mdt.' + CONFIG_NAME);
        }
        if (config.ChunkSize__c == null || config.ChunkSize__c < 1) {
            throw new SyncException('ChunkSize__c invalide dans ApiConfig__mdt.' + CONFIG_NAME);
        }
        if (config.TimeoutMs__c == null || config.TimeoutMs__c < 1) {
            throw new SyncException('TimeoutMs__c invalide dans ApiConfig__mdt.' + CONFIG_NAME);
        }
        return config;
    }
}