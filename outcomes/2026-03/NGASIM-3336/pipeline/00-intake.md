# NGASIM-3336: INTAKE

> **Pipeline Stage:** 00-intake
> **Produced by:** orchestrator agent
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T20:58:00Z
> **Status:** COMPLETE — handed off to PLAN

---

## Feature Metadata

| Field | Value |
|---|---|
| Key | NGASIM-3336 |
| Summary | [DoubleOptIn] Mulesoft - SMS Opt In request to MC - exp-api |
| Type | Story |
| Status | To Do |
| Priority | Inherited Highest (from parent NGASIM-28) |
| Assignee | Edwin Arguijo |
| Project | NGASIM (NextGen CRM ASIM — Integration) |
| Labels | Integration, NGPI2 |
| Fix Versions | Project Infinity SOW MVP, Project Infinity Persona Release 1 (inherited from NGASIM-28) |
| Parent Feature | NGASIM-28 — Capture Transaction SMS, Transactional Email & Marketing Email Patient and Provider Consents |
| Parent Status | In Development |
| Sibling Stories | NGASIM-3335 (prc-api), NGASIM-3143 (sys-api), NGASIM-3058 (SF-side platform event publish) |
| Linked Issues | NGASIM-3058 (blocks — SF Apex trigger must publish platform event before exp-api can consume it) |
| API Layer | Experience API (exp-api) in MuleSoft API-led connectivity pattern |

---

## Description (verbatim from Jira)

> Consume platform event from Salesforce. Publish platform event to Marketing Cloud classic API.

### Key Phrases Extracted

1. **"Consume platform event from Salesforce"** — The exp-api listens for a Salesforce platform event that signals an SMS opt-in consent status change. This is a pub/sub integration pattern using Salesforce Platform Events as the triggering mechanism. The source platform event is published by Apex trigger logic in NGASIM-3058.
2. **"Publish platform event to Marketing Cloud classic API"** — The exp-api must translate the Salesforce consent payload into a Marketing Cloud-compatible format and invoke the MC Classic REST API to trigger double opt-in SMS processing. This is NOT the MC Connect managed package pathway — it is a direct REST API integration through the MuleSoft layer.
3. **"exp-api"** — This story covers ONLY the experience API layer. It is the external-facing API entry point that receives the platform event, performs initial validation and transformation, and delegates to the process API (NGASIM-3335) for orchestration logic.
4. **"DoubleOptIn"** — The double opt-in pattern requires: (a) patient submits initial consent, (b) system sends confirmation SMS, (c) patient confirms via reply. This is a regulatory/compliance pattern for SMS marketing consent.
5. **"SMS Opt In"** — Specifically scoped to SMS channel consent, not email or other channels. This differentiates it from the broader consent capture feature (NGASIM-28) which also handles Transactional Email and Marketing Email.

---

## Child/Sibling Story Decomposition

NGASIM-3336 is one story in a coordinated API-led connectivity stack under parent feature NGASIM-28. The sibling stories represent the three MuleSoft API layers plus the Salesforce-side trigger that initiates the flow.

### API-Led Layer Stack (this flow)

| Key | Summary | API Layer | Status | Assignee | Implications |
|---|---|---|---|---|---|
| NGASIM-3058 | Send SMS Opt In request to Marketing Cloud through Mulesoft | SF Apex Trigger / Platform Event Publisher | **In QA** | — | **Upstream dependency.** Apex trigger on ContactPointTypeConsent fires platform event. Must be in QA/Done before MuleSoft layers can integration-test. Currently in QA — closest to ready. |
| **NGASIM-3336** | **[DoubleOptIn] Mulesoft - SMS Opt In request to MC - exp-api** | **Experience API** | **To Do** | **Edwin Arguijo** | **This story.** Consumes platform event, validates payload, delegates to prc-api. External-facing contract definition. |
| NGASIM-3335 | [DoubleOptIn] Mulesoft - SMS Opt In request to MC - prc-api | Process API | To Do | — | Orchestration layer. Receives validated payload from exp-api, applies business rules (consent state machine, dedup, enrichment), delegates to sys-api. |
| NGASIM-3143 | [DoubleOptIn] Mulesoft - SMS Opt In request to MC - sflmc-sys-api | System API | To Do | — | Backend integration layer. Translates to MC Classic REST API format, handles authentication (OAuth2), makes the actual API call to Marketing Cloud. Blocked by NGASIM-3058. |

### Parent Feature Sibling Stories (NGASIM-28 — 25 stories)

| Status | Count | Examples | Implications |
|---|---|---|---|
| Done | ~15 | Consent statuses, capture on lead creation, lead conversion consent transfer, default consent on webform | Core consent data model and SF-side logic is largely complete. ContactPointTypeConsent records are being created. |
| In QA | ~3 | NGASIM-3058 (SF→MuleSoft platform event), related QA stories | The SF-side trigger that publishes the platform event is in QA. This is the critical upstream dependency for the MuleSoft stack. |
| Blocked | 4 | QA stories blocked by NGASIM-3058 and MuleSoft readiness | Cannot complete end-to-end QA until all 3 MuleSoft layers are implemented. |
| To Do | 3 | NGASIM-3336 (exp-api), NGASIM-3335 (prc-api), NGASIM-3143 (sys-api) | All 3 MuleSoft API layer stories are To Do. They form a coordinated delivery unit. |

### Completion Summary

- **Done:** ~15 of 25 (60%) — SF-side consent capture is mature
- **In QA:** ~3 of 25 (12%) — platform event publisher nearing completion
- **To Do / Blocked:** ~7 of 25 (28%) — MuleSoft integration stack and QA validation
- **Net assessment:** SF-side is mature; MuleSoft integration is 0% started

---

## Requirements Extraction

NGASIM-3336 has **no formal acceptance criteria** in Jira. The description is a single sentence. Requirements are derived from: the story description, the parent feature (NGASIM-28) description, the API-led connectivity pattern, the sibling story context, the DevInt2 consent data model, and Marketing Cloud SMS double opt-in requirements.

### Functional Requirements

| ID | Requirement | Source |
|---|---|---|
| FR-01 | The exp-api must subscribe to and consume the SMS opt-in consent platform event published by Salesforce (NGASIM-3058) | Story description: "Consume platform event from Salesforce" |
| FR-02 | The exp-api must validate the incoming platform event payload for required fields (ContactPointTypeConsentId, ConsentStatus, Phone, ConsentChannel=SMS) | Derived from consent data model + API-led pattern (exp-api validates before routing) |
| FR-03 | The exp-api must transform the Salesforce platform event payload into the canonical format expected by the process API (NGASIM-3335) | API-led connectivity: exp-api normalizes external/event payloads for internal consumption |
| FR-04 | The exp-api must route the transformed payload to the process API (prc-api) for business rule application | API-led connectivity: exp-api delegates orchestration to prc-api |
| FR-05 | The exp-api must support idempotent processing — re-delivery of the same platform event must not trigger duplicate MC API calls | Platform event replay + at-least-once delivery semantics require idempotency |
| FR-06 | The exp-api must publish error events to a dead-letter queue (DLQ) for failed platform event processing | MuleSoft best practice: unprocessable events must not be silently dropped |
| FR-07 | The exp-api must expose a health check endpoint for monitoring and operational visibility | Standard exp-api operational requirement |
| FR-08 | The exp-api must log all received platform events with correlation IDs for end-to-end traceability | Cross-system integration requires traceability from SF platform event → MuleSoft → MC |
| FR-09 | The exp-api must handle platform event replay (resubscription from a specific ReplayId) for recovery scenarios | Platform event durability: events are retained for 72 hours; consumer must track ReplayId |
| FR-10 | The exp-api RAML contract must define the canonical consent event schema, error response formats, and health check endpoint | Contract-first API development: RAML spec precedes implementation |

### Non-Functional Requirements

| ID | Requirement | Source |
|---|---|---|
| NFR-01 | Platform event processing latency: < 5 seconds from event publish to exp-api acknowledgment | Near-real-time consent propagation for double opt-in UX |
| NFR-02 | Throughput: support burst volumes of 500 consent events per minute during peak webform submission periods | Derived from lead creation volume estimates + batch consent processing |
| NFR-03 | Availability: 99.9% uptime for the exp-api endpoint | Standard production API SLA for consent-critical flow |
| NFR-04 | Error rate: < 0.1% unrecoverable failures (all others retried via DLQ) | Consent propagation must be reliable — missed double opt-in = compliance risk |
| NFR-05 | PII handling: phone numbers must not be logged in plaintext in MuleSoft application logs | HIPAA/TCPA: phone numbers are PII; must be masked or hashed in logs |

---

## Cross-Cloud Detection

This story triggers **three** cross-cloud detection rules. This is a high-complexity cross-cloud integration.

| Cloud | Detected | Evidence | Implication |
|---|---|---|---|
| **Salesforce (Core)** | YES | Platform Events (source), ContactPointTypeConsent (origin object), OrgSync_Consent_Staging (PE channel) | Source of truth for consent status. Apex trigger (NGASIM-3058) publishes PE on ContactPointTypeConsent insert/update. |
| **MuleSoft** | YES | API-led connectivity (exp-api / prc-api / sys-api), RAML contract, DataWeave transformations | Integration orchestration layer. Three-layer API decomposition for consent event routing. |
| **Marketing Cloud** | YES | MC Classic REST API (target), SMS double opt-in trigger, et4ae5__SMSDefinition__c (managed package objects in DevInt2) | Target system for SMS opt-in processing. MC Classic API receives consent event and triggers double opt-in SMS. |
| **Data Cloud** | POSSIBLE | Consent data may flow to Data Cloud for unified profile and segmentation | If consent data is unified in Data Cloud for segmentation/activation, the source-of-truth and freshness model must be defined. Flag for architecture review. |
| **Health Cloud** | NOT DIRECTLY | Parent feature mentions patient consents | NGASIM-28 references patients (Lead to Patient lifecycle). Health Cloud consent model may apply if patient records use Health Cloud data model. Flag for review. |

### Cross-Cloud Identity Chain

```
Patient/Lead (SF Core)
  → ContactPointTypeConsent (SF Core — source of truth)
    → Platform Event (SF → MuleSoft boundary)
      → exp-api (MuleSoft — this story)
        → prc-api (MuleSoft — NGASIM-3335)
          → sys-api (MuleSoft — NGASIM-3143)
            → MC Classic REST API (Marketing Cloud)
              → SMS Double Opt-In (MC sends confirmation SMS)
                → Patient Reply (MC receives confirmation)
                  → Consent Status Update (MC → SF? — return path undefined)
```

**Critical gap identified:** The return path — how Marketing Cloud confirms double opt-in completion back to Salesforce — is not covered by any of the 4 sibling stories. This is an open architectural question.

---

## Dependency Map

### External Dependencies

| Link Type | Key | Summary | Status | Impact |
|---|---|---|---|---|
| blocked by | NGASIM-3058 | Send SMS Opt In request to MC through Mulesoft | **In QA** | **Critical upstream dependency.** The Apex trigger that publishes the platform event on ContactPointTypeConsent must be complete and stable before the exp-api can receive events. Currently in QA — closest blocking dependency to resolution. |
| peer dependency | NGASIM-3335 | [DoubleOptIn] Mulesoft - SMS Opt In request to MC - prc-api | To Do | **Downstream peer.** The exp-api delegates to prc-api. Can develop exp-api with a mock prc-api, but integration test requires prc-api. |
| peer dependency | NGASIM-3143 | [DoubleOptIn] Mulesoft - SMS Opt In request to MC - sflmc-sys-api | To Do | **Downstream peer.** The sys-api makes the actual MC API call. Blocked by NGASIM-3058. End-to-end test requires all 3 layers. |
| parent feature | NGASIM-28 | Capture Transaction SMS, Transactional Email & Marketing Email Consents | In Development | Parent feature provides business context. ~60% complete (SF-side). |

### Internal Dependency Chain

```
NGASIM-3058 (SF Apex — In QA)
  └── MUST BE DONE FIRST — publishes platform event
      ├── NGASIM-3336 (exp-api — this story — To Do)
      │   └── consumes PE, validates, routes to prc-api
      │       └── NGASIM-3335 (prc-api — To Do)
      │           └── applies business rules, routes to sys-api
      │               └── NGASIM-3143 (sys-api — To Do)
      │                   └── calls MC Classic REST API
      └── NGASIM-3143 also directly blocked by NGASIM-3058
```

### DevInt2 Consent Data Dependencies

| Object/Entity | Exists in DevInt2 | Relevance |
|---|---|---|
| ContactPointTypeConsent | YES (standard object) | Source object — Apex trigger fires on this object's DML |
| ContactPointTypeConsentHistory | YES | Audit trail for consent status changes |
| ContactPointConsent | YES | Related consent object — may contain additional consent metadata |
| CommSubscriptionConsent | YES | Communication subscription consent — may be relevant for SMS channel |
| AuthorizationFormConsent | YES | Authorization form consent — may be relevant for double opt-in legal basis |
| PrivacyConsent | YES | Privacy consent — HIPAA implications for patient communication |
| OrgSync_Consent_Staging | YES (PE channel) | Platform Event channel for consent data — likely the channel used by NGASIM-3058 |
| et4ae5__SMSDefinition__c | YES (MC Connect managed package) | MC Connect SMS definitions — confirms MC SMS capability is provisioned |
| Platform Event Channel Members | YES | OrgSync patterns exist for Patient, Physician, Training, ASPN, Consent, Account |

---

## Risk Signals

| ID | Risk | Probability | Impact | Category |
|---|---|---|---|---|
| R-01 | **No acceptance criteria on story** — single-sentence description provides no testable criteria | High | High | Quality |
| R-02 | **Cross-cloud complexity** — 4-system integration (SF → MuleSoft [3 layers] → MC) with consent/PII data | High | Critical | Architecture |
| R-03 | **Double opt-in compliance risk** — SMS consent must comply with TCPA, CAN-SPAM, and potentially HIPAA (patient communication). Failure = regulatory exposure | Medium | Critical | Compliance |
| R-04 | **Return path undefined** — No story covers MC → SF consent confirmation callback. Double opt-in is incomplete without confirmation propagation back to ContactPointTypeConsent | High | High | Scope |
| R-05 | **NGASIM-3058 dependency** — Apex trigger must be stable and in QA/Done. Currently In QA but not yet verified against MuleSoft consumer | Medium | High | Dependency |
| R-06 | **Platform event delivery semantics** — At-least-once delivery requires idempotency in exp-api. Event replay after MuleSoft restart could cause duplicate MC API calls | Medium | High | Technical |
| R-07 | **MC Classic REST API deprecation risk** — Marketing Cloud has been transitioning to newer APIs. Classic API may have limited long-term support | Low | Medium | Technical Debt |
| R-08 | **PII in transit** — Phone numbers cross 3 system boundaries (SF → MuleSoft → MC). Each boundary requires encryption and PII handling | Medium | High | Security |
| R-09 | **Three MuleSoft layers all To Do** — coordinated delivery of exp-api, prc-api, sys-api requires synchronized development sprints | High | High | Delivery |
| R-10 | **Consent source-of-truth ambiguity** — ContactPointTypeConsent is SOT in SF, but MC also maintains subscriber consent state. Bidirectional sync risk | Medium | High | Data Architecture |
| R-11 | **Platform event volume and retention** — PE retained for 72 hours. If MuleSoft consumer is down for >72h, events are lost. No story addresses replay/recovery | Medium | Medium | Resilience |
| R-12 | **Identity alignment** — SF ContactId/LeadId must map to MC SubscriberKey. Identity resolution strategy not defined in story context | Medium | High | Cross-Cloud |
| R-13 | **No test strategy documented** — No integration test plan for the 4-system flow. E2E testing requires all layers plus MC sandbox | High | High | Testing |

---

## CTA Domain Coverage

| # | Domain | Applicable | Coverage in Story | Assessment |
|---|---|---|---|---|
| 1 | **Business Architecture** | YES | Consent capture is a core business capability for the Lead-to-Patient lifecycle. KPI: double opt-in completion rate, consent compliance rate | COVERED — parent feature NGASIM-28 provides business context |
| 2 | **Solution Architecture** | YES | API-led connectivity (exp/prc/sys) is the solution pattern. End-to-end flow from SF consent to MC double opt-in | REQUIRES ARCHITECTURE — ADRs needed for API layering justification |
| 3 | **Platform Architecture** | YES | Platform Events (Salesforce), MuleSoft Anypoint (integration), MC Classic REST API (target) | REQUIRES ARCHITECTURE — PE delivery semantics, MuleSoft worker sizing |
| 4 | **Security/Identity** | YES | PII (phone numbers), consent data, OAuth2 credentials, cross-system identity (SF ContactId → MC SubscriberKey) | CRITICAL — consent/PII flow across 3 boundaries |
| 5 | **Core Data** | YES | ContactPointTypeConsent as SOT, consent status lifecycle, MC subscriber consent state | REQUIRES ARCHITECTURE — SOT model, bidirectional sync |
| 6 | **Integration/MuleSoft** | YES | Primary domain. API-led layering, contract-first RAML, idempotency, DLQ, retry, circuit breaker | CRITICAL — this is a MuleSoft integration story |
| 7 | **Application/UX/Automation** | PARTIAL | No direct UI. Apex trigger automation (NGASIM-3058) is upstream. MuleSoft is headless. | LOW — automation is trigger-driven, no user-facing component |
| 8 | **Delivery/Testing/ALM** | YES | 4-system integration requires coordinated deployment, multi-environment testing, rollback strategy | REQUIRES PLAN — deployment sequencing across SF + MuleSoft + MC |
| 9 | **Cross-Cloud** | YES | SF Core → MuleSoft → Marketing Cloud. Possible Data Cloud implications for consent unification | CRITICAL — 3-cloud integration with consent/identity alignment required |

---

## Expert Context

### Platform Fit Reasoning

**Why Platform Events + MuleSoft API-Led Connectivity is the right pattern:**

Salesforce Platform Events provide a native, governor-limit-friendly mechanism for publishing domain events from Apex triggers without callout complexity. The Apex trigger on ContactPointTypeConsent (NGASIM-3058) can publish a PE synchronously within the transaction, avoiding the complexity of future methods or queueable Apex for callouts. The MuleSoft consumer decouples the Salesforce transaction from the downstream MC API call latency.

API-led connectivity (exp-api → prc-api → sys-api) is justified here because:
- **exp-api** (this story): normalizes the platform event payload, validates consent data, provides the external contract boundary. This layer owns the event subscription and initial transformation.
- **prc-api** (NGASIM-3335): applies consent business rules — deduplication, state machine validation (e.g., only opt-in requests for patients who haven't already opted in), enrichment with additional patient context if needed.
- **sys-api** (NGASIM-3143): encapsulates the MC Classic REST API contract, handles OAuth2 token management, and provides a reusable system API that could serve other MC integration needs.

**Tradeoffs considered:**
- Direct SF-to-MC via MC Connect managed package (et4ae5) — rejected because MC Connect does not support custom platform event-triggered SMS opt-in flows. MC Connect is designed for email/SMS sends from within SF, not for consent event propagation.
- Direct SF Apex callout to MC API — rejected because it couples the Salesforce transaction to MC API availability. Callout limits, transaction rollback on failure, and retry complexity make this brittle.
- Single MuleSoft API (no layering) — rejected because consent logic (dedup, state validation) and MC API specifics (auth, payload format) are distinct concerns. Collapsing into one API creates a monolith that's hard to test, monitor, and reuse.

**Anti-patterns avoided:**
- AP-05: MuleSoft layering without clear reuse/governance value — JUSTIFIED: sys-api is reusable for other MC integrations (email consent, marketing consent). prc-api encapsulates consent business rules that may apply to email and marketing channels too.
- AP-08: Ignoring consent/identity/auditability in cross-cloud flows — ADDRESSED: consent is the core domain; identity alignment (SF ContactId → MC SubscriberKey) and audit trail (PE replay, DLQ) are explicit requirements.
- AP-04: Data duplication without SOT consequences — FLAGGED: consent status exists in both SF (ContactPointTypeConsent) and MC (subscriber consent). SOT must be defined.

**Re-architecture triggers:**
- MC Classic REST API deprecation — if Salesforce deprecates the Classic API in favor of a newer API (e.g., MC Engagement API), the sys-api layer isolates the change.
- Platform Event volume exceeds retention window — if consent events exceed the 72-hour PE retention, a CDC-based approach or Change Data Capture may be needed.
- Bidirectional consent sync — if MC must propagate double opt-in confirmation back to SF, a return-path API flow is needed (not currently scoped).
- Data Cloud adoption — if consent data is unified in Data Cloud for segmentation, the PE-based pattern may be superseded by Data Cloud ingestion connectors.

---

## Intake Quality Assessment

| Dimension | Score | Rationale |
|---|---|---|
| Requirements Clarity | 2/10 | Single-sentence description. No acceptance criteria. No RAML spec. No payload schema. No error handling requirements. |
| Implementation Readiness | 3/10 | All 3 MuleSoft stories To Do. NGASIM-3058 (upstream) in QA but not verified against MuleSoft consumer. No MuleSoft project scaffolded. |
| Risk Visibility | 5/10 | Cross-cloud complexity is implicit from story structure. NGASIM-3058 dependency is known. PII/compliance risks not explicitly called out in Jira. |
| Dependency Clarity | 7/10 | API-led layer relationships clear from story naming convention. NGASIM-3058 blocking relationship explicit. Sibling stories identifiable. |
| Test Readiness | 1/10 | No test strategy. No integration test plan. No MC sandbox provisioned. No mock API defined. |
| **Overall** | **3.6/10** | Story is a thin placeholder. Significant requirements derivation needed. Cross-cloud complexity demands detailed architecture. |

---

## Handoff to PLAN

**Directive:** The planner agent must:

1. **Derive formal acceptance criteria** — target 12-15 ACs covering: PE subscription, payload validation, transformation, prc-api routing, idempotency, DLQ, health check, logging, error handling, RAML contract.
2. **Define the RAML contract** — exp-api input schema (PE payload), output schema (prc-api request), error response format, health check endpoint.
3. **Specify the consent event payload** — map ContactPointTypeConsent fields to the PE payload fields to the exp-api canonical format.
4. **Address the return path gap** — flag that double opt-in confirmation from MC → SF is not scoped. Recommend a follow-up story.
5. **Plan coordinated delivery** — all 3 MuleSoft layers (exp/prc/sys) must be developed in parallel or in rapid sequence. Define contract-first approach to enable parallel development.
6. **Define idempotency strategy** — how to detect and handle duplicate PE delivery (ReplayId tracking, dedup key generation).
7. **Address PII handling** — phone number masking in logs, encryption in transit, Named Credential patterns for MC OAuth2.
8. **Identify MC Classic REST API specifics** — which API endpoint, authentication method, payload format for SMS opt-in trigger.

**Blocking questions for stakeholders:**

- What is the platform event name and schema published by NGASIM-3058? Is it OrgSync_Consent_Staging or a custom PE?
- What MC Classic REST API endpoint is used for SMS double opt-in? (e.g., `/messaging/v1/sms/messages/` or `/interaction/v1/events`)
- How does MC SubscriberKey map to SF Contact/Lead ID? Is there an existing identity resolution pattern?
- Is there a return path story for MC → SF double opt-in confirmation propagation?
- What MuleSoft Anypoint environment is provisioned for this integration? (sandbox, design center project, API manager instance)
- What is the expected consent event volume? (daily, peak burst, seasonal patterns)
- Does the exp-api need to support batch/bulk consent events, or only single-event processing?
