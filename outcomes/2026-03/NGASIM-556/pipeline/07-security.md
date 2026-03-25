# NGASIM-556: SECURITY REVIEW

## Decisions Made

1. Security review scope: declarative configuration only. No custom Apex/LWC to review for injection, XSS, or SOQL injection vulnerabilities.
2. Primary security concerns: CRUD/FLS enforcement, data exposure on mobile devices, Health Cloud data segregation.

## Security Findings

| # | Severity | Category | Finding | Recommendation |
|---|----------|----------|---------|----------------|
| SEC-001 | HIGH | Data Exposure | Field Sales users accessing patient/clinical Health Cloud data via mobile. `Insulet_Sales` console shares the org with Health Cloud. If the Sales profile has read access to Health Cloud objects (e.g., `HealthCloudGA__*`, `CarePlan`, `CareProgram`), these could appear in mobile search results or global actions. | Audit `Field_Sales_Core_Access` for Health Cloud object permissions. Explicitly deny access to clinical objects. Add a `Field_Sales_Mobile_Restriction` permission set with explicit denials if needed. |
| SEC-002 | HIGH | Device Security | Salesforce Mobile App on personal iPads. No MDM (Mobile Device Management) requirement documented. If the device is lost/stolen, org data is accessible. | Require: (1) Salesforce Mobile App's built-in PIN/biometric lock, (2) Session timeout policy (max 12h), (3) Recommend org-level Connected App policy requiring device PIN. Document MDM requirement as out-of-scope but flagged to IT Security. |
| SEC-003 | MEDIUM | CRUD/FLS | `Field_Sales_Edit` permission set grants edit access. Need to verify it does NOT grant Delete on Account, Lead, Opportunity. Mobile "swipe to delete" could be destructive. | Verify CRUD matrix: Read+Create+Edit but NOT Delete on core objects. |
| SEC-004 | MEDIUM | OAuth Scope | Connected App for Salesforce Mobile uses `full` or `api` OAuth scope by default. Field Sales users get full API access which could be exploited by third-party apps if the device is compromised. | Restrict Connected App OAuth scope to `visualforce` + `web` only if possible. Otherwise, accept as standard platform behavior with compensating control of session timeout. |
| SEC-005 | LOW | Audit Trail | No specific audit logging for mobile access vs desktop access. Login history records IP and App type, but no custom tracking. | Acceptable for Phase 1. Recommend future enhancement: LoginEvent monitoring for `SalesforceMobileApp` app type. |

## CRUD/FLS Verification Matrix

### Required (for Field Sales Mobile to work)

| Object | Create | Read | Update | Delete | Notes |
|--------|--------|------|--------|--------|-------|
| Account | No | Yes | Yes | No | Edit existing only |
| Lead | Yes | Yes | Yes | No | Create new leads in field |
| Opportunity | No | Yes | Yes | No | Edit existing only |
| Task | Yes | Yes | Yes | No | Create/manage tasks |
| Event | Yes | Yes | Yes | No | Create/manage events |
| Activity | Yes | Yes | Yes | No | Log a Call creates Task |

### Must NOT have access (Health Cloud segregation)

| Object | Access | Reason |
|--------|--------|--------|
| CarePlan | None | Clinical data |
| CareProgram | None | Clinical data |
| HealthCloudGA__* (any) | None | Health Cloud managed package objects |
| Individual | Read only (if needed for consent) | Privacy-sensitive |

## OWASP Mobile Top 10 Checklist

| # | Risk | Applicability | Status |
|---|------|--------------|--------|
| M1 | Improper Platform Usage | Low -- using standard SF Mobile App | PASS |
| M2 | Insecure Data Storage | Medium -- SF Mobile caches locally | MITIGATED by SF Mobile App encryption |
| M3 | Insecure Communication | Low -- HTTPS enforced by platform | PASS |
| M4 | Insecure Authentication | Low -- OAuth 2.0 via Connected App | PASS |
| M5 | Insufficient Cryptography | N/A -- no custom crypto | PASS |
| M6 | Insecure Authorization | Medium -- verify CRUD/FLS | PENDING FLS AUDIT |
| M7 | Client Code Quality | N/A -- no custom client code | N/A |
| M8 | Code Tampering | Low -- App Store distribution | PASS |
| M9 | Reverse Engineering | N/A -- no custom app | N/A |
| M10 | Extraneous Functionality | Low -- OOTB app only | PASS |

## Recommendations Summary

1. **CRITICAL ACTION:** Audit `Field_Sales_Core_Access` for Health Cloud object permissions before deployment
2. **HIGH:** Implement session timeout policy (12h max) for mobile sessions
3. **HIGH:** Enable Salesforce Mobile App PIN/biometric requirement via Connected App settings
4. **MEDIUM:** Verify no Delete permission on Account, Lead, Opportunity in Field Sales perm sets
5. **LOW:** Set up LoginEvent monitoring for mobile access patterns

## Handoff to REFACTOR Agent

The REFACTOR agent should:
1. Review the metadata XML for any unnecessary permissions or redundant configuration
2. Check naming consistency across all metadata components
3. Verify no dead/unused compact layouts or quick actions are being deployed
