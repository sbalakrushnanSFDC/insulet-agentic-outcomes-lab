# NGOMCT-344: INTAKE Summary

## Feature Metadata

| Field | Value |
|-------|-------|
| Key | NGOMCT-344 |
| Summary | Training Creation & Assignment - Manual Training Record Creation |
| Status | FEATURE DEFINITION |
| Priority | Highest |
| Team | Team1 |
| Labels | 2026Q1, CON-13, NGOMCT, NGPI3, NextGen, PRJ0717, Team1, Training |
| Fix Versions | Project Infinity SOW MVP, Project Infinity Persona Release 2 |

## Requirements (from Jira)

**Feature Description:** Enable the ability to manually initiate the training process for a given consumer.

**Benefit Hypothesis:** Increased new customer acquisition at reduced cost to acquire by efficiently triggering the work required to coordinate and execute training for a given consumer.

**Assumption:** Training assignment logic will be handled in NGOMCT-89. This feature will focus on enabling the process and ability to manually create a training record.

## Dependency Map

- **Blocked by:** NGOMCT-139 (In Progress), NGOMCT-6 (Backlog), NGOMCT-240, NGASIM-263
- **Blocks:** NGOMCT-10, NGOMCT-54, NGONDL-60, NGMC-32
- **Cloned from:** NGOMCT-91 (Training Creation - From Direct Order)
- **Related:** NGOMCT-89 (Training Assignment Logic — out of scope)

## Risks Identified

1. **No explicit Acceptance Criteria in Jira** — AC must be derived from description, Confluence CON-13, and sibling NGOMCT-91.
2. **Blocker NGOMCT-139 In Progress** — deploy validation may depend on Order Management objects in orgsyncng.
3. **Scope boundary** — Training assignment logic (NGOMCT-89) is out of scope; boundary must be clear.
4. **Confluence content** — Full CON-13 page must be fetched for business process details.
5. **Salesforce metadata unknown** — Training-related objects/fields need discovery from DevInt2.

## References

- [Jira NGOMCT-344](https://insulet.atlassian.net/browse/NGOMCT-344)
- Confluence: CON-13 Consumer trained on Insulet product (page_id: 135170258)
- Jira source: `output/Team1/NGOMCT/Jira/NGOMCT-344/`
