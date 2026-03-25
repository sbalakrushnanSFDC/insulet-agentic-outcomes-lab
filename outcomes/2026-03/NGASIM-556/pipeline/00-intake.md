# NGASIM-556: INTAKE Summary

## Feature Metadata

| Field | Value |
|-------|-------|
| Key | NGASIM-556 |
| Summary | Access to Sales App from mobile for Field Sales |
| Status | Story Points (In Refinement) |
| Priority | Medium |
| Labels | FieldSales, NGPI1 |
| Assignee | Sowmya Umashankar |
| Reporter | Ramprasad Varri |
| Parent Feature | NGASIM-38: Mobile compatibility for TM/CSM (FEATURE REFINEMENT) |
| SF Team | Health Cloud |
| Fix Versions | (none assigned) |
| Created | 2025-08-14 |
| Updated | 2026-03-12 |

## Requirements (from Jira)

**User Story:**
As a Field Sales agent, I can access the Sales app on my mobile device through Salesforce Mobile App.

**Functional Requirements:**
1. Access to Insulet Sales application
2. Access Accounts
3. Access Leads
4. Access Opportunities
5. Manage Tasks
6. Manage Events
7. Log a Call

**Acceptance Criteria (from custom field):**
Scenario: Access Sales application from Mobile Device (iPad) through Salesforce Mobile App
Given I am a Field Sales Agent,
When I am in the field,
Then I need to access the sales application through Salesforce Mobile App.

**High-Level Design (from custom field):**
1. Enable Mobile access for Field Sales persona
2. Configure SF Mobile App so user can login and navigate to default landing page
Note: Mobile configuration is OOTB available.

## Dependency Map

- **Parent:** NGASIM-38 (Mobile compatibility for TM/CSM) -- status: FEATURE REFINEMENT
- **Blocked by:** (none)
- **Blocks:** (none)
- **Linked Issues:** (none)

## Risks Identified

1. **No explicit formal AC in Jira** -- The AC custom field contains a single GWT scenario. Seven functional requirements are listed in the description but not formalized as testable AC. Risk: scope ambiguity during implementation and QA.
2. **OOTB-first note in HLD** -- The HLD states "Mobile configuration is OOTB available." This suggests the implementation is primarily configuration, not custom code. Risk: the scope may be smaller than a full development story, but platform-specific gotchas (compact layouts, mobile-only page layouts, Lightning App Builder for mobile) could expand scope.
3. **No fix version assigned** -- Story has no fix version despite being labeled NGPI1. Risk: unclear release targeting.
4. **Parent feature still in FEATURE REFINEMENT** -- NGASIM-38 is not yet refined. Risk: parent-level scope changes could invalidate this story's implementation.
5. **iPad-specific AC** -- The AC mentions "Mobile Device (iPad)" specifically. Risk: need to clarify whether Android/phone form factors are also in scope, or only iPad.
6. **Health Cloud SF team context** -- The story is tagged to the Health Cloud SF team. Risk: Health Cloud-specific considerations (patient data visibility, HIPAA-adjacent concerns) may apply even for a "sales" app if the same org hosts clinical data.
7. **No linked test stories or QA stories** -- No subtasks or linked QA work items exist.

## References

- Jira: https://insulet.atlassian.net/browse/NGASIM-556
- Parent: https://insulet.atlassian.net/browse/NGASIM-38
- Cortex MCP context pack: retrieved 2026-03-25 (low relevance -- no domain-specific files matched)

## Handoff to PLAN Agent

The PLAN agent should:
1. Derive formal, testable acceptance criteria from the 7 functional requirements
2. Query DevInt2 for existing Salesforce Mobile App configuration, permission sets, and connected app settings
3. Identify the Field Sales persona's profile/permission set in the org
4. Determine whether a custom Salesforce Mobile App or the standard Mobile App is in scope
5. Assess iPad-specific layout requirements vs general mobile compatibility
6. Create a phased implementation plan (Phase 1: access/permissions, Phase 2: mobile layouts, Phase 3: call logging)
