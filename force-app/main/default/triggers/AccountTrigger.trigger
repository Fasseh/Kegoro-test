trigger AccountTrigger on Account (before update, after update) {
    if (Trigger.isBefore) {
        AccountTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter) {
        AccountTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}