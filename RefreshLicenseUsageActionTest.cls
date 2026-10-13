@IsTest
private class RefreshLicenseUsageActionTest {
    private class LicenseCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            String endpoint = EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8');
            if (endpoint.contains('FROM UserLicense')) {
                response.setBody('{"totalSize":0,"done":true,"records":[]}');
            } else if (endpoint.contains('FROM User')) {
                response.setBody('{"totalSize":0,"done":true,"records":[]}');
            } else {
                response.setStatusCode(400);
                response.setBody('{"message":"Unexpected endpoint"}');
            }
            return response;
        }
    }
    @IsTest
    static void testRefreshQueuesActiveOrgs() {
        Integer expectedJobs = [
            SELECT COUNT() FROM License_Source_Org__mdt WHERE Active__c = true
        ];
        RefreshLicenseUsageAction.Request request =
            new RefreshLicenseUsageAction.Request();
        request.runRefresh = true;
        Test.setMock(HttpCalloutMock.class, new LicenseCalloutMock());
        Test.startTest();
        Integer beforeJobs = Limits.getQueueableJobs();
        RefreshLicenseUsageAction.refresh(
            new List<RefreshLicenseUsageAction.Request>{ request }
        );
        Integer actualJobs = Limits.getQueueableJobs() - beforeJobs;
        System.assertEquals(expectedJobs, actualJobs,
            'Refresh should enqueue one Queueable for each active source org.');
        Test.stopTest();
    }
    @IsTest
    static void testRefreshWithEmptyRequests() {
        Test.setMock(HttpCalloutMock.class, new LicenseCalloutMock());
        Test.startTest();
        RefreshLicenseUsageAction.refresh(
            new List<RefreshLicenseUsageAction.Request>()
        );
        Test.stopTest();
        System.assert(true, 'Action completed without throwing an exception.');
    }
}
