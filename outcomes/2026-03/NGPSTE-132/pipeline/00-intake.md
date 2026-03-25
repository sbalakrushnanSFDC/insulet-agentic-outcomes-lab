# NGPSTE-132: INTAKE

> **Pipeline Stage:** 00-intake
> **Produced by:** orchestrator agent
> **Run ID:** NGPSTE-132-run-001
> **Timestamp:** 2026-03-25T00:00:00Z
> **Status:** COMPLETE — handed off to PLAN

---

## Feature Metadata

| Field | Value |
|---|---|
| Key | NGPSTE-132 |
| Summary | Integrate Amazon Connect with NextGen |
| Type | Feature |
| Status | Feature Ready |
| Priority | Highest |
| Labels | AmazonConnect, CTI, DirectIntegration, NextGen, NextGenFoundational, NGPI2, Team2, retention |
| Fix Versions | Project Infinity SOW MVP, Persona Release 1, Persona Release 2 |
| Reporter | Jira originator (NGPSTE board) |
| Child Stories | 6 (3 Done, 2 Cancelled, 1 To Do) |
| Linked Issues | NGPSTE-888, NGCCB-20, NGASIM-76 |

## Description (verbatim from Jira)

> Integrate Amazon Connect with Salesforce NextGen to enable CTI integration so that
> customer care/product support can manage calls from Salesforce. Amazon Connect is
> currently very customized today. Consider thinking about Service Cloud Voice.

### Key Phrases Extracted

1. **"CTI integration"** — Computer Telephony Integration; primary integration pattern.
2. **"customer care/product support"** — two distinct persona groups will use the softphone.
3. **"very customized today"** — existing Amazon Connect instance has non-standard contact flows, Lambda hooks, and routing rules that must be preserved or migrated.
4. **"Consider thinking about Service Cloud Voice"** — SCV is an alternative but not mandated; decision required.

---

## Child Story Decomposition

| Key | Summary | Status | Implications |
|---|---|---|---|
| NGPSTE-161 | Install Package (Configure Call Center Details) | **Done** | Call Center records exist in DevInt2. ACLightningAdapter confirmed. |
| NGPSTE-644 | Install Amazon Connect Salesforce Lambda Package | **Cancelled** | Lambda integration gap — need to confirm if Lambda functions are handled outside Salesforce or if this is a real gap. |
| NGPSTE-833 | Install Package Part 2 | **Done** | Second phase of adapter/package install completed. |
| NGPSTE-840 | Install Package Part 3 - TTEC Insulet Collaboration | **Done** | TTEC-specific configuration completed. Implies external partner dependency. |
| NGPSTE-905 | NFR for NGPSTE-132 | **Cancelled** | Non-functional requirements story was cancelled. No formal NFR documentation. |
| NGPSTE-1123 | Classic Dev: Install Package Part 3 | **To Do** | Classic environment work still outstanding. Blocks full Classic-to-Lightning migration validation. |

### Completion Summary

- **Done:** 3 of 6 (50%)
- **Cancelled:** 2 of 6 (33%)
- **To Do:** 1 of 6 (17%)
- **Net completion (Done / non-cancelled):** 3 of 4 (75%)

---

## Requirements Extraction

Since NGPSTE-132 (parent Feature) has no formal acceptance criteria, requirements are
derived from child story descriptions, the feature description, and DevInt2 live state.

### Functional Requirements

| ID | Requirement | Source |
|---|---|---|
| FR-01 | CTI adapter must be installed and registered as a Salesforce Call Center | NGPSTE-161 (Done) |
| FR-02 | Lightning CTI adapter (ACLightningAdapter) must be the primary adapter | DevInt2 CallCenter records |
| FR-03 | Agents must receive inbound calls via Lightning softphone | Feature description |
| FR-04 | Agents must initiate outbound calls from Contact and Case records | Feature description |
| FR-05 | Screen pop must resolve caller to existing Contact based on ANI | Feature description (CTI standard) |
| FR-06 | Call recordings must be accessible to authorized users | DevInt2 AC_CallRecording PermissionSet |
| FR-07 | Omni-Channel must route voice work items to available agents | DevInt2 sfdc_phone ServiceChannel |
| FR-08 | Agent presence states must be configured for voice channel | Derived — sfdc_phone exists but no ServicePresenceStatus records |
| FR-09 | TTEC agents must have CTI access through their profile/permission set | NGPSTE-840 (Done) |
| FR-10 | Classic-to-Lightning adapter migration must preserve existing configuration | NGPSTE-1123 (To Do) |

### Non-Functional Requirements (derived)

| ID | Requirement | Source |
|---|---|---|
| NFR-01 | CTI adapter latency < 2s for screen pop | Industry standard for telephony UX |
| NFR-02 | Call recording storage must comply with data retention policies | AC_CallRecording permission implies recording storage |
| NFR-03 | Integration must handle Connect API outages gracefully | Feature description ("very customized") |

---

## DevInt2 Live Data Inventory

### CallCenter Records (5 found)

| Developer Name | Adapter Type | Implication |
|---|---|---|
| ACClassicAdapter | Classic CTI | Legacy adapter — Classic environment |
| ACConsoleAdapter | Console CTI | Service Console integration |
| ACLightningAdapter | Lightning CTI | **Primary target adapter** for NextGen |
| DevInt2ACLightningAdapter | Lightning CTI | Environment-specific variant |
| SITACLightningAdapter | Lightning CTI | SIT environment variant |

**Observation:** Multiple Lightning adapter variants exist. ADR needed on which adapter to standardize.

### Permission Sets (CTI-relevant)

| Name | Purpose |
|---|---|
| AC_CallRecording | Grants access to Amazon Connect call recordings |
| CTI_Integration_Access | Grants API-level access for CTI integration |

### ServiceChannel

| Developer Name | Related Entity | Master Label |
|---|---|---|
| sfdc_phone | VoiceCall | Phone |

**Observation:** VoiceCall standard object is available. This confirms Service Cloud Voice objects are provisioned even if SCV is not the active telephony model.

### ServicePresenceStatus

**None configured.** This is a gap — agents cannot set presence states for voice channel routing without ServicePresenceStatus records.

---

## Dependency Map

| Link Type | Key | Summary | Impact |
|---|---|---|---|
| is cloned by | NGPSTE-888 | R2 clone of NGPSTE-132 | Persona Release 2 will extend this feature. Changes here propagate. |
| relates to | NGCCB-20 | CCB item for Amazon Connect | Change Control Board review required. Governance dependency. |
| blocks | NGASIM-76 | Blocked by this feature | Downstream feature cannot proceed until CTI integration is stable. |

### Dependency Risks

1. **NGCCB-20:** If the CCB has not approved the Amazon Connect integration approach, implementation could be blocked or reversed.
2. **NGASIM-76:** Blocking relationship means delays in NGPSTE-132 cascade to NGASIM-76 delivery.
3. **NGPSTE-888:** R2 clone means any architectural decisions here constrain the R2 implementation.

---

## Risk Register (Intake-Level)

| ID | Risk | Probability | Impact | Category |
|---|---|---|---|---|
| R-01 | No formal acceptance criteria on parent Feature | High | High | Quality |
| R-02 | Amazon Connect "very customized" — migration complexity unknown | High | High | Technical |
| R-03 | Classic-to-Lightning migration (NGPSTE-1123 still To Do) | Medium | High | Delivery |
| R-04 | TTEC collaboration dependency — external partner schedule | Medium | Medium | External |
| R-05 | ServicePresenceStatus not configured — agents lack presence states | High | Medium | Configuration |
| R-06 | 2 child stories cancelled (Lambda install + NFR) — potential gaps | Medium | Medium | Scope |
| R-07 | SCV vs Open CTI decision not made — could force rework later | Medium | High | Architecture |
| R-08 | NGCCB-20 approval status unknown | Medium | High | Governance |

---

## Intake Quality Assessment

| Dimension | Score | Rationale |
|---|---|---|
| Requirements Clarity | 4/10 | No formal ACs on parent. Derived from child stories only. |
| Implementation Readiness | 6/10 | 3 of 4 active child stories Done. Adapters exist in DevInt2. |
| Risk Visibility | 5/10 | Significant unknowns around Connect customization depth. |
| Dependency Clarity | 7/10 | Jira links present. CCB and downstream impacts identified. |
| Test Readiness | 3/10 | NFR story cancelled. No test strategy documented. |
| **Overall** | **5/10** | Feature is partially implemented but poorly specified. |

---

## Handoff to PLAN

**Directive:** The planner agent must:

1. Derive formal acceptance criteria from child story descriptions — target 10+ ACs covering all FR/NFR items.
2. Query DevInt2 for full CTI metadata inventory (CallCenter XML, ConnectedApp, NamedCredential, CustomMetadata for Connect config).
3. Map the Classic → Lightning migration path using ACClassicAdapter and ACLightningAdapter configurations.
4. Resolve the SCV vs Open CTI architectural decision with a formal ADR.
5. Address the ServicePresenceStatus gap with a configuration plan.
6. Confirm NGCCB-20 approval status via atlassian-guardrails.
7. Produce implementation phases (S/M/L) aligned to Fix Versions.

**Blocking questions for stakeholders:**

- Is NGPSTE-644 (Lambda package) truly not needed, or was it completed outside Jira?
- What is the NGCCB-20 disposition? Has the CCB approved the Amazon Connect approach?
- Are TTEC agent profiles already provisioned in DevInt2?
