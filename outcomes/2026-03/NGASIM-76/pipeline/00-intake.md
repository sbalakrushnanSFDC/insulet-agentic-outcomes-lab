# NGASIM-76: INTAKE

> **Pipeline Stage:** 00-intake
> **Produced by:** orchestrator agent
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:30:00Z
> **Status:** COMPLETE — handed off to PLAN

---

## Feature Metadata

| Field | Value |
|---|---|
| Key | NGASIM-76 |
| Summary | Incoming & outgoing calls handling for Lead & Consumer by Inside Sales (CTI) |
| Type | Feature |
| Status | Feature Ready |
| Priority | Highest |
| Assignee | Eric Manzi |
| Reporter | Kyle Wiant |
| Labels | 2026Q1, AI, AmazonConnect, CON-6, DIS-1, DirectIntegration, JanWorkshop, LEAD-1, LEAD-2, LEAD-3, NGASIM, NGPI1, NGPI2, NextGen, PRJ0717, Tableau, Team2 |
| Fix Versions | Project Infinity SOW MVP, Project Infinity Persona Release 1 |
| Child Stories | 16 (0 Done, 2 To Verify, 7 To Do, 4 Technical Refinement, 2 Cancelled, 1 Other) |
| Linked Issues | NGPSTE-132 (blocked by), NGPSTE-51 (relates), NGPSTE-888 (blocked by), NGCRMI-123 (duplicated by), NGCRMI-2007 (relates) |

## Description (verbatim from Jira)

> **Feature Description:**
> The purpose of this feature is to allow Inside Sales reps to engage with Consumers/Leads via phone.
>
> **Benefit Hypothesis:**
> We believe this feature will enable Inside Sales reps to engage with Consumers/Leads who prefer phone to alternative contact mediums, driving increased new customer acquisition.
>
> **Feature Source:**
> Capability Excel Spreadsheet

### Key Phrases Extracted

1. **"Inside Sales reps"** — Primary persona: Inside Sales (not Customer Care/Product Support as in NGPSTE-132). Different routing, queues, and agent profiles required.
2. **"Consumers/Leads"** — Target objects are Lead and a custom Consumer/Patient entity, not just Contact. Screen pop must resolve across multiple objects.
3. **"engage via phone"** — Both inbound and outbound call handling required.
4. **"increased new customer acquisition"** — Business KPI: call-to-conversion rate for Inside Sales.

---

## Child Story Decomposition

| Key | Summary | Status | Type | Assignee | Implications |
|---|---|---|---|---|---|
| NGPSTE-531 | Set up Sales Queues (group of users) in Infinity | **Cancelled** | Story | — | Queue setup for Inside Sales cancelled. May indicate queue config moved elsewhere or deferred. |
| NGPSTE-532 | Inbound Call: Screen Pop w/ Relevant Info | **Technical Refinement** | Story | Greg Cameron | Core screen pop for inbound calls. Searches on Patient Phone fields. Linked to NGPSTE-536 (call logging). |
| NGPSTE-533 | SSO Login to CTI from within Salesforce | **To Verify** | Story | Eric Manzi | SSO/SAML integration for Amazon Connect CCP. Blocked by NGASIM-1523 (recording opt-out). |
| NGPSTE-534 | Inbound Call: HCP / Provider / Physician | **To Do** | Story | — | Inbound calls from healthcare providers. Separate routing/screen pop logic vs consumer calls. |
| NGPSTE-535 | Outbound Calls: Click to Dial | **Technical Refinement** | Story | Greg Cameron | Click-to-dial configuration. Detailed Softphone Layout setup in description. |
| NGPSTE-536 | Automating a Call Log (Activity) | **Technical Refinement** | Story | Greg Cameron | Auto-create Task record on call completion. Task→Contact (WhoId) + Case/Opportunity (WhatId). Critical for activity tracking. |
| NGPSTE-538 | Agent Status (Set in Amazon CTI) + Call Disposition | **Technical Refinement** | Story | Greg Cameron | Agent status management in Connect. Pain point: reps limited to 8 inbound calls/day, need status flexibility. Linked to NGPSTE-536. |
| NGPSTE-708 | Call Transfers | **Technical Refinement** | Story | Greg Cameron | Warm/cold transfer between agents. Blocked by NGPSTE-1123. Pain point: difficult multi-party merging. |
| NGPSTE-809 | Define/Configure quick connect within Amazon Connect for Sales | **To Do** | Story | — | Quick connect buttons for rapid transfer to common destinations. |
| NGPSTE-811 | Access/View Voice Mails for Sales Teams | **To Do** | Story | — | Voicemail access from within Salesforce for Sales users. |
| NGASIM-1523 | Stop Recording when Patient opts out | **To Verify** | Story | Eric Manzi | Call/screen recording pause/stop when patient declines. Blocks NGPSTE-533. Active TTEC ticket. |
| NGASIM-1524 | Ensure Insulet's Phone Number is not marked as spam | **To Do** | Story | Dave Finstein | Outbound caller ID reputation management. Calls being dropped or flagged as spam. |
| NGASIM-1525 | Ability to determine true connections | **To Do** | Story | — | Differentiate real connections from voicemails. Current threshold: >90s = connection. Analytics/reporting concern. |
| NGASIM-1526 | Differentiate types of inbound calls | **To Do** | Story | — | Cannot distinguish inbound call types (new member vs transfer). IVR/queue redesign needed with TTEC. |
| NGASIM-1527 | Configure IS Reps with proper software, extensions, etc. | **To Do** | Story | — | Onboarding gap: Maestro + Chrome extension + screen recording tools not auto-configured for new hires. |
| NGASIM-2549 | NFR for NGASIM-76 | **Cancelled** | Story | — | Non-functional requirements cancelled. Contains performance targets (page load <3s, API <2s, 1000 concurrent users). |

### Completion Summary

- **Done:** 0 of 16 (0%)
- **To Verify:** 2 of 16 (13%)
- **Technical Refinement:** 4 of 16 (25%)
- **To Do:** 7 of 16 (44%)
- **Cancelled:** 2 of 16 (13%)
- **Other:** 1 of 16 (6%)
- **Net completion (Done+ToVerify / non-cancelled):** 2 of 14 (14%)

---

## Requirements Extraction

NGASIM-76 (parent Feature) has no formal acceptance criteria. Requirements are derived from child story descriptions, the feature description, linked feature NGPSTE-132, and the Inside Sales persona context.

### Functional Requirements

| ID | Requirement | Source |
|---|---|---|
| FR-01 | Inside Sales reps must receive inbound calls via Lightning softphone from Leads and Consumers | Feature description, NGPSTE-532 |
| FR-02 | Inbound screen pop must resolve caller to existing Lead or Patient record based on ANI | NGPSTE-532 (search on Patient Phone fields) |
| FR-03 | Inbound calls from HCPs/Providers must be identified and routed separately from consumer calls | NGPSTE-534 |
| FR-04 | Inside Sales reps must initiate outbound click-to-dial calls from Lead, Contact, and Patient records | Feature description, NGPSTE-535 |
| FR-05 | SSO login to Amazon Connect CCP must work from within Salesforce Lightning | NGPSTE-533 |
| FR-06 | A Task (Activity) record must be auto-created on call completion with agent, Contact WhoId, and Case/Opportunity WhatId | NGPSTE-536 |
| FR-07 | Agent status (Available, Busy, ACW, custom) must be settable from within the CTI adapter | NGPSTE-538 |
| FR-08 | Call disposition must be captured on Task record at call end | NGPSTE-538 |
| FR-09 | Warm and cold call transfers between agents must be supported via softphone controls | NGPSTE-708 |
| FR-10 | Quick connect buttons must be configured for rapid transfer to common Inside Sales destinations | NGPSTE-809 |
| FR-11 | Inside Sales reps must be able to access and listen to voicemails from within Salesforce | NGPSTE-811 |
| FR-12 | Recording must stop/pause when a patient verbally opts out of call/screen recording | NGASIM-1523 |
| FR-13 | Insulet outbound phone numbers must not be flagged as spam by carrier networks | NGASIM-1524 |
| FR-14 | System must differentiate true connections from voicemails/abandoned calls for reporting | NGASIM-1525 |
| FR-15 | Inbound call types (new member, transfer, callback) must be distinguishable in reporting | NGASIM-1526 |
| FR-16 | New Inside Sales rep onboarding must include automated CTI software/extension configuration | NGASIM-1527 |

### Non-Functional Requirements (derived from cancelled NGASIM-2549)

| ID | Requirement | Source |
|---|---|---|
| NFR-01 | Page load time < 3 seconds | NGASIM-2549 (cancelled but requirements captured) |
| NFR-02 | Record save time < 2 seconds | NGASIM-2549 |
| NFR-03 | API response time < 2s average, < 5s maximum | NGASIM-2549 |
| NFR-04 | Support 1000 concurrent agent sessions | NGASIM-2549 |
| NFR-05 | Handle 2-3x data volume growth with <= 10% performance degradation | NGASIM-2549 |
| NFR-06 | Screen pop latency < 2 seconds from ring to record display | Industry standard CTI UX |

---

## Dependency Map

| Link Type | Key | Summary | Status | Impact |
|---|---|---|---|---|
| is blocked by | NGPSTE-132 | Integrate Amazon Connect with NextGen | Feature Ready | **Critical upstream dependency.** CTI adapter installation, package configuration, and Omni-Channel routing are prerequisites. NGPSTE-132 pipeline run completed with ACCEPT_WITH_CAVEATS. |
| is blocked by | NGPSTE-888 | R2: Integrate Amazon Connect with NextGen | Backlog | Persona Release 2 extension. Decisions made here constrain R2 scope. |
| relates to | NGPSTE-51 | Summarize Voice and Video Calls with AI (Einstein Conversation Insights) | Backlog | Future AI capability that depends on CTI call recordings being available. Low priority, no immediate impact. |
| is duplicated by | NGCRMI-123 | Lead Engagement via Phone | **Cancelled** | Duplicate feature in NGCRMI project was cancelled. Confirms NGASIM-76 is the canonical feature. |
| relates to | NGCRMI-2007 | Tasks - OrgSync | Feature Refinement | Task synchronization between Classic and Lightning orgs. NGPSTE-536 (call logging as Task) creates data that must sync. |

### Dependency on NGPSTE-132

NGASIM-76 is explicitly blocked by NGPSTE-132 (Amazon Connect NextGen integration). The NGPSTE-132 pipeline run (completed 2026-03-25) established:

- **ADR-001:** Use ACLightningAdapter (OOB) — the same adapter serves both Care and Inside Sales
- **ADR-002:** Open CTI over SCV — same architectural decision applies here
- **ADR-003:** Omni-Channel routing via sfdc_phone — Inside Sales needs its own routing configuration
- **ADR-004:** Extend existing permission sets — Inside Sales needs its own PSG variant

The key **delta** for NGASIM-76 vs NGPSTE-132 is:
1. **Persona:** Inside Sales reps (not Customer Care) — different profiles, queues, routing rules
2. **Objects:** Lead + Patient/Consumer (not just Contact/Case) — screen pop must search across more objects
3. **Capabilities:** Call logging as Task, call disposition, call transfers, voicemail — beyond basic CTI
4. **Volume:** Inside Sales has an 8-call/day target per rep — different capacity model than Care

### Internal Dependency Map (Child Stories)

```
NGPSTE-533 (SSO Login)
  └── blocked by NGASIM-1523 (Recording Opt-out)

NGPSTE-708 (Call Transfers)
  └── blocked by NGPSTE-1123 (Classic Dev Package Part 3)

NGPSTE-532 (Screen Pop)
  └── relates to NGPSTE-536 (Call Logging)

NGPSTE-538 (Agent Status)
  └── relates to NGPSTE-536 (Call Logging)
```

---

## Risk Register (Intake-Level)

| ID | Risk | Probability | Impact | Category |
|---|---|---|---|---|
| R-01 | No formal acceptance criteria on parent Feature | High | High | Quality |
| R-02 | 0% of child stories in Done status — feature is early in implementation | High | High | Delivery |
| R-03 | NGPSTE-132 upstream dependency — CTI infrastructure not yet deployed to target org | High | Critical | Dependency |
| R-04 | NFR story (NGASIM-2549) cancelled — performance targets not formally validated | Medium | High | Quality |
| R-05 | 7 of 16 child stories still in To Do — significant scope remaining | High | High | Scope |
| R-06 | Screen pop must resolve across Lead + Patient (not just Contact) — multi-object complexity | Medium | Medium | Technical |
| R-07 | Call disposition and Task auto-creation require custom Apex/Flow — more code than NGPSTE-132 | Medium | High | Technical |
| R-08 | TTEC dependency — external partner manages Amazon Connect configuration and IVR flows | Medium | Medium | External |
| R-09 | Caller ID spam reputation (NGASIM-1524) — carrier-level issue outside Salesforce control | Medium | Medium | External |
| R-10 | Call transfer (NGPSTE-708) blocked by NGPSTE-1123 (Classic package install) | Medium | Medium | Dependency |
| R-11 | Recording opt-out (NGASIM-1523) blocks SSO (NGPSTE-533) — HIPAA/compliance concern | High | High | Compliance |
| R-12 | NGCRMI-2007 Task sync requires Classic↔Lightning OrgSync — cross-org dependency | Medium | Medium | Integration |
| R-13 | Different persona (Inside Sales) needs separate queue/routing from Customer Care (NGPSTE-132) | Medium | Medium | Configuration |

---

## Intake Quality Assessment

| Dimension | Score | Rationale |
|---|---|---|
| Requirements Clarity | 3/10 | No formal ACs on parent. Child stories have pain points but few structured ACs. Feature description is a one-liner. |
| Implementation Readiness | 2/10 | 0 of 16 child stories Done. 2 in To Verify. Most still in refinement or To Do. |
| Risk Visibility | 6/10 | NGPSTE-132 dependency is explicit. TTEC dependency known. Caller ID spam and recording opt-out risks identified. |
| Dependency Clarity | 7/10 | Jira links present. Upstream NGPSTE-132 relationship clear. Internal blocking relationships mapped. |
| Test Readiness | 2/10 | NFR story cancelled. No test strategy documented. NGASIM-2549 captured some metrics before cancellation. |
| **Overall** | **4/10** | Feature is in early stages with significant scope remaining. Strong dependency on NGPSTE-132. Requirements must be formalized. |

---

## Handoff to PLAN

**Directive:** The planner agent must:

1. Derive formal acceptance criteria for all 16 functional requirements — target 15+ ACs covering inbound, outbound, screen pop, call logging, transfers, status, and voicemail.
2. Leverage NGPSTE-132 ADRs — reuse architectural decisions but extend for Inside Sales persona.
3. Define Inside Sales-specific routing: separate queues, routing configurations, and presence statuses.
4. Plan screen pop resolver that searches Lead AND Patient/Consumer objects (not just Contact).
5. Design Task auto-creation flow/trigger for call activity logging (FR-06, FR-08).
6. Address the recording opt-out requirement (NGASIM-1523) — HIPAA compliance.
7. Produce implementation phases aligned to Fix Versions (SOW MVP → Persona Release 1).
8. Identify which child stories can proceed independently vs which have blocking dependencies.

**Blocking questions for stakeholders:**

- Is NGPSTE-531 (Sales Queues) cancelled because it was completed outside Jira, or is it a real gap?
- What is the target object for screen pop — Lead, Patient__c (custom), or Contact? All three?
- What call dispositions are required? (NGPSTE-538 mentions the concept but no values listed)
- Is the 8-call/day target per rep a hard capacity constraint or a reporting goal?
- Who manages the Amazon Connect IVR/contact flow changes needed for NGASIM-1526 (call type differentiation)?
