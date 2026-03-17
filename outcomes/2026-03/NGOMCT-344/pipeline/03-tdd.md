# NGOMCT-344: TDD / BUILD

**Agent:** tdd-guide  
**Input:** 01-plan.md, 02-architecture.md

---

## RED Phase

Test class created first: `TrainingManualCreationServiceTest.cls`

| Test | Purpose |
|------|---------|
| createTraining_withValidAccount_createsRecord | AC1, AC2: Create with Account only; assert Training_Stage__c = Pending Assignment |
| createTraining_withOptionalFields_populatesCorrectly | AC3: Type, Method, Product populated |
| createTraining_withInvalidAccountId_returnsError | Null accountId returns error |
| createTraining_withNonExistentAccount_returnsError | Invalid Account Id returns error |
| createTraining_bulkHandlesMultipleRequests | Bulk: 5 requests, all succeed |

---

## GREEN Phase

Implementation: `TrainingManualCreationService.cls`

- Invocable method `createManualTraining(List<Request> requests)`
- Bulkified: single SOQL for RecordType, single SOQL for Accounts, single DML insert
- CRUD check: `Schema.sObjectType.Training__c.isCreateable()`
- SOQL: `WITH SECURITY_ENFORCED`
- Database.insert with allOrNone=false for per-record error handling
- Default RecordType: Live_Training; Training_Stage__c = Pending Assignment

---

## IMPROVE Phase

- Extracted `getLiveTrainingRecordTypeId()`, `fetchAccounts()`, `buildTraining()` helpers
- Result ordering preserved for bulk (Map requestIdxToInsertIdx)
- Error messages user-facing

---

## Files Created/Modified

| File | Action |
|------|--------|
| force-app/main/default/classes/TrainingManualCreationService.cls | Created |
| force-app/main/default/classes/TrainingManualCreationService.cls-meta.xml | Created |
| force-app/main/default/classes/TrainingManualCreationServiceTest.cls | Created |
| force-app/main/default/classes/TrainingManualCreationServiceTest.cls-meta.xml | Created |

---

## Deploy and Test

```bash
sf project deploy start --target-org orgsyncng --source-dir force-app/main/default/classes/ --test-level RunSpecifiedTests --tests TrainingManualCreationServiceTest --wait 15
```

**Note:** Deploy target is orgsyncng per salesforce-deployment skill. Run when org is authenticated.

---

## Decisions Made

- Implemented Apex Invocable (not pure Flow) for TDD and test coverage
- Flow can call this via Invocable Action
- Bulkification: single insert for all valid requests; per-result error mapping
