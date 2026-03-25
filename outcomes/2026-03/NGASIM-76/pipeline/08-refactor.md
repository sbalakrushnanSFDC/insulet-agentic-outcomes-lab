# NGASIM-76: REFACTOR (Clean)

> **Pipeline Stage:** 08-refactor
> **Produced by:** refactor-cleaner agent
> **Input:** 05-buildfix.md, 07-security.md, 01-plan.md (metadata inventory), 02-architecture.md (ADRs)
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:48:00Z
> **Status:** COMPLETE — handed off to DOC

---

## Decisions Made

1. Refactoring scope covers metadata naming hygiene, constant extraction for disposition picklist values, environment exclusion review, and configuration debt from cancelled/blocked child stories.
2. No Apex code to refactor yet (pseudo-code only). Refactoring recommendations apply to the eventual implementation.
3. TTEC dependency creates external configuration debt that cannot be resolved in the Salesforce layer alone.
4. Cross-reference with security findings (S-04, S-05) drives permission set refinement recommendations.

---

## Refactoring Log

| # | Category | Before | After | Rationale |
|---|----------|--------|-------|-----------|
| R-01 | Naming | IS-specific ServicePresenceStatus names: `IS_Available_Voice`, `IS_Busy_Voice`, `IS_ACW` | Keep as-is | `IS_` prefix clearly segregates Inside Sales presence statuses from Customer Care's `Available_Voice`, `Busy_Voice`, `After_Call_Work`. Follows the persona-prefix convention established in 02-architecture.md segregation table. Consistent and discoverable. |
| R-02 | Naming | PermissionSetGroup `IS_CTI_Agent_Access` | Keep as-is | Follows the existing org convention where PSGs describe the access bundle (e.g., `CTI_Agent_Access` from NGPSTE-132). `IS_` prefix differentiates from Care's `CTI_Agent_Access`. No `_PSG` suffix needed — metadata type already identifies it. |
| R-03 | Naming | PermissionSet `IS_CTI_Base` | Keep as-is | Parallel naming to the concept of "base" permissions. IS_CTI_Base provides Lead/Task/VoiceCall access specific to Inside Sales. The name clearly communicates it is the base layer of the IS PSG bundle. |
| R-04 | Naming | Queue names: `Inside_Sales_Voice`, `HCP_Inbound_Voice` | Keep as-is | Descriptive, follows Salesforce underscore convention. `Inside_Sales_Voice` mirrors the `IS_` prefix pattern used elsewhere. `HCP_Inbound_Voice` clearly identifies the queue's routing purpose. |
| R-05 | Naming | SoftphoneLayout `IS_Softphone_Layout` | Keep as-is | `IS_` prefix consistent with all other Inside Sales metadata. Differentiates from any future Care-specific softphone layout. |
| R-06 | Naming | CustomField `Task.Call_Disposition__c` | Keep as-is | Generic name (not IS-prefixed) because call disposition is applicable to any persona's call activity. If Customer Care later implements call logging, the same field can be reused. Avoiding `IS_Call_Disposition__c` prevents schema fragmentation. |
| R-07 | Naming | CustomField `VoiceCall.Recording_Opted_Out__c` | Keep as-is | Persona-agnostic — recording opt-out applies to any call, not just Inside Sales. Consistent with HIPAA requirement that spans all agent types. |
| R-08 | Naming Audit | CustomField `Task.Call_Duration_Seconds__c` | Recommend rename to `Task.CallDurationSeconds__c` (remove underscores in compound words) | Current name uses underscore-separated compound words (`Call_Duration_Seconds`). Salesforce convention for custom fields is CamelCase within the name portion. However, existing org may use underscore style — **defer to org convention audit.** Decision: keep as-is unless org-wide refactoring standardizes naming. |

---

## Constant Extraction

### Call Disposition Picklist Values

The call disposition picklist (Task.Call_Disposition__c) contains 6 values defined in 05-buildfix.md CustomField XML. These values are also referenced in:
- 01-plan.md AC-10 (acceptance criterion)
- 02-architecture.md Integration Point #5 (Flow updates Task)
- VoiceCallActivityHandler (future implementation will reference values)

**Recommendation:** Extract picklist values into a centralized location to avoid drift between metadata XML, Apex code, Flow references, and test data.

| Value | Current Location | Recommended Location | Priority |
|-------|-----------------|---------------------|----------|
| `Interested`, `Not_Interested`, `Callback_Requested`, `Wrong_Number`, `Voicemail`, `No_Answer` | CustomField XML `valueSetDefinition` | Custom Metadata Type `Call_Disposition_Config__mdt` with `Value__c`, `Label__c`, `Sort_Order__c`, `Is_Active__c` fields | MEDIUM |
| — | — | Alternative: Apex constants class `CallDispositionConstants.cls` with `public static final String INTERESTED = 'Interested';` etc. | LOW (simpler but less admin-configurable) |

**Rationale:** Custom Metadata Type allows PO/admin to add/remove/reorder disposition values without code changes. Apex constants class is simpler but requires deployment for changes. Given F-07 (PO confirmation pending), the CMT approach is preferred for agility.

### Connect API Endpoints

The RecordingOptOutController will reference Amazon Connect API endpoints. These should be externalized:

| Value | Current Location | Recommended Location | Priority |
|-------|-----------------|---------------------|----------|
| Connect instance URL | Named Credential endpoint | Named Credential (already externalized) | N/A — correct pattern |
| StopContactRecording API path | Apex class (future) | Custom Metadata Type `CTI_Config__mdt.Recording_API_Path__c` | LOW |
| Recording opt-out timeout (ms) | Apex class (future) | Custom Metadata Type `CTI_Config__mdt.Recording_API_Timeout__c` | LOW |

### Screen Pop URL Patterns

InsideSalesScreenPopResolver constructs Lightning URLs. These patterns should be extracted:

| Value | Current Location | Recommended Location | Priority |
|-------|-----------------|---------------------|----------|
| `/lightning/r/Lead/{id}/view` | Pseudo-code string literal | Apex constant or `URL.getSalesforceBaseUrl()` + standard pattern | MEDIUM |
| `/lightning/o/Lead/new?defaultFieldValues=Phone=` | Pseudo-code string literal | Apex constant | MEDIUM |

---

## Configuration Debt Flagged

| Item | Type | Severity | Notes |
|------|------|----------|-------|
| NGPSTE-531 (Sales Queues) Cancelled | Scope gap | HIGH | The original story for Inside Sales queue setup was Cancelled. Queue metadata is generated in 05-buildfix.md to fill the gap, but the cancellation reason is unknown. Possible causes: (1) queue setup moved to a different story, (2) queues were manually created outside Jira tracking, (3) genuine scope gap. **Action:** Verify with PM whether NGPSTE-531 cancellation was intentional and whether the 05-buildfix.md queue definitions are the correct replacement. |
| NGASIM-2549 (NFRs) Cancelled | Compliance debt | HIGH | Non-functional requirements story was cancelled. Performance targets (page load < 3s, API < 2s, 1000 concurrent) are captured in 00-intake.md but not tracked in any active Jira story. Without an active story, NFR validation will not be included in QA test plans. **Action:** Create replacement story or add NFR acceptance criteria to parent Feature. |
| TTEC Contact Flow Dependency | External debt | HIGH | TTEC manages Amazon Connect contact flows. The following NGASIM-76 features require TTEC changes: (1) HCP routing — IVR menu option to route to HCP_Inbound_Voice queue (AC-05), (2) Call type tagging — IVR-driven attribute passed to VoiceCall.Call_Category__c (AC-16), (3) Warm/cold transfer — contact flow transfer configuration (AC-11, AC-12), (4) Quick connect — TTEC-managed quick connect entries (AC-13). These are Salesforce-side metadata that requires external partner activation. **Action:** Create TTEC change request for PI planning. |
| NGCRMI-2007 Task OrgSync Gap | Integration debt | MEDIUM | VoiceCallActivityHandler creates Tasks with custom fields (Call_Disposition__c, Call_Duration_Seconds__c). These Tasks must sync to Classic org via OrgSync (NGCRMI-2007). The OrgSync field mapping has not been updated to include these custom fields. **Action:** Coordinate with OrgSync team. Add custom field mapping to NGCRMI-2007 backlog. |
| Named Credential Not Created | Infrastructure debt | HIGH | Named Credential `AmazonConnect_API` has been an open item since NGPSTE-132 (S-02). It remains unresolved and now blocks NGASIM-76 RecordingOptOutController (AC-14). This is the longest-running open infrastructure item across both pipeline runs. **Action:** Escalate to DevOps/AWS team. Cannot implement any Connect API callout without this. |
| No Omni-Channel Routing Config Metadata | Process gap | MEDIUM | IS_Voice_Routing (OmniChannelRoutingConfig) is in the metadata inventory (01-plan.md #1) but no XML was generated in 05-buildfix.md. Omni-Channel routing configuration is typically configured via Setup UI, not metadata XML. The manual setup step is documented in the deployment approach but creates a non-repeatable configuration. **Action:** Consider generating OmniChannelRoutingConfig XML for repeatable deployment. |
| NGPSTE-1123 (Classic Dev Package Part 3) Still To Do | Delivery debt | MEDIUM | NGPSTE-708 (Call Transfers) is blocked by NGPSTE-1123. No owner or target sprint assigned (same gap flagged in NGPSTE-132 F-05). Transfer functionality (AC-11, AC-12) cannot be fully validated without Classic package installation. **Action:** Assign owner and sprint for NGPSTE-1123. |
| Recording Re-enable After Opt-Out Not Designed | Design debt | MEDIUM | Security finding S-03 notes that once Recording_Opted_Out__c = true, there is no mechanism to prevent auto-resume on call transfer. If a call is transferred to another agent, Connect may auto-start recording on the new leg, violating the patient's opt-out. **Action:** Add ResumeContactRecording block logic to RecordingOptOutController. |

---

## No Apex Refactoring Needed (Pseudo-Code Only)

This pipeline run produced pseudo-code for three Apex classes but no deployable code:

- **InsideSalesScreenPopResolver:** Waterfall SOQL pattern. When implemented, refactoring focus should be: (1) extract each SOQL query into a separate private method, (2) use a custom exception class for screen pop failures, (3) add `@TestVisible` on private methods for unit test access.
- **VoiceCallActivityHandler:** Trigger handler pattern. When implemented: (1) follow single-trigger-per-object convention, (2) extract Task field mapping into a separate method, (3) use Custom Metadata for field mapping if OrgSync requires different mappings per environment.
- **RecordingOptOutController:** HTTP callout pattern. When implemented: (1) extract endpoint construction into Named Credential + path method, (2) add retry logic (1 retry with exponential backoff), (3) log all callout responses to Platform Event for monitoring.

---

## Environment Exclusion List

The following metadata should be added to `.forceignore` or excluded from cross-environment migration packages:

```
# NGPSTE-132: Environment-specific CallCenter adapters (carried forward)
force-app/main/default/callCenters/DevInt2ACLightningAdapter.callCenter-meta.xml
force-app/main/default/callCenters/SITACLightningAdapter.callCenter-meta.xml

# NGASIM-76: No IS-specific exclusions needed — all IS metadata is net-new and environment-agnostic
# Queue membership assignments are org-specific (Setup UI, not metadata) — inherently excluded
```

**Note:** Unlike NGPSTE-132 which had environment-specific CallCenter adapters (DevInt2, SIT), NGASIM-76 metadata is entirely net-new and not environment-bound. Queue definitions, ServicePresenceStatus records, and PermissionSets are generic across environments. The only environment-specific value is the Connect instance URL in the CallCenter XML, which is already flagged as a parameterization item (NGPSTE-132 R-04).

---

## Cross-Reference: Security Findings Impact on Refactoring

| Security Finding | Refactoring Implication | Action |
|-----------------|------------------------|--------|
| S-01 (Screen pop PHI exposure) | IS-specific PersonAccount page layout required. Not metadata refactoring — new Layout metadata to create. | Create `PersonAccount-Inside_Sales` layout hiding PHI fields. Add to Phase 1 deployment. |
| S-02 (Named Credential) | No metadata refactoring — infrastructure creation. | Tracked in configuration debt. |
| S-03 (Recording opt-out audit trail) | New custom fields required on VoiceCall: `Recording_Opted_Out_At__c`, `Recording_Opted_Out_By__c`. | Add to Phase 2 metadata inventory. Update IS_CTI_Base FLS. |
| S-04 (Lead duplicate risk) | Lead duplicate matching rule required. Not IS-specific — org-wide data quality improvement. | Create DuplicateRule + MatchingRule metadata. Consider as separate backlog item. |
| S-05 (VoiceCall custom field editability) | IS_CTI_Base PermissionSet XML needs update: `Call_Category__c` editable should be `false`, `True_Connection__c` editable should be `false`. | Update 05-buildfix.md IS_CTI_Base XML. Already flagged — correction needed before deploy. |
| S-06 (Task visibility across departments) | Task Record Type `IS_Call_Activity` may be needed for sharing rule boundaries. | Design decision: defer to Phase 2 if OWD allows adequate isolation without Record Type. |
| S-07 (ANI validation) | InsideSalesScreenPopResolver needs length validation (10-15 digits). | Add to Apex implementation checklist. Not a metadata change. |

---

## Permission Set Refinement Recommendations (from S-04, S-05)

Based on security findings, the IS_CTI_Base permission set requires the following FLS corrections before deployment:

| Field | Current FLS (05-buildfix.md) | Corrected FLS | Rationale |
|-------|------------------------------|---------------|-----------|
| VoiceCall.Call_Category__c | editable: true, readable: true | editable: **false**, readable: true | S-05: Call categories should be system-set (IVR attribute), not agent-editable |
| VoiceCall.True_Connection__c | editable: false, readable: true | editable: false, readable: true | Already correct — no change needed |
| VoiceCall.Recording_Opted_Out__c | editable: false, readable: true | editable: false, readable: true | Already correct — set by RecordingOptOutController only |
| Task.Call_Disposition__c | editable: true, readable: true | editable: true, readable: true | Correct — agents must set disposition at call end |
| Task.Call_Duration_Seconds__c | editable: false, readable: true | editable: false, readable: true | Already correct — system-populated from VoiceCall |

**Action:** Update IS_CTI_Base permission set XML in 05-buildfix.md to change `Call_Category__c` from `editable: true` to `editable: false` before Phase 1 deployment.

---

## Handoff to DOC Agent

The DOC agent should:
1. Create deployment runbook for orgsyncng including NGPSTE-132 prerequisite deployment, NGASIM-76 Phase 1 sequenced deploy, manual Omni-Channel routing configuration, and queue membership assignment.
2. Document the Inside Sales permission model tree (Profile → IS_CTI_Base + AC_CallRecording + CTI_Integration_Access → IS_CTI_Agent_Access PSG → Object/Field access).
3. Build full traceability matrix across all 10 pipeline artifacts (00-intake through 09-docs).
4. Write Jira-ready implementation summary for NGASIM-76 (feature description, deliverables, key decisions, security flags, test coverage, configuration debt).
5. Create child story status summary table.
6. Produce open items tracker consolidating all open items from all pipeline stages.
7. Document the NGPSTE-132 dependency relationship and what must complete before NGASIM-76 can proceed.
