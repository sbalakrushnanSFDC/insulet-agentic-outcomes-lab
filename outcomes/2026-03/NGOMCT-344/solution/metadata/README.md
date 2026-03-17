# Salesforce Metadata — NGOMCT-344

**Author:** Som Balakrushnan  
**Feature:** NGOMCT-344 — Manual Training Record Creation  
© Som Balakrushnan

This folder contains the Salesforce metadata constructs associated with NGOMCT-344, classified by status.

---

## Classification Key

| Tag | Meaning |
|-----|---------|
| **[NEW]** | Created by the NGOMCT-344 pipeline run; did not exist before |
| **[RETRIEVED]** | Pre-existing in DevInt2; retrieved read-only for context; **not modified** |
| **[PLANNED — NOT BUILT]** | Specified in the implementation plan; deferred to follow-up |

---

## Contents

### `classes/` — Apex

| File | Tag | Description |
|------|-----|-------------|
| `TrainingManualCreationService.cls` | **[NEW]** | Invocable service: creates `Training__c` for a consumer Account |
| `TrainingManualCreationService.cls-meta.xml` | **[NEW]** | API version metadata |
| `TrainingManualCreationServiceTest.cls` | **[NEW]** | TDD test class — 5 test methods covering all 5 ACs |
| `TrainingManualCreationServiceTest.cls-meta.xml` | **[NEW]** | API version metadata |

### `objects/Training__c/` — Custom Object

| File | Tag | Description |
|------|-----|-------------|
| `Training__c.object-meta.xml` | **[RETRIEVED]** | Full object definition; confirms `Account__c` MasterDetail, sharing model |
| `fields/Account__c.field-meta.xml` | **[RETRIEVED]** | Required MasterDetail field; used in Apex |
| `fields/Training_Stage__c.field-meta.xml` | **[RETRIEVED]** | Picklist; `Pending Assignment` default confirmed here |
| `fields/Training_Type__c.field-meta.xml` | **[RETRIEVED]** | Optional input; used in Apex |
| `fields/Training_Method__c.field-meta.xml` | **[RETRIEVED]** | Optional input; used in Apex |
| `fields/Product__c.field-meta.xml` | **[RETRIEVED]** | Optional input; used in Apex |
| `recordTypes/Live_Training.recordType-meta.xml` | **[RETRIEVED]** | Default RecordType queried by `DeveloperName` in Apex |

### `flows/` — Salesforce Flows

| File | Tag | Description |
|------|-----|-------------|
| `Manual_Training_Creation.flow-spec.md` | **[PLANNED — NOT BUILT]** | Screen Flow specification; calls Invocable; entry point from Account record. Required for AC-5 and end-to-end deployment. |

### `lwc/` — Lightning Web Components

See `lwc/README.md` — no LWC components were created for this feature.

### `triggers/` — Apex Triggers

See `triggers/README.md` — no triggers were created or modified for this feature.

---

## Deployment Readiness

| Layer | Status |
|-------|--------|
| Apex Invocable (`TrainingManualCreationService`) | Ready — built, tested, linter-clean |
| Screen Flow (`Manual_Training_Creation`) | **Not ready — not built** |
| Lightning Action (`Create_Training` on Account) | **Not ready — not built** |
| FlexiPage update (Account record page) | **Not ready — not built** |

The feature **cannot be triggered by an end user** until the Flow, Action, and FlexiPage are implemented in a follow-up pipeline run. The Apex layer is independently deployable and testable.
