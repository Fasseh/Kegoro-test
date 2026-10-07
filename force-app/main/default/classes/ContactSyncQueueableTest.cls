/** Tests de la bulkification (limite de callouts) et de la traçabilité (ContactSyncLog__c). */
@IsTest
private class ContactSyncQueueableTest {

    private static List<ContactSyncClient.ContactStatus> buildStatuses(Integer count) {
        List<ContactSyncClient.ContactStatus> statuses = new List<ContactSyncClient.ContactStatus>();
        for (Integer i = 0; i < count; i++) {
            statuses.add(new ContactSyncClient.ContactStatus(String.valueOf(i).leftPad(15, '0'), false));
        }
        return statuses;
    }

    // Lots d'un seul contact : 120 contacts = 120 appels nécessaires, mais un job est limité à 90.
    // Les 30 restants sont rendus à l'appelant, qui les confie à un nouveau job.
    @IsTest
    static void sendWithinLimits_stopsAtMaxCallouts_andReturnsRemaining() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200, 1));

        List<ContactSyncClient.ContactStatus> remaining =
            ContactSyncQueueable.sendWithinLimits(buildStatuses(120));

        Assert.areEqual(ContactSyncQueueable.MAX_CALLOUTS_PER_JOB, ContactSyncMock.callCount);
        Assert.areEqual(120 - ContactSyncQueueable.MAX_CALLOUTS_PER_JOB, remaining.size());
        // Le reste commence exactement après le dernier contact envoyé : aucun doublon, aucun oubli.
        Assert.areEqual(
            String.valueOf(ContactSyncQueueable.MAX_CALLOUTS_PER_JOB).leftPad(15, '0'),
            remaining[0].id
        );
    }

    // Sous la limite : tout part dans le même job, rien à chaîner.
    @IsTest
    static void sendWithinLimits_underLimit_sendsEverything() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200, 1000));

        List<ContactSyncClient.ContactStatus> remaining =
            ContactSyncQueueable.sendWithinLimits(buildStatuses(2500));

        Assert.areEqual(3, ContactSyncMock.callCount);
        Assert.isTrue(remaining.isEmpty());
    }

    // Un job réussi laisse une trace SUCCESS avec le nombre de contacts envoyés.
    @IsTest
    static void successfulJob_writesSuccessLog() {
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));
        Account acc = new Account(Name = 'Test log');
        insert acc;
        Contact c = new Contact(LastName = 'Log', AccountId = acc.Id, IsActive__c = false);
        insert c;

        Test.startTest();
        System.enqueueJob(new ContactSyncQueueable(new List<Contact>{ c }));
        Test.stopTest();

        ContactSyncLog__c log = [SELECT Status__c, ContactCount__c, Attempt__c FROM ContactSyncLog__c];
        Assert.areEqual(ContactSyncQueueable.SUCCESS, log.Status__c);
        Assert.areEqual(1, log.ContactCount__c);
        Assert.areEqual(1, log.Attempt__c);
    }

    // La trace enregistre le statut, la tentative et le message d'erreur.
    @IsTest
    static void log_storesFailureDetails() {
        ContactSyncQueueable.log(ContactSyncQueueable.FAILED, 5, 3, 'API sync contacts : HTTP 401');

        ContactSyncLog__c log = [SELECT Status__c, ContactCount__c, Attempt__c, ErrorMessage__c FROM ContactSyncLog__c];
        Assert.areEqual(ContactSyncQueueable.FAILED, log.Status__c);
        Assert.areEqual(5, log.ContactCount__c);
        Assert.areEqual(3, log.Attempt__c);
        Assert.isTrue(log.ErrorMessage__c.contains('401'));
    }
}
