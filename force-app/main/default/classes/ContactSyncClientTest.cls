/** Tests du client HTTP seul (découpage en lots, Named Credential, gestion des erreurs). */
@IsTest
private class ContactSyncClientTest {

    /** Fabrique "count" statuts fictifs, avec des Id de 15 caractères comme les vrais. */
    private static List<ContactSyncClient.ContactStatus> buildStatuses(Integer count) {
        List<ContactSyncClient.ContactStatus> statuses = new List<ContactSyncClient.ContactStatus>();
        for (Integer i = 0; i < count; i++) {
            statuses.add(new ContactSyncClient.ContactStatus(String.valueOf(i).leftPad(15, '0'), false));
        }
        return statuses;
    }

    // Au-delà de la taille de lot, l'envoi est découpé en plusieurs appels.
    @IsTest
    static void largePayload_isSplitInChunks() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200, 1000));

        ContactSyncClient.sync(buildStatuses(2500));

        Assert.areEqual(3, ContactSyncMock.callCount, '2500 contacts / 1000 par lot = 3 appels');
        Assert.areEqual('PATCH', ContactSyncMock.lastMethod);
    }

    // L'URL et le token viennent du Named Credential : le code n'envoie pas d'Authorization lui-même.
    @IsTest
    static void callout_usesNamedCredential_andNoSecretInCode() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        ContactSyncClient.sync(buildStatuses(1));

        Assert.areEqual('callout:ContactSyncApi', ContactSyncMock.lastEndpoint);
        Assert.isNull(ContactSyncMock.lastAuth,
            'Le header Authorization est ajouté par le Named Credential, pas par le code');
    }

    // Rien à synchroniser : aucun appel inutile (l'API renverrait une erreur).
    @IsTest
    static void emptyPayload_doesNotCallApi() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        ContactSyncClient.sync(new List<ContactSyncClient.ContactStatus>());

        Assert.areEqual(0, ContactSyncMock.callCount);
    }

    // Tout code différent de 200 doit remonter une erreur claire, contenant le code reçu.
    @IsTest
    static void apiError_throwsSyncException() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(400));

        try {
            ContactSyncClient.sync(buildStatuses(1));
            Assert.fail('Une SyncException était attendue');
        } catch (ContactSyncClient.SyncException e) {
            Assert.isTrue(e.getMessage().contains('400'));
        }
    }

    // Une taille de lot de 0 provoquerait une boucle infinie : la configuration est validée avant.
    @IsTest
    static void invalidChunkSize_throwsSyncException() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200, 0));

        try {
            ContactSyncClient.sync(buildStatuses(1));
            Assert.fail('Une SyncException était attendue');
        } catch (ContactSyncClient.SyncException e) {
            Assert.isTrue(e.getMessage().contains('ChunkSize__c'));
        }
    }
}