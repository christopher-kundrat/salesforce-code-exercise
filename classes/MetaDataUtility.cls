public class MetaDataUtility {

    // Storing the value in a static variable so we don't have to use SOQL whenever we need these values
    private static API_Settings__mdt config;

    // Function to make sure that the settings are loaded before making the call
    private static void loadAPIConfig() {
        if (config == null) {
            config = [SELECT URL__c, Bearer_Token__c FROM API_Settings__mdt LIMIT 1];
        }
    }

    // The functions used to get the setting values, calls to make sure that the custom meta data values are already loaded.
    public static String getAPIEndpoint() {
        loadAPIConfig();
        return config.URL__c;
    }

    public static String getBearerToken() {
        loadAPIConfig();
        return config.Bearer_Token__c;
    }
}