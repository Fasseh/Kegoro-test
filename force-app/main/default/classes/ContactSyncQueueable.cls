/** Asynchrone car un callout est impossible après un DML dans la transaction du trigger. */
public with sharing class ContactSyncQueueable implements Queueable, Database.AllowsCallouts {

    private final List<ContactSyncClient.ContactStatus> statuses = new List<ContactSyncClient.ContactStatus>();

    public ContactSyncQueueable(List<Contact> contacts) {
        for (Contact c : contacts) {
            statuses.add(new ContactSyncClient.ContactStatus(c.Id, c.IsActive__c));
        }
    }

    public void execute(QueueableContext ctx) {
        System.attachFinalizer(new SyncFinalizer(statuses.size()));
        ContactSyncClient.sync(statuses);
    }

    /** Trace l'échec même si le job plante. */
    private class SyncFinalizer implements Finalizer {
        private final Integer contactCount;

        SyncFinalizer(Integer contactCount) {
            this.contactCount = contactCount;
        }

        public void execute(FinalizerContext ctx) {
            if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
                System.debug(LoggingLevel.ERROR,
                    'Sync de ' + contactCount + ' contacts en échec : ' + ctx.getException().getMessage());
            }
        }
    }
}