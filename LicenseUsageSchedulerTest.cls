@IsTest
private class LicenseUsageSchedulerTest {
    private class SchedulerCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
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
                response.setBody('{"message":"Unexpected test endpoint"}');
            }
            return response;
        }
    }
    @IsTest
    static void testScheduledExecution() {
        Test.setMock(HttpCalloutMock.class, new SchedulerCalloutMock());
        Test.startTest();
        String jobId = System.schedule('LicenseUsageSchedulerTest', '0 0 2 ? * SUN', new LicenseUsageScheduler());
        Test.stopTest();
        CronTrigger job = [
            SELECT Id, CronExpression
            FROM CronTrigger WHERE Id = :jobId LIMIT 1
        ];
        System.assertNotEquals(null, job.Id, 'Scheduled job should exist.');
        System.assertEquals('0 0 2 ? * SUN', job.CronExpression, 'CRON expression should match.');
    }
    @IsTest
    static void testDirectExecution() {
        Integer expectedJobs = [
            SELECT COUNT() FROM License_Source_Org__mdt WHERE Active__c = true
        ];
        Test.setMock(HttpCalloutMock.class, new SchedulerCalloutMock());
        Test.startTest();
        Integer beforeJobs = Limits.getQueueableJobs();
        new LicenseUsageScheduler().execute(null);
        Integer actualJobs = Limits.getQueueableJobs() - beforeJobs;
        System.assertEquals(expectedJobs, actualJobs,
            'One Queueable should be enqueued per active source org.');
        Test.stopTest();
    }
}
