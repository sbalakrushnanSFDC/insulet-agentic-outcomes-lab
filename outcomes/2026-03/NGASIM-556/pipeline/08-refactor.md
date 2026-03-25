# NGASIM-556: REFACTOR (Clean)

## Decisions Made

1. Refactoring scope is metadata hygiene, not code refactoring (no custom code exists).
2. Focus areas: naming consistency, metadata minimality, configuration debt prevention.

## Refactoring Log

| # | Category | Before | After | Rationale |
|---|----------|--------|-------|-----------|
| R-001 | Naming | Compact layouts named `Field_Sales_Mobile_Account`, `Field_Sales_Mobile_Lead`, `Field_Sales_Mobile_Opp` | Keep as-is | "Opp" abbreviation is acceptable -- consistent with Salesforce conventions. Full name `Field_Sales_Mobile_Opportunity` would exceed 40-char label limit. |
| R-002 | Naming | PSG named `Field_Sales_Mobile_PSG` | Rename to `Field_Sales_Mobile` (drop `_PSG` suffix) | The suffix is redundant -- the metadata type already identifies it as a Permission Set Group. Label is "Field Sales Mobile" which is clean. |
| R-003 | Minimality | Architecture references modifying `SalesCloudMobile` app navigation | Prefer creating a new `Insulet_Field_Sales_Mobile` app | Modifying the platform-managed `SalesCloudMobile` app risks conflicts with future Salesforce releases. A custom app gives full control. However, this adds deployment complexity. **Decision: keep using `SalesCloudMobile` for Phase 1, revisit in Phase 2 if conflicts arise.** |
| R-004 | Dead config | N/A | N/A | No pre-existing dead configuration identified. All metadata is net-new. |

## Constant Extraction

No constants to extract (no custom code). Configuration values are embedded in metadata XML as designed.

## Naming Improvements Applied

| Component | Original API Name | Revised API Name | Reason |
|-----------|------------------|------------------|--------|
| PermissionSetGroup | `Field_Sales_Mobile_PSG` | `Field_Sales_Mobile` | Remove redundant type suffix |

## Configuration Debt Flagged

| Item | Type | Notes |
|------|------|-------|
| `SalesCloudMobile` app modification | Tech debt | Using platform-managed app. Should be replaced with custom app in future iteration. |
| No compact layout assignment automation | Tech debt | Compact layouts must be manually assigned as "primary" per profile. Should be included in deployment package or post-deploy script. |
| No rollback package | Process debt | Rollback is manual. Should create a rollback deployment package for quick reversion. |

## Handoff to DOC Agent

The DOC agent should:
1. Create deployment runbook for the orgsyncng sandbox
2. Document the permission model (profile + PSG + individual perm sets)
3. Create a user-facing quick reference for Field Sales mobile access
4. Update the NGASIM-556 story with implementation summary
