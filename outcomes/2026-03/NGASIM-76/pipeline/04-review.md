# NGASIM-76: CODE REVIEW

> **Pipeline Stage:** 04-code-review
> **Produced by:** code-reviewer agent
> **Input:** 00-intake.md, 01-plan.md, 02-architecture.md, 03-tdd.md
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:40:00Z
> **Status:** COMPLETE — handed off to BUILD-FIX

---

## Review Summary

| Severity | Count | Action Required |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 3 | Must resolve before deployment |
| MEDIUM | 4 | Should resolve; acceptable risk if deferred with justification |
| LOW | 2 | Address during implementation or defer to backlog |
| INFO | 2 | Advisory observations |
| **Total** | **11** | |

### Verdict: **CONDITIONAL PASS**

The feature architecture is a well-reasoned extension of NGPSTE-132 with clear ADRs (005–008) and comprehensive acceptance criteria. However, the primary blocker is that NGPSTE-132 has not been deployed to orgsyncng yet, which blocks all NGASIM-76 work. The three HIGH findings (prerequisite deployment, multi-object SOQL governor risk, and missing Named Credential) must be resolved before any Phase 1 deployment. The feature maturity is very low (0% child stories Done), which means code review is primarily an architecture/design review at this stage.

---

## Findings

### F-01 — NGPSTE-132 Not Yet Deployed — Blocks All NGASIM-76 Work

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Prerequisite Dependency |
| AC Impacted | All (AC-01 through AC-17) |
| Source | 00-intake.md dependency map: NGPSTE-132 "Feature Ready (pipeline complete, not deployed)" |
| Phase Impacted | All phases (Phase 1, 2, 3) |

**Description:**
NGPSTE-132 (Amazon Connect base integration) is the critical upstream dependency for NGASIM-76. The NGPSTE-132 pipeline run produced metadata artifacts (ServicePresenceStatus, CTI_Agent_Access PSG, CallCenter update) but none have been deployed to orgsyncng. Without the base CTI adapter, Omni-Channel voice channel, and permission infrastructure in place, no NGASIM-76 work can begin.

**Evidence:**
- 00-intake.md: "is blocked by NGPSTE-132 — Feature Ready (pipeline complete, not deployed)"
- 01-plan.md PD-01: "Reuse ACLightningAdapter from NGPSTE-132"
- 02-architecture.md: "Standard Objects (already provisioned via NGPSTE-132)" — this statement is aspirational, not factual
- NGPSTE-132 06-e2e.md: All 15 tests status "NOT RUN — Deployment to orgsyncng pending"

**Impact:**
All 17 ACs are blocked. No Apex classes, no metadata, and no routing configuration can function without the NGPSTE-132 foundation. The ACLightningAdapter, sfdc_phone ServiceChannel, and base permission sets (AC_CallRecording, CTI_Integration_Access) are prerequisites for every NGASIM-76 component.

**Recommendation:**
1. **Immediate action:** Deploy NGPSTE-132 metadata package to orgsyncng (ServicePresenceStatus, CTI_Agent_Access PSG, CallCenter update).
2. Run NGPSTE-132 SOQL validation queries (SQ-01 through SQ-06) to confirm base infrastructure.
3. Only after NGPSTE-132 validation passes should NGASIM-76 Phase 1 deployment begin.
4. Add NGPSTE-132 deployment status to the NGASIM-76 daily stand-up as a gating item.

---

### F-02 — Multi-Object Screen Pop SOQL Governor Limit Risk with Duplicate Phones

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Code Design / Governor Limits |
| AC Impacted | AC-02, AC-03, AC-04 |
| Source | 02-architecture.md ADR-005 (waterfall search strategy) |
| Phase Impacted | Phase 1 |

**Description:**
ADR-005 specifies a waterfall SOQL strategy: Lead.Phone/MobilePhone → PersonAccount.Phone → Contact.Phone/MobilePhone. While 3 SOQL queries are within governor limits (3 of 150), the design does not address the scenario where the same phone number exists on multiple records of the same object type (e.g., two Leads with the same phone). The `resolveRecord` method returns "the first match" but does not specify behavior when multiple matches are found. A SOQL query `WHERE Phone = :ani OR MobilePhone = :ani` on Lead could return 5+ records in production data, each requiring disambiguation.

**Evidence:**
- ADR-005 consequences: "Must handle duplicate phone numbers across objects (return first match with disambiguation note)"
- 01-plan.md R-06: "Screen pop must resolve across Lead + Patient (not just Contact) — multi-object complexity"
- ADR-005 alternatives: Rejected SOSL for "inconsistent index behavior" — but SOQL on non-unique Phone fields can also return multiple rows

**Impact:**
If the screen pop returns multiple matches without disambiguation, the agent sees the wrong record. For Inside Sales, popping the wrong Lead means the agent has the wrong prospect context — damaging to call quality and customer trust. If the resolver returns `LIMIT 1` without ordering, the match is non-deterministic.

**Recommendation:**
1. Add `ORDER BY LastModifiedDate DESC LIMIT 1` to all waterfall SOQL queries for deterministic single-record return.
2. When multiple matches exist, return the single best match AND log a Finding/Platform Event for data quality remediation.
3. Add a disambiguation UI component: if >1 match found, show a short list for agent selection (deferred UX enhancement).
4. Add bulk test case for InsideSalesScreenPopResolver: 5 Leads with same phone → verify single, deterministic result.
5. Consider a composite Phone index (Phone + MobilePhone) using a formula field for efficient matching.

---

### F-03 — Recording Opt-Out Requires Named Credential Not Yet Created

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Prerequisite Dependency |
| AC Impacted | AC-14 |
| Source | 02-architecture.md ADR-008, NGPSTE-132 07-security.md S-02 |
| Phase Impacted | Phase 2 |

**Description:**
ADR-008 specifies that RecordingOptOutController makes an HTTP callout to Amazon Connect's StopContactRecording API via Named Credential. However, the Named Credential (`AmazonConnect_API`) has not been created in any org. NGPSTE-132 security review (S-02) flagged this same gap: "Amazon Connect API endpoint must use a Salesforce Named Credential." This is a prerequisite for both NGPSTE-132 and NGASIM-76, and remains unresolved.

**Evidence:**
- ADR-008: "Named Credential (AmazonConnect_API) with IAM role"
- NGPSTE-132 07-security.md S-02: "CRITICAL ACTION: Create Named Credential for Amazon Connect API"
- NGPSTE-132 09-docs.md OI-02: "Named Credential for Connect API — Status: Open"
- RecordingOptOutController design: `HttpRequest req = new HttpRequest(); req.setEndpoint('callout:AmazonConnect_API/...')`

**Impact:**
Without the Named Credential, RecordingOptOutController will throw `System.CalloutException: Invalid endpoint` at runtime. AC-14 (recording opt-out within 2 seconds) is completely blocked. This is a HIPAA compliance feature — patients who verbally opt out must have recording stopped promptly.

**Recommendation:**
1. Create Named Credential `AmazonConnect_API` in orgsyncng with OAuth 2.0 JWT Bearer authentication.
2. Coordinate with AWS team for IAM role and endpoint configuration.
3. Test Named Credential connectivity before implementing RecordingOptOutController.
4. Add Named Credential creation to Phase 1 checklist (even though RecordingOptOutController is Phase 2) to avoid last-minute blockers.

---

### F-04 — VoiceCallActivityHandler WhoId Resolution Depends on Screen Pop Context Sharing

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Code Design |
| AC Impacted | AC-08 |
| Source | 02-architecture.md ADR-006, Integration Point #2 |
| Phase Impacted | Phase 2 |

**Description:**
ADR-006 states that VoiceCallActivityHandler creates a Task with WhoId (Lead/Contact). The WhoId comes from the screen pop result — whichever record was resolved by InsideSalesScreenPopResolver. However, the architecture specifies that WhoId resolution requires "a shared context mechanism (Custom Metadata or static variable) between screen pop and Task creation." No design for this context-sharing mechanism has been documented.

**Evidence:**
- ADR-006 consequences: "WhoId resolution depends on the screen pop result — requires a shared context mechanism"
- Integration Point #2: "WhoId Resolution: From VoiceCall.CallerId or from screen pop context (custom setting/cache)"
- No custom metadata or static variable design exists in any artifact

**Impact:**
Without context sharing, the Task's WhoId will be null or require a secondary SOQL lookup (duplicating the screen pop logic). Null WhoId means the Task is an orphan activity with no Lead/Contact association — defeating the purpose of call activity logging.

**Recommendation:**
1. Design a context-sharing pattern: store the screen pop result (recordId, objectType) on the VoiceCall record via a custom field `VoiceCall.Screen_Pop_Record_Id__c`.
2. InsideSalesScreenPopResolver writes the resolved record ID to VoiceCall on screen pop.
3. VoiceCallActivityHandler reads `Screen_Pop_Record_Id__c` for WhoId population.
4. This creates a clean data flow: screen pop → VoiceCall → Task, without static variables or platform cache dependencies.

---

### F-05 — No Bulk Test for Concurrent VoiceCall Completion Triggering Task Creation

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Testing Gap |
| AC Impacted | AC-08 |
| Source | 02-architecture.md ADR-006, handoff to TDD |
| Phase Impacted | Phase 2 |

**Description:**
ADR-006 notes that VoiceCallActivityHandler must be bulk-safe: "handle 200+ VoiceCall records in a single transaction for batch scenarios." The TDD handoff requests a "bulk call completion (200 records)" test case. However, no test specification exists yet for concurrent VoiceCall completion where multiple agents finish calls simultaneously, triggering Task creation in a single transaction.

**Evidence:**
- ADR-006 consequences: "Handler processes List<VoiceCall> with single Task DML insert for all records"
- 02-architecture.md handoff to TDD #3: "bulk call completion (200 records)"
- 03-tdd.md: Not yet produced (pipeline stage not yet executed)

**Impact:**
Without bulk testing, the trigger may fail in production when batch operations (data loads, API bulk updates) modify multiple VoiceCall records simultaneously. A non-bulk-safe trigger will hit `System.LimitException: Too many DML statements` if it inserts one Task per VoiceCall iteration.

**Recommendation:**
1. Add explicit bulk test: insert 200 VoiceCall records in a single DML → verify 200 Tasks created in a single DML.
2. Test mixed-status bulk update: 200 VoiceCall records, 100 transitioning to Completed, 100 remaining InProgress → verify 100 Tasks only.
3. Include governor limit assertions: `System.assert(Limits.getDMLStatements() < 5, 'Bulk safety violated')`.

---

### F-06 — Inside Sales Queue Membership Not Defined — Which Profiles?

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Configuration Gap |
| AC Impacted | AC-01, AC-05 |
| Source | 01-plan.md metadata inventory, 02-architecture.md ADR-007 |
| Phase Impacted | Phase 1 |

**Description:**
ADR-007 creates two queues (Inside_Sales_Voice, HCP_Inbound_Voice) but does not specify which profiles or users should be queue members. Queue membership determines which agents receive routed calls. Without membership, the queues are empty and no calls will be routed to Inside Sales agents.

**Evidence:**
- 01-plan.md metadata #2: Queue `Inside_Sales_Voice` — no member specification
- 01-plan.md metadata #3: Queue `HCP_Inbound_Voice` — no member specification
- 02-architecture.md: "Agent profiles must be assigned to the correct queue membership" — stated as requirement but not designed
- NGPSTE-531 (Sales Queues setup) was Cancelled — original queue setup story is gone

**Impact:**
Omni-Channel will not route calls to agents who are not queue members. AC-01 (inbound call reception) and AC-05 (HCP routing) require agents to be in the correct queue. Without defining membership criteria, deployment succeeds but routing fails.

**Recommendation:**
1. Define queue membership: Inside_Sales_Voice → all users with IS_CTI_Agent_Access PSG.
2. Define HCP queue membership: HCP_Inbound_Voice → designated HCP handlers within Inside Sales team.
3. Document the queue membership assignment step in the deployment runbook (manual Setup UI step).
4. Clarify whether NGPSTE-531 cancellation means queue setup was moved elsewhere or if it's a genuine gap.

---

### F-07 — Call Disposition Picklist Values Need PO Confirmation

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Requirements Completeness |
| AC Impacted | AC-10 |
| Source | 01-plan.md AC-10 |
| Phase Impacted | Phase 2 |

**Description:**
AC-10 specifies six call disposition values: Interested, Not Interested, Callback Requested, Wrong Number, Voicemail, No Answer. These were derived by the planner agent from child story descriptions. The values have not been confirmed by the Product Owner. The NGPSTE-538 story description mentions "Call Disposition" as a concept but provides no enumerated values.

**Evidence:**
- 01-plan.md AC-10: picklist values listed
- NGPSTE-538 description: mentions disposition concept, no specific values
- 00-intake.md: "What call dispositions are required? (NGPSTE-538 mentions the concept but no values listed)"

**Impact:**
Deploying incorrect disposition values creates rework — picklist values are difficult to remove once agents begin using them. Inside Sales may require industry-specific dispositions (e.g., "DM Reached," "Gatekeeper," "Appointment Set") not included in the current list.

**Recommendation:**
1. Send disposition value list to PO for confirmation before Phase 2 implementation.
2. Include an "Other" catch-all value to handle edge cases.
3. Add a text field `Task.Call_Disposition_Notes__c` for free-form agent notes when "Other" is selected.

---

### F-08 — HCP Routing Depends on IVR Configuration Managed by TTEC

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | External Dependency |
| AC Impacted | AC-05 |
| Source | 02-architecture.md ADR-007, 00-intake.md NGASIM-1526 |
| Phase Impacted | Phase 3 |

**Description:**
AC-05 requires inbound HCP/Provider calls to route to HCP_Inbound_Voice queue. This routing decision happens at the IVR level (Amazon Connect contact flow), which is managed by TTEC, an external partner. NGASIM-1526 ("Differentiate types of inbound calls") is in To Do status and explicitly requires "IVR/queue redesign needed with TTEC."

**Evidence:**
- 00-intake.md NGASIM-1526: "Cannot distinguish inbound call types... IVR/queue redesign needed with TTEC"
- 01-plan.md PD-06: "Defer voicemail access and caller ID reputation to Phase 3"
- 01-plan.md R-08: "TTEC manages Connect contact flows — changes require external coordination"

**Impact:**
Without TTEC modifying the contact flow to add an IVR menu option (e.g., "Press 1 for Patient Support, Press 2 for Healthcare Provider"), all inbound calls land in the same queue. HCP routing is purely a Phase 3 delivery risk — no Salesforce metadata change alone can achieve this.

**Recommendation:**
1. Initiate TTEC coordination for IVR redesign in current sprint to avoid Phase 3 delays.
2. Provide TTEC with the target queue names (Inside_Sales_Voice, HCP_Inbound_Voice) and routing criteria.
3. Add a TTEC contact flow change request to the project dependency tracker.
4. Consider a Salesforce-side fallback: agent manually transfers HCP calls to HCP_Inbound_Voice queue if IVR redesign is delayed.

---

### F-09 — Task OrgSync (NGCRMI-2007) Dependency Not Addressed in Architecture

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Integration Gap |
| AC Impacted | AC-08 |
| Source | 00-intake.md linked issues, 01-plan.md R-10 |
| Phase Impacted | Phase 2 |

**Description:**
NGCRMI-2007 ("Tasks - OrgSync") is a related feature in Feature Refinement status. NGASIM-76's Task auto-creation (AC-08) generates call activity Tasks in the Lightning org. These Tasks must synchronize to the Classic org via OrgSync. However, the architecture (02-architecture.md) does not address OrgSync compatibility — specifically whether custom fields (Task.Call_Disposition__c, Task.Call_Duration_Seconds__c) will be included in the OrgSync field mapping.

**Evidence:**
- 00-intake.md: "NGCRMI-2007 relates to — Task synchronization between Classic and Lightning orgs"
- 01-plan.md R-10: "NGCRMI-2007 Task OrgSync dependency — call log Tasks must sync to Classic org"
- 02-architecture.md: No mention of OrgSync or Task field mapping
- ADR-006: Defines Task creation but not cross-org synchronization

**Impact:**
If OrgSync is not configured to include the new custom fields, Classic org users will see the Task but without disposition and duration data. This creates an inconsistent experience for teams still operating in Classic.

**Recommendation:**
1. Add OrgSync field mapping for Task.Call_Disposition__c and Task.Call_Duration_Seconds__c to the NGCRMI-2007 backlog.
2. Coordinate with OrgSync team to verify Task sync configuration supports custom fields.
3. Add a task in Phase 2 plan: "Validate Task OrgSync mapping for call activity fields."
4. If OrgSync cannot handle custom picklist fields, consider using a standard Task field (Subject line suffix) as a workaround.

---

### F-10 — 0% Child Stories Done — Feature Maturity Very Low

| Field | Value |
|---|---|
| Severity | **INFO** |
| Category | Delivery Risk |
| AC Impacted | All |
| Source | 00-intake.md completion summary |

**Description:**
Of 16 child stories, 0 are Done, 2 are in To Verify, 4 are in Technical Refinement, 7 are in To Do, 2 are Cancelled, and 1 is in another status. The net completion rate (Done + To Verify / non-cancelled) is 14%. This is the lowest completion rate of any feature entering the assurance pipeline.

**Evidence:**
- 00-intake.md: "Done: 0 of 16 (0%)"
- 00-intake.md quality assessment: "Implementation Readiness: 2/10"
- Overall intake quality: 4/10 (lowest recorded)

**Impact:**
This pipeline run is effectively a design review and deployment planning exercise, not a code review. No Apex code exists to review. The value of this run is in identifying blockers and design risks early — which it has accomplished through F-01 through F-09.

**Recommendation:**
1. Re-run the pipeline when Phase 1 child stories reach 50%+ Done for a meaningful code review.
2. Use this run's findings as a pre-implementation quality gate checklist.
3. Track child story progress in weekly stand-ups with a target: 4+ stories Done before next pipeline run.

---

### F-11 — NFR Targets from Cancelled NGASIM-2549 Should Be Preserved

| Field | Value |
|---|---|
| Severity | **INFO** |
| Category | Process |
| AC Impacted | NFR-01 through NFR-06 |
| Source | 00-intake.md NGASIM-2549, 01-plan.md R-11 |

**Description:**
NGASIM-2549 ("NFR for NGASIM-76") was cancelled, but the story contained performance targets that were captured in 00-intake.md (page load < 3s, API response < 2s, 1000 concurrent sessions, etc.). These NFR targets are now orphaned — they exist in the pipeline artifacts but not in any active Jira story.

**Evidence:**
- 00-intake.md NFR table: 6 NFR requirements derived from cancelled NGASIM-2549
- 01-plan.md R-11: "NFR targets from NGASIM-2549 (cancelled) not formally tracked"
- 02-architecture.md performance considerations: targets referenced but no traceability to active Jira story

**Impact:**
Without a Jira story, NFR targets will not be included in QA test plans, UAT acceptance criteria, or production readiness reviews. Performance degradation may go undetected.

**Recommendation:**
1. Create a new Jira story: "NGASIM-76: NFR Validation" to formalize the 6 NFR targets.
2. Alternatively, add NFR targets as acceptance criteria on the parent Feature (NGASIM-76).
3. Include NFR validation in Phase 2 or Phase 3 exit criteria.
4. Screen pop latency (NFR-06: < 2s) is especially critical for Inside Sales UX — this should be tested in Phase 1.

---

## Cross-Artifact Consistency Check

| Check | Result | Notes |
|---|---|---|
| All ACs (01-plan) have tests planned (02-architecture handoff) | **PASS** | AC-01 through AC-17 all have corresponding test requirements in 02-architecture.md TDD handoff |
| All ADRs (02-architecture) trace to ACs | **PASS** | ADR-005→AC-02/03/04, ADR-006→AC-08/10, ADR-007→AC-01/05/09, ADR-008→AC-14 |
| All risks (01-plan) have mitigations | **PASS** | R-01 through R-11 all have mitigation strategies and assigned owners |
| Metadata inventory matches implementation phases | **PASS** | 23 items across 3 phases, all sequenced correctly with dependency chains |
| SOQL queries use bind variables (architecture) | **PASS** | InsideSalesScreenPopResolver design uses `:ani` bind variable pattern |
| Test coverage estimate meets 80% target | **PASS** | Architecture specifies 85%+ for all three Apex classes |
| DevInt2 data referenced accurately | **PASS** | ACLightningAdapter, sfdc_phone, AC_CallRecording, CTI_Integration_Access match NGPSTE-132 intake data |
| Child story status matches Jira | **PASS** | 0 Done, 2 To Verify, 4 Technical Refinement, 7 To Do, 2 Cancelled — consistent across all artifacts |
| NGPSTE-132 dependency consistently flagged | **PASS** | All artifacts reference NGPSTE-132 as gating prerequisite |
| Permission model segregation (IS vs Care) defined | **PASS** | 02-architecture.md segregation table clearly differentiates IS_CTI_Agent_Access from CTI_Agent_Access |

---

## Recommendations Summary

| # | Action | Priority | Owner | Phase |
|---|---|---|---|---|
| 1 | Deploy NGPSTE-132 metadata to orgsyncng (F-01) | **Must** | DevOps | Pre-Phase 1 |
| 2 | Add deterministic ordering and disambiguation to screen pop SOQL (F-02) | **Must** | Dev lead | Phase 1 |
| 3 | Create Named Credential for Amazon Connect API (F-03) | **Must** | DevOps/AWS | Pre-Phase 2 |
| 4 | Design WhoId context-sharing mechanism for Task creation (F-04) | Should | Dev lead | Phase 2 |
| 5 | Add bulk test for concurrent VoiceCall→Task creation (F-05) | Should | QA lead | Phase 2 |
| 6 | Define queue membership criteria for Inside Sales (F-06) | Should | Config lead | Phase 1 |
| 7 | Get PO confirmation on disposition picklist values (F-07) | Could | PM | Pre-Phase 2 |
| 8 | Initiate TTEC coordination for IVR redesign (F-08) | Should | PM | Current sprint |
| 9 | Add OrgSync field mapping for Task custom fields (F-09) | Should | Integration lead | Phase 2 |
| 10 | Re-run pipeline at 50%+ story completion (F-10) | Could | Process owner | Ongoing |
| 11 | Create NFR Jira story to formalize performance targets (F-11) | Should | QA lead | Current sprint |

---

## Handoff to BUILD-FIX

**Directive:** The build-fix agent must:

1. Resolve F-06 by producing Queue metadata XML with member specifications for Inside_Sales_Voice and HCP_Inbound_Voice.
2. Produce metadata XML for all Phase 1 items: ServicePresenceStatus (3 IS-specific records), PermissionSet (IS_CTI_Base), PermissionSetGroup (IS_CTI_Agent_Access), SoftphoneLayout (IS_Softphone_Layout), Queue definitions.
3. Produce CustomField XML for Phase 2 fields: Task.Call_Disposition__c, Task.Call_Duration_Seconds__c, VoiceCall.Recording_Opted_Out__c.
4. Generate pseudo-code for InsideSalesScreenPopResolver (not deployable without full implementation but establishes the waterfall pattern).
5. Define deployment order respecting metadata dependencies.
6. Run pre-deployment validation checklist.
7. Report addressed review findings.

**Blocking items for deployment:**
- F-01 (NGPSTE-132 deployment) must complete before any NGASIM-76 metadata can be deployed.
- F-03 (Named Credential) must be created before RecordingOptOutController implementation.
- F-08 (TTEC IVR changes) must be initiated before Phase 3 HCP routing can be tested.
