# NGASIM-556: CODE REVIEW

## Decisions Made

1. Review scope is metadata configuration, not Apex/LWC code.
2. Review focuses on: permission model correctness, compact layout usability, OOTB-first compliance, and test coverage adequacy.

## Review Summary

| Severity | Count | Category |
|----------|-------|----------|
| CRITICAL | 0 | -- |
| HIGH | 2 | Permission model, app configuration |
| MEDIUM | 3 | Layout, documentation, test gaps |
| LOW | 2 | Naming, minor improvements |

## Findings

### HIGH-001: Console App Cannot Render on Mobile
**File:** Architecture decision ADR-001
**Finding:** Correctly identified that `Insulet_Sales` (NavType=Console) will not render on the Salesforce Mobile App. The plan to use `SalesCloudMobile` is correct. However, the plan should explicitly document that Field Sales users who access the desktop will still use `Insulet_Sales`, while mobile uses `SalesCloudMobile`. These are two different apps with potentially different navigation items.
**Recommendation:** Add a mapping table: Desktop App -> `Insulet_Sales`, Mobile App -> `SalesCloudMobile`. Ensure navigation item parity for core objects.

### HIGH-002: Permission Set Group May Not Exist Yet
**File:** Architecture metadata inventory
**Finding:** The plan creates `Field_Sales_Mobile_PSG` as a new Permission Set Group. This is a net-new metadata component. If the org's permission set group feature is not enabled or if there are licensing constraints, this could fail at deploy time.
**Recommendation:** Verify Permission Set Group feature is available in the org before deployment. Fallback: assign all 3 permission sets individually if PSG is not supported.

### MED-001: Compact Layout 5-Field Limit Assumption
**File:** 02-architecture.md, Compact Layout Specifications
**Finding:** Compact layouts support up to 10 fields (first 4 show in card, rest accessible via expand). The architecture assumes 5 fields. This is fine but should be documented that only the first 4 will show in the compact card header on mobile.
**Recommendation:** Prioritize the 4 most important fields in positions 1-4 of each compact layout.

### MED-002: Missing Global Action vs Object-Specific Action Distinction
**File:** 02-architecture.md, Quick Action Configuration
**Finding:** "Log a Call" is listed as a Global action, but it should be an object-specific action on Account, Lead, Contact, and Opportunity page layouts for it to appear in the mobile action bar for those records. Global actions appear on the home page, not record pages.
**Recommendation:** Configure "Log a Call" as object-specific quick actions on Account, Lead, and Opportunity mobile page layouts.

### MED-003: No Rollback Plan Documented
**File:** 01-plan.md
**Finding:** The plan has 3 phases but no rollback strategy. If the deployment causes issues (e.g., breaks existing mobile users), there's no documented way to revert.
**Recommendation:** Document rollback: remove PSG assignment, revert compact layout assignments to defaults, remove navigation items from `SalesCloudMobile`.

### LOW-001: Typo in Jira Summary
**Finding:** The Jira summary reads "Access to to Sales App" (double "to"). This is a Jira data quality issue, not a code issue.
**Recommendation:** Flag to story owner for correction.

### LOW-002: Test Plan Could Include Offline Scenario
**File:** 03-tdd.md
**Finding:** Salesforce Mobile App supports offline access for certain objects. The test plan does not include an offline test scenario.
**Recommendation:** Add optional TS-11: verify offline caching behavior for Account/Lead records if offline access is enabled.

## Recommendations Summary

1. Add desktop/mobile app mapping table to architecture doc
2. Verify PSG feature availability before deploy
3. Reorder compact layout fields with top-4 priority
4. Change "Log a Call" from Global to object-specific actions
5. Add rollback plan to implementation phases
6. Consider offline test scenario

## Handoff to BUILD-FIX Agent

The BUILD-FIX agent should:
1. Generate the actual metadata XML files for the Permission Set Group, Compact Layouts, and App configuration
2. Validate XML against the Salesforce Metadata API schema
3. Attempt a check-only deployment to the dev sandbox to catch any issues before full deploy
