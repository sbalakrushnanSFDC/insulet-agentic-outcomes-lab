# Outcome Metadata

> Copy this file into `outcomes/{YEAR-MONTH}/{JIRA-KEY}/outcome-metadata.md` and fill in all fields before opening a PR.
> Fields marked **[required]** must be completed. Fields marked **[if available]** should be filled when data exists.

---

## Feature Identification

| Field | Value |
|-------|-------|
| **Feature ID** [required] | <!-- e.g. NGOMCT-344 --> |
| **Feature Summary** [required] | <!-- One-sentence description from Jira title --> |
| **Jira Project** [required] | <!-- e.g. NGOMCT --> |
| **Jira Status at Run Time** [required] | <!-- e.g. Feature Definition, In Progress --> |
| **Jira Priority** [required] | <!-- e.g. Critical, High, Medium --> |
| **Team** [required] | <!-- e.g. Team1 / Omnichannel --> |
| **Sprint / Quarter** [if available] | <!-- e.g. Q1 2026, Sprint 14 --> |

---

## Source References

| Source | URL / Reference |
|--------|----------------|
| **Jira Story** [required] | <!-- https://insulet.atlassian.net/browse/{JIRA-KEY} --> |
| **Confluence Page** [if available] | <!-- CON-### or full URL --> |
| **Jira Align Feature** [if available] | <!-- Feature name or URL --> |
| **Parent Epic** [if available] | <!-- Epic Jira key --> |
| **Linked Stories (blockers/blocked-by)** [if available] | <!-- Comma-separated Jira keys --> |

---

## Pipeline Execution

| Field | Value |
|-------|-------|
| **Pipeline Version** [required] | <!-- From status.json pipeline_version field --> |
| **Run Date** [required] | <!-- YYYY-MM-DD --> |
| **ECC Framework Version** [if available] | <!-- e.g. ECC v1.0 --> |
| **Custom Agents Used** [required] | <!-- e.g. salesforce-deployer, jira-reader --> |
| **Orchestration Prompt ID** [if available] | <!-- Reference to the prompt that initiated the run, e.g. chat UUID --> |
| **Target Org (deploy)** [required] | <!-- e.g. orgsyncng --> |
| **Source Org (retrieve)** [required] | <!-- e.g. DevInt2 --> |

### Pipeline Step Summary

| Step | Agent | Status | Artifact |
|------|-------|--------|----------|
| INTAKE | orchestrator | <!-- pass/fail/partial --> | 00-intake.md |
| PLAN | planner | <!-- pass/fail/partial --> | 01-plan.md |
| ARCH | architect | <!-- pass/fail/partial --> | 02-architecture.md |
| BUILD | tdd-guide | <!-- pass/fail/partial --> | 03-tdd.md |
| REVIEW | code-reviewer | <!-- pass/fail/partial --> | 04-code-review.md |
| STABILIZE | build-error-resolver | <!-- pass/fail/partial --> | 05-build-fix.md |
| VALIDATE | e2e-runner | <!-- pass/fail/partial --> | 06-e2e.md |
| SECURE | security-reviewer | <!-- pass/fail/partial --> | 07-security.md |
| CLEAN | refactor-cleaner | <!-- pass/fail/partial --> | 08-refactor.md |
| DOC | doc-updater | <!-- pass/fail/partial --> | 09-docs.md |

*Copy the actual step statuses from `pipeline/status.json`.*

---

## Agent Assumptions

> List the assumptions the agent made during planning and execution. These are surfaced in `00-intake.md` and `01-plan.md`. Be explicit — reviewers need to know what the agent took for granted.

1. <!-- Assumption 1: e.g. "Training__c object exists with standard fields; schema retrieved from DevInt2 metadata" -->
2. <!-- Assumption 2 -->
3. <!-- Add more as needed -->

---

## Known Gaps

> List what the agent could not do, did not do correctly, or could not verify. Include any data sources that were unavailable.

| Gap | Category | Severity | Notes |
|-----|----------|----------|-------|
| <!-- e.g. "Confluence CON-13 body not fetched — auth required" --> | Data Missing | Medium | <!-- How this affected the output --> |
| <!-- Add more rows as needed --> | | | |

*Categories: Prompt Error / Logic Gap / Data Missing / Scope Drift / Security Concern*
*Severity: Critical / High / Medium / Low*

---

## Reviewer Notes

> Leave this section blank before opening the PR. Reviewers add their notes here or in GitHub Issues.

- <!-- Reviewer name / date / notes -->

---

## Links to Related Feedback Issues

> Populated after review. Add links to GitHub Issues opened against this outcome.

- <!-- #123 — [Gap title] -->
