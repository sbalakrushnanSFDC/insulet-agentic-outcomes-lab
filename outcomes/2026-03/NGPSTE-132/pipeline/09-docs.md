# NGPSTE-132: DOCUMENTATION

## Decisions Made

1. Documentation deliverables: deployment runbook, permission model reference, full traceability matrix, and Jira-ready implementation summary.
2. No end-user training docs in scope — agent training on Amazon Connect CCP is a separate initiative (TTEC-managed).
3. Runbook covers orgsyncng deployment only. Production deployment requires a separate change request.

## Documentation Created

### 1. Deployment Runbook

**Pre-requisites:**
- SF CLI authenticated to `orgsyncng` sandbox
- Amazon Connect sandbox instance provisioned with CCP URL
- Test agent user exists with Customer Care Agent profile
- Package.xml includes ServicePresenceStatus, PermissionSetGroup, and CallCenter metadata types

**Deployment Steps:**

1. **Verify target org (MANDATORY — never skip):**
   ```bash
   sf org display --target-org orgsyncng
   # MUST show: sbalakrushnan@insulet.com.orgsyncng
   # STOP if DevInt2 alias or username appears
   ```

2. **Replace CCP URL placeholder:**
   Update `ACLightningAdapter` CallCenter XML — replace `your-instance.my.connect.aws` with actual Connect sandbox instance URL.

3. **Check-only deploy (validation):**
   ```bash
   sf project deploy start --target-org orgsyncng --dry-run \
     --manifest package.xml
   ```

4. **Full deploy (sequenced):**
   ```bash
   # Step 1: ServicePresenceStatus (no dependencies)
   sf project deploy start --target-org orgsyncng \
     --source-dir force-app/main/default/servicePresenceStatuses/

   # Step 2: PermissionSetGroup (depends on existing perm sets)
   sf project deploy start --target-org orgsyncng \
     --source-dir force-app/main/default/permissionsetgroups/CTI_Agent_Access.permissionsetgroup-meta.xml

   # Step 3: CallCenter update (depends on existing CallCenter record)
   sf project deploy start --target-org orgsyncng \
     --source-dir force-app/main/default/callCenters/ACLightningAdapter.callCenter-meta.xml
   ```

5. **Assign PSG to test user:**
   ```bash
   sf org assign permset \
     --name CTI_Agent_Access \
     --target-org orgsyncng \
     --on-behalf-of testagent@insulet.com.orgsyncng
   ```

6. **Run SOQL validation (from 06-e2e.md):**
   ```bash
   sf data query --query "SELECT Id, DeveloperName, MasterLabel FROM ServicePresenceStatus WHERE DeveloperName IN ('Available_Voice','Busy_Voice','After_Call_Work')" --target-org orgsyncng

   sf data query --query "SELECT PermissionSet.Name FROM PermissionSetGroupComponent WHERE PermissionSetGroup.DeveloperName = 'CTI_Agent_Access'" --target-org orgsyncng

   sf data query --query "SELECT Id, Name, InternalName FROM CallCenter WHERE InternalName = 'ACLightningAdapter'" --target-org orgsyncng
   ```

7. **Manual Omni-Channel routing configuration (not deployable via metadata):**
   - Navigate to Setup → Omni-Channel → Routing Configurations
   - Create routing config: `Voice_Routing` with priority-based model
   - Navigate to Setup → Omni-Channel → Service Channels → `sfdc_phone`
   - Associate `Voice_Routing` configuration with `sfdc_phone` channel
   - Navigate to Setup → Queues → create/update voice queue with `sfdc_phone` channel
   - Assign test agent user to the voice queue

8. **Execute E2E test suite:** Follow TS-01 through SQ-06 in `06-e2e.md`

**Rollback Steps:**

1. Remove PSG assignment from test users:
   ```bash
   sf org assign permset --name CTI_Agent_Access --target-org orgsyncng --on-behalf-of testagent@insulet.com.orgsyncng
   # Note: SF CLI doesn't support unassign — use Setup UI to remove PSG assignment
   ```
2. Delete ServicePresenceStatus records via Setup → Omni-Channel → Presence Statuses
3. Delete PermissionSetGroup via Setup → Permission Set Groups
4. Revert CallCenter settings via Setup → Call Centers

### 2. Permission Model Reference

```
Customer Care Agent Profile (base)
  │
  ├── AC_CallRecording           → Read access to call recording links
  │                                 (S3 presigned URLs via Connect integration)
  │
  ├── CTI_Integration_Access     → Open CTI API permissions
  │                                 VoiceCall: Read + Edit
  │                                 CallCenter: Read
  │                                 ServicePresenceStatus: Read
  │
  └── CTI_Agent_Access (PSG)     = AC_CallRecording + CTI_Integration_Access
        │
        ├── Enables: Softphone in utility bar
        ├── Enables: Agent status control (Available/Busy/ACW)
        ├── Enables: Inbound call screen pop
        ├── Enables: Outbound click-to-dial
        └── Enables: Call recording playback
```

**Object Access Chain (Profile + PSG combined):**

| Object | Profile (base) | AC_CallRecording | CTI_Integration_Access | Effective Access |
|--------|---------------|------------------|----------------------|-----------------|
| VoiceCall | None | Read | Read + Edit | Read + Edit |
| CallCenter | Read | None | Read | Read |
| ServicePresenceStatus | Read | None | Read | Read |
| Account | Read + Edit | None | None | Read + Edit (from profile) |
| Contact | Read + Edit | None | None | Read + Edit (from profile) |
| Case | Read + Create + Edit | None | None | Read + Create + Edit (from profile) |

### 3. Traceability Links

| Artifact | Source | Evidence | Key Outputs |
|----------|--------|----------|-------------|
| 00-intake.md | NGPSTE-132 Jira | `jira_get_issue('NGPSTE-132')`, `jira_search` (6 child stories: 3 Done, 2 Cancelled, 1 To Do) | 10 ACs, child story status matrix |
| 01-plan.md | DevInt2 SOQL (read-only) | `run_soql_query`: CallCenter (5 records), PermissionSet (AC_CallRecording, CTI_Integration_Access), ServiceChannel (sfdc_phone), ServicePresenceStatus (0 records) | Dependency map, gap analysis, implementation approach |
| 02-architecture.md | 01-plan.md + DevInt2 data | Architectural analysis of CTI options | ADR-001 (use ACLightningAdapter OOB), ADR-002 (Open CTI over SCV), ADR-003 (Omni-Channel routing via sfdc_phone), ADR-004 (extend existing perm sets via PSG) |
| 03-tdd.md | 02-architecture.md + ACs | Test specification against acceptance criteria | 12 test specs (TS-01 through TS-10, TS-NEG-01, TS-NEG-02) |
| 04-review.md | 00–03 artifacts | Cross-artifact review | 7 findings (F-01 through F-07): 2 HIGH (no ServicePresenceStatus, Lambda cancellation), 5 MEDIUM/LOW |
| 05-buildfix.md | 04-review.md findings | Metadata XML generation | 3 ServicePresenceStatus, 1 PSG (CTI_Agent_Access), 1 CallCenter update |
| 06-e2e.md | 03-tdd.md + 05-buildfix.md | Test execution plan | 15-test matrix (12 functional + 3 SOQL), 5 pre-execution blockers |
| 07-security.md | 05-buildfix.md + integration surface | Security assessment | 6 findings (S-01 through S-06): 2 HIGH (S3 encryption, Named Credential), 3 MEDIUM, 1 LOW |
| 08-refactor.md | 05-buildfix.md + DevInt2 data | Metadata hygiene review | 4 refactoring items, 6 configuration debt items, environment exclusion list |
| 09-docs.md | All prior artifacts | Synthesis and documentation | Runbook, permission model, traceability, Jira summary |

### 4. Child Story Status Summary

| Story | Title | Status | Impact on This Run |
|-------|-------|--------|-------------------|
| NGPSTE-641 | Configure ACLightningAdapter for Lightning | Done | Covered — CallCenter update in 05-buildfix.md |
| NGPSTE-642 | Set up Omni-Channel voice routing | Done | Covered — ServicePresenceStatus in 05-buildfix.md, routing config in runbook |
| NGPSTE-643 | Configure CTI permission sets | Done | Covered — PSG in 05-buildfix.md |
| NGPSTE-644 | Deploy Lambda CTI event package | Cancelled | Gap documented — ADR-002, R-04 in 08-refactor.md |
| NGPSTE-645 | Validate CTI integration E2E | To Do | Partially covered by 06-e2e.md test plan; blocked by Amazon Connect sandbox |
| NGPSTE-646 | Enable call recording access | Cancelled | Gap documented — S-01 in 07-security.md covers recording storage security |

### 5. Story Implementation Summary (Jira-ready)

> **NGPSTE-132 Implementation Summary**
>
> **Approach:** OOTB configuration using Amazon Connect CTI Adapter (ACLightningAdapter) with Open CTI integration. No custom Apex or LWC — leverages managed package components.
>
> **Deliverables:**
> - 3 ServicePresenceStatus records: Available_Voice, Busy_Voice, After_Call_Work (mapped to sfdc_phone channel)
> - Permission Set Group: CTI_Agent_Access (bundles AC_CallRecording + CTI_Integration_Access)
> - CallCenter update: ACLightningAdapter configured for Lightning CCP with softphone dimensions and Open CTI enabled
> - Omni-Channel routing configuration (manual setup — documented in runbook)
>
> **Key Decisions (4 ADRs):**
> - ADR-001: Use existing ACLightningAdapter (OOB) — no custom adapter needed
> - ADR-002: Open CTI over Service Cloud Voice — lower cost, existing infrastructure, Lambda proxy not required (NGPSTE-644 cancelled)
> - ADR-003: Omni-Channel routing via sfdc_phone ServiceChannel — standard voice routing
> - ADR-004: Extend existing permission sets via PSG — cleaner provisioning than individual assignment
>
> **Security Flags (2 HIGH):**
> - S-01: Call recording S3 bucket encryption policy not documented — PII/PHI risk — escalate to InfoSec
> - S-02: Amazon Connect API endpoint must use Named Credential — verify before production
>
> **Test Coverage:** 15 test cases (10 positive + 2 negative + 3 SOQL validations). All NOT RUN — blocked by orgsyncng deployment and Amazon Connect sandbox provisioning.
>
> **Configuration Debt:** 6 items flagged (see 08-refactor.md) — highest priority: NGPSTE-644 Lambda gap documentation, environment-specific adapter exclusion
>
> **Deploy Target:** orgsyncng sandbox (NEVER DevInt2)

### 6. Open Items Tracker

| # | Item | Owner | Priority | Status | Artifact Reference |
|---|------|-------|----------|--------|-------------------|
| OI-01 | S3 bucket encryption audit | InfoSec | CRITICAL | Open | 07-security.md S-01 |
| OI-02 | Named Credential for Connect API | DevOps | HIGH | Open | 07-security.md S-02 |
| OI-03 | Amazon Connect sandbox provisioning | Cloud Infra | HIGH | Open | 06-e2e.md B-02 |
| OI-04 | CCP URL replacement in CallCenter XML | Dev | HIGH | Open | 05-buildfix.md, 06-e2e.md B-04 |
| OI-05 | CTI_Integration_Access perm set audit | Dev | MEDIUM | Open | 07-security.md S-03 |
| OI-06 | VoiceCall FLS configuration | Dev | MEDIUM | Open | 07-security.md S-04 |
| OI-07 | CSP Trusted Sites for Connect domain | Dev | MEDIUM | Open | 07-security.md S-05 |
| OI-08 | NGPSTE-645 scope verification | PM | MEDIUM | Open | 08-refactor.md |
| OI-09 | Call recording retention policy | Compliance | MEDIUM | Open | 08-refactor.md |
| OI-10 | Omni-Channel routing config (manual) | Dev | LOW | Open | 09-docs.md Runbook Step 7 |

## Documentation Updated

| Document | Status | Notes |
|----------|--------|-------|
| NGPSTE-132 Jira story | NOT YET UPDATED | Implementation summary ready for Jira comment (Section 5 above) |
| Confluence: CTI Integration Guide | NOT YET CREATED | Recommend creating under NextGen space — covers adapter config, permission model, agent onboarding |
| Confluence: Deployment Runbook | NOT YET CREATED | Runbook content ready (Section 1 above) — recommend Confluence page for team reference |
| This run folder (`runs/NGPSTE-132/`) | COMPLETE | All 10 pipeline artifacts produced (00-intake through 09-docs) |
| `.forceignore` | NOT YET UPDATED | Environment exclusion list ready (08-refactor.md) — add DevInt2/SIT adapters |
