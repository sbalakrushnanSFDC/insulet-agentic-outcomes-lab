# NGPSTE-132: PLAN

> **Pipeline Stage:** 01-plan
> **Produced by:** planner agent
> **Input:** 00-intake.md + DevInt2 live data
> **Run ID:** NGPSTE-132-run-001
> **Timestamp:** 2026-03-25T00:00:00Z
> **Status:** COMPLETE — handed off to ARCHITECTURE

---

## Planning Decisions

| # | Decision | Rationale |
|---|---|---|
| PD-01 | Use existing ACLightningAdapter Call Center (already registered in DevInt2) | Adapter is installed and active. No reason to create a new one. |
| PD-02 | Leverage sfdc_phone ServiceChannel for Omni-Channel voice routing | ServiceChannel already targets VoiceCall entity. Reuse over recreation. |
| PD-03 | Add ServicePresenceStatus configuration for voice agents | Gap identified in intake — agents need Available/Busy/ACW states. |
| PD-04 | Retain Open CTI pattern; defer SCV migration | Amazon Connect is "very customized" — SCV would require contact flow rebuilds. |
| PD-05 | Extend AC_CallRecording and CTI_Integration_Access permission sets | Permission sets exist in DevInt2. Extend assignments rather than creating new ones. |
| PD-06 | Track Classic migration as a gated sub-phase | NGPSTE-1123 still To Do — don't block Lightning work on Classic completion. |

---

## Formalized Acceptance Criteria

Derived from child story descriptions (NGPSTE-161, -833, -840, -1123), the parent Feature
description, and DevInt2 live state. Each AC traces to at least one source.

| AC ID | Acceptance Criterion | Source | Priority | Verification Method |
|---|---|---|---|---|
| AC-01 | CTI adapter is installed and registered as ACLightningAdapter Call Center in the target org | NGPSTE-161 (Done), DevInt2 CallCenter records | Must Have | SOQL: `SELECT Id, DeveloperName FROM CallCenter WHERE DeveloperName = 'ACLightningAdapter'` |
| AC-02 | Agents can receive inbound calls via the Lightning softphone utility bar component | Feature description, NGPSTE-161 | Must Have | Manual test: place inbound call → softphone rings |
| AC-03 | Agents can make outbound calls from Contact and Case record pages using click-to-dial | Feature description | Must Have | Manual test: click phone field → outbound call initiates |
| AC-04 | Screen pop resolves to correct Contact record based on ANI/caller ID lookup | Feature description (CTI standard) | Must Have | Automated test: simulate inbound with known ANI → Contact opens |
| AC-05 | Call recordings are accessible to users with AC_CallRecording permission set | DevInt2 AC_CallRecording PermissionSet | Must Have | Permission set assignment → verify recording playback |
| AC-06 | Omni-Channel routes voice work items to available agents via sfdc_phone ServiceChannel | DevInt2 sfdc_phone ServiceChannel | Must Have | SOQL + routing test: voice work item → agent assignment |
| AC-07 | Agent presence states (Available, Busy, After-Call Work) are configured and functional for voice channel | Gap from intake (no ServicePresenceStatus records) | Must Have | SOQL: `SELECT Id, MasterLabel FROM ServicePresenceStatus` |
| AC-08 | CTI_Integration_Access permission set grants necessary API access for CTI operations | DevInt2 CTI_Integration_Access PermissionSet | Must Have | Permission check: user with PS can invoke CTI APIs |
| AC-09 | Classic-to-Lightning adapter migration preserves existing Call Center configuration and routing rules | NGPSTE-1123 (To Do) | Should Have | Regression test: compare Classic vs Lightning adapter behavior |
| AC-10 | TTEC agents can access CTI features with their profile and permission set assignments | NGPSTE-840 (Done) | Must Have | Login as TTEC profile → verify softphone loads |
| AC-11 | Inbound call with unrecognized ANI shows new Contact creation form | Derived (negative path) | Should Have | Manual test: call from unknown number → new Contact form |
| AC-12 | CTI integration handles Amazon Connect API outages gracefully without crashing the agent desktop | Derived (NFR) | Must Have | Simulate API timeout → verify error message, no crash |

---

## Implementation Phases

### Phase 1: Call Center Configuration and Lightning CTI Adapter Validation (Size: S)

**Target:** Persona Release 1 (Project Infinity SOW MVP)
**Duration:** 1 sprint
**Dependencies:** None (adapter already installed)

| Task | Description | Owner | Status |
|---|---|---|---|
| P1-T1 | Validate ACLightningAdapter Call Center registration in DevInt2 | Config team | Verify (NGPSTE-161 Done) |
| P1-T2 | Verify Lightning app utility bar includes Open CTI softphone | Config team | Configure |
| P1-T3 | Validate click-to-dial from Contact and Case page layouts | Config team | Configure |
| P1-T4 | Test inbound call reception via Lightning softphone | QA | Test |
| P1-T5 | Document Call Center XML configuration for migration reference | Docs | Document |

**Exit criteria:** AC-01, AC-02, AC-03 verified in DevInt2.

### Phase 2: Omni-Channel Routing and Agent Presence Status Setup (Size: M)

**Target:** Persona Release 1
**Duration:** 1–2 sprints
**Dependencies:** Phase 1 complete

| Task | Description | Owner | Status |
|---|---|---|---|
| P2-T1 | Create ServicePresenceStatus records: Available_Voice, Busy_Voice, AfterCallWork_Voice | Config team | New |
| P2-T2 | Configure Omni-Channel routing for sfdc_phone ServiceChannel | Config team | Configure |
| P2-T3 | Assign ServicePresenceStatus to voice-capable profiles | Config team | Configure |
| P2-T4 | Configure routing priority and overflow rules | Config team | Configure |
| P2-T5 | Test agent presence state transitions | QA | Test |
| P2-T6 | Validate voice work item routing to available agents | QA | Test |

**Exit criteria:** AC-06, AC-07 verified. Agents can set presence and receive routed calls.

### Phase 3: Screen Pop, Permissions, and Agent Enablement (Size: L)

**Target:** Persona Release 1 / Persona Release 2
**Duration:** 2–3 sprints
**Dependencies:** Phase 1 + Phase 2 complete

| Task | Description | Owner | Status |
|---|---|---|---|
| P3-T1 | Implement screen pop resolver (ANI → Contact lookup via Open CTI onNavigationChange) | Dev team | New |
| P3-T2 | Handle unknown ANI — route to new Contact creation form | Dev team | New |
| P3-T3 | Assign AC_CallRecording permission set to authorized profiles | Config team | Configure |
| P3-T4 | Assign CTI_Integration_Access permission set to CTI users | Config team | Configure |
| P3-T5 | Validate TTEC agent access (profile + permission set combination) | QA | Test |
| P3-T6 | Validate call recording access/deny scenarios | QA | Test |
| P3-T7 | Classic → Lightning migration validation (NGPSTE-1123 dependency) | Config team | Blocked |
| P3-T8 | Error handling for Connect API outages | Dev team | New |
| P3-T9 | End-to-end integration test across all ACs | QA | Test |

**Exit criteria:** AC-04, AC-05, AC-08, AC-09, AC-10, AC-11, AC-12 verified.

---

## Risk Register

| ID | Risk | Prob | Impact | Severity | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R-01 | No formal ACs on parent Feature — scope ambiguity | High | High | Critical | Formalized 12 ACs in this plan (above). Seek PO sign-off. | Planner |
| R-02 | Amazon Connect is "very customized" — migration complexity | High | High | Critical | Conduct Connect contact flow audit before Phase 3. Document all custom Lambdas. | Architect |
| R-03 | NGPSTE-1123 (Classic Dev Part 3) still To Do — blocks AC-09 | Medium | High | High | Decouple Classic migration from Lightning phases. Track as gated sub-phase. | PM |
| R-04 | TTEC collaboration dependency — external partner schedule | Medium | Medium | Medium | Coordinate TTEC UAT window in Phase 3 planning. | PM |
| R-05 | ServicePresenceStatus not configured — agents lack presence states | High | Medium | High | Phase 2 explicitly creates these records. Prioritize. | Config lead |
| R-06 | NGPSTE-644 (Lambda) cancelled — potential integration gap | Medium | Medium | Medium | Confirm Lambda functions deployed outside Jira tracking. Audit AWS Console. | Dev lead |
| R-07 | SCV vs Open CTI — deferred decision may force future rework | Medium | High | High | Document ADR in architecture stage. Include SCV migration path estimate. | Architect |
| R-08 | NGCCB-20 approval status unknown | Medium | High | High | Query NGCCB-20 status. If unapproved, escalate to CCB chair. | PM |
| R-09 | NGASIM-76 blocked by this feature — downstream pressure | Low | High | Medium | Communicate timeline to NGASIM-76 owner. Provide Phase 1 date. | PM |

---

## Dependencies Table

| Dependency | Type | Status | Impact if Delayed | Mitigation |
|---|---|---|---|---|
| NGPSTE-161 (Install Package) | Predecessor | Done | N/A — completed | N/A |
| NGPSTE-833 (Install Package Part 2) | Predecessor | Done | N/A — completed | N/A |
| NGPSTE-840 (TTEC Collaboration) | Predecessor | Done | N/A — completed | N/A |
| NGPSTE-1123 (Classic Dev Part 3) | Parallel | To Do | Blocks AC-09 Classic migration validation | Decouple; validate Lightning path first |
| NGPSTE-644 (Lambda Package) | Cancelled | Cancelled | Lambda functions may not be in Salesforce | Audit AWS to confirm Lambda deployment |
| NGPSTE-888 (R2 Clone) | Successor | Persona R2 | Architectural decisions constrain R2 | Document extensibility in ADRs |
| NGCCB-20 (CCB Review) | Governance | Unknown | Could block entire feature | Query status immediately |
| NGASIM-76 (Blocked Feature) | Downstream | Blocked | Downstream delay | Provide Phase 1 completion date |
| Amazon Connect API | External | Active | CTI integration fails | Named Credential + error handling |
| TTEC Partner | External | Active | Phase 3 UAT delayed | Pre-schedule UAT window |

---

## Metadata Inventory (Planned)

| # | Metadata Type | API Name | Phase | Action |
|---|---|---|---|---|
| 1 | CallCenter | ACLightningAdapter | 1 | Validate (exists) |
| 2 | CallCenter | ACClassicAdapter | 3 | Migrate config |
| 3 | FlexiPage | Lightning app with softphone | 1 | Configure |
| 4 | ServiceChannel | sfdc_phone | 2 | Validate (exists) |
| 5 | ServicePresenceStatus | Available_Voice | 2 | Create |
| 6 | ServicePresenceStatus | Busy_Voice | 2 | Create |
| 7 | ServicePresenceStatus | AfterCallWork_Voice | 2 | Create |
| 8 | PermissionSet | AC_CallRecording | 3 | Validate + assign |
| 9 | PermissionSet | CTI_Integration_Access | 3 | Validate + assign |
| 10 | ApexClass | ScreenPopResolver | 3 | Create |
| 11 | ApexClass | ScreenPopResolverTest | 3 | Create |
| 12 | NamedCredential | AmazonConnect_API | 3 | Create |
| 13 | CustomMetadata | CTI_Config__mdt | 3 | Create |
| 14 | Layout | Contact-CTI layout | 1 | Modify |
| 15 | Layout | Case-CTI layout | 1 | Modify |

---

## Effort Estimation

| Phase | Size | Sprints | Story Points | Confidence |
|---|---|---|---|---|
| Phase 1 — Call Center + CTI Adapter | S | 1 | 5 | High (adapter exists) |
| Phase 2 — Omni-Channel + Presence | M | 1–2 | 13 | Medium (new config) |
| Phase 3 — Screen Pop + Permissions + Migration | L | 2–3 | 21 | Low (custom Apex + Classic migration) |
| **Total** | | **4–6** | **39** | |

---

## Handoff to ARCHITECTURE

**Directive:** The architect agent must:

1. Produce ADR-001: ACLightningAdapter reuse vs custom adapter.
2. Produce ADR-002: Open CTI vs Service Cloud Voice — with SCV migration cost estimate.
3. Produce ADR-003: Omni-Channel routing configuration for voice.
4. Produce ADR-004: Permission set strategy (extend existing vs Permission Set Group).
5. Design component integration diagram: Amazon Connect → CTI Adapter → Salesforce → Omni-Channel → Agent.
6. Specify object model: CallCenter, VoiceCall, ServiceChannel, ServicePresenceStatus, PermissionSet.
7. Detail integration points: Named Credential for Connect API, S3 for recordings, Lambda invocations.
8. Enumerate metadata inventory with per-item deployment instructions.
