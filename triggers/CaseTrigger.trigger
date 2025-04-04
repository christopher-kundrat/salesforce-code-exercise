trigger CaseTrigger on Case (after update) {
	// We could setup different conditionals on Trigger (ex. Trigger.IsAfter and Trigger.isUpdate ) to seperate logic into different handler functions.
	// I'm keeping it simple for this exercise and only setting up after update. 
    CaseTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}