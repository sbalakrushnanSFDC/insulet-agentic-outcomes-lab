# NGASIM-556: DOCUMENTATION

## Decisions Made

1. Documentation deliverables: deployment runbook, permission model reference, and traceability links.
2. No end-user training docs are in scope (training is a separate story/epic).

## Documentation Created

### 1. Deployment Runbook

**Pre-requisites:**
- SF CLI authenticated to `orgsyncng` sandbox
- Field Sales test user exists with Sales profile
- iPad with Salesforce Mobile App installed

**Deployment Steps:**

1. **Verify target org:**
   ```bash
   sf org display --target-org orgsyncng
   ```

2. **Check-only deploy (validation):**
   ```bash
   sf project deploy start --target-org orgsyncng --dry-run \
     --source-dir force-app/main/default/permissionsetgroups/Field_Sales_Mobile.permissionsetgroup-meta.xml \
     --source-dir force-app/main/default/compactLayouts/
   ```

3. **Full deploy:**
   ```bash
   sf project deploy start --target-org orgsyncng \
     --source-dir force-app/main/default/permissionsetgroups/Field_Sales_Mobile.permissionsetgroup-meta.xml \
     --source-dir force-app/main/default/compactLayouts/
   ```

4. **Assign PSG to test user:**
   ```bash
   sf org assign permset --name Field_Sales_Mobile --target-org orgsyncng --on-behalf-of testuser@insulet.com.orgsyncng
   ```

5. **Run SOQL validation:**
   ```bash
   sf data query --query "SELECT Id, DeveloperName FROM PermissionSetGroup WHERE DeveloperName = 'Field_Sales_Mobile'" --target-org orgsyncng
   ```

6. **Manual test execution:** Follow TS-01 through TS-10 in `03-tdd.md`

**Rollback Steps:**
1. Remove PSG assignment from users
2. Delete PSG: `sf project delete source --source-dir force-app/main/default/permissionsetgroups/Field_Sales_Mobile.permissionsetgroup-meta.xml --target-org orgsyncng`
3. Revert compact layout assignments to org default

### 2. Permission Model Reference

```
Sales Profile (base)
  │
  ├── Field_Sales_Core_Access    → Object read access (Account, Lead, Opp, Task, Event)
  ├── Field_Sales_Edit           → Object edit/create access
  ├── Field_Sales_TM_DSM         → TM/DSM-specific fields and reports
  ├── Field_Sales_GM_RBD         → GM/RBD-specific fields and reports
  └── SalesCloudMobileUser       → Salesforce Mobile App entitlement
      │
      └── Field_Sales_Mobile (PSG) = Core_Access + Edit + MobileUser
```

### 3. Traceability Links

| Artifact | Source | Traces To |
|----------|--------|-----------|
| Requirements | NGASIM-556 (Jira) | 00-intake.md |
| Acceptance Criteria | NGASIM-556 custom field + 01-plan.md | AC-1 through AC-10 |
| Architecture | 02-architecture.md | ADR-001 through ADR-004 |
| Test Cases | 03-tdd.md | TS-01 through TS-NEG-02 |
| Security Findings | 07-security.md | SEC-001 through SEC-005 |
| Metadata | 05-buildfix.md | PSG XML, CompactLayout XMLs |
| Parent Feature | NGASIM-38 | 00-intake.md |
| DevInt2 Queries | SOQL results (read-only) | 01-plan.md Dependencies |

### 4. Story Implementation Summary (for Jira comment)

> **NGASIM-556 Implementation Summary**
>
> **Approach:** OOTB configuration (no custom Apex/LWC)
>
> **Deliverables:**
> - Permission Set Group: `Field_Sales_Mobile` (bundles Core Access + Edit + Mobile User)
> - 3 compact layouts: Account, Lead, Opportunity (mobile-optimized)
> - SalesCloudMobile app navigation configuration
>
> **Key Decisions:**
> - Use `SalesCloudMobile` (Standard NavType), not `Insulet_Sales` (Console -- incompatible with mobile)
> - PSG-based permission layering for clean assignment
> - No custom code required
>
> **Security Flags:**
> - SEC-001: Health Cloud data exposure audit required before prod deployment
> - SEC-002: Device security policy (PIN/biometric) recommended
>
> **Test Coverage:** 12 functional test cases (10 positive + 2 negative), 3 SOQL validations
>
> **Deploy Target:** orgsyncng sandbox

## Documentation Updated

| Document | Status | Notes |
|----------|--------|-------|
| NGASIM-556 Jira story | NOT YET UPDATED | Implementation summary ready for Jira comment (above) |
| Confluence: Mobile Access Guide | NOT YET CREATED | Recommend creating under AJST space |
| This run folder (`runs/NGASIM-556/`) | COMPLETE | All 10 pipeline artifacts produced |
