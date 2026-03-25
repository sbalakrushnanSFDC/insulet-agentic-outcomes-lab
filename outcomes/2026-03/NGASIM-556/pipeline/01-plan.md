# NGASIM-556: PLAN

## Decisions Made

1. **OOTB-first approach confirmed** -- The HLD states mobile is OOTB. DevInt2 already has `SalesCloudMobile` app and `SalesCloudMobileUser` permission set. No custom Apex or LWC required.
2. **Leverage existing permission model** -- Four Field Sales permission sets already exist (`Field_Sales_Core_Access`, `Field_Sales_Edit`, `Field_Sales_TM_DSM`, `Field_Sales_GM_RBD`). The mobile-specific `SalesCloudMobileUser` also exists. Implementation should assign the mobile perm set to Field Sales users, not create new ones.
3. **Target app: `Insulet_Sales` (Console)** -- The story says "Access to Insulet Sales." The org has an `Insulet_Sales` console app. Mobile needs a Standard (non-console) variant or the `SalesCloudMobile` app configured with Insulet Sales navigation items.
4. **iPad as primary form factor** -- AC specifies iPad. Mobile layouts should prioritize tablet breakpoints. Phone form factor is secondary but should not be broken.

## Formalized Acceptance Criteria

| ID | Criteria | Testable? |
|----|----------|-----------|
| AC-1 | Field Sales user can authenticate and launch the Salesforce Mobile App on iPad | Yes |
| AC-2 | Upon login, the user lands on the `Insulet_Sales` or `SalesCloudMobile` app home page | Yes |
| AC-3 | User can navigate to and view Account list view and Account records | Yes |
| AC-4 | User can navigate to and view Lead list view and Lead records | Yes |
| AC-5 | User can navigate to and view Opportunity list view and Opportunity records | Yes |
| AC-6 | User can create, edit, and complete Task records from mobile | Yes |
| AC-7 | User can create, edit, and manage Event records from mobile (calendar view accessible) | Yes |
| AC-8 | User can log a call (create Activity/Task with Call type) from mobile | Yes |
| AC-9 | All visible fields respect FLS defined by `Field_Sales_Core_Access` + `Field_Sales_Edit` permission sets | Yes |
| AC-10 | Mobile compact layouts show the most important fields for Account, Lead, Opportunity | Yes |

## Implementation Phases

### Phase 1: Permission & Access Configuration (T-shirt: S)
- Verify `SalesCloudMobileUser` permission set grants mobile app access
- Create Permission Set Group: `Field_Sales_Mobile_PSG` combining `Field_Sales_Core_Access` + `Field_Sales_Edit` + `SalesCloudMobileUser`
- Assign PSG to Field Sales users (TM/DSM population first)
- Verify Connected App settings allow mobile login

### Phase 2: Mobile App Navigation & Layout (T-shirt: M)
- Configure `SalesCloudMobile` or create new Lightning App for mobile with navigation items: Accounts, Leads, Opportunities, Tasks, Events
- Create/adjust compact layouts for Account, Lead, Opportunity optimized for mobile (5-field limit)
- Configure mobile-specific page layouts or Lightning pages if needed
- Verify "Log a Call" quick action is on Account, Lead, Opportunity mobile layouts

### Phase 3: Validation & Polish (T-shirt: S)
- Test on iPad (Safari, Salesforce Mobile App)
- Test on iPhone (secondary form factor -- should not be broken)
- Verify FLS enforcement end-to-end
- Validate calendar/event creation flow

## Dependencies

| Dependency | Type | Status |
|-----------|------|--------|
| `SalesCloudMobileUser` perm set exists in org | Hard | Available (confirmed via SOQL) |
| `Field_Sales_Core_Access` perm set exists | Hard | Available (confirmed) |
| `Field_Sales_Edit` perm set exists | Hard | Available (confirmed) |
| `Insulet_Sales` app exists | Hard | Available (confirmed -- Console nav) |
| `SalesCloudMobile` app exists | Hard | Available (confirmed -- Standard nav) |
| Field Sales user population identified | Soft | Needs confirmation from business |
| Compact layouts for Account/Lead/Opportunity exist | Soft | Needs audit |

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Console apps don't render on mobile -- `Insulet_Sales` is NavType=Console | High | High | Use `SalesCloudMobile` (Standard NavType) as the mobile app, or create a new mobile-specific Standard-nav app |
| Compact layouts not configured for mobile-critical fields | Medium | Medium | Audit and create compact layouts in Phase 2 |
| Field Sales users don't have Connected App access | Low | High | Verify Connected App "Salesforce for iOS/Android" profile access |
| Health Cloud objects visible on mobile exposing patient data | Medium | High | Audit tab visibility and object permissions in Field Sales perm sets |
| iPad-specific responsive issues with custom Lightning pages | Low | Medium | Test on iPad; standard OOTB pages are well-tested on tablet |

## Handoff to ARCHITECTURE Agent

The ARCHITECTURE agent should:
1. Design the Permission Set Group composition
2. Define the mobile app navigation item list and order
3. Specify compact layout field selections for Account, Lead, Opportunity
4. Determine whether to use `SalesCloudMobile` directly or create a new `Insulet_Field_Sales_Mobile` app
5. Document the "Log a Call" quick action configuration requirements
6. Address the Console-vs-Standard NavType risk for `Insulet_Sales`
