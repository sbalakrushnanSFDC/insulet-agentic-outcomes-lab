# NGASIM-76: PLAN

> **Pipeline Stage:** 01-plan
> **Produced by:** planner agent
> **Input:** 00-intake.md + NGPSTE-132 run artifacts (ADRs, architecture) + DevInt2 live data
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:32:00Z
> **Status:** COMPLETE — handed off to ARCHITECTURE

---

## Planning Decisions

| # | Decision | Rationale |
|---|---|---|
| PD-01 | Reuse ACLightningAdapter from NGPSTE-132 — no separate adapter needed for Inside Sales | Same Amazon Connect instance serves both Care and Inside Sales. Adapter is persona-agnostic. |
| PD-02 | Create Inside Sales-specific Omni-Channel routing configuration and queues | Inside Sales has different SLA, capacity (8 calls/day target), and skill requirements vs Care. Separate routing avoids cross-contamination. |
| PD-03 | Extend screen pop resolver to search Lead, Contact, AND Patient/Account objects | NGPSTE-132 only resolves Contact. Inside Sales engages Leads (pre-conversion) and Consumers (Patient__c or PersonAccount). Multi-object search required. |
| PD-04 | Build call activity logging as Apex trigger + Flow hybrid | Task auto-creation (NGPSTE-536) needs both: trigger for guaranteed execution on VoiceCall insert, Flow for agent-driven disposition capture. |
| PD-05 | Create Inside Sales Permission Set Group (IS_CTI_Agent_Access) separate from Care's CTI_Agent_Access | Different object access patterns: Inside Sales needs Lead Create/Edit, Patient Read, Opportunity Read/Edit. Care PSG doesn't include these. |
| PD-06 | Defer voicemail access (NGPSTE-811) and caller ID reputation (NGASIM-1524) to Phase 3 | These require Amazon Connect configuration changes outside Salesforce. Focus Phase 1-2 on core call handling. |
| PD-07 | Phase recording opt-out (NGASIM-1523) with SSO (NGPSTE-533) since they are co-dependent | SSO is blocked by recording opt-out. Deliver both in Phase 2 together. |

---

## Formalized Acceptance Criteria

Derived from 16 child stories, the feature description, NGPSTE-132 architectural context, and Inside Sales persona requirements.

| AC ID | Acceptance Criterion | Source | Priority | Verification Method |
|---|---|---|---|---|
| AC-01 | Inside Sales reps can receive inbound calls via Lightning softphone and the call rings within 5 seconds of contact flow completion | FR-01, NGPSTE-532 | Must Have | Manual test: inbound call → softphone rings |
| AC-02 | Inbound screen pop resolves caller ANI to Lead record (by Phone/MobilePhone) and displays Lead detail page | FR-02, NGPSTE-532 | Must Have | Apex unit test: known Lead phone → Lead page URL returned |
| AC-03 | Inbound screen pop resolves caller ANI to Patient/PersonAccount record if no Lead match found | FR-02, NGPSTE-532 | Must Have | Apex unit test: known Patient phone, no Lead → Patient page URL |
| AC-04 | Inbound screen pop displays new Lead creation form with ANI pre-populated when no match found | FR-02 (negative path) | Must Have | Apex unit test: unknown ANI → new Lead form URL |
| AC-05 | Inbound calls from HCP/Provider numbers route to a dedicated HCP queue with provider-specific screen pop | FR-03, NGPSTE-534 | Should Have | Manual test: HCP number → HCP queue, Account (HCP) page |
| AC-06 | Inside Sales reps can initiate outbound click-to-dial calls from Lead, Contact, and Patient record phone fields | FR-04, NGPSTE-535 | Must Have | Manual test: click phone field → outbound call initiates |
| AC-07 | SSO authentication to Amazon Connect CCP works within the Salesforce Lightning softphone without separate login | FR-05, NGPSTE-533 | Must Have | Manual test: Lightning login → CCP auto-authenticated |
| AC-08 | A Task record is auto-created on call completion with Subject, WhoId (Contact/Lead), WhatId (Case/Opportunity), Call Duration, Call Type, and Call Disposition | FR-06, FR-08, NGPSTE-536 | Must Have | Apex unit test: VoiceCall insert → Task created with correct fields |
| AC-09 | Agent status transitions (Available → Busy → After Call Work → Available) are reflected in both Amazon Connect CCP and Salesforce Omni-Channel widget | FR-07, NGPSTE-538 | Must Have | Manual test: status change in CCP → reflected in Omni-Channel |
| AC-10 | Call disposition values (Interested, Not Interested, Callback Requested, Wrong Number, Voicemail, No Answer) are selectable at call end and persisted on the Task record | FR-08, NGPSTE-538 | Must Have | Manual test: select disposition → saved on Task.CallDisposition |
| AC-11 | Warm transfer: agent can consult with second agent before connecting them to the caller | FR-09, NGPSTE-708 | Must Have | Manual test: initiate warm transfer → consult → connect |
| AC-12 | Cold transfer: agent can transfer caller directly to another agent or queue without consultation | FR-09, NGPSTE-708 | Must Have | Manual test: initiate cold transfer → caller moves immediately |
| AC-13 | Quick connect buttons are configured for Inside Sales common transfer destinations (Sales Manager, Product Support, HCP line) | FR-10, NGPSTE-809 | Should Have | Manual test: quick connect buttons visible and functional |
| AC-14 | Recording stops/pauses within 2 seconds when agent triggers opt-out action during an active call | FR-12, NGASIM-1523 | Must Have | Manual test: trigger opt-out → recording indicator changes |
| AC-15 | Inside Sales reps can access and play voicemails assigned to them from within Salesforce | FR-11, NGPSTE-811 | Should Have | Manual test: voicemail list visible, playback works |
| AC-16 | Inbound call types (new prospect, transfer, callback) are tagged on the VoiceCall record for reporting | FR-15, NGASIM-1526 | Should Have | SOQL query: VoiceCall records have CallType populated |
| AC-17 | True connections (calls >90s or agent-confirmed) are flagged for accurate connection rate reporting | FR-14, NGASIM-1525 | Should Have | Report: connection rate calculation uses flag, not raw duration |

---

## Implementation Phases

### Phase 1: Core Inside Sales CTI — Inbound/Outbound Call Handling (Size: M)

**Target:** Project Infinity SOW MVP
**Duration:** 2 sprints
**Dependencies:** NGPSTE-132 Phase 1 complete (adapter installed, Omni-Channel base configured)

| Task | Description | Story | Owner | Status |
|---|---|---|---|---|
| P1-T1 | Create Inside Sales Omni-Channel routing configuration | New | Config team | New |
| P1-T2 | Create Inside Sales voice queue with sfdc_phone channel | NGPSTE-531 scope | Config team | New |
| P1-T3 | Create ServicePresenceStatus for Inside Sales (IS_Available_Voice, IS_Busy_Voice, IS_ACW) | New | Config team | New |
| P1-T4 | Extend InsideSalesScreenPopResolver to search Lead → Patient → Contact in sequence | NGPSTE-532 | Dev team | New |
| P1-T5 | Configure Softphone Layout with click-to-dial enabled for all phone fields | NGPSTE-535 | Config team | New |
| P1-T6 | Create IS_CTI_Agent_Access Permission Set Group | New | Config team | New |
| P1-T7 | Validate inbound call reception via Lightning softphone | NGPSTE-532 | QA | Test |
| P1-T8 | Validate outbound click-to-dial from Lead and Contact records | NGPSTE-535 | QA | Test |

**Exit criteria:** AC-01, AC-02, AC-03, AC-04, AC-06 verified.

### Phase 2: Call Logging, SSO, Agent Status, and Recording Controls (Size: L)

**Target:** Persona Release 1
**Duration:** 2-3 sprints
**Dependencies:** Phase 1 complete

| Task | Description | Story | Owner | Status |
|---|---|---|---|---|
| P2-T1 | Implement VoiceCallActivityTrigger — auto-create Task on VoiceCall completion | NGPSTE-536 | Dev team | New |
| P2-T2 | Create call disposition picklist on Task (Interested, Not Interested, Callback, Wrong Number, Voicemail, No Answer) | NGPSTE-538 | Config team | New |
| P2-T3 | Build call disposition capture Flow (post-call agent screen) | NGPSTE-538 | Dev team | New |
| P2-T4 | Configure SSO/SAML integration for Amazon Connect CCP | NGPSTE-533 | Dev team | New |
| P2-T5 | Implement recording opt-out action (Apex + Connect API callout) | NGASIM-1523 | Dev team | New |
| P2-T6 | Configure agent status sync between Connect CCP and Omni-Channel | NGPSTE-538 | Config team | New |
| P2-T7 | Test Task auto-creation with correct WhoId/WhatId mapping | NGPSTE-536 | QA | Test |
| P2-T8 | Test SSO login flow end-to-end | NGPSTE-533 | QA | Test |
| P2-T9 | Test recording opt-out compliance | NGASIM-1523 | QA | Test |

**Exit criteria:** AC-07, AC-08, AC-09, AC-10, AC-14 verified.

### Phase 3: Transfers, Quick Connect, Voicemail, and Reporting (Size: L)

**Target:** Persona Release 1 / Persona Release 2
**Duration:** 2-3 sprints
**Dependencies:** Phase 1 + Phase 2 complete

| Task | Description | Story | Owner | Status |
|---|---|---|---|---|
| P3-T1 | Configure warm transfer in Amazon Connect contact flows | NGPSTE-708 | TTEC/Connect team | New |
| P3-T2 | Configure cold transfer in Amazon Connect contact flows | NGPSTE-708 | TTEC/Connect team | New |
| P3-T3 | Configure Quick Connect entries for Inside Sales destinations | NGPSTE-809 | TTEC/Connect team | New |
| P3-T4 | Implement voicemail access component (LWC or Connect embedded) | NGPSTE-811 | Dev team | New |
| P3-T5 | Add call type tagging logic (IVR-driven attribute → VoiceCall field) | NGASIM-1526 | Dev team | New |
| P3-T6 | Implement true connection flagging (duration threshold + agent confirmation) | NGASIM-1525 | Dev team | New |
| P3-T7 | Build Inside Sales call reporting dashboard (Tableau integration per labels) | New | Analytics team | New |
| P3-T8 | HCP/Provider inbound routing and screen pop | NGPSTE-534 | Dev/Config team | New |
| P3-T9 | New hire onboarding automation for CTI setup | NGASIM-1527 | DevOps | New |
| P3-T10 | End-to-end integration test across all ACs | All | QA | Test |

**Exit criteria:** AC-05, AC-11, AC-12, AC-13, AC-15, AC-16, AC-17 verified.

---

## Risk Register

| ID | Risk | Prob | Impact | Severity | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R-01 | No formal ACs on parent Feature — scope ambiguity | High | High | Critical | Formalized 17 ACs in this plan. Seek PO sign-off. | Planner |
| R-02 | 0% Done — feature in early implementation | High | High | Critical | Phase delivery gated on NGPSTE-132. Focus on Phase 1 quick wins. | PM |
| R-03 | NGPSTE-132 not deployed to orgsyncng yet — blocks all NGASIM-76 work | High | Critical | Critical | Track NGPSTE-132 deployment. Cannot start Phase 1 until adapter is live. | DevOps |
| R-04 | Multi-object screen pop (Lead + Patient + Contact) complexity | Medium | High | High | Design waterfall search: Lead first, then Patient, then Contact. Use SOSL for efficiency. | Dev lead |
| R-05 | Task auto-creation trigger may conflict with existing automation | Medium | Medium | Medium | Audit existing VoiceCall triggers and flows in DevInt2 before implementation. | Dev lead |
| R-06 | Agent status sync between Connect CCP and Omni-Channel is notoriously fragile | Medium | High | High | Use Connect Streams API events for real-time sync. Add monitoring. | Dev lead |
| R-07 | Recording opt-out (NGASIM-1523) requires Connect API callout during active call — latency risk | Medium | High | High | Pre-test API latency. Provide visual feedback while API call is in-flight. | Dev lead |
| R-08 | TTEC manages Connect contact flows — changes require external coordination | Medium | Medium | Medium | Establish joint sprint planning with TTEC for Phase 3 contact flow changes. | PM |
| R-09 | Caller ID reputation (NGASIM-1524) is carrier-level — outside Salesforce/Connect control | Medium | Medium | Medium | Engage carrier compliance team. Consider STIR/SHAKEN attestation. | Telecom lead |
| R-10 | NGCRMI-2007 Task OrgSync dependency — call log Tasks must sync to Classic org | Medium | Medium | Medium | Coordinate with OrgSync team on Task field mapping. | Integration lead |
| R-11 | NFR targets from NGASIM-2549 (cancelled) not formally tracked | Medium | High | High | Incorporate NFR targets into test plan. Monitor during UAT. | QA lead |

---

## Dependencies Table

| Dependency | Type | Status | Impact if Delayed | Mitigation |
|---|---|---|---|---|
| NGPSTE-132 (Amazon Connect base integration) | Predecessor | Feature Ready (pipeline complete, not deployed) | Blocks all NGASIM-76 work | Track NGPSTE-132 deployment to orgsyncng |
| NGPSTE-132 ServicePresenceStatus | Predecessor | Metadata generated (05-buildfix) | Blocks Phase 1 routing config | Deploy NGPSTE-132 metadata first |
| NGPSTE-132 ACLightningAdapter | Predecessor | Exists in DevInt2 | Blocks softphone rendering | Validate adapter in orgsyncng post-deploy |
| NGPSTE-1123 (Classic Dev Package Part 3) | Parallel | To Do | Blocks call transfer testing (NGPSTE-708) | Decouple transfer config from Classic validation |
| NGASIM-1523 (Recording Opt-out) | Internal | To Verify | Blocks NGPSTE-533 (SSO) per Jira link | Co-deliver in Phase 2 |
| NGCRMI-2007 (Task OrgSync) | External | Feature Refinement | Task records not synced to Classic | Coordinate field mapping with OrgSync team |
| TTEC Partner (Connect config) | External | Active | Phase 3 contact flow changes delayed | Pre-schedule TTEC sprint participation |
| Amazon Connect Sandbox | External | Not provisioned (per NGPSTE-132 E2E) | All live call tests blocked | Escalate provisioning request |

---

## Metadata Inventory (Planned)

| # | Metadata Type | API Name | Phase | Action | Depends On |
|---|---|---|---|---|---|
| 1 | OmniChannelRoutingConfig | IS_Voice_Routing | 1 | Create | sfdc_phone ServiceChannel |
| 2 | Queue | Inside_Sales_Voice | 1 | Create | IS_Voice_Routing |
| 3 | Queue | HCP_Inbound_Voice | 1 | Create | IS_Voice_Routing |
| 4 | ServicePresenceStatus | IS_Available_Voice | 1 | Create | sfdc_phone |
| 5 | ServicePresenceStatus | IS_Busy_Voice | 1 | Create | sfdc_phone |
| 6 | ServicePresenceStatus | IS_ACW | 1 | Create | sfdc_phone |
| 7 | ApexClass | InsideSalesScreenPopResolver | 1 | Create | — |
| 8 | ApexClass | InsideSalesScreenPopResolverTest | 1 | Create | #7 |
| 9 | SoftphoneLayout | IS_Softphone_Layout | 1 | Create | ACLightningAdapter |
| 10 | PermissionSet | IS_CTI_Base | 1 | Create | — |
| 11 | PermissionSetGroup | IS_CTI_Agent_Access | 1 | Create | #10 + existing AC_CallRecording + CTI_Integration_Access |
| 12 | ApexTrigger | VoiceCallActivityTrigger | 2 | Create | — |
| 13 | ApexClass | VoiceCallActivityHandler | 2 | Create | — |
| 14 | ApexClass | VoiceCallActivityHandlerTest | 2 | Create | #13 |
| 15 | Flow | Call_Disposition_Capture | 2 | Create | Task picklist |
| 16 | CustomField | Task.Call_Disposition__c | 2 | Create (picklist) | — |
| 17 | CustomField | Task.Call_Duration_Seconds__c | 2 | Create (number) | — |
| 18 | CustomField | VoiceCall.Call_Category__c | 3 | Create (picklist) | — |
| 19 | CustomField | VoiceCall.True_Connection__c | 3 | Create (checkbox) | — |
| 20 | ApexClass | RecordingOptOutController | 2 | Create | Named Credential |
| 21 | ApexClass | RecordingOptOutControllerTest | 2 | Create | #20 |
| 22 | LightningWebComponent | voicemailPlayer | 3 | Create | — |
| 23 | Report | IS_Call_Activity_Dashboard | 3 | Create | #16, #17, #18, #19 |

---

## Effort Estimation

| Phase | Size | Sprints | Story Points | Confidence |
|---|---|---|---|---|
| Phase 1 — Core CTI (inbound/outbound, screen pop, routing) | M | 2 | 13 | Medium (depends on NGPSTE-132 deployment) |
| Phase 2 — Call Logging, SSO, Status, Recording Controls | L | 2-3 | 21 | Low (custom Apex + Connect API integration) |
| Phase 3 — Transfers, Voicemail, Reporting, HCP Routing | L | 2-3 | 21 | Low (TTEC dependency + multiple new capabilities) |
| **Total** | | **6-8** | **55** | |

---

## Handoff to ARCHITECTURE

**Directive:** The architect agent must:

1. Extend NGPSTE-132 ADRs for Inside Sales persona — create ADR-005 (multi-object screen pop strategy) and ADR-006 (call activity auto-logging pattern).
2. Design InsideSalesScreenPopResolver with waterfall search: Lead.Phone/MobilePhone → PersonAccount.Phone → Contact.Phone. Include SOSL alternative for cross-object search efficiency.
3. Design VoiceCallActivityTrigger → VoiceCallActivityHandler with Task creation logic. Map VoiceCall fields to Task fields. Handle bulk DML.
4. Design recording opt-out flow: agent action → Apex callout to Connect API → stop recording → update VoiceCall record.
5. Specify Inside Sales-specific Omni-Channel routing: queue structure, skill-based routing, capacity model (8 calls/day target).
6. Produce component integration diagram showing the Inside Sales call flow delta from NGPSTE-132.
7. Define permission model for Inside Sales vs Customer Care access segregation.
8. Address HCP/Provider routing (NGPSTE-534) as a sub-flow of the main inbound call architecture.
