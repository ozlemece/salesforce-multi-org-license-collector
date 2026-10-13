/**
 * @description Collects license usage information from a configured
 * Salesforce source organization asynchronously.
 */
public with sharing class LicenseUsageQueueable
    implements Queueable, Database.AllowsCallouts {

    private final String sourceOrgDeveloperName;

    public LicenseUsageQueueable(String sourceOrgDeveloperName) {
        if (String.isBlank(sourceOrgDeveloperName)) {
            throw new IllegalArgumentException(
                'Source organization DeveloperName is required.'
            );
        }
        this.sourceOrgDeveloperName = sourceOrgDeveloperName;
    }

    public void execute(QueueableContext context) {
        List<License_Source_Org__mdt> configs = [
            SELECT DeveloperName,
                   Org_Name__c,
                   Named_Credential__c,
                   Active__c,
                   Sort_Order__c
            FROM License_Source_Org__mdt
            WHERE DeveloperName = :sourceOrgDeveloperName
            AND Active__c = true
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'License collection skipped: source org not found or inactive.'
            );
            return;
        }
        LicenseUsageCollector.collectOrg(configs[0]);
    }
}
