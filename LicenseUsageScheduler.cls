/**
 * @description Schedules license usage collection
 * across configured Salesforce source organizations.
 */
public with sharing class LicenseUsageScheduler
    implements Schedulable {

    public void execute(SchedulableContext context) {
        List<License_Source_Org__mdt> orgConfigs = [
            SELECT DeveloperName
            FROM License_Source_Org__mdt
            WHERE Active__c = true
            ORDER BY Sort_Order__c ASC
            LIMIT 50
        ];
        for (License_Source_Org__mdt config : orgConfigs) {
            System.enqueueJob(
                new LicenseUsageQueueable(config.DeveloperName)
            );
        }
    }
}
