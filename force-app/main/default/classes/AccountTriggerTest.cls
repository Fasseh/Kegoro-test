@IsTest
private class AccountTriggerTest {

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Acc ' + i, MissionStatus__c = MissionConstants.STATUS_ACTIVE));
        }
        Account stillActive = new Account(Name = 'Reste active', MissionStatus__c = MissionConstants.STATUS_ACTIVE);
        accounts.add(stillActive);
        insert accounts;

        // 1 contact par entreprise (relation directe via AccountId)
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            contacts.add(new Contact(LastName = 'C' + i, AccountId = accounts[i].Id, IsActive__c = true));
        }
        contacts.add(new Contact(LastName = 'Reste', AccountId = stillActive.Id, IsActive__c = true));
        insert contacts;
    }

    private static List<Account> mainAccounts() {
        return [SELECT Id, MissionStatus__c, MissionCanceledDate__c FROM Account WHERE Name LIKE 'Acc %'];
    }

    @IsTest
    static void cancel200Accounts_deactivatesOnlyContactsOfCanceledAccounts() {
        List<Account> accounts = mainAccounts();
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        Test.startTest();
        for (Account a : accounts) {
            a.MissionStatus__c = MissionConstants.STATUS_CANCELED;
        }
        update accounts;
        Test.stopTest();

        for (Account a : mainAccounts()) {
            Assert.areEqual(Date.today(), a.MissionCanceledDate__c);
        }
        Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE IsActive__c = false]);
        Assert.isTrue([SELECT IsActive__c FROM Contact WHERE LastName = 'Reste'].IsActive__c,
            'Le compte de ce contact a encore une mission en cours');
        Assert.areEqual(1, ContactSyncMock.callCount);
        Assert.areEqual('PATCH', ContactSyncMock.lastMethod);
        Assert.areEqual(200, ContactSyncMock.lastPayload.size());
    }

    @IsTest
    static void cancelAllAccounts_deactivatesAllContacts() {
        List<Account> accounts = [SELECT Id, MissionStatus__c FROM Account];
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        Test.startTest();
        for (Account a : accounts) {
            a.MissionStatus__c = MissionConstants.STATUS_CANCELED;
        }
        update accounts;
        Test.stopTest();

        Assert.areEqual(201, [SELECT COUNT() FROM Contact WHERE IsActive__c = false]);
        // 201 comptes = 2 lots de trigger (200 + 1) = 2 jobs asynchrones, donc 2 appels API.
        Assert.areEqual(2, ContactSyncMock.callCount);
        Assert.areEqual(1, ContactSyncMock.lastPayload.size());
    }

    @IsTest
    static void cancelAccountWithoutContacts_doesNotCallApi() {
        Account lonely = new Account(Name = 'Seule', MissionStatus__c = MissionConstants.STATUS_ACTIVE);
        insert lonely;
        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        Test.startTest();
        lonely.MissionStatus__c = MissionConstants.STATUS_CANCELED;
        update lonely;
        Test.stopTest();

        Assert.areEqual(0, ContactSyncMock.callCount);
        Assert.areEqual(Date.today(), [SELECT MissionCanceledDate__c FROM Account WHERE Id = :lonely.Id].MissionCanceledDate__c);
    }

    @IsTest
    static void updateOfAlreadyCanceledAccount_isIgnored() {
        Account acc = new Account(Name = 'Déjà annulée', MissionStatus__c = MissionConstants.STATUS_ACTIVE);
        insert acc;
        acc.MissionStatus__c = MissionConstants.STATUS_CANCELED;
        update acc;

        Test.setMock(HttpCalloutMock.class, new ContactSyncMock(200));

        Test.startTest();
        acc.Name = 'Renommée';
        update acc;
        Test.stopTest();

        Assert.areEqual(0, ContactSyncMock.callCount);
        Assert.areEqual(Date.today(), [SELECT MissionCanceledDate__c FROM Account WHERE Id = :acc.Id].MissionCanceledDate__c,
            'La date d\'annulation ne doit pas être réécrite');
    }
}