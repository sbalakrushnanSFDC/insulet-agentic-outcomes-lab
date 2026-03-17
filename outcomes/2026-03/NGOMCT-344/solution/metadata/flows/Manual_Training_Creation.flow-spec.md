# Flow Specification: Manual_Training_Creation

**Author:** Som Balakrushnan  
**Feature:** NGOMCT-344 — Manual Training Record Creation  
© Som Balakrushnan

**Status:** [PLANNED — NOT BUILT]  
This Screen Flow was designed during the ARCH and PLAN pipeline steps but was **not implemented** in the v1 pipeline run. The Apex Invocable (`TrainingManualCreationService`) it would call has been built and tested. This file documents the specification for a follow-up implementation.

---

## Purpose

A Salesforce Screen Flow that provides the user interface for creating a `Training__c` record manually from a consumer Account record. It calls `TrainingManualCreationService` via an Invocable Action and navigates to the newly created record on success.

---

## Flow Variables

| Variable | Type | Direction | Description |
|----------|------|-----------|-------------|
| `varAccountId` | Text | Input | Id of the consumer Account record; pre-populated when launched from Account |
| `varTrainingType` | Text | Input (optional) | `Training_Type__c` API value selected by user |
| `varTrainingMethod` | Text | Input (optional) | `Training_Method__c` API value selected by user |
| `varProduct` | Text | Input (optional) | `Product__c` API value selected by user |
| `varTrainingId` | Text | Output | Id of the created `Training__c` record |
| `varErrorMessage` | Text | Output | Error message displayed if creation fails |

---

## Flow Steps

```
[Start: Record-triggered or Quick Action on Account]
        │
        │ varAccountId pre-populated
        ▼
[Screen 1: Training Details]
    - Training Type (picklist, optional)
    - Training Method (picklist, optional)
    - Product (picklist, optional)
        │
        ▼
[Action: Create Manual Training]
    Invocable: TrainingManualCreationService.createManualTraining
    Input: accountId = {!varAccountId}
           trainingType = {!varTrainingType}
           trainingMethod = {!varTrainingMethod}
           product = {!varProduct}
    Output: success, trainingId, errorMessage
        │
        ├── [Decision: success = true]
        │       │
        │       ▼
        │   [Navigate to Record: varTrainingId]
        │
        └── [Decision: success = false]
                │
                ▼
            [Screen 2: Error Display]
                Message: {!varErrorMessage}
                [Retry] button → back to Screen 1
```

---

## Entry Point

- **Object:** Account
- **Type:** Quick Action (Flow) or Lightning Action
- **Action Name:** `Create_Training` (to be created on Account object)
- **Page Layout:** Add to Account Record Page via FlexiPage update

---

## Acceptance Criteria Covered by This Flow

| AC | How |
|----|-----|
| AC-1 | User initiates from Account record; Flow collects input and calls service |
| AC-2 | Invocable sets required fields (Account, RecordType, Stage = Pending Assignment) |
| AC-3 | Screen 1 collects optional Type, Method, Product |
| AC-5 | Entry point is the Account record page |

---

## Implementation Notes

- RecordType and Stage defaults are handled in the Apex layer — no Flow variable needed
- Flow should enforce `with sharing` context; user must have Account read + Training__c create
- On successful creation, navigate directly to the new Training record (avoids CSM having to search)
- `Training_After_Save` pre-existing Flow will fire after insert — verify no conflicts with `Pending Assignment` stage
