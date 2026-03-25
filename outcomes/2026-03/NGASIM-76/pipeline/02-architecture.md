# NGASIM-76: ARCHITECTURE

> **Pipeline Stage:** 02-architecture
> **Produced by:** architect agent
> **Input:** 01-plan.md + NGPSTE-132 ADRs + DevInt2 live metadata
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:35:00Z
> **Status:** COMPLETE — handed off to TDD

---

## Architecture Decision Records

### ADR-005: Multi-Object Screen Pop Strategy for Inside Sales

| Field | Value |
|---|---|
| Status | Accepted |
| Context | NGPSTE-132's ScreenPopResolver only searches Contact.Phone. Inside Sales engages Leads (pre-conversion) and Patients/PersonAccounts. Screen pop must resolve across multiple objects with priority ordering. NGPSTE-532 notes "search will happen on Patient level." |
| Decision | Implement InsideSalesScreenPopResolver with a waterfall search strategy: (1) Lead.Phone/MobilePhone, (2) PersonAccount.PersonHomePhone/PersonMobilePhone/Phone, (3) Contact.Phone/MobilePhone. Return the first match found. If no match, return new Lead creation form with ANI pre-populated. |
| Rationale | Waterfall approach avoids SOSL limitations (no real-time index for phone fields). Lead is searched first because Inside Sales primarily engages unconverted leads. PersonAccount second because existing patients may call back. Contact last as a fallback. |
| Alternatives Considered | (A1) SOSL `FIND {+1555...} IN PHONE FIELDS RETURNING Lead, Contact, Account` — rejected: SOSL phone field search has inconsistent index behavior across orgs and may return stale results. (A2) Single unified Contact Point Phone lookup — rejected: CPP adoption is inconsistent in the org; many Lead phone values are not yet synced to CPP. (A3) Parallel SOQL with `Promise.all` — rejected: Apex is synchronous; cannot parallelize SOQL. Sequential waterfall with short-circuit is equivalent performance. |
| Consequences | Three SOQL queries worst-case (no match). Selective queries on indexed Phone fields keep each under 100ms. Governor limit impact: 3 of 150 SOQL limit per transaction — negligible. Must handle duplicate phone numbers across objects (return first match with disambiguation note). |
| Traces to | AC-02, AC-03, AC-04, FR-02, PD-03 |

### ADR-006: Call Activity Auto-Logging via Apex Trigger

| Field | Value |
|---|---|
| Status | Accepted |
| Context | NGPSTE-536 requires automatic Task creation on call completion. NGPSTE-538 requires call disposition capture. The VoiceCall standard object fires triggers on insert/update. A Task record must be created with populated WhoId (Lead/Contact), WhatId (Case/Opportunity), Subject, Duration, and Disposition. |
| Decision | Implement a VoiceCallActivityTrigger (after insert, after update) that delegates to VoiceCallActivityHandler. On VoiceCall status transition to 'Completed', the handler creates a Task record. Disposition capture is handled by a Screen Flow presented to the agent post-call, which updates the Task. |
| Rationale | Trigger-based approach guarantees Task creation regardless of how the VoiceCall is completed (agent hang-up, caller hang-up, transfer). Flow-based disposition capture provides a guided UI experience for the agent. Hybrid approach separates guaranteed automation from agent-driven data entry. |
| Alternatives Considered | (A1) Pure Flow (Process Builder / Record-Triggered Flow) — rejected: Flow on VoiceCall has limited field access and cannot reliably determine WhoId from the screen pop context. (A2) Pure trigger with auto-disposition — rejected: disposition requires agent input; cannot be automated. (A3) Platform Event → trigger chain — over-engineered for the use case. |
| Consequences | Custom trigger on VoiceCall standard object. Must be bulk-safe (handle 200+ VoiceCall records in a single transaction for batch scenarios). WhoId resolution depends on the screen pop result — requires a shared context mechanism (Custom Metadata or static variable) between screen pop and Task creation. |
| Traces to | AC-08, AC-10, FR-06, FR-08, PD-04 |

### ADR-007: Inside Sales Omni-Channel Routing Configuration

| Field | Value |
|---|---|
| Status | Accepted |
| Context | NGPSTE-132 ADR-003 configured Omni-Channel for Customer Care via sfdc_phone ServiceChannel. Inside Sales needs separate routing because: (1) different agent pool, (2) different capacity model (8 calls/day target = max 1 concurrent voice capacity), (3) separate queue structure for Inside Sales vs HCP routing. |
| Decision | Create a dedicated Inside Sales routing configuration (IS_Voice_Routing) with priority-based routing. Create two queues: Inside_Sales_Voice (general consumer calls) and HCP_Inbound_Voice (provider calls routed by IVR selection). Reuse the existing sfdc_phone ServiceChannel (no need for a new channel). Create Inside Sales-specific ServicePresenceStatus records (IS_Available_Voice, IS_Busy_Voice, IS_ACW). |
| Rationale | Separate routing config allows independent SLA management, capacity rules, and overflow handling. Reusing sfdc_phone avoids ServiceChannel sprawl. Inside Sales presence statuses are separate because their capacity weight (max 1 concurrent call) differs from Care's model. |
| Alternatives Considered | (A1) Share routing config with Care — rejected: different capacity models and agent pools would cause cross-routing. (A2) Create a new ServiceChannel for Inside Sales — rejected: sfdc_phone already maps to VoiceCall; creating a duplicate channel is not supported by Omni-Channel. |
| Consequences | Two queues to manage. IVR must route to the correct queue based on caller selection. Agent profiles must be assigned to the correct queue membership. Omni-Channel Supervisor must be configured to show Inside Sales queues. |
| Traces to | AC-01, AC-05, AC-09, FR-01, FR-03, PD-02 |

### ADR-008: Recording Opt-Out Implementation Pattern

| Field | Value |
|---|---|
| Status | Accepted |
| Context | NGASIM-1523 requires agents to stop/pause recording when a patient verbally opts out. This is a HIPAA compliance requirement. Amazon Connect supports recording control via the StartContactRecording/StopContactRecording/SuspendContactRecording/ResumeContactRecording APIs. |
| Decision | Implement a Lightning Quick Action backed by RecordingOptOutController (Apex). The controller makes an HTTP callout to Amazon Connect's StopContactRecording API via Named Credential. The VoiceCall record is updated with a Recording_Opted_Out__c flag. The action is available on the VoiceCall-related utility bar component. |
| Rationale | Quick Action provides the "quickly and easily" UX requested in NGASIM-1523. Apex callout via Named Credential is the secure Salesforce pattern for external API calls. Updating VoiceCall with opt-out flag provides audit trail for HIPAA compliance. |
| Alternatives Considered | (A1) Connect Streams JavaScript API (stopRecording) — rejected: client-side only, no audit trail in Salesforce, agent could bypass. (A2) Contact Flow Lambda function triggered by agent DTMF — rejected: poor UX, requires phone key press during conversation. (A3) Custom LWC with direct API call — rejected: bypasses Named Credential security model. |
| Consequences | Requires Named Credential for Amazon Connect API (dependency on NGPSTE-132 S-02 recommendation). 2-second latency target for recording stop. Must handle API failure gracefully — display error toast, do not crash softphone. VoiceCall.Recording_Opted_Out__c field required. |
| Traces to | AC-14, FR-12, PD-07, R-07, R-11 |

---

## Component Integration Design

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AMAZON CONNECT                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Contact       │  │ Lambda       │  │ S3 Call   │  │ Connect       │  │
│  │ Flows (IVR)   │  │ Functions    │  │ Recordings│  │ Streams API   │  │
│  │ ┌────────────┐│  └──────┬───────┘  └─────┬────┘  └───────┬───────┘  │
│  │ │IS Queue    ││         │                │              │           │
│  │ │HCP Queue   ││         │                │              │           │
│  │ └────────────┘│         │                │              │           │
│  └──────┬────────┘         │                │              │           │
└─────────┼──────────────────┼────────────────┼──────────────┼───────────┘
          │                  │                │              │
          ▼                  ▼                ▼              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    INTEGRATION LAYER                                     │
│  ┌──────────────────┐  ┌────────────────────┐  ┌──────────────────────┐│
│  │ Named Credential  │  │ CSP Trusted Sites   │  │ Recording API       ││
│  │ (AmazonConnect    │  │ (Connect instance    │  │ (Stop/Pause/Resume  ││
│  │  _API)            │  │  domain)             │  │  via Named Cred)    ││
│  └────────┬─────────┘  └──────────┬───────────┘  └──────────┬─────────┘│
└───────────┼────────────────────────┼─────────────────────────┼──────────┘
            │                        │                         │
            ▼                        ▼                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    SALESFORCE LIGHTNING                                   │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ CTI ADAPTER LAYER                                                  │ │
│  │  ┌─────────────────────┐  ┌──────────────────────────────────┐    │ │
│  │  │ ACLightningAdapter  │  │ Open CTI JavaScript API           │    │ │
│  │  │ (shared with Care)  │──│ (sforce.opencti)                  │    │ │
│  │  └─────────┬───────────┘  └──────────────┬────────────────────┘    │ │
│  └────────────┼─────────────────────────────┼────────────────────────┘ │
│               │                             │                           │
│               ▼                             ▼                           │
│  ┌──────────────────────────┐  ┌──────────────────────────────────┐   │
│  │ Softphone Utility Bar    │  │ InsideSalesScreenPopResolver     │   │
│  │ (IS_Softphone_Layout)    │  │  1. Lead.Phone/MobilePhone       │   │
│  │ + Recording Opt-Out Btn  │  │  2. PersonAccount.Phone          │   │
│  │ + Disposition Capture    │  │  3. Contact.Phone/MobilePhone    │   │
│  └──────────┬───────────────┘  │  4. → New Lead form (fallback)   │   │
│             │                   └──────────────────────────────────┘   │
│             ▼                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │ CALL ACTIVITY ENGINE                                            │  │
│  │  ┌────────────────────────┐  ┌───────────────────────────────┐ │  │
│  │  │ VoiceCallActivityTrig  │  │ Call_Disposition_Capture Flow  │ │  │
│  │  │ → VoiceCallActivity    │  │ (post-call agent screen)      │ │  │
│  │  │   Handler              │  │ → Updates Task.Disposition    │ │  │
│  │  │ → Task auto-creation   │  │                               │ │  │
│  │  └────────────────────────┘  └───────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │ OMNI-CHANNEL ROUTING (INSIDE SALES)                             │  │
│  │  ┌─────────────────┐  ┌──────────────────────────────────────┐ │  │
│  │  │ sfdc_phone       │  │ ServicePresenceStatus (IS-specific)  │ │  │
│  │  │ ServiceChannel   │  │  - IS_Available_Voice                │ │  │
│  │  │ (VoiceCall)      │  │  - IS_Busy_Voice                     │ │  │
│  │  │                  │  │  - IS_ACW                             │ │  │
│  │  └─────┬───────────┘  └──────────────────────────────────────┘ │  │
│  │        │                                                        │  │
│  │        ▼                                                        │  │
│  │  ┌─────────────────────────┐  ┌──────────────────────────────┐ │  │
│  │  │ Inside_Sales_Voice      │  │ HCP_Inbound_Voice            │ │  │
│  │  │ Queue                   │  │ Queue                        │ │  │
│  │  │ (consumer/lead calls)   │  │ (provider/HCP calls)         │ │  │
│  │  └─────────────────────────┘  └──────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │ AGENT DESKTOP (INSIDE SALES)                                    │  │
│  │  Lead/Patient Record + Softphone + Omni-Channel Widget          │  │
│  │  + Disposition Flow + Recording Controls                        │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Object Model

### Standard Objects (already provisioned via NGPSTE-132)

| Object API Name | Usage | Inside Sales Delta |
|---|---|---|
| CallCenter | CTI adapter registration | Shared — ACLightningAdapter serves both personas |
| VoiceCall | Represents a phone call | New custom fields: Call_Category__c, True_Connection__c, Recording_Opted_Out__c |
| ServiceChannel | Defines Omni-Channel channel | Shared — sfdc_phone |
| ServicePresenceStatus | Agent availability states | New IS-specific records (IS_Available_Voice, IS_Busy_Voice, IS_ACW) |
| Task | Call activity log | New custom fields: Call_Disposition__c, Call_Duration_Seconds__c |
| Lead | Inside Sales primary target | Screen pop target. Phone/MobilePhone used for ANI lookup. |
| PersonAccount | Patient/Consumer record | Screen pop secondary target. PersonHomePhone/PersonMobilePhone used. |
| Contact | Fallback screen pop | Tertiary search. Phone/MobilePhone used. |

### Custom Objects / Metadata (to be created)

| Type | API Name | Purpose | Phase |
|---|---|---|---|
| ApexClass | InsideSalesScreenPopResolver | Multi-object ANI → record resolution for Inside Sales | 1 |
| ApexClass | InsideSalesScreenPopResolverTest | Test class for screen pop resolver | 1 |
| ApexTrigger | VoiceCallActivityTrigger | Auto-create Task on VoiceCall completion | 2 |
| ApexClass | VoiceCallActivityHandler | Business logic for Task creation from VoiceCall | 2 |
| ApexClass | VoiceCallActivityHandlerTest | Test class for activity handler | 2 |
| ApexClass | RecordingOptOutController | Apex callout to Connect StopContactRecording API | 2 |
| ApexClass | RecordingOptOutControllerTest | Test class for recording opt-out | 2 |
| Flow | Call_Disposition_Capture | Post-call Screen Flow for agent disposition entry | 2 |
| CustomField | Task.Call_Disposition__c | Picklist: Interested, Not Interested, Callback Requested, Wrong Number, Voicemail, No Answer | 2 |
| CustomField | Task.Call_Duration_Seconds__c | Number: call duration in seconds from VoiceCall | 2 |
| CustomField | VoiceCall.Call_Category__c | Picklist: New Prospect, Transfer, Callback, HCP, Unknown | 3 |
| CustomField | VoiceCall.True_Connection__c | Checkbox: true if real connection (>90s or agent-confirmed) | 3 |
| CustomField | VoiceCall.Recording_Opted_Out__c | Checkbox: true if patient opted out of recording | 2 |
| PermissionSet | IS_CTI_Base | Lead CRUD, Patient Read, Opportunity Read, VoiceCall Read/Edit, Task CRUD | 1 |
| PermissionSetGroup | IS_CTI_Agent_Access | Bundles IS_CTI_Base + AC_CallRecording + CTI_Integration_Access | 1 |
| SoftphoneLayout | IS_Softphone_Layout | Click-to-dial enabled, screen pop settings, recording controls | 1 |
| OmniChannelRoutingConfig | IS_Voice_Routing | Priority-based routing for Inside Sales voice queue | 1 |
| Queue | Inside_Sales_Voice | Consumer/Lead inbound calls for Inside Sales agents | 1 |
| Queue | HCP_Inbound_Voice | HCP/Provider inbound calls routed to dedicated queue | 1 |
| LightningWebComponent | voicemailPlayer | Voicemail playback from S3/Connect | 3 |

---

## Integration Points

### 1. Inbound Call: ANI → Screen Pop (Inside Sales Delta)

| Aspect | Detail |
|---|---|
| Protocol | Connect Streams → CTI adapter → Open CTI `onIncomingCall` → InsideSalesScreenPopResolver |
| Data Flow | ANI from Connect → adapter → `InsideSalesScreenPopResolver.resolveRecord(ani)` → SOQL waterfall (Lead → PersonAccount → Contact) → screen pop URL |
| Authentication | CTI adapter session (SSO via SAML — NGPSTE-533) |
| Error Handling | SOQL exception → fallback to new Lead form. Null/empty ANI → new Lead form. |
| Performance | 3 SOQL queries worst-case × ~50ms each = 150ms. Target: < 500ms total method execution. |

### 2. Call Completion: VoiceCall → Task Creation

| Aspect | Detail |
|---|---|
| Protocol | VoiceCall DML trigger (after update, Status = 'Completed') |
| Data Flow | VoiceCall record → VoiceCallActivityHandler.createActivityTask() → Task insert with WhoId, WhatId, Subject, Duration |
| WhoId Resolution | From VoiceCall.CallerId or from screen pop context (custom setting/cache) |
| WhatId Resolution | From the agent's current record context (Case or Opportunity) — may be null |
| Bulk Safety | Handler processes List<VoiceCall> with single Task DML insert for all records |

### 3. Recording Opt-Out: Agent Action → Connect API

| Aspect | Detail |
|---|---|
| Protocol | HTTPS POST to Amazon Connect StopContactRecording API |
| Authentication | Named Credential (AmazonConnect_API) with IAM role |
| Data Flow | Agent clicks Quick Action → RecordingOptOutController.stopRecording(voiceCallId) → HTTP callout → Connect API → recording stops → VoiceCall.Recording_Opted_Out__c = true |
| Error Handling | CalloutException → toast error "Recording stop failed — please try again." Log to custom object or platform event. |
| Latency Target | < 2 seconds from button click to recording stop confirmation |

### 4. Agent Status Sync: Connect CCP ↔ Omni-Channel

| Aspect | Detail |
|---|---|
| Protocol | Connect Streams API events + Omni-Channel API |
| Data Flow | Agent changes status in CCP → Connect Streams fires `agent.onStateChange` → JavaScript handler updates Omni-Channel presence via `sforce.opencti.setPresenceStatusId()` |
| Bi-directional | Agent changes Omni-Channel presence → CTI adapter syncs to Connect via `agent.setState()` |
| Conflict Resolution | Connect CCP is authoritative. If desync detected, CCP state wins. |

### 5. Call Disposition: Agent Screen → Task Update

| Aspect | Detail |
|---|---|
| Protocol | Screen Flow launched on call completion |
| Data Flow | Call ends → Flow launches → agent selects disposition → Flow updates Task.Call_Disposition__c and Task.Description |
| Trigger | Flow auto-launched from VoiceCallActivityHandler after Task creation, or manually by agent from utility bar |

---

## Security Considerations

| Concern | Mitigation |
|---|---|
| Multi-object screen pop: Lead data visible to all IS agents | FLS on Lead fields restricted by IS_CTI_Base permission set. Only Phone/Name/Status visible in screen pop. |
| Recording opt-out audit trail | VoiceCall.Recording_Opted_Out__c field is read-only to agents (set only by RecordingOptOutController). Audit trail via Field History Tracking. |
| Task auto-creation with PII | Task.Subject includes caller name. FLS on Task restricted by profile. Description field does not auto-populate with PII. |
| Named Credential for Connect API | OAuth 2.0 JWT Bearer token. No hardcoded API keys. Named Credential stored in Salesforce vault. |
| HIPAA: recording contains PHI | Recording opt-out mechanism (ADR-008) provides patient control. S3 encryption at rest. Access gated by AC_CallRecording permission set. |

---

## Performance Considerations

| Concern | Target | Approach |
|---|---|---|
| Screen pop latency (multi-object) | < 2s total | Indexed SOQL on Phone fields. Waterfall with short-circuit. 3 queries × 50ms = 150ms Apex + 500ms network = well under 2s. |
| Task creation latency | < 1s | Single DML insert in bulk-safe trigger handler. No callouts in trigger context. |
| Recording opt-out latency | < 2s | Single HTTP callout to Connect API. Named Credential handles auth. Async confirmation acceptable. |
| Agent status sync | < 1s | Client-side JavaScript (Connect Streams → Open CTI). No server round-trip. |
| Omni-Channel routing | < 5s | Standard platform routing engine. Priority-based model. Platform SLA. |

---

## Inside Sales vs Customer Care Access Segregation

| Dimension | Customer Care (NGPSTE-132) | Inside Sales (NGASIM-76) |
|---|---|---|
| Primary Objects | Contact, Case | Lead, Patient/PersonAccount, Opportunity |
| Permission Set Group | CTI_Agent_Access | IS_CTI_Agent_Access |
| Queues | Care voice queues | Inside_Sales_Voice, HCP_Inbound_Voice |
| ServicePresenceStatus | Available_Voice, Busy_Voice, AfterCallWork_Voice | IS_Available_Voice, IS_Busy_Voice, IS_ACW |
| Routing Config | Care_Voice_Routing | IS_Voice_Routing |
| Screen Pop | Contact.Phone only | Lead → PersonAccount → Contact (waterfall) |
| Call Logging | TBD (NGPSTE-132 Phase 3) | Task auto-creation with disposition (Phase 2) |
| Capacity Model | Multiple concurrent | Max 1 concurrent (8 calls/day target) |

---

## Handoff to TDD

**Directive:** The tdd-guide agent must:

1. Write test specifications for all 17 ACs (AC-01 through AC-17).
2. Design InsideSalesScreenPopResolver test class with: known Lead match, known PersonAccount match, known Contact match, unknown ANI, null ANI, empty ANI, duplicate phone across objects.
3. Design VoiceCallActivityHandler test class with: single call completion, bulk call completion (200 records), missing WhoId, call with disposition.
4. Design RecordingOptOutController test class with: successful stop, API timeout, API error, already-opted-out call.
5. Include SOQL validation queries for Inside Sales routing configuration.
6. Define test data factory for Lead, PersonAccount, Contact, VoiceCall, Task records.
7. Estimate coverage targets: all three Apex classes must reach 85%+.
