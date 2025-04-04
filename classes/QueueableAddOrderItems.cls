public class QueueableAddOrderItems implements Queueable {
    private List<Order> orders;
	private List<OrderItem> orderItems;
    private List<Order> ordersToUpdate;
    
    public QueueableAddOrderItems(List<Order> orders) {
        this.orders = orders;
        this.orderItems = new List<OrderItem>();
        this.ordersToUpdate = new List<Order>();
    }

    public void execute(QueueableContext context) {
        
        // Get related Cases so that we can find the products from case product relationship
        Set<Id> caseIds = new Set<Id>();
        for (Order o : orders) {
            caseIds.add(o.Case__c);
        }
        
        // Another validation to make sure these orders have cases
        if (caseIds.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'No related Case IDs found, exiting QueueableAddOrderItems.');
            return;
        }
        
        //SOQL to get the case product data and store it in a map for easy lookup in order loop
        //This is where it would have been nice to already have the pricebookentry on the case products
        List<Case_Product__c> caseProductsList = [
            SELECT Id, Case__c, Product__c, Quantity__c, Unit_Price__c 
            FROM Case_Product__c 
            WHERE Case__c IN :caseIds
        
        ];
		
        // Map of the products and set of product Ids for the pricebook lookup later
        Map<Id, List<Case_Product__c>> caseProductsMap = new Map<Id, List<Case_Product__c>>();
        Set<Id> productIds = new Set<Id>();
        
        for (Case_Product__c cp : caseProductsList) {
            // Since Cases can have more than one product just making sure it's handled correctly
            if (!caseProductsMap.containsKey(cp.Case__c)) {
                caseProductsMap.put(cp.Case__c, new List<Case_Product__c>());
            }
            caseProductsMap.get(cp.Case__c).add(cp);
            productIds.add(cp.Product__c);
        }
        
        // Now querying the pricebook entry with that list of productIds
        // Again unneeded if I setup the pricebooketnry on the case products 
        Map<Id, Id> productToPricebookEntryMap = new Map<Id, Id>();
		List<PricebookEntry> PricebookEntryList = [
            	SELECT Id, Product2Id 
            	FROM PricebookEntry 
            	WHERE Product2Id IN :productIds AND Pricebook2.IsStandard = TRUE
        ];
        
        for (PricebookEntry pbe : PricebookEntryList) {
        	productToPricebookEntryMap.put(pbe.Product2Id, pbe.Id);
        }
        
        // Loop over the orders to create the order items with the map we created of case product.
        for (Order o : orders) {
            
            if (caseProductsMap.containsKey(o.Case__c)) {
                List<Case_Product__c> caseProducts = caseProductsMap.get(o.Case__c);
                for (Case_Product__c cp : caseProducts) {
                   
                    orderItems.add(new OrderItem(
                        OrderId = o.Id,
                        Product2Id = cp.Product__c,
                        Quantity = cp.Quantity__c,
                        UnitPrice = cp.Unit_Price__c,
                        PricebookEntryId = productToPricebookEntryMap.get(cp.Product__c)
                    ));
                }
            }
            
            // Update Order status
            o.Status = 'Activated';
            ordersToUpdate.add(o);
        }

        if (!orderItems.isEmpty()) {
            insert orderItems;
        }

        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
    }
}