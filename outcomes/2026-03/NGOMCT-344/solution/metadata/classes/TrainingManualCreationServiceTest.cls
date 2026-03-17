/**
 * @description Test class for TrainingManualCreationService (NGOMCT-344).
 * Manual Training Record Creation — TDD tests (RED → GREEN → IMPROVE).
 *
 * @author Som Balakrushnan
 * © Som Balakrushnan
 * Feature: NGOMCT-344 — Training Creation & Assignment: Manual Training Record Creation
 * Status: [NEW] — Created by agentic pipeline run 54bee681 (2026-03-14)
 */
@IsTest
private class TrainingManualCreationServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Test Consumer'
        );
        insert acc;
    }

    @IsTest
    static void createTraining_withValidAccount_createsRecord() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        TrainingManualCreationService.Request req = new TrainingManualCreationService.Request();
        req.accountId = acc.Id;

        Test.startTest();
        List<TrainingManualCreationService.Result> results = TrainingManualCreationService.createManualTraining(
            new List<TrainingManualCreationService.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assert(results[0].success, 'Should succeed');
        System.assertNotEquals(null, results[0].trainingId, 'Should return training Id');

        List<Training__c> trainings = [SELECT Id, Account__c, Training_Stage__c FROM Training__c WHERE Id = :results[0].trainingId];
        System.assertEquals(1, trainings.size(), 'Training should be created');
        System.assertEquals(acc.Id, trainings[0].Account__c, 'Account should match');
        System.assertEquals('Pending Assignment', trainings[0].Training_Stage__c, 'Stage should be Pending Assignment');
    }

    @IsTest
    static void createTraining_withOptionalFields_populatesCorrectly() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        TrainingManualCreationService.Request req = new TrainingManualCreationService.Request();
        req.accountId = acc.Id;
        req.trainingType = 'Insulin Start Training';
        req.trainingMethod = 'Live Virtual';
        req.product = 'Omnipod 5';

        Test.startTest();
        List<TrainingManualCreationService.Result> results = TrainingManualCreationService.createManualTraining(
            new List<TrainingManualCreationService.Request>{ req }
        );
        Test.stopTest();

        System.assert(results[0].success, 'Should succeed');
        Training__c t = [SELECT Training_Type__c, Training_Method__c, Product__c FROM Training__c WHERE Id = :results[0].trainingId];
        System.assertEquals('Insulin Start Training', t.Training_Type__c);
        System.assertEquals('Live Virtual', t.Training_Method__c);
        System.assertEquals('Omnipod 5', t.Product__c);
    }

    @IsTest
    static void createTraining_withInvalidAccountId_returnsError() {
        TrainingManualCreationService.Request req = new TrainingManualCreationService.Request();
        req.accountId = null;

        Test.startTest();
        List<TrainingManualCreationService.Result> results = TrainingManualCreationService.createManualTraining(
            new List<TrainingManualCreationService.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(!results[0].success, 'Should fail');
        System.assert(results[0].errorMessage != null, 'Should have error message');
    }

    @IsTest
    static void createTraining_withNonExistentAccount_returnsError() {
        TrainingManualCreationService.Request req = new TrainingManualCreationService.Request();
        req.accountId = '001000000000000AAA'; // Fake 15-char Id

        Test.startTest();
        List<TrainingManualCreationService.Result> results = TrainingManualCreationService.createManualTraining(
            new List<TrainingManualCreationService.Request>{ req }
        );
        Test.stopTest();

        System.assert(!results[0].success, 'Should fail for non-existent Account');
        System.assert(results[0].errorMessage != null);
    }

    @IsTest
    static void createTraining_bulkHandlesMultipleRequests() {
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accs.add(new Account(Name = 'Bulk Test ' + i));
        }
        insert accs;

        List<TrainingManualCreationService.Request> requests = new List<TrainingManualCreationService.Request>();
        for (Account a : accs) {
            TrainingManualCreationService.Request req = new TrainingManualCreationService.Request();
            req.accountId = a.Id;
            requests.add(req);
        }

        Test.startTest();
        List<TrainingManualCreationService.Result> results = TrainingManualCreationService.createManualTraining(requests);
        Test.stopTest();

        System.assertEquals(5, results.size());
        for (TrainingManualCreationService.Result r : results) {
            System.assert(r.success, 'All should succeed');
            System.assertNotEquals(null, r.trainingId);
        }
        System.assertEquals(5, [SELECT COUNT() FROM Training__c], 'Should create 5 trainings');
    }
}
