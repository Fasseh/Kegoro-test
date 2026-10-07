@IsTest
private class ContactSyncClientTest {

    private static List<ContactSyncClient.ContactStatus> buildStatuses(Integer count) {
        List<ContactSyncClient.ContactStatus> statuses = new List<ContactSyncClient.ContactStatus>();
        for (Integer i = 0; i < count; i++) {
            statuses.add(new ContactSyncClient.ContactStatus(String.valueOf(i).leftPad(15, '0'), false));
        }
        return statuses;
    }

    @IsTest
    static void largePayload_isSplitInChunks() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200, 1000));

        ContactSyncClient.sync(buildStatuses(2500));

        Assert.areEqual(3, ContactSyncMock.callCount, '2500 contacts / 1000 par lot = 3 appels');
        Assert.areEqual('PATCH', ContactSyncMock.lastMethod);
    }

    @IsTest
    static void callout_usesNamedCredential_andNoSecretInCode() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        ContactSyncClient.sync(buildStatuses(1));

        Assert.areEqual('callout:ContactSyncApi', ContactSyncMock.lastEndpoint);
        Assert.isNull(ContactSyncMock.lastAuth,
            'Le header Authorization est ajouté par le Named Credential, pas par le code');
    }

    @IsTest
    static void emptyPayload_doesNotCallApi() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        ContactSyncClient.sync(new List<ContactSyncClient.ContactStatus>());

        Assert.areEqual(0, ContactSyncMock.callCount);
    }

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