# NGPSTE-132: CODE REVIEW

> **Pipeline Stage:** 04-code-review
> **Produced by:** code-reviewer agent
> **Input:** 00-intake.md, 01-plan.md, 02-architecture.md, 03-tdd.md
> **Run ID:** NGPSTE-132-run-001
> **Timestamp:** 2026-03-25T00:00:00Z
> **Status:** COMPLETE — handed off to BUILD-FIX

---

## Review Summary

| Severity | Count | Action Required |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 3 | Must resolve before deployment |
| MEDIUM | 4 | Should resolve; acceptable risk if deferred with justification |
| LOW | 3 | Address during implementation or defer to backlog |
| INFO | 2 | Advisory observations |
| **Total** | **12** | |

### Verdict: **CONDITIONAL PASS**

The feature is architecturally sound with well-reasoned ADRs. The primary risks are
configuration gaps (ServicePresenceStatus, Lambda), not code quality issues. Conditional
on resolving HIGH findings F-01 and F-02 before Phase 2 go-live.

---

## Findings

### F-01 — No ServicePresenceStatus Configured in DevInt2

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Configuration Gap |
| AC Impacted | AC-06, AC-07 |
| Source | DevInt2 SOQL: `SELECT Id FROM ServicePresenceStatus` → 0 rows |
| Phase Impacted | Phase 2 (Omni-Channel Routing and Agent Presence) |

**Description:**
DevInt2 has zero ServicePresenceStatus records. Without these, agents cannot set their
availability for the voice channel. Omni-Channel cannot route voice work items because
no presence state mapping exists for sfdc_phone ServiceChannel.

**Evidence:**
- 00-intake.md: "ServicePresenceStatus: None configured yet"
- 02-architecture.md ADR-003: "Create ServicePresenceStatus records for Available_Voice, Busy_Voice, AfterCallWork_Voice"
- 03-tdd.md T-09: SOQL validation expects 3 rows post-deployment

**Impact:**
AC-06 (Omni-Channel routing) and AC-07 (presence states) cannot be satisfied without this
configuration. Phase 2 is entirely blocked.

**Recommendation:**
1. Create ServicePresenceStatus metadata in Phase 2 deployment package (already planned).
2. Add pre-deployment validation script that checks for these records.
3. Add ServicePresenceStatus to the Phase 2 deployment checklist as a gating item.

---

### F-02 — NGPSTE-644 (Lambda Package Install) Cancelled — Integration Gap Risk

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Scope Gap |
| AC Impacted | AC-04 (screen pop depends on Connect data), AC-12 (error handling) |
| Source | Jira NGPSTE-644: Status = Cancelled |
| Phase Impacted | Phase 3 (Screen Pop, Permissions, Agent Enablement) |

**Description:**
NGPSTE-644 ("Install Amazon Connect Salesforce Lambda Package") was cancelled. Lambda
functions are invoked by Amazon Connect contact flows to perform Salesforce data lookups
(e.g., caller identification for screen pop). If these Lambda functions are not deployed
via an alternative mechanism, the contact flow will fail to pass caller context to
Salesforce, breaking screen pop and potentially call routing.

**Evidence:**
- 00-intake.md child story table: NGPSTE-644 Cancelled
- 02-architecture.md Integration Point #4: "Lambda functions may be deployed outside Salesforce package"
- 02-architecture.md risk: "If Lambda functions are not deployed, Contact Flow lookups will fail silently"

**Impact:**
Without Lambda functions, Amazon Connect cannot perform real-time Salesforce lookups during
call routing. Screen pop (AC-04) relies on ANI being passed from Connect to Salesforce
via the CTI adapter, which may depend on Lambda-enriched contact attributes.

**Recommendation:**
1. **Immediate action:** Audit AWS Lambda console for existing functions related to the Salesforce-Connect integration.
2. If Lambda functions exist (deployed outside Jira tracking), document them and add monitoring.
3. If Lambda functions do NOT exist, re-open NGPSTE-644 or create a new story to address the gap.
4. Add Lambda health check to T-12 (Connect API outage handling test).

---

### F-03 — SCV vs Open CTI Decision Should Be Formally Documented for Future Migration

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Architecture Documentation |
| AC Impacted | None directly (future planning) |
| Source | 02-architecture.md ADR-002 |

**Description:**
ADR-002 correctly chooses Open CTI over SCV and provides rationale. However, the ADR
should include a more detailed SCV migration cost estimate and a triggering condition
(e.g., "revisit when Connect customization is reduced to OOB contact flows" or "revisit
when Einstein Call Coaching becomes a business requirement").

**Evidence:**
- Jira description: "Consider thinking about Service Cloud Voice"
- ADR-002 alternatives: "SCV with Amazon Connect as telephony provider — rejected for now"
- ADR-002 consequences: "No Einstein Call Coaching, no native voice transcription"

**Impact:**
Future architects/PMs may not understand when to revisit the SCV decision. Without a
triggering condition, the decision may be revisited unnecessarily or too late.

**Recommendation:**
1. Add "Revisit Trigger" section to ADR-002 specifying conditions for SCV re-evaluation.
2. Include rough SCV migration effort estimate (the architecture doc mentions 3–6 months — formalize this).
3. Link ADR-002 to NGPSTE-888 (R2 clone) since SCV could be an R2 initiative.

---

### F-04 — Call Recording S3 Access Pattern Not Fully Specified

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Security / Architecture |
| AC Impacted | AC-05 |
| Source | 02-architecture.md Integration Point #3 |

**Description:**
The architecture describes S3 pre-signed URLs for call recording playback and mentions
a Named Credential for Connect API access. However, the specification lacks detail on:
- S3 bucket encryption policy (at-rest encryption)
- Pre-signed URL expiration duration
- IAM role least-privilege scope
- Data residency requirements (if recordings contain PII)
- Retention policy alignment with company data governance

**Evidence:**
- 02-architecture.md: "S3 pre-signed URLs served via Connect API"
- 02-architecture.md security: "S3 pre-signed URLs expire" (no duration specified)
- 00-intake.md: NFR story NGPSTE-905 was Cancelled — no formal NFR documentation

**Impact:**
Without explicit security controls, call recordings could be exposed beyond intended
access windows or retained beyond policy limits.

**Recommendation:**
1. Specify pre-signed URL TTL (recommend 300s / 5 minutes).
2. Document S3 bucket encryption requirement (AES-256 or KMS).
3. Define IAM policy with `s3:GetObject` on specific recording prefix only.
4. Add data retention policy to NFR documentation (since NGPSTE-905 was cancelled, capture here).

---

### F-05 — NGPSTE-1123 (Classic Dev) Still in To Do — Parallel Work Stream Risk

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Delivery Risk |
| AC Impacted | AC-09 |
| Source | Jira NGPSTE-1123: Status = To Do |

**Description:**
NGPSTE-1123 ("Classic Dev: Install Package Part 3") is the only child story still in To Do.
It is required for Classic-to-Lightning migration validation (AC-09). The plan correctly
gates AC-09 on NGPSTE-1123, but there is no timeline or owner assigned.

**Evidence:**
- 00-intake.md child story table: NGPSTE-1123 To Do
- 01-plan.md Phase 3 task P3-T7: "Blocked" by NGPSTE-1123
- 03-tdd.md T-11: "Blocked By: NGPSTE-1123"

**Impact:**
Low immediate impact since Phases 1–2 are not blocked. However, if NGPSTE-1123 remains
in To Do indefinitely, AC-09 cannot be verified and Classic users lose CTI access.

**Recommendation:**
1. Assign an owner and target sprint for NGPSTE-1123.
2. If Classic support is being deprecated, formally cancel AC-09 and document the decision.
3. Add NGPSTE-1123 status to weekly stand-up tracking.

---

### F-06 — No Apex Code Review Possible — Implementation Is Primarily Configuration

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Process |
| AC Impacted | All |
| Source | 02-architecture.md, 03-tdd.md |

**Description:**
The only custom Apex in NGPSTE-132 is ScreenPopResolver (Phase 3). The code-reviewer
agent cannot perform a traditional code review on configuration-only work. This means
Phases 1 and 2 will not have Apex artifacts to review.

**Evidence:**
- 02-architecture.md metadata inventory: Only 2 ApexClass items (ScreenPopResolver, test class) out of 15 metadata items.
- 03-tdd.md: 14 of 20 tests are SOQL validation or manual — only 6 are automated Apex.

**Impact:**
Standard code review gates (style, security, performance) apply only to Phase 3. Phases 1–2
need a **configuration review** gate instead.

**Recommendation:**
1. Add a "configuration review" stage for Phases 1–2 that validates:
   - CallCenter XML settings
   - FlexiPage utility bar configuration
   - ServicePresenceStatus metadata values
   - Omni-Channel routing configuration
2. Use SOQL validation queries (SQ-01 through SQ-08) as the automated review mechanism.
3. When ScreenPopResolver code is written in Phase 3, schedule a dedicated code review.

---

### F-07 — Consider Permission Set Group to Bundle AC_CallRecording + CTI_Integration_Access

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Best Practice |
| AC Impacted | AC-05, AC-08 |
| Source | 02-architecture.md ADR-004 |

**Description:**
ADR-004 mentions a Permission Set Group (CTI_Agent_Bundle) to bundle AC_CallRecording
and CTI_Integration_Access. This is correctly identified in the metadata inventory (#15)
but not reflected in the test plan.

**Evidence:**
- 02-architecture.md metadata #15: "CTI_Agent_Bundle — Create (bundles #9 + #10)"
- 03-tdd.md: No test for Permission Set Group existence or membership

**Impact:**
Low — Permission Set Groups are an assignment convenience. Missing the group does not
block functionality. However, without the group, admins must assign two permission sets
individually, increasing onboarding friction and error risk.

**Recommendation:**
1. Add SOQL validation query for Permission Set Group.
2. Include in Phase 3 deployment checklist.

```sql
SELECT Id, DeveloperName, MasterLabel
FROM PermissionSetGroup
WHERE DeveloperName = 'CTI_Agent_Bundle'
```

---

### F-08 — ScreenPopResolver Design Review (Pre-Implementation)

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Code Design |
| AC Impacted | AC-04, AC-11 |
| Source | 03-tdd.md test specifications |

**Description:**
Based on the test specifications in 03-tdd.md, ScreenPopResolver has three code paths:
1. Known ANI → return Contact Id and screen pop URL
2. Unknown/null/empty ANI → return new Contact form URL
3. API error → return error message

Design observations from test code:
- `resolveContact(String ani)` appears to be a single static method. Consider splitting into
  `findContactByPhone` (SOQL) and `buildScreenPopUrl` (URL construction) for SRP.
- Null ANI handling (T-14) is tested but the method signature does not indicate nullable input.
  Add `@SuppressWarnings('PMD.NullAssignment')` or use explicit null guard.
- The test for API timeout (T-12) uses HttpCalloutMock, implying ScreenPopResolver makes
  HTTP callouts. Clarify whether this is for Connect API or purely SOQL-based.

**Recommendation:**
1. Split resolveContact into query + URL builder methods.
2. Add `@InvocableMethod` annotation if the resolver will be called from Flows.
3. Add explicit null/empty guard at method entry with descriptive error.
4. Clarify whether the method makes HTTP callouts (if not, T-12 should be on a different class).
5. Add governor limit consideration: if called per-call, SOQL query must be selective (indexed Phone field).

---

### F-09 — Missing Monitoring and Alerting Strategy

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Operational Readiness |
| AC Impacted | AC-12 |
| Source | 02-architecture.md |

**Description:**
No monitoring or alerting strategy is defined for the CTI integration. In production,
Amazon Connect outages, Lambda failures, or Omni-Channel routing errors need proactive
detection.

**Recommendation:**
1. Define CloudWatch alarms for Lambda function errors and Connect API latency.
2. Create a Salesforce report/dashboard for VoiceCall records with errors.
3. Set up Omni-Channel Supervisor alerts for routing failures.
4. Add monitoring to Phase 3 delivery scope or create a follow-up story.

---

### F-10 — Test Plan Missing Load/Performance Tests

| Field | Value |
|---|---|
| Severity | **INFO** |
| Category | Testing Completeness |
| AC Impacted | NFR-01, NFR-03 |
| Source | 03-tdd.md |

**Description:**
The test plan covers functional scenarios thoroughly but does not include load or
performance tests. NFR-01 specifies "CTI adapter latency < 2s for screen pop" and
02-architecture.md sets performance targets, but no test validates these under load.

**Recommendation:**
1. For Phase 3, consider a basic load test: 10 concurrent inbound calls → measure screen pop latency.
2. This may be out of scope for the initial release but should be tracked for production readiness.

---

### F-11 — Intake Quality Score Is Low (5/10) — Process Improvement

| Field | Value |
|---|---|
| Severity | **INFO** |
| Category | Process |
| AC Impacted | All |
| Source | 00-intake.md |

**Description:**
The intake assessment scored the feature at 5/10 overall, with Requirements Clarity at
4/10 and Test Readiness at 3/10. While the plan and architecture stages compensated by
deriving formal ACs and test specs, this indicates the feature entered the pipeline
under-specified.

**Recommendation:**
1. For future features, require PO to define acceptance criteria on the parent Feature before entering pipeline.
2. Require NFR documentation (or explicitly mark as N/A) — the cancellation of NGPSTE-905 left a gap.
3. Add an intake quality gate: features scoring below 5/10 should be returned for enrichment.

---

## Cross-Artifact Consistency Check

| Check | Result | Notes |
|---|---|---|
| All ACs (01-plan) have tests (03-tdd) | **PASS** | AC-01 through AC-12 all have corresponding tests T-01 through T-14 |
| All ADRs (02-architecture) trace to ACs | **PASS** | ADR-001→AC-01, ADR-002→AC-02/03/04, ADR-003→AC-06/07, ADR-004→AC-05/08 |
| All risks (01-plan) have mitigations | **PASS** | R-01 through R-09 all have mitigation strategies |
| Metadata inventory matches deployment phases | **PASS** | 15 items across 3 phases, all sequenced correctly |
| SOQL queries use bind variables | **PASS** | ScreenPopResolver test uses `:permSetName` bind variable pattern |
| Test coverage estimate meets 80% target | **PASS** | 90%+ estimated for ScreenPopResolver |
| DevInt2 data referenced accurately | **PASS** | CallCenter, PermissionSet, ServiceChannel data matches intake |
| Child story status matches Jira | **PASS** | 3 Done, 2 Cancelled, 1 To Do — consistent across all artifacts |

---

## Recommendations Summary

| # | Action | Priority | Owner | Phase |
|---|---|---|---|---|
| 1 | Create ServicePresenceStatus records (F-01) | **Must** | Config lead | Phase 2 |
| 2 | Audit AWS Lambda for Connect functions (F-02) | **Must** | Dev lead | Pre-Phase 3 |
| 3 | Add SCV migration trigger to ADR-002 (F-03) | Should | Architect | Phase 1 |
| 4 | Specify S3 recording security controls (F-04) | Should | Security lead | Phase 3 |
| 5 | Assign owner for NGPSTE-1123 (F-05) | Should | PM | Sprint planning |
| 6 | Add configuration review gate for Phases 1–2 (F-06) | Should | QA lead | Phase 1 |
| 7 | Add PermissionSetGroup validation query (F-07) | Could | QA | Phase 3 |
| 8 | Refine ScreenPopResolver design (F-08) | Should | Dev lead | Phase 3 |
| 9 | Define monitoring/alerting strategy (F-09) | Should | DevOps | Phase 3 |
| 10 | Plan load test for screen pop latency (F-10) | Could | QA | Post-Phase 3 |
| 11 | Improve intake quality gate (F-11) | Could | Process owner | Ongoing |

---

## Handoff to BUILD-FIX

**Directive:** The build-fix agent must:

1. Resolve F-01 by creating ServicePresenceStatus metadata files in the deployment package.
2. Resolve F-02 by auditing AWS Lambda (or documenting the gap for PO action).
3. Begin Phase 1 implementation: validate CallCenter, configure FlexiPage, modify layouts.
4. Run SOQL validation queries SQ-01 through SQ-04 against the target org post-deployment.
5. Report build results with pass/fail per AC for Phase 1.

**Blocking items for deployment:**
- F-01 (ServicePresenceStatus) must be resolved before Phase 2 deployment.
- F-02 (Lambda audit) must be resolved before Phase 3 deployment.
- F-05 (NGPSTE-1123) must be resolved before AC-09 verification.
