/** Continues the user collection at the next REST API query page. */
public with sharing class LicenseUsageUserPageQueueable
    implements Queueable, Database.AllowsCallouts {
    private String sourceOrgDeveloperName;
    private String nextRecordsUrl;

    public LicenseUsageUserPageQueueable(String sourceOrgDeveloperName, String nextRecordsUrl) {
        this.sourceOrgDeveloperName = sourceOrgDeveloperName;
        this.nextRecordsUrl = nextRecordsUrl;
    }

    public void execute(QueueableContext context) {
        List<License_Source_Org__mdt> configs = [
            SELECT DeveloperName, Org_Name__c, Named_Credential__c, Active__c
            FROM License_Source_Org__mdt
            WHERE DeveloperName = :sourceOrgDeveloperName AND Active__c = true
            LIMIT 1
        ];
        if (!configs.isEmpty()) {
            LicenseUsageCollector.collectUserPage(configs[0], nextRecordsUrl);
        }
    }
}
