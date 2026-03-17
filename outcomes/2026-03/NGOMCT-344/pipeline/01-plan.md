# NGOMCT-344: Implementation Plan

**Agent:** planner  
**Source:** Jira NGOMCT-344, Confluence CON-13 (unavailable - auth required), DevInt2 Training__c discovery, NGOMCT-91

---

## 1. Derived Acceptance Criteria

| ID | Criterion | Traceability |
|----|-----------|---------------|
| AC1 | A user (CSM/Training Coordinator) can initiate manual creation of a Training record for a given consumer (Account). | Jira: "manually initiate the training process for a given consumer" |
| AC2 | The new Training record is created with minimum required fields: Account__c (consumer), RecordType (Live_Training default), Training_Stage__c = "New" or "Pending Assignment". | Training__c object; Account__c is MasterDetail (required) |
| AC3 | Training Type, Training Method, and Product may be specified at creation; assignment logic is out of scope (NGOMCT-89). | Jira assumption; NGOMCT-91 pattern |
| AC4 | The created record enters the existing training lifecycle (Pending Assignment → Pending Acceptance → ...) without manual assignment in this feature. | Training_Stage__c picklist; NGOMCT-89 boundary |
| AC5 | Entry point is reachable from the consumer Account record (Create Training action). | CON-13 implied; NGOMCT-91 creates from Order context |

---

## 2. Salesforce Metadata Impact

### Objects (already in force-app from retrieve)

| Object | Action | Notes |
|--------|--------|-------|
| Training__c | Use | Exists; Account__c MasterDetail; RecordTypes: Live_Training, E_Learning, CPT_Training |

### New/Create

| Type | Full Name | Purpose |
|------|-----------|---------|
| Screen Flow | Manual_Training_Creation | Collect consumer, type, method, product; create Training__c |
| Lightning Action | Create_Training (Action type: Flow) | Add to Account page layout; launches Manual_Training_Creation |
| FlexiPage | Account Record Page update | Add Create Training action to Actions |

### Retrieve (if not present)

- Account object layout(s) for Live Training / CSM use case
- Training__c page layout (Live Training Layout) — already retrieved

---

## 3. Files to Create

| Path | Description |
|------|-------------|
| `force-app/main/default/flows/Manual_Training_Creation.flow-meta.xml` | Screen flow: record-create for Training__c |
| `force-app/main/default/objects/Account/objectActions/Create_Training.objectAction-meta.xml` | Lightning Action (Flow) |

### Flow Design (Manual_Training_Creation)

1. **Input**: AccountId (from record or screen), optional: Training_Type__c, Training_Method__c, Product__c
2. **Get Record**: Account by Id (validate)
3. **Create Record**: Training__c with:
   - Account__c = {!AccountId}
   - RecordTypeId = Live_Training (query for Id)
   - Training_Stage__c = "Pending Assignment"
   - Training_Type__c, Training_Method__c, Product__c = user input (optional)
4. **Navigate**: To new Training record
5. **Error**: Display message, allow retry

---

## 4. Test Cases (TDD)

| # | Test | Expected |
|---|------|----------|
| T1 | Create Training with required Account only | Training__c created; Training_Stage__c = Pending Assignment |
| T2 | Create Training with optional Type, Method, Product | Fields populated correctly |
| T3 | Create Training with invalid Account Id | Graceful error, no DML |
| T4 | Flow launched from Account record | AccountId pre-populated |
| T5 | Bulk: Create multiple trainings for different Accounts | No governor limit violations (Flow limits) |

**Note:** If Flow is chosen, unit tests apply to any supporting Apex. Flow testing is manual/automated via UI. If Apex controller is used instead, full TDD applies.

---

## 5. Risk Areas and Mitigations

| Risk | Mitigation |
|------|------------|
| Live_Training RecordTypeId varies by org | Query RecordType by DeveloperName in Flow; use Get Records |
| Account record may have multiple trainings already | No validation in scope; assignment logic (NGOMCT-89) may handle duplicates |
| Flow governor limits (DML rows, etc.) | Single-record create; minimal SOQL |
| CON-13 business rules unknown | Derived from Training__c metadata; CON-13 to be reviewed when accessible |

---

## 6. Phase Breakdown

### Phase 1: Flow + Action (Core)

1. Create Manual_Training_Creation flow (Screen flow, record create)
2. Create Create_Training Lightning Action on Account
3. Add action to Account record page (FlexiPage)
4. Manual test: Create training from Account

### Phase 2: Validation & Edge Cases

1. Add error handling for invalid Account
2. Add optional field support (Type, Method, Product)
3. Document for CSM/Training Coordinator personas

### Phase 3: Integration Readiness

1. Ensure Training_Stage__c = "Pending Assignment" triggers NGOMCT-89 assignment (no code change if assignment is stage-based)
2. Verify with Product Owner on CON-13 once accessible

---

## 7. Out of Scope

- **NGOMCT-89**: Training assignment logic (assigning a trainer)
- **NGOMCT-91**: Creating training from Direct Order (separate feature)
- **Group Training**: NGOMCT-24, NGOMCT-83 (different record type/path)
- **E-Learning, CPT Training**: Record types exist; manual creation could extend to them in future iteration

---

## 8. Decisions Made

| Decision | Rationale |
|----------|-----------|
| Use Screen Flow over LWC | Lower complexity; no Apex for simple create; declarative first |
| Default RecordType = Live_Training | Most common for CSM-initiated consumer training |
| Training_Stage__c = "Pending Assignment" | Puts record in queue for NGOMCT-89 without manual assignment |
| Entry from Account | Consumer is Account; Create Training from consumer record |

---

## 9. Handoff to Architect

- Confirm Flow vs LWC+Apex for scalability and testability
- Validate RecordType and field defaults
- Identify any platform events or automation that fire on Training__c create
