@IsTest
private class LicenseUsageCollectorTest {
    private class LicenseApiMock implements HttpCalloutMock {
        private Integer userCalls = 0;
        private Boolean fail;
        LicenseApiMock(Boolean fail) { this.fail = fail; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (fail) {
                res.setStatusCode(503);
                res.setBody('{"message":"Unavailable"}');
                return res;
            }
            System.assertEquals('GET', req.getMethod());
            System.assert(req.getEndpoint().startsWith('callout:Source_Org_1/'));
            res.setStatusCode(200);
            if (req.getEndpoint().contains('FROM+UserLicense') ||
                req.getEndpoint().contains('FROM%20UserLicense')) {
                res.setBody('{"totalSize":1,"done":true,"records":[' +
                    '{"Id":"0PL000000000001AAA","Name":"Salesforce",' +
                    '"TotalLicenses":100,"UsedLicenses":70,"Status":"Active"}]}');
            } else {
                userCalls++;
                res.setBody('{"totalSize":1,"done":true,"records":[' +
                    '{"Id":"005000000000001AAA","Name":"Test User",' +
                    '"Email":"test@example.com","Username":"test@example.com",' +
                    '"IsActive":true,"Profile":{"Name":"Standard User",' +
                    '"UserLicense":{"Name":"Salesforce"}}}]}');
            }
            return res;
        }
    }

    private static License_Source_Org__mdt config() {
        return new License_Source_Org__mdt(
            DeveloperName = 'Source_Org_1',
            MasterLabel = 'Source Org 1',
            Org_Name__c = 'Source Org 1',
            Named_Credential__c = 'Source_Org_1',
            Active__c = true
        );
    }

    @IsTest
    static void collectsLicenseTotalsAndUsers() {
        Test.setMock(HttpCalloutMock.class, new LicenseApiMock(false));
        Test.startTest();
        LicenseUsageCollector.collectOrg(config());
        Test.stopTest();
        List<License_Usage__c> licenses = [
            SELECT External_Key__c, Total_Licenses__c, Used_Licenses__c
            FROM License_Usage__c
            WHERE External_Key__c = 'Source_Org_1|0PL000000000001AAA'
        ];
        System.assertEquals(1, licenses.size());
        System.assertEquals(100, licenses[0].Total_Licenses__c);
        System.assertEquals(70, licenses[0].Used_Licenses__c);
        List<License_User__c> users = [
            SELECT External_Key__c, Normalized_Email__c, License_Name__c
            FROM License_User__c
            WHERE External_Key__c = 'Source_Org_1|005000000000001AAA'
        ];
        System.assertEquals(1, users.size());
        System.assertEquals('test@example.com', users[0].Normalized_Email__c);
        System.assertEquals('Salesforce', users[0].License_Name__c);
    }

    @IsTest
    static void rejectsInvalidConfig() {
        try {
            LicenseUsageCollector.collectOrg(null);
            System.assert(false, 'Expected invalid config exception');
        } catch (LicenseUsageCollector.LicenseCollectionException e) {
            System.assert(e.getMessage().contains('Invalid source org'));
        }
    }

    @IsTest
    static void handlesHttpFailure() {
        Test.setMock(HttpCalloutMock.class, new LicenseApiMock(true));
        Test.startTest();
        try {
            LicenseUsageCollector.collectOrg(config());
            System.assert(false, 'Expected HTTP failure');
        } catch (LicenseUsageCollector.LicenseCollectionException e) {
            System.assert(e.getMessage().contains('503'));
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsUnsafePaginationCursor() {
        Test.setMock(HttpCalloutMock.class, new LicenseApiMock(false));
        try {
            LicenseUsageCollector.collectUserPage(config(), 'https://malicious.example/');
            System.assert(false, 'Expected unsafe cursor rejection');
        } catch (LicenseUsageCollector.LicenseCollectionException e) {
            System.assert(e.getMessage().contains('pagination cursor'));
        }
    }
}
