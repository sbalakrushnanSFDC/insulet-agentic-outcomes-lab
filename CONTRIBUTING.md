# Contributing to the Insulet Agentic Outcomes Lab

This guide explains how workflow operators publish new outcomes, and how reviewers can contribute feedback.

---

## Who Publishes?

**Workflow Operators** — the people who run the agentic pipeline — are responsible for:

1. Curating the pipeline output artifacts for a completed run
2. Filling out `outcome-metadata.md` before publishing
3. Opening a Pull Request for peer review before merging to `main`

Cross-functional reviewers contribute via GitHub Issues and PR comments, not direct commits.

---

## Publishing a New Outcome

### Step 1: Complete the pipeline run

Ensure the pipeline has reached a meaningful stopping point. This does **not** require all 10 steps to pass. Partial runs are valuable. What matters is that:

- `status.json` reflects the actual completion state (do not edit it to show false passes)
- At least INTAKE (`00-intake.md`) and PLAN (`01-plan.md`) artifacts exist

### Step 2: Create the outcome folder

Use this naming convention strictly:

```
outcomes/{YEAR-MONTH}/{JIRA-KEY}/
```

Examples:
- `outcomes/2026-03/NGOMCT-344/`
- `outcomes/2026-04/NGONDL-60/`

`YEAR-MONTH` is the month the pipeline run was **completed**, not the Jira story creation date.

### Step 3: Populate the folder structure

```
outcomes/{YEAR-MONTH}/{JIRA-KEY}/
    outcome-metadata.md        <- required; fill from templates/outcome-metadata.md
    pipeline/
        00-intake.md           <- copy from runs/{JIRA-KEY}/00-intake.md
        01-plan.md
        02-architecture.md     <- if completed
        03-tdd.md              <- if completed
        04-code-review.md      <- if completed
        05-build-fix.md        <- if completed
        06-e2e.md              <- if completed
        07-security.md         <- if completed
        08-refactor.md         <- if completed
        09-docs.md             <- if completed
        status.json            <- copy from runs/{JIRA-KEY}/status.json
        traceability.json      <- copy from runs/{JIRA-KEY}/traceability.json
    solution/
        {JIRA-KEY}-Solution-Architecture.md   <- if produced by doc-updater step
```

### Step 4: Fill out outcome-metadata.md

Copy `templates/outcome-metadata.md` into the outcome folder and fill in all required fields.  
See [templates/outcome-metadata.md](templates/outcome-metadata.md) for field definitions.

The most critical fields are:
- Source references (Jira/Confluence URLs)
- Assumptions made by the agent
- Known gaps — what the agent could not do or did not do correctly

### Step 5: Open a Pull Request

1. Create a branch: `outcome/{JIRA-KEY}-{YEAR-MONTH}`
   - Example: `outcome/NGOMCT-344-2026-03`
2. Commit all new files in the outcome folder
3. Open a PR to `main` using the [outcome review template](.github/PULL_REQUEST_TEMPLATE/outcome_review.md)
4. Assign at least one cross-functional reviewer who is not the operator

---

## What to Include vs. Exclude

### Include

| Artifact | Location |
|----------|----------|
| Pipeline handoff files | `pipeline/00-intake.md` through `pipeline/09-docs.md` |
| Pipeline metadata | `pipeline/status.json`, `pipeline/traceability.json` |
| Solution architecture | `solution/{JIRA-KEY}-Solution-Architecture.md` |
| Outcome metadata | `outcome-metadata.md` |

### Exclude — Never Commit

| Excluded | Reason |
|----------|--------|
| `.env` files or credentials | Security |
| `raw_payload.json` (full Jira API responses) | Contains internal data |
| Salesforce source code (`force-app/`) | Lives in the SFDX project |
| `MEMORY.md` | Contains org aliases and sandbox URLs |
| Execution configs (`.cursorrules`, `PIPELINE.md`, `AGENTS.md`) | Lives in the harness project |
| Any file with hardcoded usernames, org IDs, or session tokens | Security |

---

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Outcome folder | `{JIRA-KEY}` | `NGOMCT-344` |
| Date folder | `{YYYY-MM}` | `2026-03` |
| Pipeline artifacts | `{NN}-{step-name}.md` | `01-plan.md` |
| Branch | `outcome/{JIRA-KEY}-{YYYY-MM}` | `outcome/NGOMCT-344-2026-03` |
| PR title | `outcome: {JIRA-KEY} [{YYYY-MM}]` | `outcome: NGOMCT-344 [2026-03]` |

---

## Updating an Existing Outcome

Do **not** edit files in a published outcome folder. Instead:

1. Create a new iteration folder with a suffix: `outcomes/{YEAR-MONTH}/{JIRA-KEY}-v2/`
2. Fill a new `outcome-metadata.md` referencing the original
3. Include only the artifacts that changed
4. Note in the metadata what changed from the previous iteration

This preserves the immutability of published outcomes and makes the evolution of the pipeline visible.
