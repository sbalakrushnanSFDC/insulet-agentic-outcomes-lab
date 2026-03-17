# Outcome Metadata — NGOMCT-344

**Author:** Som Balakrushnan  
© Som Balakrushnan

> Reference implementation for the Insulet Agentic Outcomes Lab.
> This is the first published outcome and serves as the canonical example for all templates and guides.

---

## Feature Identification

| Field | Value |
|-------|-------|
| **Feature ID** | NGOMCT-344 |
| **Feature Summary** | Training Creation & Assignment — Manual Training Record Creation |
| **Jira Project** | NGOMCT (Omnichannel Training) |
| **Jira Status at Run Time** | FEATURE DEFINITION |
| **Jira Priority** | Highest |
| **Team** | Team1 |
| **Sprint / Quarter** | 2026 Q1 — Project Infinity SOW MVP / Persona Release 2 |

---

## Source References

| Source | URL / Reference |
|--------|----------------|
| **Jira Story** | https://insulet.atlassian.net/browse/NGOMCT-344 |
| **Confluence Page** | CON-13 — "Consumer trained on Insulet product" (page_id: 135170258) |
| **Jira Align Feature** | NGPI3 (Project Infinity) |
| **Parent Epic** | NGOMCT (Training Creation & Assignment) |
| **Linked Stories (blockers)** | NGOMCT-139 (In Progress), NGOMCT-6 (Backlog), NGOMCT-240 (Backlog), NGASIM-263 (Backlog) |
| **Linked Stories (blocked-by this)** | NGOMCT-10, NGOMCT-54, NGONDL-60, NGMC-32 |
| **Cloned from** | NGOMCT-91 (Training Creation — From Direct Order) |

---

## Pipeline Execution

| Field | Value |
|-------|-------|
| **Pipeline Version** | 1.0 |
| **Run Date** | 2026-03-14 |
| **ECC Framework Version** | ECC v1.0 (everything-claude-experiment) |
| **Custom Agents Used** | salesforce-deployer, jira-reader |
| **Orchestration Prompt ID** | 54bee681-4e70-43e6-b492-f0c65dc8853e |
| **Target Org (deploy)** | orgsyncng (sbalakrushnan@insulet.com.orgsyncng) |
| **Source Org (retrieve)** | DevInt2 (read-only) |

### Pipeline Step Summary

| Step | Agent | Status | Artifact |
|------|-------|--------|----------|
| INTAKE | Orchestrator | pass | 00-intake.md |
| PLAN | planner | pass | 01-plan.md |
| ARCH | architect | pass | 02-architecture.md |
| BUILD | tdd-guide | pass | 03-tdd.md |
| REVIEW | code-reviewer | pass | 04-code-review.md |
| STABILIZE | build-error-resolver | pass | 05-build-fix.md |
| VALIDATE | e2e-runner | pass | 06-e2e.md |
| SECURE | security-reviewer | pass | 07-security.md |
| CLEAN | refactor-cleaner | pass | 08-refactor.md |
| DOC | doc-updater | pass | 09-docs.md |

**Note:** `status.json` contains a duplicate `BUILD` key (lines 10–11) — a JSON write artifact from the pipeline run. The effective BUILD status is `pass`. A duplicate key issue should be flagged as a low-severity data quality gap.

---

## Agent Assumptions

1. **Training__c object exists** with standard fields including `Account__c` (MasterDetail), `RecordType`, and `Training_Stage__c` — schema was discovered from DevInt2 metadata.
2. **Default RecordType = `Live_Training`** — most common for CSM-initiated consumer training; derived from sibling feature NGOMCT-91 and metadata discovery.
3. **Default `Training_Stage__c = 'Pending Assignment'`** — places the record in the queue for the assignment logic in NGOMCT-89; this stage value was inferred, not confirmed in Jira.
4. **NGOMCT-89 (Training Assignment Logic) is out of scope** — the agent correctly respected this boundary as stated in the Jira description.
5. **Acceptance Criteria were not explicit in Jira** — all 5 ACs were derived from the Jira description, sibling feature NGOMCT-91, and Salesforce metadata discovery; none were confirmed against the original business requirements in Confluence CON-13.
6. **Blockers**: Primary blocker NGOMCT-139 was In Progress; other blockers (NGOMCT-6, NGOMCT-240, NGASIM-263) were in Backlog. The agent proceeded with implementation, noting the deployment dependency.

---

## Known Gaps

| Gap | Category | Severity | Notes |
|-----|----------|----------|-------|
| **Feature is partially implemented** — Apex Invocable built but Screen Flow (`Manual_Training_Creation`), Lightning Action (`Create_Training` on Account), and FlexiPage update were **not built** | Scope Drift | **Critical** | The feature cannot be triggered by an end user. Only the service contract layer exists. See `solution/metadata/flows/Manual_Training_Creation.flow-spec.md` for the deferred specification. Follow-up pipeline run required. |
| Confluence CON-13 body not retrieved — the agent used `mcp_web_fetch` (unauthenticated HTTP) instead of `atlassian-guardrails` `confluence_get_page` | Data Missing | Medium | All ACs were derived without access to the definitive business process documentation. A re-run using the correct MCP tool would validate or correct the derived ACs. |
| Duplicate `BUILD` key in `status.json` | Logic Gap | Low | JSON object with duplicate key; only one value is retained by most parsers. The pipeline state write had a logic error. |
| E2E validation was a paper exercise — `sf org display` on orgsyncng returned exit code 1 | Data Missing | High | The E2E artifact describes test scenarios but does not confirm actual deployment and execution against the live sandbox. Consider this step `partial` rather than `pass`. |
| `Training_Stage__c` default value (`Pending Assignment`) inferred, not confirmed | Logic Gap | Medium | The stage value drives the downstream NGOMCT-89 workflow. If the value is wrong, the training record will not enter the correct queue. Requires confirmation against CON-13 or the DevInt2 picklist values. |
| `Training_After_Save` pre-existing Flow behavior on new record not verified | Logic Gap | Medium | Pre-existing record-triggered Flow fires on `Training__c` save. Whether it conflicts with a new record at `Pending Assignment` stage was not verified in the org. |
| Blockers NGOMCT-6, NGOMCT-240, NGASIM-263 were in Backlog at run time | Data Missing | Low | The agent acknowledged these dependencies but did not assess their impact on the implementation. If these stories define object structures or business rules that affect `Training__c`, the implementation may need revision. |

---

## Architectural Decisions (from traceability.json)

| Decision | Rationale | AC Mapping |
|----------|-----------|-----------|
| Implement as Apex `@InvocableMethod` (not a bare Screen Flow) | TDD mandate required unit-testable code; Flows are not unit-testable in Apex | AC-1, AC-2 |
| Default RecordType = `Live_Training` | Most common CSM-initiated path; matches NGOMCT-91 pattern | AC-2 |
| Default `Training_Stage__c = 'Pending Assignment'` | Places record in queue for NGOMCT-89 downstream | AC-4 |
| `Training_Stage__c` lifecycle and `NGOMCT-89` out of scope | Explicit Jira description boundary | AC-3 |
| Entry from Account record (Screen Flow or Quick Action) | Standard Salesforce UX for related record creation | AC-5 |

---

## Salesforce Constructs

Full details and file classification in `solution/metadata/README.md`.

| Construct | Type | Tag | Notes |
|-----------|------|-----|-------|
| `TrainingManualCreationService.cls` | Apex Class | **[NEW]** | Invocable service; core deliverable of this pipeline run |
| `TrainingManualCreationServiceTest.cls` | Apex Test Class | **[NEW]** | 5 TDD test methods; covers AC-1 through AC-3, bulk, and error cases |
| `TrainingManualCreationService.cls-meta.xml` | Apex Metadata | **[NEW]** | API version |
| `TrainingManualCreationServiceTest.cls-meta.xml` | Apex Metadata | **[NEW]** | API version |
| `Training__c` object | Custom Object | **[RETRIEVED]** | Pre-existing in DevInt2; context for reviewers |
| `Training__c.Account__c` | Field | **[RETRIEVED]** | MasterDetail — required by Apex implementation |
| `Training__c.Training_Stage__c` | Field | **[RETRIEVED]** | Picklist — `Pending Assignment` default confirmed from this field definition |
| `Training__c.Training_Type__c` | Field | **[RETRIEVED]** | Optional input to Invocable |
| `Training__c.Training_Method__c` | Field | **[RETRIEVED]** | Optional input to Invocable |
| `Training__c.Product__c` | Field | **[RETRIEVED]** | Optional input to Invocable |
| `Live_Training` RecordType | Record Type | **[RETRIEVED]** | Default RecordType; queried in Apex by `DeveloperName` |
| `Manual_Training_Creation` Screen Flow | Flow | **[PLANNED — NOT BUILT]** | Deferred; spec in `solution/metadata/flows/`; required for AC-5 and end-to-end deployment |
| `Create_Training` Lightning Action on Account | Object Action | **[PLANNED — NOT BUILT]** | Deferred; required for AC-5 |
| Account Record Page FlexiPage update | FlexiPage | **[PLANNED — NOT BUILT]** | Deferred; required for AC-5 |

---

## Reviewer Notes

*Leave blank before opening PR. Reviewers add notes here or open GitHub Issues.*

---

## Links to Related Feedback Issues

*Populated after review.*
