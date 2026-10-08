/**
 * Retrieves license totals and paginated user records from a configured org.
 * Each user page is persisted in its own Queueable transaction.
 */
public with sharing class LicenseUsageCollector {
    private static final String API_PREFIX = '/services/data/v66.0/query/?q=';
    private static final Integer TIMEOUT_MS = 120000;

    public class UserLicenseResponse {
        public Integer totalSize;
        public Boolean done;
        public List<UserLicenseRecord> records;
    }
    public class UserLicenseRecord {
        public String Id;
        public String Name;
        public Integer TotalLicenses;
        public Integer UsedLicenses;
        public String Status;
    }
    public class UserResponse {
        public Integer totalSize;
        public Boolean done;
        public String nextRecordsUrl;
        public List<UserRecord> records;
    }
    public class UserRecord {
        public String Id;
        public String Name;
        public String Email;
        public String Username;
        public Boolean IsActive;
        public ProfileRecord Profile;
    }
    public class ProfileRecord {
        public String Name;
        public SmallLicense UserLicense;
    }
    public class SmallLicense {
        public String Name;
    }

    /** Enqueues one initial job per configured org. Call from synchronous contexts only. */
    public static void collectAllActiveOrgs() {
        List<License_Source_Org__mdt> configs = [
            SELECT DeveloperName FROM License_Source_Org__mdt
            WHERE Active__c = true ORDER BY Sort_Order__c
        ];
        if (configs.size() > Limits.getLimitQueueableJobs() - Limits.getQueueableJobs()) {
            throw new LicenseCollectionException('Too many source orgs for this transaction.');
        }
        for (License_Source_Org__mdt config : configs) {
            System.enqueueJob(new LicenseUsageQueueable(config.DeveloperName));
        }
    }

    /** Called by the existing LicenseUsageQueueable. */
    public static void collectOrg(License_Source_Org__mdt config) {
        validateConfig(config);
        collectLicenseTotals(config);
        collectUserPage(config, null);
    }

    /** Collects exactly one REST query page, then chains a Queueable if more exist. */
    public static void collectUserPage(License_Source_Org__mdt config, String nextRecordsUrl) {
        validateConfig(config);
        String soql = 'SELECT Id, Name, Email, Username, IsActive, ' +
            'Profile.Name, Profile.UserLicense.Name FROM User ' +
            'WHERE IsActive = true AND Profile.UserLicense.Name != null';
        String path = String.isBlank(nextRecordsUrl)
            ? API_PREFIX + EncodingUtil.urlEncode(soql, 'UTF-8')
            : validateNextRecordsUrl(nextRecordsUrl);

        UserResponse response = (UserResponse) JSON.deserialize(
            sendQuery(config, path), UserResponse.class
        );
        if (response == null || response.records == null) {
            throw new LicenseCollectionException('Invalid user query response.');
        }
        List<License_User__c> users = new List<License_User__c>();
        Datetime collectedAt = System.now();
        for (UserRecord userRecord : response.records) {
            if (userRecord == null || String.isBlank(userRecord.Id)) {
                continue;
            }
            License_User__c userRow = new License_User__c();
            userRow.Source_Org_Name__c = config.Org_Name__c;
            userRow.Source_Org_Key__c = config.DeveloperName;
            userRow.Source_User_Id__c = userRecord.Id;
            userRow.User_Name__c = userRecord.Name;
            userRow.Email__c = userRecord.Email;
            userRow.Normalized_Email__c = String.isBlank(userRecord.Email)
                ? null : userRecord.Email.trim().toLowerCase();
            userRow.Username__c = userRecord.Username;
            userRow.Active__c = userRecord.IsActive;
            userRow.Profile_Name__c = userRecord.Profile == null
                ? null : userRecord.Profile.Name;
            userRow.License_Name__c = userRecord.Profile == null ||
                userRecord.Profile.UserLicense == null
                ? null : userRecord.Profile.UserLicense.Name;
            userRow.Collected_At__c = collectedAt;
            userRow.External_Key__c = config.DeveloperName + '|' + userRecord.Id;
            users.add(userRow);
        }
        saveUsers(users);
        if (response.done == false) {
            String cursor = validateNextRecordsUrl(response.nextRecordsUrl);
            System.enqueueJob(new LicenseUsageUserPageQueueable(config.DeveloperName, cursor));
        }
    }

    private static void collectLicenseTotals(License_Source_Org__mdt config) {
        String soql = 'SELECT Id, Name, TotalLicenses, UsedLicenses, Status FROM UserLicense';
        UserLicenseResponse response = (UserLicenseResponse) JSON.deserialize(
            sendQuery(config, API_PREFIX + EncodingUtil.urlEncode(soql, 'UTF-8')),
            UserLicenseResponse.class
        );
        if (response == null || response.records == null) {
            throw new LicenseCollectionException('Invalid license query response.');
        }
        List<License_Usage__c> usage = new List<License_Usage__c>();
        Datetime collectedAt = System.now();
        for (UserLicenseRecord licenseRecord : response.records) {
            if (licenseRecord == null || String.isBlank(licenseRecord.Id)) {
                continue;
            }
            License_Usage__c row = new License_Usage__c();
            row.Source_Org_Name__c = config.Org_Name__c;
            row.Source_Org_Key__c = config.DeveloperName;
            row.License_Name__c = licenseRecord.Name;
            row.License_Id__c = licenseRecord.Id;
            row.Total_Licenses__c = licenseRecord.TotalLicenses;
            row.Used_Licenses__c = licenseRecord.UsedLicenses;
            row.Status__c = licenseRecord.Status;
            row.Collected_At__c = collectedAt;
            row.External_Key__c = config.DeveloperName + '|' + licenseRecord.Id;
            usage.add(row);
        }
        if (!usage.isEmpty()) {
            if (!Schema.sObjectType.License_Usage__c.isCreateable() ||
                !Schema.sObjectType.License_Usage__c.isUpdateable()) {
                throw new LicenseCollectionException('Insufficient access to license usage records.');
            }
            Database.UpsertResult[] results = Database.upsert(
                usage, License_Usage__c.External_Key__c, false
            );
            assertNoFailures(results, 'license usage');
        }
    }

    private static void saveUsers(List<License_User__c> users) {
        if (users.isEmpty()) return;
        if (!Schema.sObjectType.License_User__c.isCreateable() ||
            !Schema.sObjectType.License_User__c.isUpdateable()) {
            throw new LicenseCollectionException('Insufficient access to license user records.');
        }
        Database.UpsertResult[] results = Database.upsert(
            users, License_User__c.External_Key__c, false
        );
        assertNoFailures(results, 'license users');
    }

    private static void assertNoFailures(Database.UpsertResult[] results, String label) {
        for (Database.UpsertResult result : results) {
            if (!result.isSuccess()) {
                throw new LicenseCollectionException('Unable to save ' + label + '.');
            }
        }
    }

    private static String sendQuery(License_Source_Org__mdt config, String path) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + config.Named_Credential__c + path);
        request.setMethod('GET');
        request.setTimeout(TIMEOUT_MS);
        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new LicenseCollectionException(
                'Source org query failed. HTTP status: ' + response.getStatusCode()
            );
        }
        return response.getBody();
    }

    private static void validateConfig(License_Source_Org__mdt config) {
        if (config == null || String.isBlank(config.DeveloperName) ||
            String.isBlank(config.Named_Credential__c) ||
            !Pattern.matches('^[A-Za-z0-9_]+$', config.Named_Credential__c)) {
            throw new LicenseCollectionException('Invalid source org configuration.');
        }
    }

    private static String validateNextRecordsUrl(String path) {
        if (String.isBlank(path) ||
            !path.startsWith('/services/data/v66.0/query/') ||
            path.contains('://') || path.contains('..') || path.contains('#')) {
            throw new LicenseCollectionException('Invalid query pagination cursor.');
        }
        return path;
    }

    public class LicenseCollectionException extends Exception {}
}
