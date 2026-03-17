# Gap Analysis

> Use this template to document a specific gap found during review of an agentic outcome.
> One gap per file. Save as `outcomes/{YEAR-MONTH}/{JIRA-KEY}/gap-analysis-{NN}.md` where `NN` is a sequence number.

---

## Gap Identification

| Field | Value |
|-------|-------|
| **Gap ID** | <!-- GAP-001 --> |
| **Feature ID** | <!-- e.g. NGOMCT-344 --> |
| **Artifact** | <!-- e.g. 01-plan.md, 07-security.md, outcome-metadata.md --> |
| **Pipeline Step** | <!-- e.g. PLAN, SECURE, BUILD --> |
| **Identified By** | <!-- Reviewer name --> |
| **Date Identified** | <!-- YYYY-MM-DD --> |
| **GitHub Issue** | <!-- #NNN (if filed) --> |

---

## Category

Select the primary category for this gap:

- [ ] **Prompt Error** — The agent's output was wrong due to a flawed instruction or prompt
- [ ] **Logic Gap** — The reasoning or decision was incorrect, independent of the prompt
- [ ] **Data Missing** — A required data source was unavailable (e.g. Confluence auth, missing Jira field)
- [ ] **Scope Drift** — The agent went out of scope, included irrelevant content, or missed scope boundaries
- [ ] **Security Concern** — The output has a security implication that should be reviewed

---

## Severity

- [ ] **Critical** — Blocks use of the output; must be addressed before next iteration
- [ ] **High** — Significant gap; should be addressed in the next pipeline iteration
- [ ] **Medium** — Notable but tolerable; address when possible
- [ ] **Low** — Minor issue; cosmetic or stylistic
- [ ] **Informational** — Observation only; no action required

---

## Description

> Describe the gap clearly and specifically. Include the exact section or line in the artifact where it appears.

```
<!-- Paste the relevant excerpt from the artifact here, if applicable -->
```

**What is wrong:**

<!-- Explain the problem in 2-5 sentences. Be specific about what the agent did and why it is incorrect or incomplete. -->

---

## Impact

> What is the downstream effect of this gap if it is not corrected?

<!-- e.g. "The acceptance criteria derived by the agent excluded AC-4 from the Jira story, which means the Apex class does not handle the case where the consumer account is inactive. If deployed, this would cause a runtime exception in production." -->

---

## Root Cause Hypothesis

> What do you believe caused this gap?

- [ ] Missing context in the orchestration prompt
- [ ] Agent did not have access to the required data source
- [ ] Agent hallucinated or inferred incorrectly from partial data
- [ ] Orchestration step was skipped or abbreviated
- [ ] Known limitation of the LLM model
- [ ] Other: <!-- describe -->

---

## Recommended Action

> What should be done to prevent this gap in future runs?

- [ ] Fix the orchestration prompt
- [ ] Add or fix a guardrail rule
- [ ] Add a new data source or MCP integration
- [ ] Change the agent sequencing
- [ ] No action required — acceptable limitation
- [ ] Other: <!-- describe -->

**Specific recommendation:**

<!-- e.g. "Add an explicit instruction in 01-plan.md system prompt: 'If Confluence fetch fails, attempt atlassian-guardrails confluence_get_page as fallback before marking as unavailable.'" -->

---

## Resolution

> Filled after the gap is addressed. Leave blank until resolved.

| Field | Value |
|-------|-------|
| **Resolved in iteration** | <!-- e.g. NGOMCT-344-v2 --> |
| **Fix applied** | <!-- Brief description of what changed --> |
| **Verified by** | <!-- Who confirmed the fix worked --> |
| **Date resolved** | <!-- YYYY-MM-DD --> |
