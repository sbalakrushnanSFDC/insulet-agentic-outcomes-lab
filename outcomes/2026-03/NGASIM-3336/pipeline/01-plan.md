# NGASIM-3336: IMPLEMENTATION PLAN

> **Pipeline Stage:** 01-plan
> **Produced by:** planner agent
> **Input:** 00-intake.md + NGASIM-28 parent feature context + DevInt2 consent model + MC Classic API reference
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T20:58:00Z
> **Status:** COMPLETE — handed off to ARCHITECTURE

---

## Objective

Build the MuleSoft experience API (exp-api) that subscribes to SMS opt-in consent platform events published by Salesforce, validates and transforms the consent payload into a canonical format, and routes it to the process API (prc-api) layer for orchestration toward Marketing Cloud's Classic REST API. This enables the double opt-in SMS flow for patient and provider consent management within the Lead-to-Patient lifecycle.

---

## Planning Decisions

| # | Decision | Rationale |
|---|---|---|
| PD-01 | Contract-first development — define RAML spec before implementation | API-led best practice. Enables parallel development of exp-api, prc-api, and sys-api against agreed contracts. Sibling stories (NGASIM-3335, NGASIM-3143) can mock the exp-api contract. |
| PD-02 | Use Salesforce Platform Event subscription via MuleSoft Salesforce Connector (Pub/Sub API) | Native connector provides reliable event consumption with ReplayId tracking. Avoids custom polling or CometD complexity. Pub/Sub API (gRPC-based) is the modern Salesforce eventing standard. |
| PD-03 | Implement idempotency via composite dedup key (ContactPointTypeConsentId + ConsentStatus + Timestamp) | Platform Events have at-least-once delivery semantics. MuleSoft consumer may receive replayed events after restart. Composite key prevents duplicate MC API invocations. |
| PD-04 | Dead-letter queue (DLQ) for unprocessable events via Anypoint MQ | Unprocessable events (validation failure, downstream timeout) must not block the main flow. Anypoint MQ provides durable DLQ with reprocessing capability. |
| PD-05 | Phone number masking in all application logs (PII compliance) | HIPAA/TCPA requirement. Phone numbers are PII. MuleSoft logs must mask or hash phone fields. DataWeave masking function applied at logging layer. |
| PD-06 | OAuth2 Client Credentials for MuleSoft-to-MC authentication (delegated to sys-api) | MC Classic REST API requires OAuth2. Auth responsibility belongs to sys-api layer, not exp-api. Exp-api authenticates to prc-api via Anypoint Platform client credentials. |
| PD-07 | Flag return path (MC → SF consent confirmation) as out of scope — recommend follow-up story | Double opt-in completion event from MC must eventually update ContactPointTypeConsent.Status in SF. No story exists for this. Recommend NGASIM-XXXX. |
| PD-08 | Develop all 3 MuleSoft layers in parallel using contract-first stubs | Exp-api, prc-api, and sys-api can be developed concurrently once RAML contracts are agreed. Integration testing is sequential but unit testing is parallel. |

---

## Derived Acceptance Criteria

Derived from the single-sentence story description, parent feature NGASIM-28, sibling story context, the DevInt2 consent data model, API-led connectivity standards, and MuleSoft best practices.

| AC ID | Acceptance Criterion | Source | Priority | Verification Method |
|---|---|---|---|---|
| AC-01 | The exp-api subscribes to the Salesforce SMS consent platform event channel and receives events within 5 seconds of publication | FR-01, NFR-01 | Must Have | Integration test: publish PE in SF → exp-api logs receipt with timestamp delta |
| AC-02 | The exp-api validates incoming platform event payloads and rejects events missing required fields (ContactPointTypeConsentId, ConsentStatus, Phone, ConsentChannel) with a structured error response | FR-02 | Must Have | Unit test: send payload with missing Phone → 400 validation error logged + DLQ routed |
| AC-03 | The exp-api transforms the Salesforce platform event payload into the canonical consent event format defined in the RAML spec | FR-03, FR-10 | Must Have | Unit test: SF PE payload in → canonical format out, all fields mapped correctly |
| AC-04 | The exp-api routes the transformed consent event to the prc-api endpoint and receives a synchronous acknowledgment | FR-04 | Must Have | Integration test: exp-api sends to prc-api mock → 202 Accepted response received |
| AC-05 | The exp-api processes each consent event idempotently — redelivery of the same PE (identical ContactPointTypeConsentId + ConsentStatus + EventTimestamp) does not produce a duplicate downstream call | FR-05 | Must Have | Unit test: send same event twice → second invocation returns 200 with "already processed" status |
| AC-06 | Failed events (validation failure, prc-api timeout, prc-api 5xx) are published to the Anypoint MQ dead-letter queue with the original payload, error reason, and correlation ID | FR-06 | Must Have | Integration test: prc-api returns 503 → event appears in DLQ with error metadata |
| AC-07 | The exp-api exposes a `/health` endpoint that returns HTTP 200 with service status, PE subscription status, and DLQ depth | FR-07 | Must Have | HTTP test: GET /health → 200 with JSON body containing status fields |
| AC-08 | Every processed event is logged with a correlation ID that traces from the SF platform event ReplayId through exp-api to the prc-api request ID | FR-08 | Must Have | Log inspection: correlation ID present in all log entries for a single consent event |
| AC-09 | The exp-api supports PE replay from a specific ReplayId for recovery after consumer restart or failure | FR-09 | Must Have | Recovery test: stop exp-api → publish 10 events → restart exp-api → all 10 events processed from last committed ReplayId |
| AC-10 | The exp-api RAML spec defines: (a) canonical consent event schema, (b) error response schema, (c) health check response schema, (d) API versioning (v1) | FR-10 | Must Have | RAML validation: spec passes API Designer linting with no errors |
| AC-11 | Phone numbers are masked (e.g., `***-***-1234`) in all MuleSoft application logs. No plaintext phone numbers appear in CloudHub log output | NFR-05 | Must Have | Log audit: process 10 events → grep logs for phone patterns → zero plaintext matches |
| AC-12 | The exp-api handles burst volumes of 500 events per minute without message loss or consumer lag exceeding 30 seconds | NFR-02 | Should Have | Load test: publish 500 PEs in 60 seconds → all processed, max lag < 30s |
| AC-13 | The exp-api applies circuit breaker pattern on the prc-api call — after 5 consecutive failures in 60 seconds, circuit opens and events are routed directly to DLQ for 120 seconds before half-open retry | Derived from MuleSoft resilience patterns | Should Have | Resilience test: prc-api returns 503 for 5 calls → 6th call goes to DLQ without attempting prc-api |
| AC-14 | The exp-api filters consent events to SMS channel only — events with ConsentChannel != 'SMS' are acknowledged but not routed to prc-api | Derived from story scope (SMS only) | Must Have | Unit test: send email consent event → acknowledged, not routed, not in DLQ |
| AC-15 | The exp-api RAML contract is published to Anypoint Exchange and discoverable by the prc-api and sys-api development teams | API-led governance | Should Have | Exchange check: RAML asset visible in Anypoint Exchange with correct version |

---

## Implementation Phases

### Phase 1: RAML Contract & Event Schema Definition (Size: S)

**Target:** Sprint 1 (first 3 days)
**Duration:** 3 days
**Dependencies:** NGASIM-3058 platform event schema must be confirmed (ask SF team for PE field list)

| Task | Description | AC | Owner |
|---|---|---|---|
| P1-T1 | Define the canonical SMS consent event RAML data type | AC-10 | MuleSoft dev |
| P1-T2 | Define the exp-api RAML spec: event receiver endpoint, health check, error responses | AC-10 | MuleSoft dev |
| P1-T3 | Map ContactPointTypeConsent fields to PE payload fields to canonical format | AC-03 | MuleSoft dev + SF dev |
| P1-T4 | Publish RAML to Anypoint Exchange as v1.0.0-rc1 | AC-15 | MuleSoft dev |
| P1-T5 | Share RAML contract with prc-api (NGASIM-3335) and sys-api (NGASIM-3143) teams for review | AC-15 | MuleSoft dev |
| P1-T6 | Create MuleSoft Anypoint project scaffold (exp-api-sms-consent) in Design Center | — | MuleSoft dev |

**Exit criteria:** RAML spec reviewed and approved by prc-api and sys-api teams. Published to Anypoint Exchange.

### Phase 2: Platform Event Subscription & Core Transformation (Size: M)

**Target:** Sprint 1-2
**Duration:** 5-7 days
**Dependencies:** Phase 1 complete. NGASIM-3058 PE schema confirmed.

| Task | Description | AC | Owner |
|---|---|---|---|
| P2-T1 | Configure Salesforce Connector with Pub/Sub API subscription to consent PE channel | AC-01, AC-09 | MuleSoft dev |
| P2-T2 | Implement PE payload validation (required fields check, SMS channel filter) | AC-02, AC-14 | MuleSoft dev |
| P2-T3 | Implement DataWeave transformation: SF PE payload → canonical consent event format | AC-03 | MuleSoft dev |
| P2-T4 | Implement idempotency check using Object Store (composite dedup key lookup) | AC-05 | MuleSoft dev |
| P2-T5 | Implement prc-api HTTP requester with synchronous acknowledgment handling | AC-04 | MuleSoft dev |
| P2-T6 | Implement correlation ID generation and propagation (X-Correlation-ID header) | AC-08 | MuleSoft dev |
| P2-T7 | Implement PII masking in logging configuration (phone number DataWeave mask) | AC-11 | MuleSoft dev |
| P2-T8 | Write MUnit tests for all transformation, validation, and idempotency logic | AC-01–AC-05, AC-08, AC-11, AC-14 | MuleSoft dev |

**Exit criteria:** AC-01 through AC-05, AC-08, AC-11, AC-14 verified via MUnit. PE subscription confirmed against SF sandbox.

### Phase 3: Error Handling, DLQ & Resilience (Size: M)

**Target:** Sprint 2
**Duration:** 3-5 days
**Dependencies:** Phase 2 complete.

| Task | Description | AC | Owner |
|---|---|---|---|
| P3-T1 | Configure Anypoint MQ DLQ queue (sms-consent-dlq) | AC-06 | MuleSoft dev |
| P3-T2 | Implement error routing: validation failures → DLQ with error metadata | AC-06 | MuleSoft dev |
| P3-T3 | Implement error routing: prc-api failures (timeout, 5xx) → DLQ with retry metadata | AC-06 | MuleSoft dev |
| P3-T4 | Implement circuit breaker on prc-api call (5 failures / 60s → open for 120s) | AC-13 | MuleSoft dev |
| P3-T5 | Implement health check endpoint (/health) with PE subscription status and DLQ depth | AC-07 | MuleSoft dev |
| P3-T6 | Implement PE replay recovery (ReplayId persistence to Object Store, resubscribe on restart) | AC-09 | MuleSoft dev |
| P3-T7 | Write MUnit tests for DLQ routing, circuit breaker, health check, and replay recovery | AC-06, AC-07, AC-09, AC-13 | MuleSoft dev |

**Exit criteria:** AC-06, AC-07, AC-09, AC-13 verified via MUnit. DLQ messages inspectable in Anypoint MQ console.

### Phase 4: Integration Testing & Load Validation (Size: M)

**Target:** Sprint 2-3
**Duration:** 3-5 days
**Dependencies:** Phase 3 complete. NGASIM-3058 in QA/Done. prc-api mock or stub available.

| Task | Description | AC | Owner |
|---|---|---|---|
| P4-T1 | Deploy exp-api to CloudHub Sandbox environment | — | MuleSoft dev |
| P4-T2 | Integration test: SF publishes PE → exp-api receives → routes to prc-api mock | AC-01, AC-04 | MuleSoft dev + QA |
| P4-T3 | Integration test: DLQ routing on prc-api failure scenarios | AC-06, AC-13 | QA |
| P4-T4 | Load test: 500 events/minute burst → verify no message loss, lag < 30s | AC-12 | Performance team |
| P4-T5 | Log audit: verify no plaintext phone numbers in CloudHub logs | AC-11 | Security team |
| P4-T6 | End-to-end smoke test with prc-api and sys-api stubs | AC-01–AC-14 | QA |
| P4-T7 | Replay recovery test: stop → publish → restart → verify catch-up | AC-09 | QA |

**Exit criteria:** All 15 ACs verified. Load test passed. Log audit clean. Ready for end-to-end integration with prc-api (NGASIM-3335) and sys-api (NGASIM-3143).

---

## 10 Mandatory Lenses

### Lens 1: Business Intent

The exp-api enables automated propagation of SMS opt-in consent from Salesforce (where consent is captured during lead intake, webform submission, or Inside Sales interaction) to Marketing Cloud (where double opt-in SMS is sent to the patient/provider). This is a compliance-critical flow: failure to propagate consent means MC cannot send the confirmation SMS, and the patient's consent is not legally validated under TCPA.

**KPI alignment:** Double opt-in completion rate. Consent propagation latency (time from SF consent capture to MC SMS send). Consent compliance audit pass rate.

### Lens 2: Scope Boundary

**In scope:**
- Exp-api RAML contract definition
- PE subscription via Salesforce Connector (Pub/Sub API)
- Payload validation (required fields, SMS channel filter)
- Canonical transformation (SF PE → consent event format)
- Idempotent processing (dedup by composite key)
- prc-api routing (HTTP request with acknowledgment)
- DLQ for unprocessable events
- Health check endpoint
- Correlation ID tracing
- PII masking in logs

**Out of scope:**
- Salesforce Apex trigger / PE publish (NGASIM-3058)
- Process API business rules (NGASIM-3335)
- System API MC Classic REST call (NGASIM-3143)
- MC → SF return path (double opt-in confirmation callback)
- Email or marketing consent channels (SMS only)
- Data Cloud consent ingestion
- MC Connect managed package integration

### Lens 3: Assumptions

| # | Assumption | Risk if Wrong |
|---|---|---|
| A-01 | NGASIM-3058 publishes a platform event on ContactPointTypeConsent insert/update with fields: Id, ConsentStatus, Phone, ConsentChannel, ContactId/LeadId, Timestamp | If PE schema differs, exp-api transformation and validation must be redesigned |
| A-02 | The PE channel is OrgSync_Consent_Staging (or a dedicated consent PE type) | If a different channel is used, connector configuration changes |
| A-03 | MC Classic REST API endpoint for SMS opt-in is `/messaging/v1/sms/messages/` or `/interaction/v1/events` | If endpoint differs, sys-api contract changes (exp-api unaffected due to layering) |
| A-04 | MuleSoft Anypoint environment (CloudHub) is provisioned and accessible | If not provisioned, deployment is blocked |
| A-05 | Anypoint MQ is available for DLQ | If Anypoint MQ is not licensed, alternative DLQ (e.g., ActiveMQ, database table) needed |
| A-06 | SF ContactId or LeadId maps 1:1 to MC SubscriberKey | If identity resolution is complex, prc-api or sys-api must handle lookup |
| A-07 | Event volume is < 1000/day average with peak burst of 500/minute | If volume exceeds this, horizontal scaling and partitioning needed |
| A-08 | Consent status values are standardized: OptIn, OptOut, Pending, Confirmed | If status values differ between SF and MC, transformation must include value mapping |

### Lens 4: Open Questions

| # | Question | Impact | Assigned To |
|---|---|---|---|
| OQ-01 | What is the exact PE name and field schema published by NGASIM-3058? | Blocks RAML definition and transformation | SF dev team |
| OQ-02 | Which MC Classic REST API endpoint triggers SMS double opt-in? | Blocks sys-api contract, indirectly affects exp-api canonical format | MC admin |
| OQ-03 | How is MC SubscriberKey derived from SF ContactId/LeadId? | Blocks identity mapping in prc-api/sys-api | Integration architect |
| OQ-04 | Is there a return path story for MC → SF consent confirmation? | Scope gap — double opt-in is incomplete without return path | Product Owner |
| OQ-05 | What MuleSoft Anypoint environment and organization is provisioned? | Blocks deployment and Exchange publishing | MuleSoft admin |
| OQ-06 | Is Anypoint MQ licensed and available for DLQ? | Affects DLQ implementation choice | MuleSoft admin |
| OQ-07 | Does the org use the standard ContactPointTypeConsent object or a custom consent object? | Affects PE payload mapping | SF data architect |
| OQ-08 | What are the MC Classic REST API rate limits for SMS endpoints? | Affects sys-api throttling, indirectly affects exp-api burst handling | MC admin |
| OQ-09 | Is there an existing MuleSoft API for MC communication that sys-api should extend rather than create net-new? | Affects reuse vs new development decision | MuleSoft architect |
| OQ-10 | What consent status values does MC expect for double opt-in initiation? | Affects value mapping in transformation | MC admin |

### Lens 5: Tradeoffs Considered

| # | Tradeoff | Option A | Option B | Decision | Rationale |
|---|---|---|---|---|---|
| T-01 | Event subscription mechanism | CometD Streaming API (legacy) | Pub/Sub API (gRPC, modern) | **Pub/Sub API** | Pub/Sub API is the Salesforce-recommended modern eventing standard. Higher throughput, better ReplayId management, gRPC efficiency. CometD is legacy and has known scaling limitations. |
| T-02 | Idempotency store | Anypoint Object Store | External Redis/database | **Object Store** | Object Store is native to MuleSoft CloudHub, requires no additional infrastructure. Sufficient for the expected volume. Redis adds operational complexity for marginal performance gain. |
| T-03 | DLQ technology | Anypoint MQ | Database error table | **Anypoint MQ** | Anypoint MQ provides native integration with MuleSoft, supports reprocessing, and has built-in monitoring. Database table is simpler but lacks reprocessing workflow. |
| T-04 | Error handling | Retry inline (blocking) | DLQ + async retry | **DLQ + async retry** | Blocking retry delays subsequent event processing. DLQ allows the main flow to continue while failed events are retried independently. |
| T-05 | PII masking | Application-level DataWeave | Platform-level log policy | **Application-level DataWeave** | CloudHub log policies are limited. DataWeave masking in the logging module provides field-level control and is testable via MUnit. |
| T-06 | API layering | 3-layer (exp/prc/sys) | 2-layer (exp/sys, skip prc) | **3-layer** | Consent business rules (dedup, state validation, enrichment) warrant a dedicated prc-api. Collapsing into 2 layers makes the exp-api do too much or the sys-api know business rules. |
| T-07 | Exp-api trigger model | PE subscription (push) | Polling / scheduled batch | **PE subscription** | Real-time consent propagation is required for double opt-in UX. Polling introduces latency (minimum 1 minute) that is unacceptable for SMS confirmation timing. |

### Lens 6: Risks

| ID | Risk | Prob | Impact | Severity | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R-01 | No ACs on story — scope ambiguity | High | High | Critical | Formalized 15 ACs in this plan. Seek PO sign-off. | Planner |
| R-02 | NGASIM-3058 PE schema unknown — blocks transformation | High | High | Critical | Request PE schema from SF dev team immediately. Block Phase 2 until confirmed. | SF dev lead |
| R-03 | 3 MuleSoft layers all To Do — coordinated delivery risk | High | High | Critical | Contract-first approach enables parallel development. Stubs enable independent testing. | MuleSoft architect |
| R-04 | Return path (MC → SF) not scoped — double opt-in incomplete | High | High | Critical | Recommend follow-up story. Flag to PO and architecture review. | Product Owner |
| R-05 | MC Classic REST API deprecation risk | Low | Medium | Medium | Sys-api layer isolates the change. Monitor Salesforce deprecation announcements. | MuleSoft architect |
| R-06 | PE delivery at-least-once semantics → duplicate processing | Medium | High | High | Idempotency via composite dedup key (AC-05). Dedup window configurable. | MuleSoft dev |
| R-07 | PII exposure in MuleSoft logs | Medium | Critical | Critical | PII masking mandated (AC-11). Log audit in Phase 4 (P4-T5). | Security team |
| R-08 | MuleSoft Anypoint env not provisioned | Medium | High | High | Confirm env availability before Phase 4 deployment. | MuleSoft admin |
| R-09 | Consent event volume exceeds estimates | Low | Medium | Medium | Circuit breaker (AC-13) and DLQ (AC-06) provide backpressure. Horizontal scaling available in CloudHub. | MuleSoft dev |
| R-10 | Identity alignment (SF ContactId → MC SubscriberKey) undefined | Medium | High | High | Delegate to prc-api/sys-api scope. Flag as cross-story dependency. | Integration architect |

### Lens 7: Dependencies

| Dependency | Type | Status | Impact if Delayed | Mitigation |
|---|---|---|---|---|
| NGASIM-3058 (SF Apex trigger / PE publish) | Predecessor | In QA | Blocks integration testing. Can unit test with mock PE data. | Confirm NGASIM-3058 QA completion timeline. |
| NGASIM-3335 (prc-api) | Downstream peer | To Do | Exp-api can be tested with prc-api stub. Integration test blocked. | Contract-first stubs enable parallel development. |
| NGASIM-3143 (sys-api) | Downstream peer | To Do | End-to-end test blocked. Exp-api unaffected for unit/integration. | Contract-first stubs. |
| MuleSoft Anypoint environment | Infrastructure | Unknown | Blocks deployment and CloudHub testing. | Confirm provisioning status immediately. |
| Anypoint MQ license | Infrastructure | Unknown | Blocks DLQ implementation. Fallback: database error table. | Confirm MQ availability. |
| MC Classic REST API sandbox | Infrastructure | Unknown | Blocks sys-api testing, indirectly blocks E2E. | Confirm MC sandbox provisioning. |
| SF Connected App for MuleSoft | Configuration | Unknown | Blocks PE subscription. MuleSoft Salesforce Connector requires Connected App with OAuth2. | Confirm Connected App exists or create one. |

### Lens 8: Security / Compliance

| Concern | Assessment | Mitigation |
|---|---|---|
| **PII in transit** | Phone numbers cross SF → MuleSoft → MC boundaries. Each transit is over HTTPS/TLS 1.2+. MuleSoft VPC ensures in-transit encryption within CloudHub. | HTTPS enforced. No plaintext HTTP endpoints. |
| **PII in logs** | MuleSoft application logs may contain phone numbers from PE payload. CloudHub logs are stored in Anypoint log storage. | PII masking via DataWeave (AC-11). Log audit in Phase 4. |
| **TCPA compliance** | SMS consent must be double opt-in for marketing messages. Failure to propagate consent = sending without valid consent = TCPA violation. | Reliable event processing (DLQ, replay, idempotency). Monitoring via health check. |
| **HIPAA** | Patient phone numbers and consent preferences are PHI-adjacent. If the org is HIPAA-covered, MuleSoft must be in a HIPAA-compliant CloudHub environment. | Confirm HIPAA BAA with MuleSoft. Encrypt at rest. Minimize PII retention. |
| **OAuth2 credentials** | MuleSoft Salesforce Connector uses OAuth2 (JWT Bearer or Connected App client credentials). MC API uses OAuth2 client credentials. Credentials must be stored securely. | Use MuleSoft Secure Configuration Properties. No hardcoded credentials. Credential rotation policy. |
| **Consent audit trail** | Consent status changes must be auditable. PE provides event timestamp and ReplayId. MuleSoft provides correlation ID. MC provides SMS send timestamp. | Correlation ID chain enables full audit trace: SF PE ReplayId → MuleSoft Correlation ID → MC API response ID. |
| **Data residency** | MuleSoft CloudHub region must align with data residency requirements (US for HIPAA). MC data center must be in the same region. | Confirm CloudHub deployment region. Confirm MC instance region. |

### Lens 9: Scale / Performance / Latency

| Metric | Target | Basis | Risk |
|---|---|---|---|
| **Event processing latency** | < 5 seconds (PE publish → exp-api ack) | NFR-01. Double opt-in UX requires near-real-time. Patients expect confirmation SMS within seconds. | Pub/Sub API latency is typically < 1s. Transformation + prc-api call adds 1-3s. Target achievable. |
| **Throughput** | 500 events/minute peak | NFR-02. Derived from peak webform submission + batch consent processing during marketing campaigns. | CloudHub worker can process ~100 events/second. Single worker sufficient. Scale out if needed. |
| **Error rate** | < 0.1% unrecoverable | NFR-04. DLQ captures all transient failures for retry. Only permanently invalid events are unrecoverable. | Circuit breaker + DLQ provide resilience. 0.1% = 1 in 1000. Achievable with proper validation. |
| **PE retention** | 72 hours | Salesforce platform limit. Events not consumed within 72h are lost. | ReplayId tracking ensures consumer restarts from last committed position. If MuleSoft is down >72h, events are lost. Alert on consumer lag. |
| **Idempotency window** | 24 hours | Dedup key retained in Object Store for 24h. Events replayed within 24h are deduplicated. After 24h, same event processed again. | 24h window covers typical replay scenarios. Extend if replay patterns exceed 24h. |
| **MC API rate limits** | ~2000 calls/hour (Classic API estimate) | MC Classic API has per-BU rate limits. Exact limit depends on MC edition and BU configuration. | Sys-api (NGASIM-3143) must implement throttling. Exp-api circuit breaker provides upstream backpressure. |

### Lens 10: Testing / Operational Implications

| Dimension | Plan |
|---|---|
| **Unit testing** | MUnit tests for all DataWeave transformations, validation logic, idempotency check, PII masking, circuit breaker behavior. Target: 90%+ MUnit coverage. |
| **Integration testing** | Exp-api → prc-api mock (HTTP). SF sandbox → exp-api (PE subscription). DLQ routing verification. |
| **End-to-end testing** | Requires all 4 components: NGASIM-3058 (SF) + NGASIM-3336 (exp-api) + NGASIM-3335 (prc-api) + NGASIM-3143 (sys-api) + MC sandbox. Defer to coordinated integration sprint. |
| **Load testing** | 500 events/minute burst test. Monitor CloudHub worker memory, CPU, and message throughput. |
| **Security testing** | Log audit for PII. Credential rotation test. HTTPS enforcement validation. |
| **Monitoring** | CloudHub application monitoring. Anypoint MQ DLQ depth alerting. Health check endpoint polling. Custom dashboard for: events received, events processed, events failed, DLQ depth, processing latency. |
| **Alerting** | Alert on: DLQ depth > 10, processing latency > 10s, PE consumer lag > 5 minutes, health check failure, circuit breaker open. |
| **Operational runbook** | Document: how to reprocess DLQ events, how to replay PE from specific ReplayId, how to restart consumer, how to check MC API health, escalation path for consent delivery failure. |

---

## Anti-Pattern Gate Evaluation

| # | Anti-Pattern | Evaluation | Verdict |
|---|---|---|---|
| AP-01 | Treats Salesforce as a generic custom app platform | NO — uses platform-native Platform Events for domain event publishing. ContactPointTypeConsent is standard Salesforce Consent Management object. PE is the idiomatic Salesforce mechanism for cross-system event propagation. | PASS |
| AP-02 | Defaults to custom build without OOTB comparison | NO — evaluated MC Connect managed package (et4ae5) as OOTB alternative. MC Connect does not support custom PE-triggered SMS double opt-in flows. MC Connect is designed for email/SMS sends from within SF UI, not automated consent event propagation. Custom MuleSoft integration is justified. | PASS |
| AP-03 | Uses async as a hand-wave for scale without specific analysis | NO — specific volume estimates provided (500 events/min peak). PE latency analyzed (< 1s Pub/Sub API). CloudHub worker capacity estimated. Circuit breaker thresholds defined. Scale-out path documented. | PASS |
| AP-04 | Duplicates data without source-of-truth consequences stated | FLAGGED — Consent status exists in both SF (ContactPointTypeConsent) and MC (subscriber consent state). **SOT: Salesforce ContactPointTypeConsent is the source of truth.** MC subscriber consent is a derived state that should reflect SF SOT. Return path (MC → SF confirmation) must update SF SOT. Bidirectional sync risk acknowledged in R-04 and R-10. | PASS WITH FLAG |
| AP-05 | Proposes MuleSoft layering without clear reuse/governance value | NO — 3-layer pattern justified: exp-api (event normalization, external contract), prc-api (consent business rules, reusable for email/marketing consent), sys-api (MC API encapsulation, reusable for other MC integrations). Each layer has distinct responsibility and reuse potential. | PASS |
| AP-06 | Places Data Cloud without clarifying ingestion/federation/hybrid rationale | NOT APPLICABLE — Data Cloud is not in scope for this story. Flagged as future consideration if consent data flows to Data Cloud for unified profile/segmentation. | PASS (N/A) |
| AP-07 | Assumes rapid MC activation without checking data freshness path | NO — Platform Events provide near-real-time delivery (< 1s). Double opt-in SMS is triggered within seconds of consent capture. Data freshness is inherent in the event-driven architecture. MC Classic API SMS send is synchronous. | PASS |
| AP-08 | Ignores consent, identity, or auditability in cross-cloud flows | NO — consent is the core domain. Identity alignment (SF ContactId → MC SubscriberKey) flagged as open question. Auditability via correlation ID chain (PE ReplayId → MuleSoft Correlation ID → MC API response ID). Consent audit trail documented. | PASS |
| AP-09 | Omits operational and observability consequences | NO — monitoring, alerting, DLQ reprocessing, PE replay recovery, health check, and operational runbook all documented in Lens 10. | PASS |
| AP-10 | Avoids stating rejected alternatives | NO — rejected alternatives documented: MC Connect managed package, direct SF Apex callout, single MuleSoft API, CometD legacy subscription, polling/batch model. Each with specific rejection rationale. | PASS |

---

## Cross-Cloud Implications

### MuleSoft (Primary)

- **API-led connectivity:** Exp-api (this story) → prc-api (NGASIM-3335) → sys-api (NGASIM-3143). Three stories covering three layers.
- **Contract-first:** RAML specs for all 3 layers enable parallel development and consumer-driven contract testing.
- **Bounded domain:** Consent event processing is the bounded context. The MuleSoft layer does not own consent state — it is a conduit with validation, transformation, and routing responsibilities.
- **Governance:** API Manager policies (rate limiting, client ID enforcement, JWT validation) should be applied to exp-api. Exp-api is the only layer exposed to external event sources (SF PE subscription).
- **DDD assessment:** The consent domain is well-bounded. No evidence of org-chart decomposition driving API layering. Layer separation follows functional responsibility, not team structure.

### Marketing Cloud

- **MC Classic REST API:** Target endpoint for SMS double opt-in trigger. Specific endpoint TBD (OQ-02).
- **Subscriber Key alignment:** MC SubscriberKey must map to SF ContactId or LeadId. If the org uses a custom subscriber key pattern, prc-api/sys-api must handle lookup (OQ-03).
- **Consent propagation:** MC receives opt-in consent event → sends confirmation SMS → patient replies → MC updates subscriber consent status. Return path to SF is not scoped (OQ-04).
- **Deliverability:** SMS deliverability depends on phone number validity, carrier compliance, and MC sender reputation. Not in exp-api scope but affects end-to-end success.
- **Anti-pattern check:** Not treating MC as generic operational master. SF ContactPointTypeConsent is SOT. MC subscriber consent is derived.

### Data Cloud (Future Consideration)

- **Not in scope** for this story.
- **Future trigger:** If consent data is unified in Data Cloud for segmentation (e.g., "all SMS-opted-in patients"), the PE-based architecture may be superseded by Data Cloud ingestion connectors or Data Cloud-to-MC activation flows.
- **Recommendation:** If Data Cloud adoption is planned, evaluate whether consent data should flow through Data Cloud rather than direct SF → MuleSoft → MC path. This would change the architecture significantly.

---

## Technology Stack

| Component | Technology | Purpose |
|---|---|---|
| Event Source | Salesforce Platform Events (Pub/Sub API) | Consent status change event publication |
| Event Consumer | MuleSoft Salesforce Connector (Pub/Sub API mode) | PE subscription and consumption |
| Experience API | MuleSoft Anypoint (CloudHub 2.0) | Event validation, transformation, routing |
| API Contract | RAML 1.0 | Contract-first API specification |
| Transformation | DataWeave 2.0 | SF PE payload → canonical consent event format |
| Idempotency Store | MuleSoft Object Store v2 | Composite dedup key storage (24h TTL) |
| Dead-Letter Queue | Anypoint MQ | Unprocessable event storage and reprocessing |
| Downstream Routing | HTTP Requester (MuleSoft) | Exp-api → prc-api synchronous call |
| Monitoring | Anypoint Monitoring + CloudHub Insights | Application metrics, log aggregation, alerting |
| Security | Anypoint Platform Client Credentials, Secure Configuration Properties | API authentication, credential storage |

---

## Metadata Inventory (MuleSoft Artifacts)

| # | Artifact Type | Name | Phase | Action | Purpose |
|---|---|---|---|---|---|
| 1 | RAML Spec | sms-consent-exp-api.raml | 1 | Create | API contract definition |
| 2 | RAML Data Type | ConsentEvent.raml | 1 | Create | Canonical consent event schema |
| 3 | RAML Data Type | ErrorResponse.raml | 1 | Create | Standard error response schema |
| 4 | RAML Data Type | HealthResponse.raml | 1 | Create | Health check response schema |
| 5 | Mule Application | sms-consent-exp-api | 2 | Create | Main Mule application project |
| 6 | Mule Flow | sms-consent-exp-api-main.xml | 2 | Create | PE subscription + validation + transformation + routing |
| 7 | Mule Flow | error-handling.xml | 3 | Create | Global error handler + DLQ routing |
| 8 | Mule Flow | health-check.xml | 3 | Create | Health check endpoint implementation |
| 9 | DataWeave Module | consent-transform.dwl | 2 | Create | SF PE → canonical consent event transformation |
| 10 | DataWeave Module | pii-masking.dwl | 2 | Create | Phone number masking for logging |
| 11 | Properties File | config-{env}.yaml | 2 | Create | Environment-specific configuration (dev, sandbox, prod) |
| 12 | Anypoint MQ Queue | sms-consent-dlq | 3 | Create | Dead-letter queue for failed events |
| 13 | Object Store Key | consent-dedup-{key} | 2 | Runtime | Idempotency dedup keys (24h TTL) |
| 14 | MUnit Test Suite | sms-consent-exp-api-test-suite.xml | 2-3 | Create | Unit and integration test suite |
| 15 | Anypoint Exchange Asset | sms-consent-exp-api | 1 | Create | Published RAML contract |

---

## Effort Estimation

| Phase | Size | Duration | Story Points | Confidence |
|---|---|---|---|---|
| Phase 1 — RAML Contract & Event Schema | S | 3 days | 3 | High (no external dependencies for spec work) |
| Phase 2 — PE Subscription & Core Transformation | M | 5-7 days | 8 | Medium (depends on NGASIM-3058 PE schema confirmation) |
| Phase 3 — Error Handling, DLQ & Resilience | M | 3-5 days | 5 | Medium (depends on Anypoint MQ availability) |
| Phase 4 — Integration Testing & Load Validation | M | 3-5 days | 5 | Low (depends on NGASIM-3058 QA, prc-api stub, MC sandbox) |
| **Total** | | **14-20 days (2-3 sprints)** | **21** | |

---

## Handoff to ARCHITECTURE

**Directive:** The architect agent must:

1. **ADR-001: API-Led Connectivity pattern** — justify 3-layer decomposition (exp/prc/sys) for consent event propagation. Document why this is the right approach vs MC Connect, direct callout, or single API.
2. **ADR-002: Platform Events vs Change Data Capture** — evaluate both as the trigger mechanism for consent status changes. Recommend one with clear rationale.
3. **ADR-003: Error handling strategy** — DLQ, retry with exponential backoff, idempotency keys, circuit breaker. Define the resilience architecture.
4. **ADR-004: MC Classic REST API vs MC Connect managed package** — evaluate both approaches for SMS opt-in trigger. Document why MC Classic API via MuleSoft is chosen over MC Connect direct.
5. **Define the data flow** — full sequence from ContactPointTypeConsent DML → Platform Event → exp-api → prc-api → sys-api → MC Classic REST API.
6. **Object model** — ContactPointTypeConsent fields, PE payload schema, exp-api canonical format, DataWeave transformation map.
7. **Sequence diagram** — full flow with error paths, retry, and DLQ.
8. **Security architecture** — OAuth2 flows, Named Credentials, PII handling, consent audit trail.
9. **Scale analysis** — event volume, API rate limits, CloudHub worker sizing, Object Store capacity.
10. **CTA domain coverage matrix** — all 9 domains rated.
