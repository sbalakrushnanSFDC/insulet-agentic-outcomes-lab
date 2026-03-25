# NGASIM-76: DOCUMENTATION

> **Pipeline Stage:** 09-docs
> **Produced by:** doc-updater agent
> **Input:** All prior artifacts (00-intake through 08-refactor)
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:50:00Z
> **Status:** COMPLETE — pipeline run finished

---

## Decisions Made

1. Documentation deliverables: deployment runbook, permission model reference, full traceability matrix, child story summary, Jira-ready implementation summary, and open items tracker.
2. No end-user training docs in scope — Inside Sales agent training on Amazon Connect CCP is TTEC-managed.
3. Runbook covers orgsyncng deployment only. Production deployment requires a separate change request.
4. NGPSTE-132 prerequisite deployment is integrated into the runbook as a mandatory first step.

---

## Documentation Created

### 1. Deployment Runbook

**Pre-requisites:**
- SF CLI authenticated to `orgsyncng` sandbox
- NGPSTE-132 metadata deployed and validated in orgsyncng (ServicePresenceStatus, CTI_Agent_Access PSG, CallCenter ACLightningAdapter)
- Amazon Connect sandbox instance provisioned with CCP URL (for live testing — not required for metadata deployment)
- Inside Sales test agent user exists with appropriate profile
- Package.xml includes ServicePresenceStatus, PermissionSet, PermissionSetGroup, SoftphoneLayout, Queue, and CustomField metadata types

**Step 0: Verify NGPSTE-132 Prerequisite (MANDATORY)**

```bash
# Verify NGPSTE-132 metadata exists in orgsyncng
sf data query --query "SELECT Id, DeveloperName FROM ServicePresenceStatus WHERE DeveloperName IN ('Available_Voice','Busy_Voice','After_Call_Work')" --target-org orgsyncng
# Expected: 3 rows

sf data query --query "SELECT Id, DeveloperName FROM PermissionSetGroup WHERE DeveloperName = 'CTI_Agent_Access'" --target-org orgsyncng
# Expected: 1 row

sf data query --query "SELECT Id, InternalName FROM CallCenter WHERE InternalName = 'ACLightningAdapter'" --target-org orgsyncng
# Expected: 1 row

# If ANY of the above return 0 rows, STOP. Deploy NGPSTE-132 first.
```

**Step 1: Verify target org (MANDATORY — never skip):**

```bash
sf org display --target-org orgsyncng
# MUST show: sbalakrushnan@insulet.com.orgsyncng
# STOP if DevInt2 alias or username appears
```

**Step 2: Check-only deploy (validation):**

```bash
sf project deploy start --target-org orgsyncng --dry-run \
  --manifest package.xml
```

**Step 3: Full deploy — Phase 1 (sequenced):**

```bash
# Step 3a: ServicePresenceStatus (depends on sfdc_phone ServiceChannel — already exists)
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/servicePresenceStatuses/IS_Available_Voice.servicePresenceStatus-meta.xml

sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/servicePresenceStatuses/IS_Busy_Voice.servicePresenceStatus-meta.xml

sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/servicePresenceStatuses/IS_ACW.servicePresenceStatus-meta.xml

# Step 3b: PermissionSet (no dependencies)
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/permissionsets/IS_CTI_Base.permissionset-meta.xml

# Step 3c: PermissionSetGroup (depends on IS_CTI_Base + AC_CallRecording + CTI_Integration_Access)
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/permissionsetgroups/IS_CTI_Agent_Access.permissionsetgroup-meta.xml

# Step 3d: SoftphoneLayout (depends on ACLightningAdapter from NGPSTE-132)
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/softphoneLayouts/IS_Softphone_Layout.softphoneLayout-meta.xml

# Step 3e: Queues (depends on VoiceCall object and routing config)
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/queues/Inside_Sales_Voice.queue-meta.xml

sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/queues/HCP_Inbound_Voice.queue-meta.xml
```

**Step 4: Full deploy — Phase 2 Custom Fields:**

```bash
# Step 4a: Task custom fields
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/objects/Task/fields/Call_Disposition__c.field-meta.xml

sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/objects/Task/fields/Call_Duration_Seconds__c.field-meta.xml

# Step 4b: VoiceCall custom fields
sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/objects/VoiceCall/fields/Recording_Opted_Out__c.field-meta.xml

sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/objects/VoiceCall/fields/Call_Category__c.field-meta.xml

sf project deploy start --target-org orgsyncng \
  --source-dir force-app/main/default/objects/VoiceCall/fields/True_Connection__c.field-meta.xml
```

**Step 5: Assign PSG to Inside Sales test user:**

```bash
sf org assign permset \
  --name IS_CTI_Agent_Access \
  --target-org orgsyncng \
  --on-behalf-of is.testagent@insulet.com.orgsyncng
```

**Step 6: Run SOQL validation (from 06-e2e.md):**

```bash
# SQ-01: IS ServicePresenceStatus records
sf data query --query "SELECT Id, DeveloperName, MasterLabel FROM ServicePresenceStatus WHERE DeveloperName IN ('IS_Available_Voice','IS_Busy_Voice','IS_ACW')" --target-org orgsyncng

# SQ-02: IS_CTI_Agent_Access PSG membership
sf data query --query "SELECT PermissionSet.Name FROM PermissionSetGroupComponent WHERE PermissionSetGroup.DeveloperName = 'IS_CTI_Agent_Access'" --target-org orgsyncng

# SQ-03: IS_CTI_Base object permissions
sf data query --query "SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete FROM ObjectPermissions WHERE Parent.Name = 'IS_CTI_Base'" --target-org orgsyncng

# SQ-04: Inside_Sales_Voice queue
sf data query --query "SELECT Id, DeveloperName, Name FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Inside_Sales_Voice'" --target-org orgsyncng

# SQ-05: HCP_Inbound_Voice queue
sf data query --query "SELECT Id, DeveloperName, Name FROM Group WHERE Type = 'Queue' AND DeveloperName = 'HCP_Inbound_Voice'" --target-org orgsyncng

# SQ-11: PSG assignment verification
sf data query --query "SELECT Assignee.Name, PermissionSetGroup.DeveloperName FROM PermissionSetAssignment WHERE PermissionSetGroup.DeveloperName = 'IS_CTI_Agent_Access' LIMIT 10" --target-org orgsyncng
```

**Step 7: Manual Omni-Channel routing configuration (not deployable via metadata):**
- Navigate to Setup → Omni-Channel → Routing Configurations
- Create routing config: `IS_Voice_Routing` with priority-based model, capacity weight = 1 (max 1 concurrent call per agent)
- Navigate to Setup → Omni-Channel → Service Channels → `sfdc_phone`
- Verify `sfdc_phone` channel exists (should be present from NGPSTE-132)
- Navigate to Setup → Queues → `Inside_Sales_Voice`
- Associate `IS_Voice_Routing` configuration with the queue
- Add Inside Sales test agent user as queue member
- Navigate to Setup → Queues → `HCP_Inbound_Voice`
- Associate `IS_Voice_Routing` configuration with the queue
- Add designated HCP handler agent as queue member
- Navigate to Setup → Omni-Channel → Omni-Channel Supervisor
- Add Inside Sales queues to Supervisor view

**Step 8: Execute E2E test suite:** Follow TS-01 through SQ-12 in `06-e2e.md`

**Rollback Steps:**

1. Remove PSG assignment from test users:
   ```bash
   # SF CLI does not support unassign — use Setup UI to remove IS_CTI_Agent_Access PSG
   ```
2. Delete ServicePresenceStatus records via Setup → Omni-Channel → Presence Statuses (IS_Available_Voice, IS_Busy_Voice, IS_ACW)
3. Delete PermissionSetGroup via Setup → Permission Set Groups → IS_CTI_Agent_Access
4. Delete PermissionSet via Setup → Permission Sets → IS_CTI_Base
5. Delete Queues via Setup → Queues → Inside_Sales_Voice, HCP_Inbound_Voice
6. Delete SoftphoneLayout via Setup → Softphone Layouts → IS_Softphone_Layout
7. Delete custom fields via Setup → Object Manager → Task → Fields → Call_Disposition__c, Call_Duration_Seconds__c; VoiceCall → Recording_Opted_Out__c, Call_Category__c, True_Connection__c

---

### 2. Permission Model Reference

```
Inside Sales Agent Profile (base)
  │
  ├── IS_CTI_Base                   → Lead: Create + Read + Edit
  │                                   Task: Create + Read + Edit
  │                                   VoiceCall: Read + Edit
  │                                   Opportunity: Read
  │                                   FLS: Call_Disposition__c (RW), Call_Duration_Seconds__c (R),
  │                                        Call_Category__c (R), True_Connection__c (R),
  │                                        Recording_Opted_Out__c (R)
  │
  ├── AC_CallRecording              → Read access to call recording links
  │                                   (S3 presigned URLs via Connect integration)
  │                                   (Shared with Customer Care — from NGPSTE-132)
  │
  ├── CTI_Integration_Access        → Open CTI API permissions
  │                                   VoiceCall: Read + Edit
  │                                   CallCenter: Read
  │                                   ServicePresenceStatus: Read
  │                                   (Shared with Customer Care — from NGPSTE-132)
  │
  └── IS_CTI_Agent_Access (PSG)     = IS_CTI_Base + AC_CallRecording + CTI_Integration_Access
        │
        ├── Enables: Softphone in utility bar (IS_Softphone_Layout)
        ├── Enables: Agent status control (IS_Available_Voice / IS_Busy_Voice / IS_ACW)
        ├── Enables: Inbound call screen pop (Lead → PersonAccount → Contact waterfall)
        ├── Enables: Outbound click-to-dial from Lead, Contact, Patient records
        ├── Enables: Call recording playback
        ├── Enables: Task auto-creation on call completion
        └── Enables: Call disposition capture (Flow-driven)
```

**Object Access Chain (Profile + PSG combined):**

| Object | Profile (base) | IS_CTI_Base | AC_CallRecording | CTI_Integration_Access | Effective Access |
|--------|---------------|-------------|------------------|----------------------|-----------------|
| Lead | Read | Create + Read + Edit | None | None | Create + Read + Edit |
| PersonAccount | Read | None (Read via profile) | None | None | Read (from profile) |
| Contact | Read | None (Read via profile) | None | None | Read (from profile) |
| VoiceCall | None | Read + Edit | Read | Read + Edit | Read + Edit |
| Task | Read + Create + Edit | Create + Read + Edit | None | None | Create + Read + Edit |
| CallCenter | Read | None | None | Read | Read |
| ServicePresenceStatus | Read | None | None | Read | Read |
| Opportunity | Read | Read | None | None | Read |
| Case | Read | None | None | None | Read (from profile) |

**Comparison: Inside Sales vs Customer Care PSG:**

| Dimension | IS_CTI_Agent_Access | CTI_Agent_Access (Care) |
|-----------|--------------------|-----------------------|
| Base PermissionSet | IS_CTI_Base | (none — uses profile only) |
| Lead Access | Create + Read + Edit | None |
| Task Custom Fields | Call_Disposition__c (RW), Call_Duration_Seconds__c (R) | None |
| VoiceCall Custom Fields | Call_Category__c (R), True_Connection__c (R), Recording_Opted_Out__c (R) | None |
| Opportunity Access | Read | None |
| Queues | Inside_Sales_Voice, HCP_Inbound_Voice | Care voice queues |
| Presence Statuses | IS_Available_Voice, IS_Busy_Voice, IS_ACW | Available_Voice, Busy_Voice, After_Call_Work |

---

### 3. Traceability Links

| Artifact | Source | Evidence | Key Outputs |
|----------|--------|----------|-------------|
| 00-intake.md | NGASIM-76 Jira | `jira_get_issue('NGASIM-76')`, `jira_search` (16 child stories: 0 Done, 2 To Verify, 7 To Do, 4 Technical Refinement, 2 Cancelled, 1 Other) | 16 FRs, 6 NFRs, child story status matrix, dependency map, 13 intake risks |
| 01-plan.md | 00-intake.md + NGPSTE-132 run artifacts + DevInt2 SOQL | Planning decisions, AC derivation | 17 ACs (AC-01 through AC-17), 3-phase implementation plan, 23-item metadata inventory, 11 risks, effort estimate (55 SP) |
| 02-architecture.md | 01-plan.md + NGPSTE-132 ADRs + DevInt2 data | Architectural analysis extending NGPSTE-132 foundation | ADR-005 (multi-object screen pop), ADR-006 (Task auto-logging), ADR-007 (IS Omni-Channel routing), ADR-008 (recording opt-out). Component integration diagram. 5 integration points. IS vs Care segregation table. |
| 03-tdd.md | 02-architecture.md + ACs | Test specification (not yet produced — TDD stage pending) | Expected: test specs for InsideSalesScreenPopResolver, VoiceCallActivityHandler, RecordingOptOutController, SOQL validation queries |
| 04-review.md | 00–02 artifacts (03-tdd pending) | Cross-artifact review | 11 findings (F-01 through F-11): 3 HIGH (NGPSTE-132 dependency, screen pop governor risk, Named Credential), 4 MEDIUM, 2 LOW, 2 INFO |
| 05-buildfix.md | 04-review.md findings + metadata inventory | Metadata XML generation + pseudo-code | 3 ServicePresenceStatus, 1 PermissionSet (IS_CTI_Base), 1 PSG (IS_CTI_Agent_Access), 1 SoftphoneLayout, 2 Queues, 2 CustomFields (Task), 1 CustomField (VoiceCall). InsideSalesScreenPopResolver pseudo-code. |
| 06-e2e.md | 01-plan.md ACs + 05-buildfix.md metadata | Test execution plan | 23-test matrix (17 AC-mapped + 3 negative + 2 bulk + 1 priority). 12 SOQL validation queries. 8 pre-execution blockers. Risk assessment for deferred tests. |
| 07-security.md | 05-buildfix.md + 02-architecture.md + integration surface | Security assessment | 8 findings (S-01 through S-08): 3 HIGH (PHI exposure via screen pop, Named Credential, HIPAA audit trail), 4 MEDIUM, 1 LOW. CRUD/FLS matrix for 5 objects × 5 profiles. OWASP checklist. HIPAA recording opt-out assessment. |
| 08-refactor.md | 05-buildfix.md + 07-security.md + DevInt2 data | Metadata hygiene review + configuration debt | 8 naming audit items (all kept as-is), constant extraction recommendations, 8 configuration debt items, permission set FLS correction (Call_Category__c), environment exclusion list. |
| 09-docs.md | All prior artifacts | Synthesis and documentation | Runbook, permission model tree, traceability matrix, child story summary, Jira-ready summary, open items tracker |

---

### 4. Child Story Status Summary

| Story | Title | Status | Phase | Impact on This Run |
|-------|-------|--------|-------|-------------------|
| NGPSTE-531 | Set up Sales Queues in Infinity | **Cancelled** | 1 | Gap addressed — queue metadata generated in 05-buildfix.md (Inside_Sales_Voice, HCP_Inbound_Voice) |
| NGPSTE-532 | Inbound Call: Screen Pop w/ Relevant Info | **Technical Refinement** | 1 | Covered — InsideSalesScreenPopResolver pseudo-code in 05-buildfix.md, ADR-005 |
| NGPSTE-533 | SSO Login to CTI from within Salesforce | **To Verify** | 2 | Noted — SSO/SAML configuration pending. Blocked by NGASIM-1523 per Jira link. TS-07 NOT RUN. |
| NGPSTE-534 | Inbound Call: HCP / Provider / Physician | **To Do** | 3 | Covered — HCP_Inbound_Voice queue created. IVR routing depends on TTEC (F-08). |
| NGPSTE-535 | Outbound Calls: Click to Dial | **Technical Refinement** | 1 | Covered — IS_Softphone_Layout with click-to-dial enabled. TS-06 NOT RUN (pending Connect sandbox). |
| NGPSTE-536 | Automating a Call Log (Activity) | **Technical Refinement** | 2 | Covered — ADR-006 (VoiceCallActivityHandler). Task.Call_Disposition__c and Call_Duration_Seconds__c fields generated. Apex not yet implemented. |
| NGPSTE-538 | Agent Status + Call Disposition | **Technical Refinement** | 1/2 | Covered — IS_Available_Voice/IS_Busy_Voice/IS_ACW created. Disposition picklist generated. F-07 notes PO confirmation pending. |
| NGPSTE-708 | Call Transfers | **Technical Refinement** | 3 | Noted — warm/cold transfer depends on Connect contact flow (TTEC). Blocked by NGPSTE-1123. TS-11, TS-12 NOT RUN. |
| NGPSTE-809 | Quick Connect for Sales | **To Do** | 3 | Noted — TTEC configuration required. TS-13 NOT RUN. |
| NGPSTE-811 | Access/View Voice Mails | **To Do** | 3 | Noted — voicemailPlayer LWC in metadata inventory. Not yet implemented. TS-15 NOT RUN. |
| NGASIM-1523 | Stop Recording (Patient Opt-out) | **To Verify** | 2 | Covered — ADR-008 (RecordingOptOutController). VoiceCall.Recording_Opted_Out__c generated. Named Credential dependency (S-02). HIPAA assessment in 07-security.md. |
| NGASIM-1524 | Insulet Phone Number Not Spam | **To Do** | 3 | Noted — carrier-level issue outside Salesforce. No metadata change. Deferred per PD-06. |
| NGASIM-1525 | Determine True Connections | **To Do** | 3 | Covered — VoiceCall.True_Connection__c field generated. Logic not yet implemented. TS-17 NOT RUN. |
| NGASIM-1526 | Differentiate Inbound Call Types | **To Do** | 3 | Covered — VoiceCall.Call_Category__c field generated. IVR tagging depends on TTEC. TS-16 NOT RUN. |
| NGASIM-1527 | Configure IS Reps with Software | **To Do** | 3 | Noted — onboarding automation. Out of scope for this CTI pipeline run. |
| NGASIM-2549 | NFR for NGASIM-76 | **Cancelled** | — | Gap documented — NFR targets captured in 00-intake.md. F-11 recommends creating replacement Jira story. |

---

### 5. Story Implementation Summary (Jira-ready)

> **NGASIM-76 Implementation Summary**
>
> **Feature:** Incoming & outgoing calls handling for Lead & Consumer by Inside Sales (CTI)
>
> **Approach:** Extension of NGPSTE-132 Amazon Connect CTI integration for the Inside Sales persona. Reuses ACLightningAdapter (OOB), Open CTI, and sfdc_phone ServiceChannel from NGPSTE-132. Creates Inside Sales-specific routing, queues, permissions, and screen pop logic. Three custom Apex classes planned: InsideSalesScreenPopResolver (multi-object waterfall search), VoiceCallActivityHandler (Task auto-creation), RecordingOptOutController (HIPAA recording opt-out via Connect API).
>
> **Deliverables (Phase 1 — Config):**
> - 3 ServicePresenceStatus records: IS_Available_Voice, IS_Busy_Voice, IS_ACW (mapped to sfdc_phone channel)
> - Permission Set: IS_CTI_Base (Lead CRUD, Task CRUD, VoiceCall Read/Edit, Opportunity Read)
> - Permission Set Group: IS_CTI_Agent_Access (bundles IS_CTI_Base + AC_CallRecording + CTI_Integration_Access)
> - Softphone Layout: IS_Softphone_Layout (click-to-dial, screen pop, recording controls)
> - Queues: Inside_Sales_Voice (consumer/lead calls), HCP_Inbound_Voice (provider calls)
> - Omni-Channel routing configuration: IS_Voice_Routing (manual setup — documented in runbook)
>
> **Deliverables (Phase 2 — Apex + Fields):**
> - InsideSalesScreenPopResolver: waterfall ANI search across Lead → PersonAccount → Contact
> - VoiceCallActivityHandler: auto-create Task on VoiceCall completion with WhoId, WhatId, Duration, Disposition
> - RecordingOptOutController: HTTP callout to Connect StopContactRecording API via Named Credential
> - Custom fields: Task.Call_Disposition__c (picklist), Task.Call_Duration_Seconds__c (number), VoiceCall.Recording_Opted_Out__c (checkbox), VoiceCall.Call_Category__c (picklist), VoiceCall.True_Connection__c (checkbox)
>
> **Key Decisions (4 ADRs):**
> - ADR-005: Multi-object waterfall screen pop (Lead → PersonAccount → Contact) — avoids SOSL limitations
> - ADR-006: Task auto-creation via Apex trigger + Flow hybrid — trigger for guaranteed execution, Flow for agent disposition
> - ADR-007: Separate IS Omni-Channel routing — different capacity model (1 concurrent) and agent pool from Care
> - ADR-008: Recording opt-out via Quick Action + Apex callout to Connect API — HIPAA compliance with audit trail
>
> **Security Flags (3 HIGH):**
> - S-01: Screen pop exposes Patient PHI to Inside Sales — restrict PersonAccount page layout + FLS
> - S-02: Named Credential for Connect API not created — blocks RecordingOptOutController
> - S-03: Recording opt-out audit trail insufficient — add timestamp, agent, API response fields
>
> **Test Coverage:** 23 test cases (17 AC-mapped + 3 negative + 2 bulk + 1 priority). 12 SOQL validation queries. All NOT RUN — blocked by NGPSTE-132 deployment, Connect sandbox provisioning, and Apex implementation.
>
> **Configuration Debt:** 8 items flagged (see 08-refactor.md) — highest priority: Named Credential creation, NGPSTE-531 queue cancellation verification, TTEC contact flow changes, NGCRMI-2007 OrgSync gap
>
> **Critical Dependency:** NGPSTE-132 must be deployed to orgsyncng before any NGASIM-76 metadata can be deployed.
>
> **Deploy Target:** orgsyncng sandbox (NEVER DevInt2)

---

### 6. Open Items Tracker

| # | Item | Owner | Priority | Status | Source Artifact | Notes |
|---|------|-------|----------|--------|----------------|-------|
| OI-01 | Deploy NGPSTE-132 metadata to orgsyncng | DevOps | **CRITICAL** | Open | 04-review F-01 | Blocks all NGASIM-76 work. Longest-running blocker across both pipeline runs. |
| OI-02 | Create Named Credential `AmazonConnect_API` | DevOps / AWS | **CRITICAL** | Open | 04-review F-03, 07-security S-02 | Blocks RecordingOptOutController and all Connect API callouts. Open since NGPSTE-132. |
| OI-03 | Amazon Connect sandbox provisioning | Cloud Infra | **HIGH** | Open | 06-e2e B-02 | No sandbox Connect instance for live call testing. Carried from NGPSTE-132. |
| OI-04 | Restrict PersonAccount PHI fields from IS agents | Dev / Security | **HIGH** | Open | 07-security S-01 | Create IS-specific PersonAccount page layout. Apply FLS on IS_CTI_Base. |
| OI-05 | Recording opt-out audit trail enhancement | Dev | **HIGH** | Open | 07-security S-03 | Add VoiceCall.Recording_Opted_Out_At__c, Recording_Opted_Out_By__c fields. Enable Field History Tracking. |
| OI-06 | IS_CTI_Base FLS correction: Call_Category__c to read-only | Dev | **HIGH** | Open | 08-refactor S-05 cross-ref | Update IS_CTI_Base XML before deployment. |
| OI-07 | TTEC contact flow changes (HCP routing, call type tagging, transfers, quick connect) | PM / TTEC | **HIGH** | Open | 04-review F-08, 08-refactor config debt | External partner dependency for Phase 3 ACs (AC-05, AC-11, AC-12, AC-13, AC-16). |
| OI-08 | PO confirmation on call disposition picklist values | PM / PO | **MEDIUM** | Open | 04-review F-07 | 6 values proposed. PO must confirm before Phase 2 deployment. |
| OI-09 | Define Inside Sales queue membership criteria | Config lead / PM | **MEDIUM** | Open | 04-review F-06 | Which users/profiles join Inside_Sales_Voice and HCP_Inbound_Voice queues? |
| OI-10 | VoiceCallActivityHandler WhoId context-sharing design | Dev lead | **MEDIUM** | Open | 04-review F-04 | Design VoiceCall.Screen_Pop_Record_Id__c or alternative mechanism. |
| OI-11 | NGCRMI-2007 Task OrgSync field mapping | Integration lead | **MEDIUM** | Open | 04-review F-09, 08-refactor config debt | Task custom fields (Call_Disposition__c, Call_Duration_Seconds__c) must be included in OrgSync mapping. |
| OI-12 | Create NFR Jira story (replacement for cancelled NGASIM-2549) | QA lead | **MEDIUM** | Open | 04-review F-11 | Formalize performance targets: page load < 3s, API < 2s, 1000 concurrent. |
| OI-13 | Verify NGPSTE-531 cancellation reason | PM | **MEDIUM** | Open | 08-refactor config debt | Was queue setup moved elsewhere or is it a genuine gap? |
| OI-14 | IS test agent user provisioned in orgsyncng | DevOps | **MEDIUM** | Open | 06-e2e B-08 | Need user with IS Agent profile + IS_CTI_Agent_Access PSG for all manual tests. |
| OI-15 | Lead duplicate matching rule for screen pop | Dev | **MEDIUM** | Open | 07-security S-04 | Prevent duplicate Lead creation from screen pop new Lead form. |
| OI-16 | SSO/SAML configuration for Connect CCP | Dev / Identity | **MEDIUM** | Open | 06-e2e B-07 | NGPSTE-533 in To Verify. Requires identity team coordination. |
| OI-17 | Task sharing model review (OWD/Record Type) | Dev / Security | **LOW** | Open | 07-security S-06 | IS call activity Tasks may be visible to other departments. Consider Record Type + sharing rules. |
| OI-18 | Omni-Channel routing config as metadata XML | Config lead | **LOW** | Open | 08-refactor config debt | IS_Voice_Routing is manual Setup UI config. Consider generating XML for repeatable deployment. |
| OI-19 | Assign owner for NGPSTE-1123 (Classic Dev Package Part 3) | PM | **LOW** | Open | 08-refactor config debt, 04-review F-08 | Blocks call transfer testing (NGPSTE-708). No owner or sprint assigned. |
| OI-20 | Recording re-enable prevention after opt-out | Dev | **LOW** | Open | 08-refactor design debt | Block ResumeContactRecording when Recording_Opted_Out__c = true. |

---

## Documentation Updated

| Document | Status | Notes |
|----------|--------|-------|
| NGASIM-76 Jira story | NOT YET UPDATED | Implementation summary ready for Jira comment (Section 5 above). Copy as-is to Jira. |
| Confluence: Inside Sales CTI Integration Guide | NOT YET CREATED | Recommend creating under NextGen space — covers screen pop design, permission model, agent onboarding, recording opt-out procedure |
| Confluence: Deployment Runbook (IS CTI) | NOT YET CREATED | Runbook content ready (Section 1 above) — recommend Confluence page for team reference |
| Confluence: IS vs Care CTI Segregation | NOT YET CREATED | Permission model comparison (Section 2 above) — important for admin reference |
| This run folder (`runs/NGASIM-76/`) | COMPLETE | All 10 pipeline artifacts produced (00-intake through 09-docs). 03-tdd.md pending (TDD stage not yet executed). |
| NGPSTE-132 run folder (`runs/NGPSTE-132/`) | REFERENCED | NGASIM-76 extends NGPSTE-132 decisions. No updates to NGPSTE-132 artifacts needed. |
| `.forceignore` | NOT YET UPDATED | Environment exclusion list in 08-refactor.md — add DevInt2/SIT adapters (carried from NGPSTE-132) |
| NGASIM-76 open items tracker | CREATED | 20 open items across all pipeline stages (Section 6 above). Track in sprint planning. |
