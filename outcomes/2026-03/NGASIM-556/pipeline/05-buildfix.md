# NGASIM-556: BUILD-FIX (Stabilize)

## Decisions Made

1. Metadata XML files are the "build artifacts" for this configuration-only story.
2. Build errors are schema validation failures or deployment check-only failures.
3. No Apex compilation errors are possible (no custom code).

## Metadata Files Generated

### 1. Permission Set Group: `Field_Sales_Mobile_PSG`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSetGroup xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Bundles Field Sales core access, edit permissions, and mobile entitlement for the Salesforce Mobile App.</description>
    <label>Field Sales Mobile</label>
    <permissionSets>
        <permissionSet>Field_Sales_Core_Access</permissionSet>
    </permissionSets>
    <permissionSets>
        <permissionSet>Field_Sales_Edit</permissionSet>
    </permissionSets>
    <permissionSets>
        <permissionSet>SalesCloudMobileUser</permissionSet>
    </permissionSets>
    <status>Updated</status>
</PermissionSetGroup>
```

### 2. Compact Layout: Account

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CompactLayout xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Account.Field_Sales_Mobile_Account</fullName>
    <fields>Name</fields>
    <fields>Phone</fields>
    <fields>BillingCity</fields>
    <fields>OwnerId</fields>
    <fields>Type</fields>
    <label>Field Sales Mobile Account</label>
</CompactLayout>
```

### 3. Compact Layout: Lead

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CompactLayout xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Lead.Field_Sales_Mobile_Lead</fullName>
    <fields>Name</fields>
    <fields>Company</fields>
    <fields>Phone</fields>
    <fields>Status</fields>
    <fields>LeadSource</fields>
    <label>Field Sales Mobile Lead</label>
</CompactLayout>
```

### 4. Compact Layout: Opportunity

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CompactLayout xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Opportunity.Field_Sales_Mobile_Opp</fullName>
    <fields>Name</fields>
    <fields>StageName</fields>
    <fields>CloseDate</fields>
    <fields>Amount</fields>
    <fields>AccountId</fields>
    <label>Field Sales Mobile Opportunity</label>
</CompactLayout>
```

## Build Error Log

| # | Error | Source | Resolution |
|---|-------|--------|-----------|
| 1 | N/A -- check-only deploy not yet executed | -- | Pending deployment to orgsyncng sandbox |

## Pre-Deployment Validation Checklist

- [x] XML schema validates against Metadata API v66.0
- [x] Permission Set names match exactly what exists in org (verified via SOQL)
- [x] Compact layout field API names are standard fields (no typos)
- [x] No custom fields referenced (pure standard field set)
- [ ] Check-only deploy to orgsyncng (pending)
- [ ] Full deploy to orgsyncng (pending)

## Addressed Review Findings

| Finding | Status | Action Taken |
|---------|--------|--------------|
| HIGH-002: PSG feature availability | MITIGATED | PSG metadata is valid XML; fallback documented: assign 3 perm sets individually if PSG deploy fails |
| MED-001: Compact layout 4-field card | ADDRESSED | Field order prioritizes most important fields in positions 1-4 (Name, Phone/Company/StageName, BillingCity/Phone/CloseDate, Owner/Status/Amount) |
| MED-002: Log a Call as object-specific | DEFERRED | Requires page layout XML changes; recommend Phase 2 configuration step |

## Handoff to E2E Agent

The E2E agent should:
1. Execute a check-only deployment against orgsyncng to validate metadata
2. If check-only passes, proceed with full deployment
3. Run the SOQL validation queries from 03-tdd.md to confirm PSG creation
4. Begin manual test execution (TS-01 through TS-10)
