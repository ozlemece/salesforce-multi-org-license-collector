@IsTest
private class LicenseUsageUserPageQueueableTest {
    private static final String USER_ID = '005000000000002AAA';
    private static final String CURSOR = '/services/data/v66.0/query/01g000000000001AAA-2000';

    private class UserPageMock implements HttpCalloutMock {
        private Integer statusCode;
        UserPageMock(Integer statusCode) {
            this.statusCode = statusCode;
        }
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('GET', request.getMethod());
            System.assert(request.getEndpoint().endsWith(CURSOR),
                'The Queueable must request the supplied nextRecordsUrl.');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setHeader('Content-Type', 'application/json');
            if (statusCode == 200) {
                response.setBody('{"totalSize":1,"done":true,"records":[' +
                    '{"Id":"' + USER_ID + '","Name":"Page Two User",' +
                    '"Email":"PageTwo@Example.com",' +
                    '"Username":"page.two@example.com","IsActive":true,' +
                    '"Profile":{"Name":"Standard User",' +
                    '"UserLicense":{"Name":"Salesforce"}}}]}');
            } else {
                response.setBody('{"message":"Service unavailable"}');
            }
            return response;
        }
    }

    private static License_Source_Org__mdt activeSourceOrg() {
        List<License_Source_Org__mdt> configs = [
            SELECT DeveloperName, Org_Name__c, Named_Credential__c, Active__c
            FROM License_Source_Org__mdt
            WHERE Active__c = true AND Named_Credential__c != null
            LIMIT 1
        ];
        System.assert(!configs.isEmpty(),
            'This test requires an active License Source Org custom metadata record.');
        return configs[0];
    }

    @IsTest
    static void processesNextPageAndSavesUser() {
        License_Source_Org__mdt config = activeSourceOrg();
        Test.setMock(HttpCalloutMock.class, new UserPageMock(200));
        Test.startTest();
        System.enqueueJob(new LicenseUsageUserPageQueueable(config.DeveloperName, CURSOR));
        Test.stopTest();

        String expectedKey = config.DeveloperName + '|' + USER_ID;
        List<License_User__c> users = [
            SELECT Source_Org_Key__c, User_Name__c, Normalized_Email__c,
                   License_Name__c, Active__c
            FROM License_User__c
            WHERE External_Key__c = :expectedKey
        ];
        System.assertEquals(1, users.size(), 'Expected the paginated user to be upserted.');
        System.assertEquals(config.DeveloperName, users[0].Source_Org_Key__c);
        System.assertEquals('Page Two User', users[0].User_Name__c);
        System.assertEquals('pagetwo@example.com', users[0].Normalized_Email__c);
        System.assertEquals('Salesforce', users[0].License_Name__c);
        System.assertEquals(true, users[0].Active__c);
    }

    @IsTest
    static void ignoresUnknownSourceOrg() {
        Test.startTest();
        System.enqueueJob(new LicenseUsageUserPageQueueable(
            'No_Such_Source_Org_999', CURSOR));
        Test.stopTest();
        System.assertEquals(0, [
            SELECT COUNT() FROM License_User__c
            WHERE Source_Org_Key__c = 'No_Such_Source_Org_999'
        ]);
    }

    @IsTest
    static void rejectsUnsafeCursor() {
        License_Source_Org__mdt config = activeSourceOrg();
        try {
            LicenseUsageCollector.collectUserPage(
                config, 'https://untrusted.example.com/query');
            System.assert(false, 'An absolute external cursor must be rejected.');
        } catch (LicenseUsageCollector.LicenseCollectionException ex) {
            System.assert(ex.getMessage().contains('pagination cursor'));
        }
    }
}
