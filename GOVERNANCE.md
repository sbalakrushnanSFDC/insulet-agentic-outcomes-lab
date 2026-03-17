# Governance

This document defines how the Insulet Agentic Outcomes Lab is maintained, how feedback is triaged, and how the human-in-the-loop review model operates.

---

## Operating Principle

> Partial outputs and agentic drafts are expected and valuable. They reveal where the orchestration needs improvement. Publishing them is not a failure — it is a signal.

This repository exists to surface the gaps and assumptions in the agentic pipeline. The goal is not to curate only polished results, but to create a structured record of what the agent produced, what it got right, and where human judgment is still required.

---

## Roles and Responsibilities

| Role | Responsibilities |
|------|----------------|
| **Workflow Operator** | Runs the pipeline, curates and publishes artifacts, fills outcome-metadata.md, opens PR |
| **Cross-Functional Reviewer** | Reviews published outcomes, opens feedback issues, approves outcome PRs |
| **Workflow Designer** | Triages feedback issues, translates gaps into prompt/orchestration improvements, creates new pipeline iterations |
| **Repository Maintainer** | Manages branch protections, labels, templates, and governance updates |

---

## Issue Labels

Feedback issues use these standard labels, which map to the review_feedback.yml categories:

| Label | Meaning |
|-------|---------|
| `cat:prompt-error` | The agent's output was wrong due to a flawed prompt or instruction |
| `cat:logic-gap` | The reasoning or decision was incorrect, not just the prompt |
| `cat:data-missing` | A required data source was unavailable (e.g. Confluence auth failure) |
| `cat:scope-drift` | The agent went out of scope or included irrelevant content |
| `cat:success` | The outcome is a positive example worth preserving |
| `sev:critical` | Blocks use of the output; must be addressed before next iteration |
| `sev:high` | Significant gap; should be addressed in next iteration |
| `sev:medium` | Notable but tolerable; address when possible |
| `sev:low` | Minor issue; cosmetic or stylistic |
| `sev:informational` | Observation only; no action required |

---

## Feedback Triage Process

```
New Issue Opened
      │
      ▼
Workflow Designer reviews within 5 business days
      │
      ├── sev:critical → Create fix task immediately, block next run until resolved
      │
      ├── sev:high → Include in next pipeline iteration
      │
      ├── sev:medium/low → Backlog; batch with next iteration
      │
      └── cat:success → Tag as reference example; no action required
```

For each critical or high issue, the Workflow Designer will:
1. Identify whether the root cause is a prompt, orchestration rule, or missing data source
2. Update the relevant prompt, skill file, or MCP configuration
3. Create a new pipeline run for the same feature (as `{JIRA-KEY}-v2`) to validate the fix
4. Close the issue with a reference to the new iteration

---

## Iteration Model

New iterations are created when feedback warrants a re-run. They are **never** edits to published outcomes.

| Trigger | Action |
|---------|--------|
| Critical gap identified | Create `{JIRA-KEY}-v2` run; publish as `outcomes/{NEXT-MONTH}/{JIRA-KEY}-v2/` |
| Multiple high issues on same feature | Batch into a single re-run |
| Prompt improvement validated | Re-run a sample of past features to confirm improvement |
| New data source added (e.g. Confluence access restored) | Re-run affected features |

---

## Pull Request Policy

All outcome publications require:

- A PR to `main` (no direct pushes)
- At least one reviewer who is not the operator
- Completed checklist in the PR description (see `.github/PULL_REQUEST_TEMPLATE/outcome_review.md`)
- No secrets, credentials, or raw API payloads in the diff
- `outcome-metadata.md` filled with assumptions and known gaps

---

## Escalation

Security or data integrity gaps found in pipeline outputs are treated with priority:

| Scenario | Response |
|----------|----------|
| Agent output contains hardcoded credentials | Block PR; rotate credentials; review all artifacts from that run |
| Agent output references real patient or customer data | Block PR; escalate to data privacy team |
| Agent output suggests a deployment action that would have hit a production org | Critical gap issue; immediate orchestration fix |
| Agent output bypassed a documented guardrail | Critical gap issue; review all artifacts from that run |

---

## Repository Hygiene

- Stale draft PRs (> 30 days with no activity) are closed with a `stale` label
- Feedback issues are closed once the fix is validated in a published iteration
- The `outcomes/` folder is append-only — no deletions or edits to published content
- Templates and docs may be updated at any time via standard PRs
