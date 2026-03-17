# Interpretation Guide

> How to read the artifacts produced by the Insulet Agentic Implementation Pipeline.

This guide is for cross-functional reviewers who are evaluating pipeline outputs. You do not need to understand Apex, LWC, or Salesforce internals to give useful feedback — but you do need to understand what each artifact is trying to do and where to look for gaps.

---

## The Pipeline at a Glance

The pipeline processes one Jira feature at a time through 10 sequential steps. Each step produces a markdown handoff artifact. Each artifact is the primary input for the next step.

```
INTAKE → PLAN → ARCH → BUILD → REVIEW → STABILIZE → VALIDATE → SECURE → CLEAN → DOC
  00       01     02     03      04        05          06         07       08      09
```

If a step fails, the pipeline triggers a **rework loop** — it goes back to the appropriate earlier step rather than proceeding forward. This is tracked in `status.json`.

---

## Artifact-by-Artifact Guide

### `00-intake.md` — INTAKE

**Produced by:** Orchestrator (initial triage)  
**What it contains:**

- Summary of the Jira story requirements
- Initial risk assessment
- A list of what data was available vs. not available at intake time
- Preliminary scope boundaries

**What to look for:**

- Are the requirements accurately summarized from the Jira story?
- Are the identified risks plausible?
- Does the scope boundary look correct, or did the agent include/exclude the wrong things?
- Did the agent note any unavailable data sources (e.g. Confluence auth failures)?

---

### `01-plan.md` — PLAN

**Produced by:** `planner` agent  
**What it contains:**

- Derived Acceptance Criteria (AC) — extracted or inferred from the Jira story
- Implementation phases and sequencing
- Dependency mapping
- Risk items with recommended mitigations
- Architecture decision hints passed to the next step

**What to look for:**

- Does the derived AC match what the Jira story actually requires?
- Are any ACs missing or over-specified?
- Were the phases broken down sensibly?
- Did the agent make any assumptions about missing data (e.g. Confluence content it could not retrieve)?

---

### `02-architecture.md` — ARCH

**Produced by:** `architect` agent  
**What it contains:**

- Component choices (e.g. Apex class vs. Flow vs. LWC)
- Object model and field usage
- Integration points (APIs, external systems)
- Salesforce-specific architectural decisions (governor limits, sharing model, security)
- Justification for key architectural choices

**What to look for:**

- Does the architecture match the requirements in `01-plan.md`?
- Are the Salesforce-specific constraints (governor limits, CRUD/FLS, sharing) addressed?
- Are the component choices justified?
- Does the architecture introduce unnecessary complexity?

---

### `03-tdd.md` — BUILD (TDD)

**Produced by:** `tdd-guide` agent  
**What it contains:**

- Test-first specification (what tests were written before implementation)
- RED phase: test cases defined, failing
- GREEN phase: minimal implementation to pass tests
- Coverage estimate

**What to look for:**

- Were tests written before the implementation (RED before GREEN)?
- Do the test cases cover the happy path and key error cases?
- Is the implementation minimal and focused on the tested behavior?
- Is the coverage estimate credible?

---

### `04-code-review.md` — REVIEW

**Produced by:** `code-reviewer` agent  
**What it contains:**

- Code quality findings: CRITICAL, HIGH, MEDIUM, LOW
- Specific file and line references for each finding
- Recommendations for each finding

**Understanding severity levels:**

| Severity | Meaning |
|----------|---------|
| CRITICAL | Must be fixed before any deployment; correctness or security issue |
| HIGH | Should be fixed; significant quality or maintainability problem |
| MEDIUM | Should be addressed; notable gap but tolerable short-term |
| LOW | Nice to fix; style or minor improvement |

**What to look for:**

- Were all CRITICAL issues resolved in `05-build-fix.md`?
- Are there any HIGH issues still open?
- Does the review look thorough, or did the agent only check surface-level issues?

---

### `05-build-fix.md` — STABILIZE

**Produced by:** `build-error-resolver` agent  
**What it contains:**

- Build or compilation errors encountered
- Fixes applied
- Confirmation of resolution

**What to look for:**

- Were all CRITICAL issues from `04-code-review.md` addressed here?
- Did the agent introduce any new issues while fixing?
- Are the fixes appropriate, or are they workarounds that paper over deeper problems?

---

### `06-e2e.md` — VALIDATE

**Produced by:** `e2e-runner` agent  
**What it contains:**

- End-to-end test plan against the dev sandbox
- Test execution results (or validated plan if sandbox was unavailable)
- Failures encountered and resolutions

**What to look for:**

- Were the E2E tests run against the real org (orgsyncng), or was this a paper exercise?
- Do the test scenarios cover the acceptance criteria from `01-plan.md`?
- Are there any open failures?

---

### `07-security.md` — SECURE

**Produced by:** `security-reviewer` agent  
**What it contains:**

- Security findings across the implemented code
- CRUD/FLS enforcement checks
- Injection risk assessment
- Sharing model verification
- OWASP-aligned checklist

**What to look for:**

- Are the identified security findings addressed, or are there open CRITICALs?
- Was CRUD/FLS enforcement verified?
- Did the agent check for sharing model compliance (`with sharing`, `without sharing`)?

---

### `08-refactor.md` — CLEAN

**Produced by:** `refactor-cleaner` agent  
**What it contains:**

- Dead code removal
- Constant extraction (replacing magic values with named constants)
- Naming and readability improvements
- Confirmation that behavior was not changed

**What to look for:**

- Were the changes purely cosmetic/structural, or did the agent accidentally alter behavior?
- Are the naming improvements sensible?
- Were the constants given meaningful names?

---

### `09-docs.md` — DOC

**Produced by:** `doc-updater` agent  
**What it contains:**

- Updated or created documentation artifacts
- API/method documentation
- Confluence update plan (or note if Confluence was inaccessible)
- Links between docs and implementation

**What to look for:**

- Does the documentation match the final implementation?
- Are the method signatures and behaviors accurately described?
- Did the agent note any documentation gaps (e.g. Confluence unavailable)?

---

## Understanding `status.json`

```json
{
  "feature_id": "NGOMCT-344",
  "pipeline_version": "1.0",
  "current_step": "COMPLETE",
  "steps": {
    "INTAKE": { "status": "pass", "completed_at": "...", "artifact": "00-intake.md" },
    "PLAN":   { "status": "pass", "completed_at": "...", "artifact": "01-plan.md" },
    ...
  },
  "rework_triggered": false,
  "last_updated": "..."
}
```

| Field | Meaning |
|-------|---------|
| `current_step` | Last step completed; `COMPLETE` means all 10 steps finished |
| `status` per step | `pass` / `fail` / `partial` |
| `rework_triggered` | Whether the pipeline looped back due to a failure |

A `fail` status on any step means the pipeline stopped or looped back. Look at the artifact for that step to understand why.

---

## Understanding `traceability.json`

This file maps implementation decisions back to:

- Jira Acceptance Criteria (AC)
- Confluence content (where available)
- Salesforce metadata discovered during retrieval

If a decision is marked `"source": "inferred"`, the agent did not have direct evidence — it made an assumption. These are the highest-priority areas for human review.

---

## Glossary

| Term | Definition |
|------|-----------|
| **AC** | Acceptance Criteria — the testable conditions that must be met for a Jira story to be considered done |
| **CRUD/FLS** | Create-Read-Update-Delete / Field-Level Security — Salesforce's permission enforcement model |
| **Governor Limits** | Salesforce runtime limits that prevent runaway code (e.g. max 100 SOQL queries per transaction) |
| **Invocable Method** | An Apex method that can be called from a Salesforce Flow via `@InvocableMethod` annotation |
| **DML** | Data Manipulation Language — Salesforce operations that write to the database (insert, update, delete) |
| **SOQL** | Salesforce Object Query Language — used to query data from Salesforce objects |
| **Bulkification** | Writing Apex to handle lists of records rather than single records, to avoid governor limit violations |
| **Sharing Model** | Controls which records a user can see/modify; `with sharing` enforces the user's permissions |
| **WITH SECURITY_ENFORCED** | SOQL clause that enforces field and object permissions at the query level |
| **ECC** | Everything-Claude-Code — the agentic implementation framework used to run the pipeline |
| **HITL** | Human-in-the-Loop — operating model where humans review and validate AI-generated outputs |
| **Rework Loop** | Pipeline behavior where a failing step causes the orchestrator to return to an earlier step |
