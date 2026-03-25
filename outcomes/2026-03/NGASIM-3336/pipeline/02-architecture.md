# NGASIM-3336: ARCHITECTURE

> **Pipeline Stage:** 02-architecture
> **Produced by:** architect agent
> **Input:** 01-plan.md + DevInt2 consent model + MC Classic API reference + MuleSoft API-led best practices
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T20:58:00Z
> **Status:** COMPLETE — handed off to TDD

---

## Architecture Overview

The SMS consent double opt-in integration follows a Salesforce Platform Event-driven, MuleSoft API-led connectivity pattern across three system boundaries: Salesforce (source of truth for consent), MuleSoft (integration orchestration), and Marketing Cloud (SMS activation).

### End-to-End Data Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           SALESFORCE (DevInt2)                                │
│                                                                              │
│  ┌──────────────────────────────────┐    ┌────────────────────────────────┐  │
│  │ ContactPointTypeConsent           │    │ Apex Trigger (NGASIM-3058)     │  │
│  │ ┌──────────────────────────────┐  │    │                                │  │
│  │ │ Id                           │  │───▶│ on insert/update:              │  │
│  │ │ Name                         │  │    │   if ConsentChannel = 'SMS'    │  │
│  │ │ PartyId (Contact/Lead)       │  │    │     AND Status = 'OptIn':      │  │
│  │ │ DataUsePurposeId             │  │    │   publish PE                    │  │
│  │ │ CaptureContactPointType      │  │    │                                │  │
│  │ │ CaptureDate                  │  │    └──────────┬─────────────────────┘  │
│  │ │ EffectiveFrom                │  │               │                        │
│  │ │ EffectiveTo                  │  │               ▼                        │
│  │ │ Status (OptIn/OptOut/...)    │  │    ┌────────────────────────────────┐  │
│  │ └──────────────────────────────┘  │    │ Platform Event                 │  │
│  └──────────────────────────────────┘    │ (OrgSync_Consent_Staging or    │  │
│                                           │  custom SMS_Consent_Event__e)  │  │
│                                           │                                │  │
│                                           │ Fields:                        │  │
│                                           │  ConsentId__c                  │  │
│                                           │  ConsentStatus__c              │  │
│                                           │  Phone__c                      │  │
│                                           │  ConsentChannel__c             │  │
│                                           │  PartyId__c (Contact/Lead)     │  │
│                                           │  CaptureDate__c                │  │
│                                           │  ReplayId (system)             │  │
│                                           └──────────┬─────────────────────┘  │
└──────────────────────────────────────────────────────┼────────────────────────┘
                                                       │
                           Pub/Sub API (gRPC)          │
                           TLS 1.2+ encrypted          │
                                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                      MULESOFT ANYPOINT (CloudHub 2.0)                        │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ EXPERIENCE API — sms-consent-exp-api (THIS STORY: NGASIM-3336)        │  │
│  │                                                                        │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌───────────┐  ┌──────────────┐  │  │
│  │  │ PE          │  │ Payload      │  │ Dedup     │  │ DataWeave    │  │  │
│  │  │ Subscriber  │─▶│ Validator    │─▶│ Check     │─▶│ Transform    │──┐│  │
│  │  │ (SF Conn.)  │  │ (SMS filter) │  │ (ObjStore)│  │ (SF→Canon.)  │  ││  │
│  │  └─────────────┘  └──────┬───────┘  └─────┬─────┘  └──────────────┘  ││  │
│  │                          │ invalid         │ duplicate                 ││  │
│  │                          ▼                 ▼                           ││  │
│  │                   ┌──────────────────────────────┐                    ││  │
│  │                   │ DLQ Router (Anypoint MQ)     │                    ││  │
│  │                   │ sms-consent-dlq              │                    ││  │
│  │                   └──────────────────────────────┘                    ││  │
│  │                                                                       ││  │
│  │  ┌──────────────┐   ┌──────────────┐                                 ││  │
│  │  │ Health Check  │   │ Correlation  │                                 ││  │
│  │  │ /health       │   │ ID Generator │                                 ││  │
│  │  │ GET → 200     │   │ X-Corr-ID   │                                 ││  │
│  │  └──────────────┘   └──────────────┘                                 ││  │
│  └───────────────────────────────────────────────────────────────────────┘│  │
│                                                                          │  │
│          HTTP POST (canonical consent event)                             │  │
│          + X-Correlation-ID header                                       │  │
│          + Circuit Breaker (5 failures / 60s → open 120s)                │  │
│                                                                          ▼  │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ PROCESS API — sms-consent-prc-api (NGASIM-3335)                       │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  • Consent state machine validation (is opt-in valid for this party?)  │  │
│  │  • Deduplication at business level (already opted-in? skip)            │  │
│  │  • Enrichment: resolve SF PartyId → MC SubscriberKey                   │  │
│  │  • Consent business rules (e.g., provider vs patient consent paths)    │  │
│  │  • Route to sys-api                                                    │  │
│  └────────────────────────────────────────────────────────────┬───────────┘  │
│                                                               │              │
│          HTTP POST (MC-ready consent payload)                 │              │
│          + SubscriberKey resolved                             │              │
│          + X-Correlation-ID propagated                        ▼              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ SYSTEM API — sflmc-sys-api (NGASIM-3143)                              │  │
│  │                                                                        │  │
│  │  Responsibilities:                                                     │  │
│  │  • OAuth2 token management for MC Classic REST API                     │  │
│  │  • Payload transformation: canonical → MC Classic API format           │  │
│  │  • MC Classic REST API call (POST /messaging/v1/sms/messages/)         │  │
│  │  • Response mapping: MC response → standard acknowledgment             │  │
│  │  • Retry with exponential backoff on 429/5xx                           │  │
│  │  • Rate limiting to stay within MC API quotas                          │  │
│  └────────────────────────────────────────────────────────────┬───────────┘  │
└───────────────────────────────────────────────────────────────┼──────────────┘
                                                                │
                           HTTPS (OAuth2 Bearer)                │
                           TLS 1.2+ encrypted                   │
                                                                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                      MARKETING CLOUD (Classic REST API)                       │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ SMS Double Opt-In Flow                                                 │  │
│  │                                                                        │  │
│  │  1. Receive SMS opt-in trigger via REST API                            │  │
│  │  2. Look up SubscriberKey in All Subscribers                           │  │
│  │  3. Send confirmation SMS: "Reply YES to confirm opt-in"               │  │
│  │  4. Wait for patient reply                                             │  │
│  │  5. On "YES" reply → update subscriber consent status to Confirmed     │  │
│  │  6. Callback to SF? → NOT SCOPED (return path gap)                     │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌──────────────────────┐  ┌─────────────────────────────────────────┐      │
│  │ et4ae5__             │  │ MC Classic REST API Endpoints            │      │
│  │ SMSDefinition__c     │  │  POST /messaging/v1/sms/messages/       │      │
│  │ (managed package     │  │  POST /interaction/v1/events             │      │
│  │  — confirms SMS      │  │  POST /auth/v2/token (OAuth2)           │      │
│  │  capability exists)  │  │                                          │      │
│  └──────────────────────┘  └─────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Architecture Decision Records

### ADR-001: API-Led Connectivity Pattern for Consent Event Propagation

| Field | Value |
|---|---|
| Status | Accepted |
| Context | NGASIM-3336, NGASIM-3335, and NGASIM-3143 collectively implement the SMS consent double opt-in integration from Salesforce to Marketing Cloud. The integration involves: (1) event consumption from SF, (2) consent business rule application, (3) MC API invocation. These are three distinct responsibilities. The parent feature NGASIM-28 also covers email and marketing consent channels, suggesting future reuse of the process and system layers. |
| Decision | Implement a 3-layer API-led connectivity pattern: **exp-api** (NGASIM-3336) for event consumption, validation, and canonical transformation; **prc-api** (NGASIM-3335) for consent business rules, identity resolution, and orchestration; **sys-api** (NGASIM-3143) for MC Classic REST API encapsulation and authentication management. |
| Rationale | **Separation of concerns:** Each layer has a distinct, testable responsibility. The exp-api owns the Salesforce boundary contract (PE subscription, payload normalization). The prc-api owns consent domain logic (state validation, dedup, enrichment). The sys-api owns the MC API boundary (auth, payload format, rate limiting). **Reuse:** The prc-api consent business rules apply equally to email consent (future) and marketing consent (future) channels — only the exp-api trigger and sys-api target change. The sys-api MC Classic API encapsulation is reusable for any MC integration (email sends, journey triggers, subscriber management). **Governance:** API Manager policies (rate limiting, client ID enforcement) are applied at the exp-api layer, providing a single governance point. **Testability:** Each layer can be unit-tested independently with mocks. Integration testing is layered: exp→prc, prc→sys, sys→MC. |
| Alternatives Considered | **(A1) MC Connect managed package (et4ae5):** Rejected — MC Connect supports email/SMS sends from within the SF UI (e.g., "Send Email" button, Journey Builder trigger from SF). It does not support custom platform event-triggered SMS double opt-in flows. MC Connect is a UI-level integration, not an event-driven automation layer. The et4ae5__SMSDefinition__c object in DevInt2 confirms MC Connect SMS capability exists, but it serves a different use case (template-based sends, not consent event propagation). **(A2) Direct SF Apex callout to MC REST API:** Rejected — couples the Salesforce DML transaction to MC API availability. If MC API is slow or unavailable, the SF transaction that updates ContactPointTypeConsent would fail or require complex queueable/future method chaining. Callout limits (100 per transaction) and governor limits make this fragile for batch consent processing. **(A3) Single MuleSoft API (no layering):** Rejected — collapses three distinct responsibilities into one API. The PE subscription logic, consent business rules, and MC API specifics become entangled. Testing requires MC sandbox for every unit test. Changes to MC API format ripple to the PE subscription layer. Maintenance cost increases as complexity grows. **(A4) 2-layer pattern (exp-api + sys-api, skip prc-api):** Considered — viable if consent business rules are minimal. Rejected because: consent state validation (is this party already opted-in?), identity resolution (SF PartyId → MC SubscriberKey), and provider vs patient consent path differentiation are non-trivial business rules that warrant a dedicated orchestration layer. Collapsing into exp-api makes it do too much; collapsing into sys-api makes the system layer know business logic. |
| Consequences | Three MuleSoft applications to develop, deploy, and operate. Increased deployment coordination (3 stories must be delivered in sync). Contract-first approach mitigates coordination risk. Operational overhead of 3 CloudHub workers (can be mitigated with shared CloudHub deployment if org allows). |
| Anti-Pattern Gate | AP-05 (MuleSoft layering without clear reuse/governance value): **PASSED** — reuse path documented for email/marketing consent. Governance via API Manager at exp-api layer. |
| Traces to | PD-01, PD-06, PD-08, T-06, AC-04, AC-10, AC-15 |

### ADR-002: Platform Events vs Change Data Capture for Consent Event Trigger

| Field | Value |
|---|---|
| Status | Accepted |
| Context | The consent integration needs a mechanism to detect ContactPointTypeConsent status changes in Salesforce and propagate them to MuleSoft. Two native Salesforce options exist: **Platform Events (PE)** — custom or standard event types published explicitly by Apex code; **Change Data Capture (CDC)** — automatic change stream for standard and custom objects. NGASIM-3058 (In QA) has already implemented the Apex trigger that publishes a PE. |
| Decision | Use **Platform Events** (as implemented by NGASIM-3058) rather than Change Data Capture. |
| Rationale | **1. Selective publishing:** The Apex trigger in NGASIM-3058 publishes a PE only when the consent status changes to 'OptIn' for the SMS channel. CDC would fire on every ContactPointTypeConsent field change (any field, any status), generating significant noise. The MuleSoft consumer would need to filter 90%+ of CDC events. **2. Custom payload shaping:** The PE payload includes exactly the fields needed downstream (ConsentId, Status, Phone, Channel, PartyId, CaptureDate). CDC payloads include all changed fields with before/after values — more data than needed, requiring heavier transformation. **3. Domain semantics:** A PE named SMS_Consent_OptIn_Event (or published via OrgSync_Consent_Staging) carries explicit domain intent: "an SMS opt-in happened." CDC carries generic structural semantics: "a row changed." Domain events are more meaningful for downstream consumers. **4. Already implemented:** NGASIM-3058 is In QA with PE-based implementation. Switching to CDC would require rewriting the upstream trigger and creating a new CDC-enabled object configuration. **5. Replay reliability:** PE replay via ReplayId is well-understood and supported by the MuleSoft Salesforce Connector (Pub/Sub API mode). CDC replay is also supported but the event volume is higher (all field changes), making replay more expensive. |
| Alternatives Considered | **(A1) Change Data Capture on ContactPointTypeConsent:** Rejected — reasons above. CDC is more appropriate when you need all changes to an object (full audit stream). For selective, domain-meaningful events, PE is the right choice. **(A2) Outbound Messages (Workflow Rule):** Rejected — legacy mechanism. Workflow Rules are being deprecated in favor of Flows and Platform Events. Outbound Messages are SOAP-based, adding unnecessary protocol complexity. **(A3) Record-Triggered Flow with HTTP callout:** Rejected — Flow callouts have limited error handling. Cannot implement retry, DLQ, or circuit breaker natively. Tightly couples the SF transaction to MuleSoft availability. **(A4) Streaming API (PushTopic):** Rejected — PushTopics are legacy (superseded by CDC and PE). Limited to 40 PushTopics per org. Not recommended by Salesforce for new development. |
| Consequences | Dependency on NGASIM-3058 Apex trigger for PE publishing. If trigger logic changes, PE payload may change (breaking exp-api transformation). Contract between SF trigger and MuleSoft consumer must be versioned. PE retention is 72 hours — events not consumed within 72h are lost. |
| Anti-Pattern Gate | AP-01 (treats SF as generic app platform): **PASSED** — Platform Events are a native Salesforce eventing mechanism, purpose-built for cross-system event propagation. |
| Traces to | PD-02, AC-01, AC-09, FR-01, FR-09 |

### ADR-003: Error Handling and Resilience Strategy

| Field | Value |
|---|---|
| Status | Accepted |
| Context | The exp-api is an event-driven consumer. Events arrive continuously from Salesforce Platform Events. Failures can occur at multiple points: PE payload validation, idempotency check, prc-api invocation, and internal processing. The architecture must ensure no consent event is silently lost (compliance requirement — a missed opt-in means MC cannot send the double opt-in SMS, which is a TCPA violation). |
| Decision | Implement a multi-layered resilience strategy: (1) **Validation failures** → route to DLQ with error metadata; (2) **Idempotent duplicates** → acknowledge and discard (200 OK, no downstream call); (3) **prc-api failures** → retry once with 2-second backoff, then DLQ on second failure; (4) **Circuit breaker** on prc-api call: open after 5 consecutive failures in 60 seconds, half-open after 120 seconds; (5) **PE ReplayId tracking** → persist last committed ReplayId to Object Store, resubscribe from last position on restart; (6) **Dead-letter queue** via Anypoint MQ with manual reprocessing capability. |
| Rationale | **Defense in depth:** Each failure mode has a specific handler. No silent drops. **DLQ as safety net:** Events that cannot be processed immediately are stored durably for later reprocessing. Anypoint MQ provides visibility (queue depth, message age) and reprocessing (redrive to main queue). **Circuit breaker as upstream protection:** If prc-api is down, continuous retries waste resources and create backlog. Circuit breaker stops attempting calls, routes to DLQ, and periodically checks if prc-api has recovered. **Idempotency as dedup guard:** At-least-once PE delivery + consumer restarts can cause duplicate processing. Composite dedup key (ConsentId + Status + Timestamp) in Object Store provides a lightweight, native dedup mechanism. **ReplayId persistence as durability guard:** On consumer restart, the last committed ReplayId ensures no events are skipped (within the 72-hour PE retention window). |
| Alternatives Considered | **(A1) Infinite retry with exponential backoff (no DLQ):** Rejected — blocks the main event processing flow during extended outages. A 2-hour prc-api outage would create a massive backlog that delays all consent events. DLQ decouples failure recovery from main flow. **(A2) Synchronous retry with 3 attempts:** Considered — 3 retries add 6-10 seconds of latency per event during failure. Rejected in favor of 1 retry + DLQ for faster failure isolation. **(A3) Database-backed error table (instead of Anypoint MQ):** Rejected — requires additional infrastructure (database). Anypoint MQ is native to MuleSoft platform, provides built-in monitoring, and supports message reprocessing without custom code. **(A4) No circuit breaker (rely on DLQ alone):** Rejected — without circuit breaker, the exp-api would continue hammering a failing prc-api, creating unnecessary network traffic and log noise. Circuit breaker provides fast-fail during outages. |
| Consequences | Anypoint MQ license required (confirm with MuleSoft admin). Object Store capacity needed for dedup keys and ReplayId (minimal — O(1000s) of entries). Circuit breaker adds state management complexity. DLQ reprocessing requires an operational runbook and team training. |
| Idempotency Key Design | `{ConsentId__c}:{ConsentStatus__c}:{EventTimestamp}` — stored in Object Store with 24-hour TTL. Lookup on each event; if key exists, event is acknowledged as duplicate. |
| Retry Policy | 1 retry with 2-second fixed backoff. On second failure → DLQ. Circuit breaker overrides retry when open. |
| Circuit Breaker Config | **Failure threshold:** 5 consecutive failures in 60-second window. **Open duration:** 120 seconds. **Half-open:** Allow 1 test request. If succeeds, close circuit. If fails, re-open for 120s. |
| Anti-Pattern Gate | AP-09 (omits operational consequences): **PASSED** — full DLQ reprocessing, alerting, and runbook documented. |
| Traces to | PD-03, PD-04, AC-05, AC-06, AC-09, AC-13, FR-05, FR-06, FR-09, R-06, R-11 |

### ADR-004: MC Classic REST API vs MC Connect Managed Package for SMS Opt-In

| Field | Value |
|---|---|
| Status | Accepted |
| Context | Marketing Cloud SMS capabilities can be accessed two ways: (1) **MC Connect managed package (et4ae5):** installed in DevInt2, provides in-Salesforce SMS sending via SMSDefinition objects and Journey Builder integration; (2) **MC Classic REST API:** direct HTTP API for triggering SMS sends, managing subscribers, and interacting with MC programmatically. The double opt-in flow requires: trigger an SMS send to a specific phone number, wait for reply, and update consent status. |
| Decision | Use **MC Classic REST API** via MuleSoft sys-api (NGASIM-3143), not the MC Connect managed package. |
| Rationale | **1. Event-driven automation:** MC Connect is designed for user-initiated sends (agent clicks "Send Email/SMS" in SF) or Journey Builder triggers (record update in SF → journey entry). It does not support platform event-triggered SMS sends natively. There is no MC Connect API that accepts a custom PE payload and triggers an SMS send. **2. Custom double opt-in flow:** The double opt-in pattern requires: (a) send confirmation SMS, (b) monitor for reply, (c) update consent status. MC Connect's SMS functionality is template-based (SMSDefinition) and does not expose the reply-monitoring capability programmatically from SF. MC Classic REST API provides the `/messaging/v1/sms/messages/` endpoint for triggering sends and the `/interaction/v1/events` endpoint for firing journey events that include reply monitoring. **3. API-led decoupling:** Using MC Classic REST API through MuleSoft sys-api provides clean decoupling. The sys-api owns the MC API contract, auth token management, and rate limiting. Changes to MC API versions or endpoints are isolated to sys-api. MC Connect tightly couples SF org to MC business unit — changes require package upgrades. **4. Reusability:** The sys-api can serve other MC integrations (email consent, marketing campaign triggers, subscriber management) using the same OAuth2 token management and API client. MC Connect is limited to its managed package capabilities. **5. Consent-as-data vs consent-as-action:** MC Connect treats SMS as an action ("send this message now"). The consent event pattern treats consent as data that flows between systems. MC Classic REST API supports both paradigms. MC Connect only supports the action paradigm. |
| Alternatives Considered | **(A1) MC Connect managed package (et4ae5):** Rejected — reasons above. MC Connect is the right choice for user-driven, template-based sends from within SF UI. Not for event-driven, automated consent propagation. **(A2) MC SOAP API:** Rejected — legacy. MC Classic REST API is the modern standard. SOAP API has been superseded for most use cases. **(A3) MC Transactional Messaging API:** Considered — this is the newer API for transactional messages (including SMS). May be more appropriate than Classic API for double opt-in. **Recommendation:** sys-api team (NGASIM-3143) should evaluate Transactional Messaging API (`/messaging/v1/sms/messages/`) vs Journey Builder Event API (`/interaction/v1/events`) as the specific endpoint. Both are accessible via MC REST API. **(A4) Direct SF-to-MC via Named Credential:** Rejected — bypasses MuleSoft integration layer. Couples SF transaction to MC API availability. Cannot implement retry, DLQ, or circuit breaker in SF Apex without significant complexity. |
| Consequences | MuleSoft-to-MC OAuth2 authentication required (client credentials flow). MC API rate limits apply (~2000 calls/hour estimate — varies by MC edition). Sys-api must implement rate limiting and throttling. MC REST API version changes require sys-api updates (isolated from exp-api/prc-api). MC sandbox required for integration testing. |
| MC Connect Role | MC Connect (et4ae5) remains valuable for user-driven email/SMS sends from the SF UI. It coexists with the API-led integration. They serve different use cases and should not conflict. |
| Anti-Pattern Gate | AP-02 (defaults to custom build without OOTB comparison): **PASSED** — MC Connect OOTB evaluated and rejected with specific rationale. Custom MuleSoft integration justified for event-driven, automated consent propagation. |
| Traces to | PD-06, T-06, FR-04, R-05, R-07 |

---

## Object Model

### ContactPointTypeConsent (Salesforce — Source of Truth)

| Field API Name | Type | Relevance to Integration |
|---|---|---|
| Id | ID | Primary key. Propagated as ConsentId in PE payload. |
| Name | String | Human-readable consent record name. |
| PartyId | Lookup (Contact/Lead) | The person who gave/revoked consent. Maps to MC SubscriberKey via identity resolution. |
| DataUsePurposeId | Lookup (DataUsePurpose) | The purpose of the consent (e.g., "SMS Marketing", "Transactional SMS"). Used to determine consent channel. |
| CaptureContactPointType | Picklist | The contact point type (Phone, Email, Web, etc.). Filtered for Phone/SMS. |
| CaptureDate | DateTime | When consent was captured. Propagated for audit trail. |
| CaptureSource | String | How consent was captured (webform, agent, lead creation). |
| EffectiveFrom | Date | When consent becomes active. |
| EffectiveTo | Date | When consent expires (if applicable). |
| Status | Picklist | Consent status: OptIn, OptOut, Pending, Expired. PE fires on transition to OptIn. |
| ContactPointTypeConsentHistory | Related | Audit trail of all status changes. Available in DevInt2. |

### Platform Event Payload (published by NGASIM-3058)

**Assumed schema** (to be confirmed with SF dev team — OQ-01):

| Field | Type | Required | Description |
|---|---|---|---|
| ConsentId__c | String(18) | Yes | SF ContactPointTypeConsent.Id |
| ConsentStatus__c | String | Yes | "OptIn" (trigger fires only on opt-in for SMS) |
| Phone__c | String | Yes | Patient/provider phone number (E.164 format expected) |
| ConsentChannel__c | String | Yes | "SMS" |
| PartyId__c | String(18) | Yes | SF Contact.Id or Lead.Id |
| PartyType__c | String | Yes | "Contact" or "Lead" |
| CaptureDate__c | DateTime | Yes | When consent was captured |
| CaptureSource__c | String | No | Webform, Agent, LeadCreation, etc. |
| DataUsePurposeId__c | String(18) | No | SF DataUsePurpose.Id |
| ReplayId | Long | System | Platform Event replay identifier (auto-assigned) |
| CreatedDate | DateTime | System | PE publication timestamp (auto-assigned) |

### Exp-API Canonical Consent Event Format (RAML Data Type)

```yaml
#%RAML 1.0 DataType

displayName: ConsentEvent
description: Canonical SMS consent event format for the consent processing pipeline
type: object
properties:
  consentId:
    type: string
    description: Salesforce ContactPointTypeConsent record ID
    pattern: "^[a-zA-Z0-9]{15,18}$"
    required: true
  consentStatus:
    type: string
    description: Consent status that triggered the event
    enum: [OptIn, OptOut, Pending, Confirmed, Expired]
    required: true
  phone:
    type: string
    description: Patient/provider phone number in E.164 format
    pattern: "^\\+[1-9]\\d{1,14}$"
    required: true
  consentChannel:
    type: string
    description: Communication channel for this consent
    enum: [SMS, Email, Push, Web]
    required: true
  partyId:
    type: string
    description: Salesforce Contact or Lead record ID
    pattern: "^[a-zA-Z0-9]{15,18}$"
    required: true
  partyType:
    type: string
    description: Type of the party record
    enum: [Contact, Lead]
    required: true
  captureDate:
    type: datetime
    description: When the consent was originally captured
    required: true
  captureSource:
    type: string
    description: How consent was captured
    enum: [Webform, Agent, LeadCreation, BulkImport, API]
    required: false
  dataUsePurposeId:
    type: string
    description: Salesforce DataUsePurpose record ID
    required: false
  metadata:
    type: object
    description: Integration metadata
    properties:
      correlationId:
        type: string
        description: Unique correlation ID for end-to-end tracing
        required: true
      sourceReplayId:
        type: integer
        description: Original Salesforce Platform Event ReplayId
        required: true
      sourceTimestamp:
        type: datetime
        description: PE publication timestamp
        required: true
      processedTimestamp:
        type: datetime
        description: When exp-api processed this event
        required: true
    required: true
```

### DataWeave Transformation Map (SF PE → Canonical)

| SF PE Field | Canonical Field | Transformation |
|---|---|---|
| ConsentId__c | consentId | Direct mapping |
| ConsentStatus__c | consentStatus | Direct mapping (validate against enum) |
| Phone__c | phone | Validate E.164 format; normalize if needed |
| ConsentChannel__c | consentChannel | Direct mapping (validate = "SMS") |
| PartyId__c | partyId | Direct mapping |
| PartyType__c | partyType | Direct mapping (validate against enum) |
| CaptureDate__c | captureDate | ISO 8601 DateTime formatting |
| CaptureSource__c | captureSource | Map to enum (or null if not provided) |
| DataUsePurposeId__c | dataUsePurposeId | Direct mapping (or null if not provided) |
| ReplayId (system) | metadata.sourceReplayId | Direct mapping |
| CreatedDate (system) | metadata.sourceTimestamp | Direct mapping |
| — (generated) | metadata.correlationId | UUID v4 generated by exp-api |
| — (generated) | metadata.processedTimestamp | Current timestamp at processing time |

### DataWeave Transformation (pseudo-code)

```dataweave
%dw 2.0
output application/json
---
{
  consentId: payload.ConsentId__c,
  consentStatus: payload.ConsentStatus__c,
  phone: payload.Phone__c,
  consentChannel: payload.ConsentChannel__c,
  partyId: payload.PartyId__c,
  partyType: payload.PartyType__c,
  captureDate: payload.CaptureDate__c as DateTime,
  captureSource: payload.CaptureSource__c default null,
  dataUsePurposeId: payload.DataUsePurposeId__c default null,
  metadata: {
    correlationId: uuid(),
    sourceReplayId: payload.ReplayId as Number,
    sourceTimestamp: payload.CreatedDate as DateTime,
    processedTimestamp: now()
  }
}
```

---

## Sequence Diagram

### Happy Path: SMS Consent Opt-In → MC Double Opt-In Trigger

```
┌─────────┐  ┌───────────────┐  ┌────────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐
│ SF User  │  │ SF Platform   │  │ exp-api    │  │ prc-api  │  │ sys-api  │  │ MC Classic │
│ (Agent/  │  │ (Apex Trigger │  │ (NGASIM-   │  │ (NGASIM- │  │ (NGASIM- │  │ REST API   │
│  Webform)│  │  + PE)        │  │  3336)     │  │  3335)   │  │  3143)   │  │            │
└────┬─────┘  └──────┬────────┘  └─────┬──────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘
     │               │                 │               │              │              │
     │ 1. Create/Update               │               │              │              │
     │ ContactPointTypeConsent         │               │              │              │
     │ (Status=OptIn, Channel=SMS)     │               │              │              │
     │──────────────▶│                 │               │              │              │
     │               │                 │               │              │              │
     │               │ 2. Apex trigger fires           │              │              │
     │               │ Publishes PE with               │              │              │
     │               │ consent payload                 │              │              │
     │               │────────────────▶│               │              │              │
     │               │  (Pub/Sub API)  │               │              │              │
     │               │                 │               │              │              │
     │               │                 │ 3. Receive PE │              │              │
     │               │                 │ Validate payload             │              │
     │               │                 │ (required fields,            │              │
     │               │                 │  SMS channel filter)         │              │
     │               │                 │               │              │              │
     │               │                 │ 4. Check idempotency         │              │
     │               │                 │ (Object Store lookup)        │              │
     │               │                 │ Key not found = new event    │              │
     │               │                 │               │              │              │
     │               │                 │ 5. Transform  │              │              │
     │               │                 │ SF PE → Canonical            │              │
     │               │                 │ (DataWeave)   │              │              │
     │               │                 │               │              │              │
     │               │                 │ 6. Generate   │              │              │
     │               │                 │ X-Correlation-ID             │              │
     │               │                 │               │              │              │
     │               │                 │ 7. POST canonical            │              │
     │               │                 │ consent event │              │              │
     │               │                 │──────────────▶│              │              │
     │               │                 │               │              │              │
     │               │                 │               │ 8. Validate  │              │
     │               │                 │               │ consent state│              │
     │               │                 │               │ (not already │              │
     │               │                 │               │  opted-in)   │              │
     │               │                 │               │              │              │
     │               │                 │               │ 9. Resolve   │              │
     │               │                 │               │ PartyId →    │              │
     │               │                 │               │ MC Subscriber│              │
     │               │                 │               │ Key          │              │
     │               │                 │               │              │              │
     │               │                 │               │ 10. POST     │              │
     │               │                 │               │ MC-ready     │              │
     │               │                 │               │ payload      │              │
     │               │                 │               │─────────────▶│              │
     │               │                 │               │              │              │
     │               │                 │               │              │ 11. OAuth2   │
     │               │                 │               │              │ token fetch  │
     │               │                 │               │              │─────────────▶│
     │               │                 │               │              │  POST /auth  │
     │               │                 │               │              │◀─────────────│
     │               │                 │               │              │  Bearer token│
     │               │                 │               │              │              │
     │               │                 │               │              │ 12. POST SMS │
     │               │                 │               │              │ opt-in trigger│
     │               │                 │               │              │─────────────▶│
     │               │                 │               │              │  /messaging/ │
     │               │                 │               │              │  v1/sms/     │
     │               │                 │               │              │  messages/   │
     │               │                 │               │              │              │
     │               │                 │               │              │◀─────────────│
     │               │                 │               │              │  202 Accepted│
     │               │                 │               │              │  + requestId │
     │               │                 │               │◀─────────────│              │
     │               │                 │               │  200 OK      │              │
     │               │                 │◀──────────────│              │              │
     │               │                 │  202 Accepted │              │              │
     │               │                 │               │              │              │
     │               │                 │ 13. Store dedup│              │              │
     │               │                 │ key in Object  │              │              │
     │               │                 │ Store (24h TTL)│              │              │
     │               │                 │               │              │              │
     │               │                 │ 14. Commit     │              │              │
     │               │                 │ ReplayId to    │              │              │
     │               │                 │ Object Store   │              │              │
     │               │                 │               │              │              │
     │               │                 │ 15. Log with   │              │              │
     │               │                 │ correlation ID │              │              │
     │               │                 │ (phone masked) │              │              │
```

### Error Path: prc-api Failure → DLQ

```
┌──────────┐  ┌──────────┐  ┌─────────┐  ┌────────────────┐
│ SF PE    │  │ exp-api  │  │ prc-api │  │ Anypoint MQ    │
│          │  │          │  │         │  │ (DLQ)          │
└────┬─────┘  └────┬─────┘  └────┬────┘  └───────┬────────┘
     │              │             │                │
     │ PE event     │             │                │
     │─────────────▶│             │                │
     │              │             │                │
     │              │ Validate ✓  │                │
     │              │ Dedup ✓     │                │
     │              │ Transform ✓ │                │
     │              │             │                │
     │              │ POST to     │                │
     │              │ prc-api     │                │
     │              │────────────▶│                │
     │              │             │                │
     │              │◀────────────│                │
     │              │ 503 Service │                │
     │              │ Unavailable │                │
     │              │             │                │
     │              │ Retry (2s   │                │
     │              │ backoff)    │                │
     │              │────────────▶│                │
     │              │             │                │
     │              │◀────────────│                │
     │              │ 503 again   │                │
     │              │             │                │
     │              │ Route to DLQ│                │
     │              │─────────────────────────────▶│
     │              │             │                │ Stored:
     │              │             │                │ - original payload
     │              │             │                │ - error: "prc-api 503"
     │              │             │                │ - correlation ID
     │              │             │                │ - attempt count: 2
     │              │             │                │ - timestamp
     │              │             │                │
     │              │ Commit      │                │
     │              │ ReplayId    │                │
     │              │ (event      │                │
     │              │  processed, │                │
     │              │  not lost)  │                │
```

### Error Path: Circuit Breaker Open

```
┌──────────┐  ┌──────────┐  ┌─────────┐  ┌────────────────┐
│ SF PE    │  │ exp-api  │  │ prc-api │  │ Anypoint MQ    │
│ (events  │  │ (circuit │  │ (DOWN)  │  │ (DLQ)          │
│  stream) │  │  breaker)│  │         │  │                │
└────┬─────┘  └────┬─────┘  └────┬────┘  └───────┬────────┘
     │              │             │                │
     │ Events 1-5   │             │                │
     │─────────────▶│────────────▶│ (all fail)     │
     │              │◀────────────│ 503 × 5        │
     │              │             │                │
     │              │ CIRCUIT     │                │
     │              │ BREAKER     │                │
     │              │ OPENS       │                │
     │              │             │                │
     │ Events 6-N   │             │                │
     │─────────────▶│             │                │
     │              │ Fast-fail   │                │
     │              │ (no prc-api │                │
     │              │  attempt)   │                │
     │              │─────────────────────────────▶│ Direct to DLQ
     │              │             │                │
     │              │ ... 120 seconds later ...    │
     │              │             │                │
     │              │ HALF-OPEN   │                │
     │ Event N+1    │             │                │
     │─────────────▶│────────────▶│                │
     │              │             │                │
     │              │◀────────────│                │
     │              │ 200 OK      │                │
     │              │             │                │
     │              │ CIRCUIT     │                │
     │              │ CLOSES      │                │
     │              │             │                │
     │ Normal flow  │             │                │
     │ resumes      │             │                │
```

---

## Security Architecture

### Authentication and Authorization

| Boundary | Mechanism | Details |
|---|---|---|
| **SF → MuleSoft** (PE subscription) | OAuth2 JWT Bearer (Connected App) | MuleSoft Salesforce Connector authenticates to SF Pub/Sub API using a Connected App with JWT Bearer flow. The Connected App must have: (a) "Access and manage your data (api)" scope, (b) "Perform requests at any time (refresh_token, offline_access)" scope, (c) the integration user profile must have "Subscribe to Platform Events" permission. Private key stored in MuleSoft Secure Configuration Properties. |
| **exp-api → prc-api** (internal MuleSoft) | Anypoint Platform Client Credentials | Internal MuleSoft API-to-API call. Secured via Anypoint API Manager client ID enforcement policy. Client credentials stored in Secure Properties. |
| **sys-api → MC** (MC Classic REST API) | OAuth2 Client Credentials | MC REST API requires OAuth2 token from `/auth/v2/token` endpoint. Client ID and Client Secret provisioned in MC Setup → Installed Packages. Token cached by sys-api (TTL = token expiry - 60s buffer). Credentials stored in MuleSoft Secure Configuration Properties. |

### PII Handling

| Data Element | Classification | Handling |
|---|---|---|
| Phone number (Phone__c) | PII (HIPAA-adjacent for patient communication) | **In transit:** TLS 1.2+ encryption on all boundaries. **In MuleSoft:** Masked in application logs (AC-11). DataWeave masking function: `payload.phone replace /\d(?=\d{4})/ with "*"` → `***-***-1234`. **In Object Store:** Dedup key does NOT contain phone number (uses ConsentId + Status + Timestamp). **In DLQ:** Full payload stored (DLQ is encrypted at rest in Anypoint MQ). Access restricted to operations team. |
| Consent status | Sensitive (regulatory) | Not PII, but regulatory. Logged for audit trail. Not masked. |
| PartyId (Contact/Lead ID) | Internal identifier | Not PII itself, but links to PII records. Logged for traceability. |
| Correlation ID | System metadata | Not sensitive. Logged everywhere for tracing. |

### Consent Audit Trail

The end-to-end audit trail for a single consent event:

| Step | System | Audit Data | Storage |
|---|---|---|---|
| 1. Consent created | SF | ContactPointTypeConsentHistory (standard) | SF database |
| 2. PE published | SF | PE ReplayId + CreatedDate | SF PE log (72h retention) |
| 3. exp-api received | MuleSoft | Correlation ID + ReplayId + timestamp + processing result | CloudHub logs (30-day retention) |
| 4. prc-api processed | MuleSoft | Correlation ID + business rule outcome | CloudHub logs |
| 5. sys-api sent to MC | MuleSoft | Correlation ID + MC API requestId + HTTP status | CloudHub logs |
| 6. MC received | MC | MC requestId + SMS send status | MC tracking data |

### Threat Model (Consent-Specific)

| Threat | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Consent event interception in transit** | Low | High | TLS 1.2+ on all boundaries. MuleSoft VPC for internal traffic. |
| **Replay attack (malicious PE republish)** | Very Low | Medium | PE can only be published by Apex code with appropriate permissions. Idempotency prevents duplicate processing. |
| **Unauthorized access to DLQ** | Low | High | Anypoint MQ access controlled by Anypoint Platform roles. DLQ messages encrypted at rest. |
| **Consent status tampering** | Low | Critical | SF ContactPointTypeConsent has field-level security. PE payload is read-only from MuleSoft perspective. MuleSoft does not write back to SF in this flow. |
| **MC SubscriberKey collision** | Medium | High | If SF PartyId → MC SubscriberKey mapping is not 1:1, wrong subscriber may receive double opt-in SMS. Identity resolution must be verified (prc-api responsibility). |

---

## Expert Context Block

### Platform Fit Reasoning

This architecture is optimal for the Salesforce-MuleSoft-Marketing Cloud ecosystem because:

1. **Platform Events are the idiomatic SF mechanism** for publishing domain events to external systems. They are transaction-safe (committed with the DML), governor-limit-friendly (count toward PE limits, not callout limits), and provide built-in replay durability (72-hour retention). Using PE instead of direct callouts keeps the Salesforce transaction clean and decoupled from downstream availability.

2. **MuleSoft API-led connectivity** is the Salesforce-endorsed integration pattern for cross-cloud orchestration. The exp/prc/sys decomposition maps naturally to the consent domain: event normalization (exp), consent business rules (prc), MC API encapsulation (sys). This is not over-engineering — each layer has a distinct, testable responsibility and a documented reuse path.

3. **MC Classic REST API** is the appropriate choice for programmatic SMS operations. MC Connect (et4ae5) serves a different purpose (UI-driven sends, Journey Builder triggers). The Classic REST API provides the flexibility needed for event-driven double opt-in flows with custom payload formatting.

### Key Tradeoffs Considered

| Decision | Tradeoff |
|---|---|
| 3-layer vs 2-layer MuleSoft | Added operational complexity (3 deployments) vs cleaner separation of concerns and reuse. Chose 3-layer because consent business rules and MC API specifics are distinct domains. |
| PE vs CDC | Selective, domain-meaningful events (PE) vs comprehensive change stream (CDC). Chose PE because only SMS opt-in events are relevant — CDC would generate 10x noise. |
| Object Store vs Redis for dedup | Native simplicity (Object Store) vs higher performance (Redis). Chose Object Store because expected volume (< 1000 events/day) is well within Object Store capacity. Redis adds infrastructure. |
| DLQ + async retry vs inline retry | Faster recovery (inline) vs non-blocking processing (DLQ). Chose DLQ because blocking retries delay all subsequent events during outages. |

### Anti-Patterns Avoided

1. **AP-01: Treating SF as generic app platform** — Used native Platform Events, not custom HTTP polling or database polling.
2. **AP-02: Defaulting to custom build** — Evaluated MC Connect OOTB. Rejected with specific rationale (does not support event-driven SMS double opt-in).
3. **AP-04: Data duplication without SOT** — Explicitly declared ContactPointTypeConsent as source of truth. MC subscriber consent is derived state.
4. **AP-05: MuleSoft layering without reuse value** — Documented reuse paths for email/marketing consent (prc-api) and other MC integrations (sys-api).
5. **AP-08: Ignoring consent/identity in cross-cloud** — Consent is the core domain. Identity alignment flagged. Audit trail designed.
6. **AP-09: Omitting operational consequences** — DLQ, monitoring, alerting, health check, replay recovery, and operational runbook all specified.
7. **AP-10: Avoiding rejected alternatives** — MC Connect, direct callout, CDC, single API, 2-layer pattern all evaluated and rejected with rationale.

### Cross-Cloud Constraints

- **SF PE retention:** 72 hours. If MuleSoft consumer is offline for >72h, events are permanently lost. Monitoring must alert on consumer lag.
- **MC API rate limits:** Classic REST API has per-BU rate limits (~2000 calls/hour). Sys-api must throttle. Circuit breaker at exp-api provides upstream backpressure.
- **MC SubscriberKey:** Must exist in MC All Subscribers before SMS can be sent. If patient is new to MC, subscriber creation must precede SMS trigger. Prc-api must handle this sequence.
- **Consent bidirectionality:** MC maintains its own subscriber consent state. If patient replies "YES" to double opt-in SMS, MC updates locally. This confirmation must eventually flow back to SF ContactPointTypeConsent. **No story exists for this return path.** This is a known architectural gap.

### Re-Architecture Triggers

| Trigger | Impact | Likelihood |
|---|---|---|
| MC Classic REST API deprecation | Sys-api refactor to new API. Exp-api and prc-api unaffected (layering benefit). | Low (2-3 year horizon) |
| Data Cloud adoption for consent | PE-based flow may be superseded by Data Cloud ingestion connector → MC activation. Fundamental architecture change. | Medium (depends on DC roadmap) |
| Return path requirement (MC → SF) | New MuleSoft flow: MC webhook/PE → MuleSoft → SF ContactPointTypeConsent update. Bidirectional sync complexity. | High (double opt-in is incomplete without it) |
| Event volume > 10,000/day | Object Store dedup may need migration to distributed cache. CloudHub worker scaling needed. | Low (current estimates < 1000/day) |
| Multi-channel expansion (email + marketing consent) | Prc-api extended with channel routing. New exp-api instances for email triggers. Sys-api extended with email API endpoints. | Medium (parent feature NGASIM-28 includes email) |

---

## CTA Domain Coverage Matrix

| # | Domain | Rating | Evidence |
|---|---|---|---|
| 1 | **Business Architecture** | ADDRESSED | Consent capture mapped as core business capability in Lead-to-Patient lifecycle. KPI: double opt-in completion rate. Business value: TCPA compliance, patient communication enablement. |
| 2 | **Solution Architecture** | ADDRESSED | End-to-end flow designed: SF → MuleSoft (3 layers) → MC. 4 ADRs with alternatives considered. API-led pattern justified. MC Connect evaluated and rejected. |
| 3 | **Platform Architecture** | ADDRESSED | Platform Events (SF native), MuleSoft CloudHub 2.0, MC Classic REST API. PE delivery semantics analyzed. CloudHub worker sizing estimated. Governor limits assessed. |
| 4 | **Security/Identity** | ADDRESSED | OAuth2 at all boundaries. PII masking for phone numbers. Consent audit trail designed. MC SubscriberKey identity alignment flagged. Threat model documented. |
| 5 | **Core Data** | ADDRESSED | ContactPointTypeConsent as SOT. Consent status lifecycle defined. MC subscriber consent as derived state. Bidirectional sync risk flagged. Data duplication anti-pattern addressed. |
| 6 | **Integration/MuleSoft** | ADDRESSED (Primary) | API-led connectivity (exp/prc/sys). Contract-first RAML. Idempotency, DLQ, circuit breaker, retry, replay. Bounded context: consent domain. Reuse paths documented. |
| 7 | **Application/UX/Automation** | MINIMAL (appropriate) | No UI component. Apex trigger automation is upstream (NGASIM-3058). MuleSoft is headless integration. No automation density concerns — single trigger, single PE, single flow per layer. |
| 8 | **Delivery/Testing/ALM** | ADDRESSED | 4-phase delivery plan. MUnit testing strategy. Integration test plan. Load testing defined. Deployment sequencing (SF → exp-api → prc-api → sys-api). Rollback: redeploy previous MuleSoft version. |
| 9 | **Cross-Cloud** | ADDRESSED | SF Core + MuleSoft + Marketing Cloud. Identity alignment flagged. Consent propagation designed. Data Cloud flagged as future consideration. Return path gap documented. |

---

## Scale & Performance Architecture

### Event Volume Estimates

| Metric | Estimate | Basis |
|---|---|---|
| Daily consent events (average) | 200-500 | Based on daily lead creation volume + existing consent capture patterns |
| Daily consent events (peak — marketing campaign) | 2,000-5,000 | Bulk webform submissions during marketing campaigns |
| Burst rate (1-minute peak) | 500 events/minute | Marketing campaign launch + batch consent processing |
| Monthly total | 6,000-15,000 | 200-500/day × 30 days |

### Capacity Planning

| Component | Capacity | Headroom |
|---|---|---|
| **SF Platform Events** | 100,000 PE/hour (Enterprise Edition) | Well within limits even at peak burst |
| **MuleSoft CloudHub worker** | ~100 events/second per 0.2 vCore worker | Single worker handles 500/min burst with 3x headroom |
| **Object Store v2** | 100,000 keys per partition, 10 MB per key | Dedup keys are < 100 bytes. 24h TTL keeps store small. |
| **Anypoint MQ** | 2,000 messages/second per queue | DLQ volume should be < 1% of main flow. Well within limits. |
| **MC Classic REST API** | ~2,000 calls/hour per BU (estimated) | At 500 events/min burst, sys-api would exceed MC rate limits. Throttling required at sys-api layer. **Risk: MC rate limit is the bottleneck.** |

### Latency Budget

| Step | Target Latency | Cumulative |
|---|---|---|
| SF DML → PE publication | < 100ms | 100ms |
| PE → MuleSoft delivery (Pub/Sub API) | < 1,000ms | 1,100ms |
| exp-api validation + dedup + transform | < 200ms | 1,300ms |
| exp-api → prc-api HTTP call | < 500ms | 1,800ms |
| prc-api business rules + identity resolution | < 1,000ms | 2,800ms |
| prc-api → sys-api HTTP call | < 500ms | 3,300ms |
| sys-api OAuth2 token (cached) + MC API call | < 1,500ms | 4,800ms |
| **Total end-to-end** | **< 5,000ms** | **Target met** |

### Bottleneck Analysis

| Bottleneck | Risk | Mitigation |
|---|---|---|
| **MC Classic REST API rate limit** | HIGH — if burst exceeds MC rate limit, sys-api receives 429 responses. Backpressure propagates to exp-api via circuit breaker. | Sys-api implements token bucket rate limiter. Exp-api circuit breaker routes to DLQ during MC throttling. DLQ reprocessed when MC rate limit resets. |
| **Object Store latency** | LOW — Object Store v2 has < 50ms read/write latency. Dedup check adds minimal overhead. | Monitor Object Store latency. Failover: skip dedup check if Object Store is unavailable (accept potential duplicates). |
| **PE Pub/Sub API latency** | LOW — gRPC-based Pub/Sub API has < 1s delivery latency for standard volumes. | Monitor PE consumer lag via health check endpoint. Alert on lag > 5 minutes. |
| **prc-api identity resolution** | MEDIUM — if PartyId → MC SubscriberKey lookup requires SOQL or MC API call, latency may increase. | Prc-api should cache SubscriberKey mappings. Design for lookup failure: DLQ if SubscriberKey cannot be resolved. |

---

## Deployment Architecture

### Environment Chain

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ SF Sandbox   │    │ MuleSoft     │    │ MC Sandbox   │
│ (DevInt2 -   │    │ CloudHub     │    │              │
│  read-only)  │    │ Sandbox      │    │              │
│              │    │              │    │              │
│ NGASIM-3058  │───▶│ exp-api      │───▶│ SMS endpoint │
│ PE publish   │    │ prc-api      │    │              │
│              │    │ sys-api      │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
       │                   │                    │
       │    DEPLOY SEQUENCE: SF first → MuleSoft → MC config
       ▼                   ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ SF Prod      │    │ MuleSoft     │    │ MC Prod      │
│              │    │ CloudHub     │    │              │
│              │    │ Production   │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
```

### Deployment Sequence

1. **SF first:** NGASIM-3058 Apex trigger must be deployed and verified (PE publishing confirmed)
2. **MuleSoft layers (bottom-up):** sys-api → prc-api → exp-api (sys-api deployed first because prc-api depends on it; exp-api deployed last because it depends on prc-api)
3. **MC configuration:** Verify MC SMS capability, SubscriberKey alignment, double opt-in journey configuration
4. **Integration verification:** End-to-end smoke test from SF consent creation to MC SMS trigger

### Rollback Strategy

| Component | Rollback Method | RTO |
|---|---|---|
| exp-api | Redeploy previous CloudHub version via Anypoint Runtime Manager | < 5 minutes |
| prc-api | Redeploy previous CloudHub version | < 5 minutes |
| sys-api | Redeploy previous CloudHub version | < 5 minutes |
| SF Apex trigger (NGASIM-3058) | Deactivate trigger via metadata deploy or quick deploy rollback | < 10 minutes |
| **Full rollback** | Deactivate SF trigger (stops PE publish). MuleSoft consumer gracefully stops. No consent events propagated until fixed. | < 15 minutes |

### Monitoring and Observability

| What to Monitor | Tool | Alert Threshold |
|---|---|---|
| PE consumer lag (events behind) | Anypoint Monitoring + health check | > 5 minutes lag |
| DLQ depth (unprocessed errors) | Anypoint MQ dashboard + API alert | > 10 messages |
| Processing latency (PE → ack) | Anypoint Monitoring (custom metric) | > 10 seconds average |
| Circuit breaker state | Health check endpoint (/health) | State = OPEN |
| CloudHub worker CPU/memory | Anypoint Monitoring | > 80% sustained |
| MC API error rate (429/5xx) | sys-api logging + Anypoint Monitoring | > 5% error rate |
| Object Store utilization | Anypoint Monitoring | > 80% capacity |
| Zero events processed in 1 hour | Custom alert (expected: > 0 during business hours) | 0 events in 60 min during 8am-8pm ET |

---

## Handoff to TDD

**Directive:** The tdd-guide agent must:

1. Write MUnit test specifications for all 15 ACs (AC-01 through AC-15).
2. Design test cases for DataWeave transformation: valid payload, missing required fields, invalid phone format, non-SMS channel, null optional fields.
3. Design test cases for idempotency: new event (process), duplicate event (skip), expired dedup key (process again).
4. Design test cases for error handling: validation failure → DLQ, prc-api timeout → retry + DLQ, prc-api 503 → retry + DLQ, circuit breaker open → fast-fail to DLQ.
5. Design test cases for PE replay recovery: stop consumer → publish events → restart → verify catch-up from last committed ReplayId.
6. Design test cases for PII masking: verify phone numbers are masked in all log output.
7. Design test cases for health check: healthy state (all green), degraded state (DLQ depth > 0), unhealthy state (PE subscription down).
8. Define test data factory for PE payloads (valid, invalid, edge cases).
9. Estimate coverage targets: 90%+ MUnit coverage for all DataWeave modules and Mule flows.
10. Define integration test matrix for exp-api → prc-api mock and SF sandbox → exp-api.
