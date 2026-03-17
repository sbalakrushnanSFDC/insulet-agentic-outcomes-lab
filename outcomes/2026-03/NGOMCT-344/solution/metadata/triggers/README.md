# Triggers — NGOMCT-344

No Apex triggers were created or modified for NGOMCT-344.

The pre-existing `TrainingTrigger.trigger` + `TrainingTriggerHandler.cls` fire on `Training__c` DML operations. These were retrieved from DevInt2 as context and reviewed by the architecture step to confirm no conflicts with the manual creation path. They were **not modified** by this feature.

The `OrgSync_TrainingStagingTrigger.trigger` is unrelated to NGOMCT-344.
