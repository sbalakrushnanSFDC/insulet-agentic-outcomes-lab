/**
 * @description Invocable service for manual Training record creation (NGOMCT-344).
 * Creates Training__c for a consumer Account. Training assignment is handled by NGOMCT-89.
 *
 * @author Som Balakrushnan
 * © Som Balakrushnan
 * Feature: NGOMCT-344 — Training Creation & Assignment: Manual Training Record Creation
 * Status: [NEW] — Created by agentic pipeline run 54bee681 (2026-03-14)
 */
public with sharing class TrainingManualCreationService {

    private static final String RECORD_TYPE_DEVELOPER_NAME = 'Live_Training';
    private static final String DEFAULT_STAGE = 'Pending Assignment';
    private static final String PLACEHOLDER_ERROR = 'Pending';

    /**
     * @description Input for manual training creation.
     */
    public class Request {
        @InvocableVariable(required=true label='Account Id' description='Consumer Account Id')
        public Id accountId;
        @InvocableVariable(label='Training Type' description='e.g. Insulin Start Training')
        public String trainingType;
        @InvocableVariable(label='Training Method' description='e.g. Live Virtual, Live In-Person')
        public String trainingMethod;
        @InvocableVariable(label='Product' description='e.g. Omnipod 5, DASH')
        public String product;
    }

    /**
     * @description Output from manual training creation.
     */
    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Training Id')
        public Id trainingId;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    /**
     * @description Creates Training records for the given requests. Invocable from Flow.
     * @param requests List of creation requests
     * @return List of results (one per request)
     */
    @InvocableMethod(label='Create Manual Training' description='Creates a Training record for a consumer (NGOMCT-344)')
    public static List<Result> createManualTraining(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        if (!Schema.sObjectType.Training__c.isCreateable()) {
            for (Request req : requests) {
                results.add(new Result {
                    success = false,
                    errorMessage = 'Insufficient permissions to create Training records.'
                });
            }
            return results;
        }

        Id recordTypeId = getLiveTrainingRecordTypeId();
        if (recordTypeId == null) {
            for (Request req : requests) {
                results.add(new Result {
                    success = false,
                    errorMessage = 'Live Training record type not found.'
                });
            }
            return results;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.accountId != null) {
                accountIds.add(req.accountId);
            }
        }
        Map<Id, Account> accountsById = fetchAccounts(accountIds);

        List<Training__c> toInsert = new List<Training__c>();
        Map<Integer, Integer> requestIdxToInsertIdx = new Map<Integer, Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            if (req == null) {
                results.add(new Result { success = false, errorMessage = 'Request is null.' });
            } else if (req.accountId == null) {
                results.add(new Result { success = false, errorMessage = 'Account Id is required.' });
            } else if (!accountsById.containsKey(req.accountId)) {
                results.add(new Result { success = false, errorMessage = 'Account not found or not accessible.' });
            } else {
                toInsert.add(buildTraining(req, recordTypeId));
                requestIdxToInsertIdx.put(i, toInsert.size() - 1);
                results.add(new Result { success = false, errorMessage = PLACEHOLDER_ERROR });
            }
        }

        if (toInsert.isEmpty()) {
            return results;
        }

        List<Database.SaveResult> saveResults;
        try {
            saveResults = Database.insert(toInsert, false);
        } catch (DmlException e) {
            for (Integer i : requestIdxToInsertIdx.keySet()) {
                results.set(i, new Result { success = false, errorMessage = e.getDmlMessage(0) });
            }
            return results;
        }

        for (Integer i : requestIdxToInsertIdx.keySet()) {
            Integer insertIdx = requestIdxToInsertIdx.get(i);
            Database.SaveResult sr = saveResults[insertIdx];
            if (sr.isSuccess()) {
                results.set(i, new Result { success = true, trainingId = sr.getId(), errorMessage = null });
            } else {
                results.set(i, new Result { success = false, errorMessage = sr.getErrors()[0].getMessage() });
            }
        }
        return results;
    }

    private static Id getLiveTrainingRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Training__c'
            AND DeveloperName = :RECORD_TYPE_DEVELOPER_NAME
            AND IsActive = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Map<Id, Account> fetchAccounts(Set<Id> accountIds) {
        if (accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>([
            SELECT Id
            FROM Account
            WHERE Id IN :accountIds
            WITH SECURITY_ENFORCED
        ]);
    }

    private static Training__c buildTraining(Request req, Id recordTypeId) {
        Training__c t = new Training__c();
        t.Account__c = req.accountId;
        t.RecordTypeId = recordTypeId;
        t.Training_Stage__c = DEFAULT_STAGE;
        if (String.isNotBlank(req.trainingType)) {
            t.Training_Type__c = req.trainingType;
        }
        if (String.isNotBlank(req.trainingMethod)) {
            t.Training_Method__c = req.trainingMethod;
        }
        if (String.isNotBlank(req.product)) {
            t.Product__c = req.product;
        }
        return t;
    }
}
