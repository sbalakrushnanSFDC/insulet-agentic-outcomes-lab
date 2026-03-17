# NGOMCT-344 — Feature Grooming: Manual Training Record Creation

**Author:** Som Balakrushnan  
**Feature:** Training Creation & Assignment — Manual Training Record Creation  
**Jira:** [NGOMCT-344](https://insulet.atlassian.net/browse/NGOMCT-344)  
**Date:** 2026-03-14  
**Iteration:** v1 (pipeline run 54bee681)  
© Som Balakrushnan

---

## 1. Feature Context & Selection Rationale

### What This Feature Does

Enable a CSM or Training Coordinator to manually initiate a `Training__c` record for a given consumer (Account) directly from the consumer's Account record. Training assignment logic (assigning a trainer) is handled by a downstream feature (NGOMCT-89) and is **out of scope**.

### Why NGOMCT-344 Was Prioritized

Three candidates were evaluated for Q1 2026 pipeline entry:

| Candidate | Summary | Status | Blocker Status | Downstream Impact |
|-----------|---------|--------|----------------|-------------------|
| **NGOMCT-344** | Manual Training Record Creation | FEATURE DEFINITION | NGOMCT-139 In Progress | Unblocks 4 features |
| NGOMCT-83 | Switch Training Group Type | Backlog | NGOMCT-24 Backlog (unresolved) | Deferred to Q1 2027 per NGCCB-10 |
| NGOMCT-139 | Order Management Setup | In Progress | N/A | Already underway |

**NGOMCT-344 selected because:**
- Primary blocker (NGOMCT-139) was already In Progress
- Labeled `2026Q1` — current quarter deliverable
- Unblocks NGOMCT-10, NGOMCT-54, NGONDL-60, NGMC-32
- FEATURE DEFINITION status ideal for a plan-first approach
- Cloned from NGOMCT-91 (Training Creation — From Direct Order), providing a validated sibling pattern

**NGOMCT-83 rejected** — its blocker (NGOMCT-24, Group Training scheduling) was still in Backlog, and NGCCB-10 explicitly deferred group training to Q1 2027.

### Dependency Map

```
Blocked by:  NGOMCT-139 (In Progress), NGOMCT-6 (Backlog), NGOMCT-240, NGASIM-263
Blocks:      NGOMCT-10, NGOMCT-54, NGONDL-60, NGMC-32
Related:     NGOMCT-91 (cloned from), NGOMCT-89 (assignment — out of scope)
```

---

## 2. Functional Requirements & Acceptance Criteria

> **Note:** Jira NGOMCT-344 contained no explicit AC. The following were derived from the Jira description, sibling feature NGOMCT-91, and Training__c metadata discovered from DevInt2. Confluence CON-13 ("Consumer trained on Insulet product", page_id: 135170258) was **not retrievable** due to authentication requirements — derived AC should be validated against it.

| ID | Acceptance Criterion | Traceability |
|----|---------------------|--------------|
| AC-1 | A CSM/Training Coordinator can manually initiate creation of a `Training__c` record for a given consumer (Account) | Jira: "manually initiate the training process for a given consumer" |
| AC-2 | The new record is created with minimum required fields: `Account__c` (consumer, required), `RecordTypeId` = `Live_Training` (default), `Training_Stage__c` = `Pending Assignment` | `Training__c` object schema; `Account__c` is MasterDetail (required) |
| AC-3 | `Training_Type__c`, `Training_Method__c`, and `Product__c` may be optionally specified at creation time | Jira assumption; NGOMCT-91 pattern |
| AC-4 | The created record enters the existing `Training_Stage__c` lifecycle without trainer assignment in this feature | `Training_Stage__c` picklist; NGOMCT-89 boundary |
| AC-5 | The entry point is reachable from the consumer Account record (Lightning Action → Flow) | CON-13 implied; NGOMCT-91 creates from Order context |

### Out of Scope

- **NGOMCT-89** — trainer assignment logic
- **NGOMCT-91** — training creation from Direct Order (separate path)
- **Group Training** (NGOMCT-24, NGOMCT-83) — different RecordType and flow path
- **E-Learning, CPT Training** — RecordTypes exist; manual creation may extend to them in a future iteration

---

## 3. Salesforce Data Model

### Training__c — Key Fields for NGOMCT-344

| Field | API Name | Type | Required | Notes |
|-------|----------|------|----------|-------|
| Consumer Account | `Account__c` | MasterDetail(Account) | Yes | Parent record; drives sharing via ControlledByParent |
| Record Type | `RecordTypeId` | RecordType | Yes | Default: `Live_Training` for CSM-initiated |
| Training Stage | `Training_Stage__c` | Picklist | Yes | Default: `Pending Assignment`; full lifecycle managed downstream |
| Training Type | `Training_Type__c` | Picklist | No | e.g. Pre-Pod, Insulin Start, Follow-Up |
| Training Method | `Training_Method__c` | Picklist | No | e.g. Live In-Person, Live Virtual |
| Product | `Product__c` | Picklist | No | e.g. Omnipod 5, DASH, UST400 |

### Training_Stage__c Lifecycle

```
New → Pending Assignment → Pending Acceptance → Accepted → Scheduled → In Progress → Completed
                ↑
         NGOMCT-344 sets this default
                                        ↑
                                   NGOMCT-89 manages everything from here
```

### Record Types

| Developer Name | Purpose | NGOMCT-344 Scope |
|----------------|---------|-----------------|
| `Live_Training` | CSM-initiated in-person or virtual | **Default for this feature** |
| `E_Learning` | Self-paced digital | Out of scope (v1) |
| `CPT_Training` | Certified Partner Trainer | Out of scope (v1) |

### Object Relationships

```
Account (consumer)
    └── Training__c (MasterDetail — sharing ControlledByParent)
            ├── RecordType: Live_Training
            ├── Training_Stage__c = "Pending Assignment"
            ├── Training_Type__c (optional)
            ├── Training_Method__c (optional)
            └── Product__c (optional)
```

### Pre-existing Automation on Training__c (Context — Not Modified)

| Construct | Type | Notes |
|-----------|------|-------|
| `Training_After_Save` | Record-Triggered Flow | Fires on Training__c save; behavior on new record should be verified before deploying NGOMCT-344 |
| `TrainingTrigger` + `TrainingTriggerHandler` | Apex Trigger | Pre-existing; not modified by this feature |
| 9 Validation Rules | Validation Rules | Relevant rule: `Check_Training_Completion` — fires on stage transition; does not fire at `Pending Assignment` |

---

## 4. Architectural Decision: Flow vs. Apex Invocable

### Options Evaluated

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| A: Screen Flow | Declarative; Flow creates `Training__c` directly | Low code, easy to modify, built-in error handling | Not unit-testable in Apex; limited coverage verification |
| B: LWC + Apex Controller | Custom UI + `@AuraEnabled` controller | Full TDD, type-safe | Higher build cost |
| **C: Apex Invocable + Screen Flow** | Apex `@InvocableMethod` handles DML; Screen Flow calls it | TDD-compliant, 80%+ coverage, Flow-friendly | Slightly more code than pure Flow |

### Decision: Option C — Apex Invocable

- TDD mandate requires 80%+ Apex test coverage; pure Flow cannot satisfy this
- `@InvocableMethod` allows a Screen Flow (to be built in follow-up) to call the service without LWC
- Keeps logic testable, bulkification enforced in Apex, and UI layer in Flow (declarative)
- `TrainingManualCreationService.cls` is the **core deliverable of this pipeline run**
- The Screen Flow (`Manual_Training_Creation`) and Lightning Action (`Create_Training` on Account) are **deferred** — see Known Gaps

---

## 5. Implementation: TrainingManualCreationService

**File:** `solution/metadata/classes/TrainingManualCreationService.cls` [NEW]  
**Test:** `solution/metadata/classes/TrainingManualCreationServiceTest.cls` [NEW]

### Service Contract

```apex
@InvocableMethod(label='Create Manual Training' description='Creates a Training record for a consumer (NGOMCT-344)')
public static List<Result> createManualTraining(List<Request> requests)
```

**Request inputs:**

| Variable | Type | Required | Maps To |
|----------|------|----------|---------|
| `accountId` | Id | Yes | `Training__c.Account__c` |
| `trainingType` | String | No | `Training__c.Training_Type__c` |
| `trainingMethod` | String | No | `Training__c.Training_Method__c` |
| `product` | String | No | `Training__c.Product__c` |

**Result outputs:**

| Variable | Type | Description |
|----------|------|-------------|
| `success` | Boolean | `true` if record created |
| `trainingId` | Id | Id of created `Training__c` |
| `errorMessage` | String | User-facing message if `success = false` |

### Key Design Choices

| Choice | Rationale |
|--------|-----------|
| Bulkified single DML insert | Governor limit compliance; Flow may call with multiple requests |
| `Schema.sObjectType.Training__c.isCreateable()` | CRUD check before DML |
| `WITH SECURITY_ENFORCED` on all SOQL | FLS enforcement at query level |
| `Database.insert(records, allOrNone=false)` | Per-record error reporting; partial success supported |
| RecordType queried by `DeveloperName = 'Live_Training'` | Org-safe; avoids hardcoded RecordType Ids |
| `Training_Stage__c = 'Pending Assignment'` | Enters lifecycle at NGOMCT-89 handoff point |

### Test Coverage

| Test Method | AC Covered |
|-------------|-----------|
| `createTraining_withValidAccount_createsRecord` | AC-1, AC-2 |
| `createTraining_withOptionalFields_populatesCorrectly` | AC-3 |
| `createTraining_withInvalidAccountId_returnsError` | Error handling |
| `createTraining_withNonExistentAccount_returnsError` | Error handling |
| `createTraining_bulkHandlesMultipleRequests` | Bulkification, AC-1, AC-2 |

---

## 6. Quality & Security Assessment

### Code Review Results (0 CRITICAL, 0 HIGH)

| Severity | Finding | Resolution |
|----------|---------|-----------|
| MEDIUM | FLS not enforced at DML level (object-level CRUD only) | Accepted for v1; `Security.stripInaccessible()` recommended before production for lower-privilege profiles |
| LOW | Placeholder string `'Pending'` as inline literal | Fixed in CLEAN step — replaced with named constant `PLACEHOLDER_ERROR` |
| LOW | Test SOQL without `WITH SECURITY_ENFORCED` | Acceptable in `@IsTest` context |

### Security Checklist

| Check | Status |
|-------|--------|
| SOQL injection | Pass — no dynamic SOQL |
| CRUD check before DML | Pass — `isCreateable()` |
| FLS on SOQL | Pass — `WITH SECURITY_ENFORCED` |
| No hardcoded secrets | Pass |
| Input validation | Pass — null `accountId` handled; Account existence validated via SOQL |
| Error messages | Pass — user-facing only; no stack traces exposed |

### Pre-Production Recommendation

Before deploying to production: confirm `Training__c` create permission is restricted to appropriate profiles/permission sets. The Flow entry point (when built) should enforce the same permission context.

---

## 7. Planned Constructs Not Built (Follow-Up Required)

The following were specified in the implementation plan but **deferred** — the feature is not end-to-end deployable without them:

| Construct | Type | Status | AC Dependency |
|-----------|------|--------|---------------|
| `Manual_Training_Creation` Screen Flow | Flow | **NOT BUILT** | AC-1, AC-2, AC-3, AC-5 |
| `Create_Training` Lightning Action on Account | Object Action | **NOT BUILT** | AC-5 |
| Account Record Page FlexiPage update | FlexiPage | **NOT BUILT** | AC-5 |

### Planned Flow Specification (Manual_Training_Creation)

When built, the Flow should implement:

1. **Input variables:** `varAccountId` (Text, Input), `varTrainingType` (optional), `varTrainingMethod` (optional), `varProduct` (optional)
2. **Get Records:** Validate Account by Id
3. **Action:** Call `TrainingManualCreationService.createManualTraining` via Invocable Action
4. **Decision:** Check `{!result.success}`
5. **Navigate:** To new Training record if success
6. **Screen (error):** Display `{!result.errorMessage}` and allow retry
7. **Output variables:** `varTrainingId` (Text, Output), `varErrorMessage` (Text, Output)

---

## 8. Known Gaps for Reviewers

| Gap | Severity | Impact |
|-----|----------|--------|
| Feature is **partially implemented** — Apex Invocable built but Flow/Action/FlexiPage not built | Critical | Not deployable as an end-to-end user feature; requires follow-up pipeline run |
| Confluence CON-13 body not retrieved (authentication required) | Medium | Derived AC not validated against definitive business process documentation |
| E2E validation was a paper exercise — SF CLI auth issue on orgsyncng prevented live deployment | High | Unit tests pass in theory; actual org deployment not confirmed |
| `Training_Stage__c` default value (`Pending Assignment`) inferred, not confirmed in CON-13 | Medium | If incorrect, created records will not enter NGOMCT-89 assignment queue |
| `Training_After_Save` Flow behavior on new record not verified | Medium | Pre-existing automation may conflict with manual creation; needs org testing |
