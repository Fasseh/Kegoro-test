/**
 * Client HTTP : ne connaît que l'API de synchronisation, rien du métier.
 * - URL et secret d'authentification : Named Credential "ContactSyncApi" (rien dans le code).
 * - Taille des lots et timeout : Custom Metadata ApiConfig__mdt (modifiables sans redéploiement).
 */
public with sharing class ContactSyncClient {

    /** Levée quand la configuration est invalide ou que l'API ne répond pas 200. */
    public class SyncException extends Exception {}

    /**
     * Un élément du payload JSON attendu par l'API : { "id": "...", "is_active": true|false }.
     * Les noms des attributs (id, is_active) sont ceux de l'API : ils sont sérialisés tels quels
     * par JSON.serialize, d'où le nom en snake_case.
     */
    public class ContactStatus {
        public String id;
        public Boolean is_active;
        public ContactStatus(String id, Boolean isActive) {
            this.id = id;
            this.is_active = isActive;
        }
    }

    // Référence au Named Credential : ni URL ni token dans le code.
    // Le header "Authorization" est ajouté automatiquement par Salesforce à partir de ce credential.
    private static final String NAMED_CREDENTIAL = 'callout:ContactSyncApi';
    // DeveloperName de l'enregistrement ApiConfig__mdt à utiliser.
    private static final String CONFIG_NAME = 'ContactSync';

    // Permet aux tests d'injecter une configuration sans dépendre des données de l'org.
    @TestVisible private static ApiConfig__mdt configOverride;

    /**
     * Envoie tous les statuts à l'API, par lots de ChunkSize__c éléments.
     * @throws SyncException si la configuration est invalide ou si l'API ne répond pas 200
     */
    public static void sync(List<ContactStatus> statuses) {
        sync(statuses, null);
    }

    /**
     * Envoie les statuts par lots, en s'arrêtant après maxCallouts appels (null = pas de limite).
     * Sert à respecter la limite de 100 callouts par transaction : l'appelant récupère le nombre
     * de statuts envoyés et traite le reste dans une autre transaction.
     * @return le nombre de statuts envoyés, en partant du début de la liste
     * @throws SyncException si la configuration est invalide ou si l'API ne répond pas 200
     */
    public static Integer sync(List<ContactStatus> statuses, Integer maxCallouts) {
        if (statuses.isEmpty()) {
            return 0;
        }
        ApiConfig__mdt config = getConfig();
        Integer chunkSize = Integer.valueOf(config.ChunkSize__c);

        Integer sent = 0;
        Integer callouts = 0;
        // Découpage en lots : i = début du lot, upperBound = fin (exclue) du lot.
        for (Integer i = 0; i < statuses.size(); i += chunkSize) {
            if (maxCallouts != null && callouts >= maxCallouts) {
                break; // Limite atteinte : le reste sera traité par l'appelant.
            }
            List<ContactStatus> chunk = new List<ContactStatus>();
            Integer upperBound = Math.min(i + chunkSize, statuses.size());
            for (Integer j = i; j < upperBound; j++) {
                chunk.add(statuses[j]);
            }
            send(chunk, config);
            callouts++;
            sent = upperBound;
        }
        return sent;
    }

    /** Un appel PATCH pour un lot. Lève SyncException si le code de retour n'est pas 200. */
    private static void send(List<ContactStatus> chunk, ApiConfig__mdt config) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        // Le header Authorization est ajouté par le Named Credential.
        req.setTimeout(Integer.valueOf(config.TimeoutMs__c));
        // Produit [ { "id": "...", "is_active": false }, ... ], le format attendu par l'API.
        req.setBody(JSON.serialize(chunk));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            // 400 = mauvais payload, 401 = token absent/invalide, 404 = mauvaise méthode.
            throw new SyncException('API sync contacts : HTTP ' + res.getStatusCode() + ' - ' + res.getBody());
        }
    }

    /**
     * Charge et valide la configuration. Valider ici évite une boucle infinie
     * (ChunkSize <= 0) ou un timeout invalide plus loin.
     */
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
