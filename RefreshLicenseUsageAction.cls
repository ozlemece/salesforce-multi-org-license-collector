public with sharing class RefreshLicenseUsageAction {

    @InvocableMethod(label='Refresh License Usage'
        description='Queues license usage collection for all active configured Salesforce source orgs.'
    )
    public static void refresh(List<Request> requests) {

        List<License_Source_Org__mdt> orgConfigs = [
            SELECT DeveloperName
            FROM License_Source_Org__mdt
            WHERE Active__c = true
            ORDER BY Sort_Order__c ASC
        ];

        for (License_Source_Org__mdt config : orgConfigs) {
            System.enqueueJob(new LicenseUsageQueueable(config.DeveloperName));
        }
    }

    public class Request {
        @InvocableVariable(label='Run Refresh'
            description='Triggers the license usage refresh.'
        )
        public Boolean runRefresh;
    }
}
