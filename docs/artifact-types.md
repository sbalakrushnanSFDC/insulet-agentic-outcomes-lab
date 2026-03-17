# Artifact Types

> Catalog of all artifact types produced by the Insulet Agentic Implementation Pipeline.
> Derived from the NGOMCT-344 reference run (2026-03).

---

## Pipeline Handoff Artifacts

These are the primary outputs of the pipeline. Each corresponds to one step in the 10-step sequence.

| Artifact File | Step | Agent | Description |
|--------------|------|-------|-------------|
| `00-intake.md` | INTAKE | Orchestrator | Requirements summary, risk triage, available data inventory, scope boundary |
| `01-plan.md` | PLAN | `planner` | Derived ACs, implementation phases, dependencies, risk register |
| `02-architecture.md` | ARCH | `architect` | Component design, object model, integration points, architectural decisions |
| `03-tdd.md` | BUILD | `tdd-guide` | Test specs (RED), implementation walkthrough (GREEN), coverage estimate |
| `04-code-review.md` | REVIEW | `code-reviewer` | Quality findings by severity (CRITICAL/HIGH/MEDIUM/LOW), recommendations |
| `05-build-fix.md` | STABILIZE | `build-error-resolver` | Build error log, applied fixes, confirmation of resolution |
| `06-e2e.md` | VALIDATE | `e2e-runner` | E2E test plan, execution results or validated plan, open failures |
| `07-security.md` | SECURE | `security-reviewer` | Security findings, CRUD/FLS verification, OWASP checklist |
| `08-refactor.md` | CLEAN | `refactor-cleaner` | Refactoring log, constant extraction, naming improvements |
| `09-docs.md` | DOC | `doc-updater` | Documentation created/updated, Confluence plan, method signatures |

---

## Pipeline Metadata Files

| Artifact File | Description |
|--------------|-------------|
| `status.json` | State machine for the pipeline run; tracks step status (`pass`/`fail`/`partial`), timestamps, and rework flags |
| `traceability.json` | Maps implementation decisions back to Jira ACs, Confluence content, and discovered Salesforce metadata |

### `status.json` Schema

```json
{
  "feature_id": "string",
  "feature_summary": "string",
  "pipeline_version": "string",
  "current_step": "string (last completed step or COMPLETE)",
  "steps": {
    "{STEP_NAME}": {
      "status": "pending | in_progress | pass | fail | partial",
      "completed_at": "ISO 8601 datetime or null",
      "artifact": "filename.md"
    }
  },
  "rework_triggered": "boolean",
  "last_updated": "ISO 8601 datetime"
}
```

### `traceability.json` Schema

```json
{
  "feature_id": "string",
  "jira_key": "string",
  "acceptance_criteria": [
    {
      "id": "AC-N",
      "description": "string",
      "source": "jira_description | confluence | inferred | metadata_discovery",
      "implemented_in": ["filename.cls", "..."],
      "test_coverage": "test method name or N/A"
    }
  ],
  "decisions": [
    {
      "decision": "string",
      "rationale": "string",
      "artifact": "NN-step.md",
      "traceability": "AC-N or jira_key or confluence_page_id"
    }
  ]
}
```

**Note:** Entries with `"source": "inferred"` indicate the agent made an assumption without direct evidence. These warrant priority human review.

---

## Solution Artifacts

| Artifact File | Description |
|--------------|-------------|
| `{JIRA-KEY}-Solution-Architecture.md` | Comprehensive architecture and execution guide; produced by the `doc-updater` step; covers design decisions, orchestration model, component breakdown, usage instructions, and a full walkthrough |

---

## Gallery Artifacts

These artifacts are created by the workflow operator when publishing to this repository (not by the pipeline itself).

| Artifact File | Description |
|--------------|-------------|
| `outcome-metadata.md` | Structured summary of the run: source refs, agent assumptions, known gaps, step summary table. Required for every published outcome. |
| `review-log.md` | Per-reviewer assessment records, verdicts, and gap references |
| `gap-analysis-{NN}.md` | Detailed analysis of a specific gap found during review; one file per gap |

---

## Lifecycle of an Artifact

```
Pipeline run starts
        │
        ▼
Agent produces handoff .md (e.g. 01-plan.md)
        │
        ▼
Next agent reads prior .md as primary input
        │
        ▼
... (steps 00–09) ...
        │
        ▼
Operator curates artifacts (removes secrets, raw payloads)
        │
        ▼
Operator fills outcome-metadata.md
        │
        ▼
PR opened → reviewer reads artifacts → feedback issues opened
        │
        ▼
Merge to outcomes/{YEAR-MONTH}/{JIRA-KEY}/
        │
        ▼
Feedback triaged → new pipeline iteration (if warranted)
```

---

## Artifact Dependency Graph

```
00-intake.md
    └─► 01-plan.md
            └─► 02-architecture.md
                    └─► 03-tdd.md (+ status.json write)
                            └─► 04-code-review.md
                                    └─► 05-build-fix.md
                                            └─► 06-e2e.md
                                                    └─► 07-security.md
                                                            └─► 08-refactor.md
                                                                    └─► 09-docs.md
                                                                            └─► traceability.json (final update)
```

Each artifact is the **canonical input** for the next step. If a step is re-run due to a rework loop, it re-reads from the most recent version of its input artifact.
