/**
 * Tests de bout en bout : de la modification du compte jusqu'à l'appel API (mocké).
 * Les données sont créées une seule fois dans @TestSetup, puis rechargées dans chaque test.
 */
@IsTest
private class AccountTriggerTest {

    /**
     * Jeu de données : 200 comptes "Acc N" actifs (le maximum traité en un lot par un trigger),
     * un compte "Reste active" qui ne sera pas annulé dans le premier test,
     * et un contact actif par compte.
     */
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

    /** Recharge les 200 comptes "Acc N" (sans "Reste active") avec leur état actuel en base. */
    private static List<Account> mainAccounts() {
        return [SELECT Id, MissionStatus__c, MissionCanceledDate__c FROM Account WHERE Name LIKE 'Acc %'];
    }

    // Cas principal : 200 comptes annulés d'un coup. Seuls leurs contacts sont désactivés,
    // le contact du compte resté actif ne change pas, et l'API est appelée une seule fois (200 contacts).
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

    // 201 comptes annulés : Salesforce découpe en deux lots de trigger (200 + 1),
    // donc deux jobs asynchrones et deux appels API.
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

    // Compte sans contact : la date est posée mais l'API n'est pas appelée.
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

    // Un compte déjà annulé, simplement renommé, ne doit rien déclencher
    // (ni appel API, ni nouvelle date d'annulation).
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