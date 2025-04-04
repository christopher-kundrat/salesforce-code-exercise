public class CaseOrderSubmissionJob implements Queueable, Database.AllowsCallouts {
    private List<Id> caseIdsToProcess;
    private List<Order> ordersToCreate = new List<Order>();
    private List<API_Request__c> apiRequestsToCreate = new List<API_Request__c>();
    private List<Case> failedCases = new List<Case>();
    
    public CaseOrderSubmissionJob(List<Id> caseIdsToProcess) {
        this.caseIdsToProcess = caseIdsToProcess;
    }
    
    public void execute(QueueableContext context) {      
        
        // Setup the calls for this in another class for code seperation.
        String apiEndpoint = metaDataUtility.getAPIEndpoint();
        String bearerToken = metaDataUtility.getBearerToken(); 
        
        // Here we're going to query for all the information we need from these cases so that we can loop over them for our API call
        List<Case> caseDataToProcess = [
            SELECT Id, AccountId, Account.Name, Account.Phone, Account.ShippingStreet,Account.ShippingCity, 
            	Account.ShippingState, Account.ShippingCountry, Account.ShippingPostalCode, 
            	(SELECT Id, Product__c, Product__r.Name, Quantity__c, Unit_Price__C FROM Case_Products__r)
            FROM Case
            WHERE Id IN :caseIdsToProcess
        ];
        
        // Get the default pricebook for the order. Can use logic to change this if needed. 
     	// Looking back it might have been better to have this already setup on the case as a custom field
        Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1];
        
        for (Case caseRecord : caseDataToProcess) {
     
            //Handling the data manipulation in another function to keep this function clean
            String payload = createApiPayload(caseRecord);
            
           	// Create the inital API Request to store in our custom object. Would need to make sure sensitive information isn't stored in the Request Body.
           	// Could set the API request object up as a polymorphic  relationship so other objects can use it, but just doing case here for simplicity
           	API_Request__c apiRequest = new API_Request__c(
                Request_Timestamp__c = System.now(),
                Request_Method__c = 'POST',
                Request_Body__c = payload,
                API_Endpoint__c = apiEndpoint,
                Case__c = caseRecord.Id
            );
                        
            //Design decision on if this API logic should be handled in another class. Beause it's a queuable function I just wanted to keep everything together.
            HttpRequest req = new HttpRequest();
            req.setEndpoint(apiEndpoint);
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + bearerToken);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(payload);
            
            boolean success = false;
            Map<String, Object> responseBody;
                
            try {
                Http http = new Http();
            	HttpResponse res = http.send(req);
                
                // Store the Api Response - Would need to make sure sensitive information isn't stored in the Response Body
                apiRequest.Response_Timestamp__c = System.now();
                apiRequest.Response_Status_Code__c = res.getStatusCode();
                apiRequest.Response_Body__c = res.getBody();
                apiRequestsToCreate.add(apiRequest);
                responseBody = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                
                success = (res.getStatusCode() == 200);
            } catch (CalloutException e) {
                system.Debug(LoggingLevel.ERROR, 'API Called failed for Case: ' + caseRecord.Id + 'Exception: ' + e.getMessage() );  
                failedCases.add(new Case(Id = caseRecord.Id, Status = 'Vendor Submit Failed'));
            }       
            
            // Handle the response
            if (success) {
                              
                // Order Creation Logic
                String externalOrderId = (String)responseBody.get('Order_Id');
                
                Order newOrder = new Order(
                	AccountId = caseRecord.AccountID,
                    Case__c = caseRecord.Id,
                    Status = 'Draft', //Orders can't be activated til it has order items
                    EffectiveDate = System.today(),
                    Pricebook2Id = standardPricebook.Id,
                    External_Order_ID__c = externalOrderId           
                );
                
                ordersToCreate.add(newOrder);            
  
            } else {		
                failedCases.add(new Case(Id = caseRecord.Id, Status = 'Vendor Submit Failed'));
            }          
        }
        
        if (!failedCases.isEmpty()) {
            update failedCases;
            
       		/* Just updating the cases status here to say it failed to submit to vendor
       		 * But could also implement retyr logic as well by recalling this queueable function passing in these values
       		 * Would want to track on the case (using a custom field ) the number of retries so that we can limit them to a max amount set by a custom meta data setting
       		*/
        }
        
        // Doing the updates and inserts in bulk to not go over DML limits 
        if (!apiRequestsToCreate.isEmpty()) {
            insert apiRequestsToCreate;
        }
        
        if (!ordersToCreate.isEmpty()) {
        	insert ordersToCreate;
                           
  			// Chain a new Queueable job to add Order Items
            System.enqueueJob(new QueueableAddOrderItems(ordersToCreate));
        }
    }
    
    private String createApiPayload(Case caseRecord) {
        
        // Build the address from the data we queried. Could use a construtor for this
        APIRequestAddress address = new APIRequestAddress();
        address.City = caseRecord.Account.ShippingCity;
		address.CompanyName = caseRecord.Account.Name;
		address.Country = caseRecord.Account.ShippingCountry;
        address.FirstName = ''; 
        address.LastName = '';
        address.Phone = caseRecord.Account.Phone;
        address.PostalCode = caseRecord.Account.ShippingPostalCode;
        address.State = caseRecord.Account.ShippingState;
        address.Street = caseRecord.Account.ShippingStreet;
        
        // Do the same for the list of items we're adding to the order
        List<APIRequestOrderItem> items = new List<APIRequestOrderItem>();
        for (Case_Product__c cp : caseRecord.Case_Products__r) {
            APIRequestOrderItem item = new APIRequestOrderItem();
            item.ProductCode = cp.Product__r.Name;
            item.Quantity = cp.Quantity__c;
            items.add(item);
        }
        
        //Finally build the API REquest Object and return the serialized JSON
        APIRequestPayload payload = new APIRequestPayload();
        payload.Address = address;
        payload.Items = items;
        
        return JSON.serialize(payload);
    }
}