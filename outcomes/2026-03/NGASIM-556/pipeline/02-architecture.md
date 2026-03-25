# NGASIM-556: ARCHITECTURE

## Decisions Made

1. **ADR-001: Use `SalesCloudMobile` app, not `Insulet_Sales`** -- `Insulet_Sales` is NavType=Console which does not render in the Salesforce Mobile App. `SalesCloudMobile` is NavType=Standard and is the platform-provided mobile experience. Decision: configure `SalesCloudMobile` with Insulet-specific navigation items rather than creating a custom app.
2. **ADR-002: Permission Set Group over individual assignment** -- Create `Field_Sales_Mobile_PSG` to bundle `Field_Sales_Core_Access` + `Field_Sales_Edit` + `SalesCloudMobileUser`. This provides a single assignable unit and follows Salesforce best practice for permission layering.
3. **ADR-003: No custom Apex/LWC required** -- This is a pure configuration story. All capabilities (Account/Lead/Opp access, Task/Event management, Log a Call) are OOTB Salesforce Mobile features. Zero custom code.
4. **ADR-004: Compact layouts are the mobile UI contract** -- Salesforce Mobile App uses compact layouts as the primary card display. We define specific compact layouts per object.

## Component Design

```
┌─────────────────────────────────────────────────────┐
│                Salesforce Mobile App                 │
│                (SalesCloudMobile)                    │
├─────────────────────────────────────────────────────┤
│  Navigation Items:                                   │
│  ┌───────┬──────┬──────────┬──────┬───────┬──────┐ │
│  │ Home  │Accts │  Leads   │Opps  │Tasks  │Events│ │
│  └───────┴──────┴──────────┴──────┴───────┴──────┘ │
├─────────────────────────────────────────────────────┤
│  Quick Actions (per object):                         │
│  • Log a Call (Task with CallType=Call)              │
│  • New Task                                          │
│  • New Event                                         │
├─────────────────────────────────────────────────────┤
│  Permission Stack:                                   │
│  ┌─────────────────────────────────────────────────┐│
│  │ Field_Sales_Mobile_PSG (Permission Set Group)   ││
│  │  ├─ Field_Sales_Core_Access (read access)       ││
│  │  ├─ Field_Sales_Edit (write access)             ││
│  │  └─ SalesCloudMobileUser (mobile entitlement)   ││
│  └─────────────────────────────────────────────────┘│
│  Profile: Sales (base profile)                       │
└─────────────────────────────────────────────────────┘
```

## Object Model (existing objects -- no new objects)

| Object | Access Level | Key Fields for Mobile Compact Layout |
|--------|-------------|-------------------------------------|
| Account | Read/Edit | Name, Phone, BillingCity, Owner, Type |
| Lead | Read/Edit/Create | Name, Company, Phone, Status, Owner |
| Opportunity | Read/Edit | Name, StageName, CloseDate, Amount, Account |
| Task | Read/Edit/Create | Subject, Status, Priority, WhoId, WhatId |
| Event | Read/Edit/Create | Subject, StartDateTime, EndDateTime, WhoId, WhatId |
| Activity (Task) | Create via "Log a Call" | Subject="Call", CallType, Description, WhoId, WhatId |

## Compact Layout Specifications

### Account Compact Layout: `Field_Sales_Mobile_Account`
1. Name
2. Phone
3. BillingCity
4. Owner.Alias
5. Type

### Lead Compact Layout: `Field_Sales_Mobile_Lead`
1. Name
2. Company
3. Phone
4. Status
5. LeadSource

### Opportunity Compact Layout: `Field_Sales_Mobile_Opp`
1. Name
2. StageName
3. CloseDate
4. Amount
5. Account.Name

## Quick Action Configuration

| Quick Action | Object | Type | Fields |
|-------------|--------|------|--------|
| LogACall | Task (Global) | Log a Call | Subject, Description, WhoId (Name), WhatId (Related To), CallDurationInSeconds |
| NewTask | Task (Global) | Create | Subject, Status, Priority, ActivityDate, WhoId, WhatId |
| NewEvent | Event (Global) | Create | Subject, StartDateTime, EndDateTime, Location, WhoId, WhatId |

## Integration Points

- **None** -- This is pure OOTB configuration. No external integrations, no MuleSoft, no custom APIs.
- The Salesforce Mobile App itself is the "integration point" -- it uses the standard Salesforce REST API under the hood.
- Connected App: `SalesforceMobileApp` (standard platform Connected App) must be enabled for the Sales profile.

## Metadata Inventory (what gets deployed)

| Metadata Type | Component | Action |
|--------------|-----------|--------|
| PermissionSetGroup | `Field_Sales_Mobile_PSG` | Create |
| CompactLayout | `Account.Field_Sales_Mobile_Account` | Create |
| CompactLayout | `Lead.Field_Sales_Mobile_Lead` | Create |
| CompactLayout | `Opportunity.Field_Sales_Mobile_Opp` | Create |
| CustomApplication | `SalesCloudMobile` | Update (add navigation items) |
| QuickAction | Verify `LogACall`, `NewTask`, `NewEvent` on layouts | Update if missing |

## Risks Identified

1. **`SalesCloudMobile` may have org-wide nav items that conflict** -- Need to audit current configuration before modifying.
2. **Compact layout assignment is profile-level** -- If multiple personas share the Sales profile, compact layout changes affect all of them.
3. **"Log a Call" requires Activity Settings enabled** -- Verify `EnableActivities` is true org-wide.

## Handoff to TDD Agent

The TDD agent should:
1. Write test scenarios validating each AC (AC-1 through AC-10) as manual test scripts (since OOTB config cannot be unit-tested with Apex)
2. Define permission validation tests: verify Field Sales user with PSG can access each object
3. Define negative tests: verify users without `SalesCloudMobileUser` cannot access mobile app
4. Estimate coverage approach: since no Apex code, coverage is N/A -- validation is functional/manual
