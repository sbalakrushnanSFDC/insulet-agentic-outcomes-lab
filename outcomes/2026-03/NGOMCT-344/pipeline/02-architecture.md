# NGOMCT-344: Architecture

**Agent:** architect  
**Input:** 01-plan.md, Training__c metadata from DevInt2

---

## 1. Data Model

### Training__c (Consumer Training)

```
Training__c
├── Account__c (MasterDetail → Account) [REQUIRED]
├── Name (AutoNumber TRN-{0000})
├── RecordTypeId → Live_Training | E_Learning | CPT_Training
├── Training_Stage__c (Picklist, default: New)
│   └── New → Pending Assignment → Pending Acceptance → Accepted → Scheduled → In Progress → Completed
├── Training_Type__c (Pre-Pod, Insulin Start, Follow-Up, etc.)
├── Training_Method__c (Live In-Person, Live Virtual)
├── Product__c (DASH, Omnipod 5, UST400)
├── Internal_Trainer__c, External_Trainer__c (assignment - NGOMCT-89)
└── [40+ other fields for scheduling, completion, reimbursement]
```

### Relationship Diagram

```mermaid
erDiagram
    Account ||--o{ Training__c : "has"
    Training__c }o--|| RecordType : "uses"
    User ||--o{ Training__c : "Internal_Trainer"
    User ||--o{ Training__c : "External_Trainer"
    Training__c }o--|| Practice__c : "optional"
    Training__c }o--|| Product__c : "optional"
    Account : Id
    Account : Name
    Training__c : Account__c
    Training__c : Training_Stage__c
    Training__c : RecordTypeId
```

---

## 2. Manual Creation Flow - Architecture

### Option A: Screen Flow (Recommended)

```
[Account Record] --> [Create Training Action] --> [Manual_Training_Creation Flow]
                                                          |
                                                          v
                                              [Screen: Select Type, Method, Product]
                                                          |
                                                          v
                                              [Create Training__c]
                                                          |
                                                          v
                                              [Navigate to Training Record]
```

**Pros:** Declarative, no Apex, easy to modify, built-in error handling  
**Cons:** Flow testing is manual/UI; limited unit test coverage

### Option B: LWC + Apex Controller

```
[Account Record] --> [Create Training LWC] --> [Apex: TrainingCreationService.createManualTraining()]
                                                          |
                                                          v
                                              [Training__c insert]
```

**Pros:** Full TDD, 80%+ Apex coverage, bulkification possible  
**Cons:** More code, longer build

### Decision: Option A (Flow)

- Scope is single-record creation; no bulk scenario in NGOMCT-344
- Flow aligns with "process and ability to manually create" (Jira)
- Faster delivery; Apex can be added if Flow limits hit

---

## 3. Object Relationships

| Relationship | Type | Notes |
|--------------|------|-------|
| Training__c → Account | MasterDetail | Consumer is Account (Person Account or standard) |
| Training__c → User (Internal_Trainer__c) | Lookup | Assigned by NGOMCT-89 |
| Training__c → User (External_Trainer__c) | Lookup | CPT/3PT assignment |
| Training__c → Practice__c | Lookup | Optional; clinic context |
| Training__c → RecordType | System | Live_Training for manual creation |

---

## 4. API Design (Flow Variables)

| Variable | Type | Input/Output | Description |
|----------|------|--------------|-------------|
| varAccountId | Text | Input | Id of consumer Account |
| varTrainingType | Text | Input (optional) | Training_Type__c API value |
| varTrainingMethod | Text | Input (optional) | Training_Method__c API value |
| varProduct | Text | Input (optional) | Product__c API value |
| varTrainingId | Text | Output | Id of created Training__c |
| varErrorMessage | Text | Output | Error message for display |

---

## 5. Scalability

| Concern | Mitigation |
|---------|------------|
| Flow interview limit | Single create per run; no loop |
| DML rows | 1 record per execution |
| SOQL | 2 max: RecordType lookup, Account validate |
| Concurrent users | Flow is stateless; no shared state |
| Future: Bulk create | Out of scope; consider Apex if needed |

---

## 6. Platform Events / Automation

**Pre-existing (from Training__c):**

- Field history on Training__c
- Validation rules: Scheduled_Date_Not_In_Past, Training_Time_Zone_Required, etc.
- Possible Process Builder/Flow on Training__c create (to be verified in org)

**This feature:**

- No new triggers or processes
- Flow creates record; standard automation applies

---

## 7. Security

| Layer | Consideration |
|-------|---------------|
| CRUD/FLS | Flow Create Record respects user's Training__c create permission |
| Sharing | ControlledByParent (Account); user must have Account access |
| Entry point | Account object action; user needs Account read + Training create |

---

## 8. Handoff to TDD/BUILD

- Implement Manual_Training_Creation flow per 01-plan.md
- Create Create_Training Lightning Action on Account
- If Flow proves insufficient, introduce Apex `TrainingCreationService` with full test coverage
