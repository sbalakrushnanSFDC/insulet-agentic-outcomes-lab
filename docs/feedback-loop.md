# Feedback Loop

> How human review of outcomes feeds back into the agentic pipeline to drive continuous improvement.

---

## Overview

The feedback loop connects three activities:

1. **Review** — A cross-functional reviewer reads published artifacts and identifies gaps or successes
2. **Triage** — The Workflow Designer categorizes and prioritizes the feedback
3. **Iteration** — The pipeline is updated and re-run, producing an improved outcome

This loop is the primary mechanism for improving the agentic pipeline over time. Without structured feedback, the pipeline has no signal about what it is getting right or wrong.

---

## Feedback Cycle Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    AGENTIC PIPELINE                         │
│                                                             │
│  Jira Story → INTAKE → PLAN → ARCH → BUILD → ... → DOC     │
│                                          │                  │
│                                     Artifacts               │
└──────────────────────────────────────────┼──────────────────┘
                                           │
                                           ▼
                              ┌────────────────────────┐
                              │  OUTCOMES GALLERY      │
                              │  outcomes/{YM}/{KEY}/  │
                              └────────────┬───────────┘
                                           │
                              Human reviewer reads artifacts
                                           │
                                           ▼
                              ┌────────────────────────┐
                              │  FEEDBACK              │
                              │  GitHub Issue (gap)    │
                              │  or PR comment         │
                              └────────────┬───────────┘
                                           │
                              Workflow Designer triages
                                           │
                              ┌────────────┴───────────┐
                              │                        │
                        Critical/High              Medium/Low
                              │                        │
                    Fix prompt/guardrail/         Backlog for
                    data source immediately       next iteration
                              │
                              ▼
                    New pipeline run ({KEY}-v2)
                              │
                              ▼
                    New outcome published
                    outcomes/{NEXT-YM}/{KEY}-v2/
                              │
                              ▼
                    Issue closed with reference
                    to new iteration
```

---

## How to Give Feedback

### Option 1: GitHub Issue (recommended for gaps)

1. Go to [Issues → New Issue](../../issues/new/choose)
2. Select **"Outcome Review Feedback"** template
3. Fill in:
   - **Feature ID** — the Jira key (e.g. `NGOMCT-344`)
   - **Artifact** — which step artifact the gap is in
   - **Category** — Prompt Error / Logic Gap / Data Missing / Scope Drift / Success
   - **Severity** — Critical / High / Medium / Low / Informational
   - **Description** — what the gap is
   - **Suggested Fix** — optional but very useful
4. Submit. Labels are applied automatically by the template.

### Option 2: PR Comment (for inline annotations)

When reviewing an outcome PR (before merge), leave inline comments directly on the artifact files. The operator will document significant comments as GitHub Issues before merging.

### Option 3: Gap Analysis File (for detailed analysis)

For complex or multi-part gaps, use the `templates/gap-analysis.md` template to write a structured analysis. Commit it as `gap-analysis-001.md` in the outcome folder and reference it in the GitHub Issue.

---

## Feedback Categories in Detail

| Category | Description | Examples |
|----------|-------------|---------|
| **Prompt Error** | The agent misunderstood its instruction | Agent planned for the wrong object; agent ignored a constraint in the system prompt |
| **Logic Gap** | The reasoning was flawed, not just the prompt | Agent correctly retrieved data but drew the wrong conclusion from it |
| **Data Missing** | A required source was unavailable | Confluence page body not fetched; Jira custom field not populated |
| **Scope Drift** | Agent went out of scope or included irrelevant content | Agent planned for a related feature that was not in scope; agent omitted required AC |
| **Success** | A positive example worth preserving | Agent correctly identified a governor limit risk; agent produced unusually thorough test cases |

---

## Triage Priorities

| Severity | Triage SLA | Action |
|----------|-----------|--------|
| Critical | Immediate | Block next run; fix and validate before continuing |
| High | Next iteration | Include fix in next pipeline run |
| Medium | Backlog | Address when batching improvements |
| Low | Backlog | Address in bulk cleanup |
| Informational | No SLA | Log for reference; no action required |

---

## What Gets Fixed Where

The root cause of a gap determines where the fix is applied:

| Root Cause | Fix Location |
|-----------|-------------|
| Flawed orchestration prompt | Update the system prompt in the relevant `.cursor/skills/` or agent config |
| Missing guardrail | Add a constraint rule to `.cursorrules` or the relevant agent skill |
| Unavailable data source | Add or configure the MCP integration (e.g. Confluence auth) |
| Agent sequence issue | Update the pipeline step order or handoff artifact structure |
| Known LLM limitation | Document in `outcome-metadata.md`; accept as a known gap |

---

## Iteration Naming Convention

When a gap triggers a re-run, the new iteration uses this naming convention:

| Scenario | Folder Name |
|----------|------------|
| First iteration | `outcomes/2026-03/NGOMCT-344/` |
| Second iteration (same month) | `outcomes/2026-03/NGOMCT-344-v2/` |
| Third iteration or later month | `outcomes/2026-04/NGOMCT-344-v3/` |

The `outcome-metadata.md` for the new iteration must reference the previous iteration and note what changed.

---

## Success Tracking

Not all feedback is about gaps. When a reviewer marks an outcome as **Success**, the Workflow Designer:

1. Labels the issue `cat:success`
2. Adds a "Positive Examples" note in the next pipeline prompt iteration
3. Uses the successful artifact as a reference in the `docs/interpretation-guide.md` glossary or examples

Over time, the gallery of successes becomes a prompt-engineering reference library.
