# Outcome Metadata: NGASIM-3336

## Feature

| Field | Value |
|-------|-------|
| Jira Key | NGASIM-3336 |
| Title | [DoubleOptIn] MuleSoft — SMS Opt-In request to Marketing Cloud (exp-api) |
| Parent | NGASIM-28: Capture Transaction SMS, Transactional Email & Marketing Email Patient and Provider Consents |
| Project | NGASIM (NextGen CRM ASIM — Integration) |
| Labels | Integration, NGPI2 |
| API Layer | Experience API (exp-api) in MuleSoft API-led connectivity |
| Sibling Stories | NGASIM-3335 (prc-api), NGASIM-3143 (sys-api), NGASIM-3058 (SF-side platform event publish) |

## Run

| Field | Value |
|-------|-------|
| Run ID | NGASIM-3336-run-001 |
| Started | 2026-03-25T20:58:00Z |
| Completed | 2026-03-25T21:15:00Z |
| Duration | 17 minutes |
| Pipeline Mode | generator-critic |
| Pipeline Steps | 10 / 10 completed |
| Overall Status | PASS_WITH_CAVEATS |
| Critic Verdict | ACCEPT_WITH_CAVEATS |
| Critic Score | 0.72 |
| Context Sources | Jira (atlassian-guardrails), DevInt2 (SOQL read-only), NGASIM-3058 run cross-reference |

## Quality

| Metric | Value |
|--------|-------|
| Acceptance Criteria Derived | 18 |
| ADRs Produced | 4 (ADR-001 through ADR-004) |
| Review Findings | 0 critical, 3 high, 4 medium, 2 low, 2 info |
| Security Findings | 2 critical, 3 high, 5 medium, 5 low |
| Test Cases Defined | 38 (10 SOQL, 14 MuleSoft unit, 6 integration mock, 8 manual) |
| Test Cases Executed | 0 (pending blocker resolution) |
| Apex / MuleSoft Coverage Estimate | 85%+ |
| Artifact Lines | 5,981 total |

## Cross-Cloud Detection

| Cloud | Detected | Key Signals |
|-------|----------|-------------|
| Salesforce | Yes | ContactPointTypeConsent, Platform Events, Apex trigger (NGASIM-3058), Named Credentials |
| MuleSoft | Yes | API-Led (exp/prc/sys), DataWeave, CloudHub, ObjectStore idempotency |
| Marketing Cloud | Yes | Classic REST API for SMS, double opt-in trigger, et4ae5__SMSDefinition__c, OAuth2 |
| Health Cloud | Yes | Medical device patient context (Omnipod), HIPAA-adjacent PII, ContactPointTypeConsent |
| Data Cloud | No | Flagged as future re-architecture trigger if consent data flows to DC |
| Experience Cloud | No | — |

## Anti-Pattern Gates

| Gate | Result |
|------|--------|
| no-generic-platform | PASS |
| ootb-before-custom | PASS |
| no-async-handwave | PASS |
| data-duplication-sot | PASS |
| mulesoft-layering-justified | PASS |
| marketing-cloud-freshness | EVALUATE |
| consent-identity-crosscloud | EVALUATE |
| operational-observability | EVALUATE |
| rejected-alternatives-stated | PASS |

## Caveats

1. **NGASIM-3058 (SF Apex trigger) in QA** — The Salesforce-side platform event publisher is a prerequisite. Live integration testing is blocked until it passes QA and is deployed.
2. **Sibling stories both To Do** — NGASIM-3335 (prc-api) and NGASIM-3143 (sys-api) have not started. The full API-led chain cannot be integration-tested until all three layers exist.
3. **Marketing Cloud sandbox not provisioned** — MC sandbox access required for double opt-in end-to-end testing.
4. **2 CRITICAL security findings** — (a) PII (patient phone numbers) logged in clear text in MuleSoft flows and DLQ messages. (b) MC API OAuth2 credentials stored as plain application properties instead of Anypoint Secure Properties or Vault.
5. **3 HIGH security findings** — Consent state machine validation missing (out-of-order events possible), platform event replay ID tracking not implemented (event gap detection), mTLS not configured between MuleSoft and MC API.
6. **Critical scope gap** — No story covers the MC → SF confirmation callback for double opt-in completion. Product Owner must decide if NGASIM-3336 owns this or if a new story is required.
7. **MuleSoft exp-api is pseudo-code** — Full Anypoint Studio project build requires CloudHub deployment credentials and Anypoint Platform access.
8. **MC Classic REST API vs MC Connect (et4ae5)** — ADR-004 documents the decision. Requires validation with MC admin team before implementation.

## Operator Notes

- This is a cross-cloud integration story touching Salesforce, MuleSoft, Marketing Cloud, and Health Cloud (HIPAA context). Higher complexity than typical NGASIM stories.
- The 2 CRITICAL security findings must be resolved before any go-live: encrypt PII in logs and move MC credentials to Anypoint Secure Properties.
- The biggest scope risk is the missing MC→SF confirmation callback — without it, double opt-in completion is unconfirmed in Salesforce.
- Recommended next step: unblock NGASIM-3058 (SF trigger) → deploy MuleSoft exp-api skeleton to CloudHub dev → run SOQL validations → iterate.

## Feedback Log

| Date | Source | Feedback | Action |
|------|--------|----------|--------|
| — | — | (no feedback yet) | — |
