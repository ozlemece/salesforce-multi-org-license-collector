@IsTest
private class LicenseUsageQueueableTest {
    private static final String LICENSE_ID = '0PL000000000003AAA';
    private static final String USER_ID = '005000000000003AAA';

    private class SourceApiMock implements HttpCalloutMock {
        private Boolean fail;
        SourceApiMock(Boolean fail) { this.fail = fail; }

        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('GET', request.getMethod());
            System.assert(request.getEndpoint().startsWith('callout:'));
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            if (fail) {
                response.setStatusCode(503);
                response.setBody('{"message":"Service unavailable"}');
                return response;
            }
            response.setStatusCode(200);
            if (request.getEndpoint().contains('UserLicense')) {
                response.setBody('{"totalSize":1,"done":true,"records":[' +
                    '{"Id":"' + LICENSE_ID + '","Name":"Salesforce",' +
                    '"TotalLicenses":50,"UsedLicenses":25,"Status":"Active"}]}');
            } else {
                response.setBody('{"totalSize":1,"done":true,"records":[' +
                    '{"Id":"' + USER_ID + '","Name":"Queueable Test User",' +
                    '"Email":"QueueTest@Example.com",' +
                    '"Username":"queue.test@example.com","IsActive":true,' +
                    '"Profile":{"Name":"Standard User",' +
                    '"UserLicense":{"Name":"Salesforce"}}}]}');
            }
            return response;
        }
    }

    private static License_Source_Org__mdt activeSourceOrg() {
        List<License_Source_Org__mdt> configs = [
            SELECT DeveloperName, Named_Credential__c
            FROM License_Source_Org__mdt
            WHERE Active__c = true AND Named_Credential__c != null
            LIMIT 1
        ];
        System.assert(!configs.isEmpty(),
            'Configure at least one active License Source Org metadata record.');
        return configs[0];
    }

    @IsTest
    static void collectsConfiguredSourceOrg() {
        License_Source_Org__mdt config = activeSourceOrg();
        Test.setMock(HttpCalloutMock.class, new SourceApiMock(false));
        Test.startTest();
        System.enqueueJob(new LicenseUsageQueueable(config.DeveloperName));
        Test.stopTest();

        String licenseKey = config.DeveloperName + '|' + LICENSE_ID;
        List<License_Usage__c> licenses = [
            SELECT Total_Licenses__c, Used_Licenses__c
            FROM License_Usage__c WHERE External_Key__c = :licenseKey
        ];
        System.assertEquals(1, licenses.size(), 'Expected license totals.');
        System.assertEquals(50, licenses[0].Total_Licenses__c);
        System.assertEquals(25, licenses[0].Used_Licenses__c);

        String userKey = config.DeveloperName + '|' + USER_ID;
        List<License_User__c> users = [
            SELECT Normalized_Email__c, License_Name__c
            FROM License_User__c WHERE External_Key__c = :userKey
        ];
        System.assertEquals(1, users.size(), 'Expected user data.');
        System.assertEquals('queuetest@example.com', users[0].Normalized_Email__c);
        System.assertEquals('Salesforce', users[0].License_Name__c);
    }

    @IsTest
    static void skipsUnknownSourceOrg() {
        Test.startTest();
        System.enqueueJob(new LicenseUsageQueueable('No_Such_Source_Org_999'));
        Test.stopTest();
        System.assertEquals(0, [
            SELECT COUNT() FROM License_Usage__c
            WHERE Source_Org_Key__c = 'No_Such_Source_Org_999'
        ]);
    }

    @IsTest
    static void rejectsBlankSourceOrgName() {
        Boolean rejected = false;
        try {
            new LicenseUsageQueueable(' ');
        } catch (Exception e) {
            rejected = true;
        }
        System.assert(rejected, 'Blank source-org keys must be rejected.');
    }

    // The async exception path should be tested separately because exceptions
    // thrown at Test.stopTest() abort the test transaction.
}
