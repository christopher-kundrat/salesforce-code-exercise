public class CaseTriggerHandler {
    
    // Here's where I'd any business logic or validation before running our Order Sync Logic
    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldCasesMap) {
        // Creating a list of case Id's that need to get orders created for them.
        List<Id> caseIdsToProcess = new List<Id>();
        
        //Because Salesforce Triggers batch them into groups of 200 just always handle it for multiple
        for (Case c : newCases) {
            
            /* Checking if the case has a status of Submit to Vendor and that the old status wasn't 'Submit to Vendor' so we know to submit the order
             * Could add additional conditionals based on busines needs (ex. only run if the case doesn't have an order).
             * Others like checking to make sure Case has a valid product could be handled in a before trigger and prevent the status from updating so this doesn't run.
			*/
            if (c.Status == 'Submit to Vendor') {
                Case oldCase = oldCasesMap.get(c.Id);
                if (oldCase != null && oldCase.Status != 'Submit to Vendor'){
                    // If it passes validation add it to a new list for processing. 
                    system.debug(LoggingLevel.INFO, 'Adding case id ' + c.id + ' to list for processing');
                    caseIdsToProcess.add(c.Id);
                }
            }
        }
        
        if (!caseIdsToProcess.isEmpty()) {
            //It needs to use Queuable Apex because it's reaching out to a third party API
            System.enqueueJob(new CaseOrderSubmissionJob(caseIdsToProcess));
        }
   
    }
}