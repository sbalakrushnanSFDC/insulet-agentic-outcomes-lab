# NGPSTE-132: REFACTOR (Clean)

## Decisions Made

1. Refactoring scope is metadata hygiene and configuration naming — no custom Apex/LWC code exists to refactor.
2. Focus areas: CallCenter naming standardization, environment-specific adapter exclusion, configuration debt from cancelled child stories.
3. ADR documentation for the NGPSTE-644 Lambda package cancellation gap.

## Refactoring Log

| # | Category | Before | After | Rationale |
|---|----------|--------|-------|-----------|
| R-01 | Naming | CallCenter adapters use inconsistent naming: `ACClassicAdapter`, `ACConsoleAdapter`, `ACLightningAdapter`, `DevInt2ACLightningAdapter`, `SITACLightningAdapter` | Recommend standard prefix `Insulet_AC_` for all production adapters: `Insulet_AC_Lightning`, `Insulet_AC_Console`, `Insulet_AC_Classic` | Current naming mixes environment prefixes (`DevInt2`, `SIT`) with functional names. Standard prefix makes adapter purpose clear and environment prefixes should only appear in environment-specific configs. **Decision: apply to new metadata only. Renaming existing adapters in DevInt2 is out of scope (read-only constraint) and risks breaking agent assignments.** |
| R-02 | Naming | PermissionSetGroup `CTI_Agent_Access` | Keep as-is | Follows the existing org convention where PSGs describe the access bundle, not the metadata type. Consistent with patterns like `Field_Sales_Mobile` (from NGASIM-556). No `_PSG` suffix needed — the metadata type already identifies it. |
| R-03 | Naming | ServicePresenceStatus `Available_Voice`, `Busy_Voice`, `After_Call_Work` | Keep as-is | Follows standard Salesforce Omni-Channel conventions. `Available_Voice` clearly indicates channel affinity. `After_Call_Work` is industry-standard telephony terminology (ACW). No changes needed. |
| R-04 | URL Hardcoding | CallCenter XML contains `https://your-instance.my.connect.aws/connect/ccp-v2` as a placeholder | Parameterize via environment: use `{!$CustomMetadata.CTI_Config__mdt.Connect_Instance_URL}` or a Custom Label | Hardcoded URLs create deployment friction across environments (dev, SIT, UAT, prod). A Custom Metadata Type `CTI_Config__mdt` with fields for `Connect_Instance_URL`, `Connect_API_Endpoint`, and `Region` allows per-environment configuration without XML changes. **Decision: document as recommendation. Implementation requires a new metadata type — defer to Phase 2 unless Security mandates it (see S-02).** |

## Constant Extraction

No Apex constants to extract (no custom code). Configuration values that should be externalized:

| Value | Current Location | Recommended Location | Priority |
|-------|-----------------|---------------------|----------|
| Connect instance URL | CallCenter XML `reqAdapterUrl` | Custom Metadata Type `CTI_Config__mdt` | HIGH (security) |
| Softphone height/width | CallCenter XML | CallCenter XML (acceptable — UI preference) | LOW |
| ServiceChannel `sfdc_phone` | ServicePresenceStatus XML | Hardcoded reference is correct — `sfdc_phone` is the platform standard voice channel | N/A |

## Naming Improvements Applied

| Component | Original API Name | Revised API Name | Reason |
|-----------|------------------|------------------|--------|
| No renames applied | -- | -- | All new metadata follows conventions. Existing DevInt2 metadata cannot be renamed (read-only). |

## Configuration Debt Flagged

| Item | Type | Severity | Notes |
|------|------|----------|-------|
| `DevInt2ACLightningAdapter` | Environment-specific | MEDIUM | This CallCenter record is DevInt2-specific and must be excluded from any cross-environment migration package. Its settings are tied to the DevInt2 Amazon Connect instance URL and agent assignments. Include in `.forceignore` or exclude from `package.xml`. |
| `SITACLightningAdapter` | Environment-specific | MEDIUM | Same as above — SIT environment-specific adapter. Must not be migrated to production or other sandboxes. |
| NGPSTE-644 cancellation (Lambda package) | Functional gap | HIGH | The cancellation of NGPSTE-644 means there is no Lambda proxy between Salesforce and Amazon Connect. ADR-002 documents the Open CTI direct approach, but this leaves a gap: (1) No server-side call event logging outside of Salesforce, (2) No middleware for retry/circuit-breaker on Connect API failures, (3) Real-time event streaming from Connect relies on CloudWatch, not a custom Lambda pipeline. Document in ADR as accepted risk with rationale. |
| NGPSTE-645 (To Do) | Incomplete child story | MEDIUM | One child story remains in "To Do" status. Verify scope: if it covers deployment validation, this run partially addresses it. If it covers production cutover, it is out of scope for this validation run. |
| No Omni-Channel routing config metadata | Process gap | MEDIUM | ServicePresenceStatus records are created, but the Omni-Channel Routing Configuration (queue-to-channel mapping) is not included in the metadata package. This is typically configured via Setup UI, not metadata XML. Document the manual setup steps in the deployment runbook. |
| Call recording retention policy | Compliance debt | HIGH | S-01 flagged the S3 encryption gap. Beyond encryption, there is no documented retention policy for call recordings. Insulet's data retention schedule (likely 7 years for customer interactions) must be applied as an S3 lifecycle rule. This is infrastructure config, not Salesforce metadata. |

## No Apex Refactoring Needed

This implementation is configuration-only:

- **CallCenter:** Declarative XML defining CTI adapter settings
- **ServicePresenceStatus:** Declarative XML defining agent presence states
- **PermissionSetGroup:** Declarative XML bundling existing permission sets
- **ServiceChannel:** Already exists (`sfdc_phone`) — no modification needed

No Apex triggers, classes, or LWC components are part of this story. The Open CTI integration (ADR-002) uses the out-of-box Amazon Connect CTI Adapter managed package, which provides its own Apex and LWC components.

## Environment Exclusion List

The following metadata should be added to `.forceignore` or excluded from cross-environment migration packages:

```
# NGPSTE-132: Environment-specific CallCenter adapters
force-app/main/default/callCenters/DevInt2ACLightningAdapter.callCenter-meta.xml
force-app/main/default/callCenters/SITACLightningAdapter.callCenter-meta.xml
```

## ADR Gap Documentation: NGPSTE-644 Lambda Cancellation

The cancellation of child story NGPSTE-644 (Deploy Lambda CTI event package) creates a documented architectural gap. This should be appended to ADR-002 or recorded as ADR-005.

**Original scope:** A Lambda function sitting between Amazon Connect and Salesforce would have provided:
- Server-side call event logging independent of Salesforce
- Retry logic and circuit-breaker for Connect API failures
- Real-time event transformation (Connect → Platform Events in SF)
- Call metrics aggregation for reporting

**Current state (without Lambda):**
- Direct CCP-to-Salesforce communication via Open CTI client-side API
- No server-side middleware — all integration is browser-based
- Call events lost if agent browser closes during active call
- No retry mechanism — failed VoiceCall record creation requires manual correction

**Accepted risk rationale:**
- Phase 1 priority is voice routing, not event durability
- Open CTI approach is simpler to deploy and maintain
- Lambda can be introduced in Phase 2 without breaking existing integration
- Amazon Connect Contact Trace Records (CTRs) provide a backup audit trail in AWS

**Recommendation:** Document this gap in the ADR and flag for Phase 2 backlog. The Lambda middleware becomes critical when call volume exceeds manual correction capacity (~500 calls/day threshold).

## Cross-Reference: Security Findings Impact on Refactoring

| Security Finding | Refactoring Implication | Action |
|-----------------|------------------------|--------|
| S-01 (S3 encryption) | No metadata refactoring needed — infrastructure concern | Tracked in open items |
| S-02 (Named Credential) | CallCenter XML URL must be parameterized — aligns with R-04 | R-04 recommendation reinforced by security requirement |
| S-03 (Perm set scope) | CTI_Integration_Access audit may reveal unnecessary permissions to remove | Post-audit refactoring may be needed |
| S-04 (VoiceCall FLS) | FLS restrictions require profile/perm set metadata updates | New metadata may be generated post-audit |
| S-05 (CSP) | CSP Trusted Sites is a new metadata type to add to the package | Add to deployment package |

## Handoff to DOC Agent

The DOC agent should:
1. Create deployment runbook for orgsyncng including manual Omni-Channel routing configuration steps
2. Document the permission model (Profile → PermissionSet → PermissionSetGroup → Object Access)
3. Build full traceability matrix across all 10 pipeline artifacts
4. Write Jira-ready implementation summary for NGPSTE-132
5. Document the NGPSTE-644 Lambda gap as an accepted architectural risk
