# NGASIM-3336: CODE REVIEW

> **Pipeline Stage:** 04-code-review
> **Produced by:** code-reviewer agent
> **Input:** 01-plan.md, 02-architecture.md, 03-tdd.md
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T21:02:00Z
> **Status:** COMPLETE — handed off to BUILD FIX

---

## Review Summary

| Severity | Count | Action Required |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 3 | Must resolve before deployment |
| MEDIUM | 4 | Should resolve; acceptable risk if deferred with justification |
| LOW | 3 | Address during implementation or defer to backlog |
| INFO | 2 | Advisory observations |
| **Total** | **12** | |

### Verdict: **CONDITIONAL PASS**

The exp-api design is architecturally sound as a MuleSoft API-led experience layer handling
Salesforce consent events. The RAML contract, DataWeave transformations, and error handling
(DLQ + circuit breaker + idempotency) follow MuleSoft best practices. However, three HIGH
findings require resolution: (1) platform event replay ID handling is not addressed — missed
events during MuleSoft downtime mean lost consent requests; (2) the idempotency ObjectStore
TTL and cluster consistency model is undefined, risking either false-positive rejections or
duplicate processing across CloudHub workers; (3) DLQ message format lacks operational replay
context, making incident recovery manual and error-prone.

The test suite (28 cases across 15 ACs) is comprehensive for unit and mock integration coverage.
The primary execution blocker is the upstream NGASIM-3058 (SF platform event trigger) and
downstream NGASIM-3335 (prc-api), both of which must be functional for live E2E validation.

---

## Findings

### F-01 — Platform Event Replay ID Handling Not Addressed — Missed Consent Events During Downtime

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Integration Resilience |
| AC Impacted | AC-01, AC-05, AC-08 |
| Source | 02-architecture.md (data flow), 03-tdd.md (no replay test) |
| Phase Impacted | Implementation |

**Description:**
The architecture specifies that Salesforce publishes ContactPointTypeConsentChangeEvent platform events, which MuleSoft consumes. However, the design does not address the **Replay ID** mechanism for Salesforce platform events. MuleSoft's Salesforce connector supports replay IDs to recover missed events after a subscriber disconnects (downtime, deployment, CloudHub restart). Without explicit replay ID management:

- Events published during MuleSoft exp-api downtime (CloudHub deployment, worker restart) are silently lost.
- Salesforce retains platform events for only 72 hours in the event bus. Events older than 72 hours are permanently unrecoverable.
- The idempotency check (AC-07) protects against duplicates but does nothing for missed events.

**Evidence:**
- 02-architecture.md data flow: "Platform Event published by Apex trigger (NGASIM-3058) → MuleSoft exp-api" — no mention of replay or redelivery.
- 03-tdd.md: No test case covering event replay after subscriber reconnection.
- MuleSoft Salesforce Connector documentation: replay ID must be persisted (ObjectStore or external DB) to survive worker restarts.

**Impact:**
A patient initiates SMS opt-in consent in Salesforce. The platform event fires, but MuleSoft is mid-deployment. The event is lost. The patient never receives the double opt-in SMS. The consent record shows "Opt In Pending" indefinitely — a dead state with no operational alert. At scale (e.g., consent campaign sending 5,000 opt-in requests), a 10-minute CloudHub deployment window could lose 50+ events.

**Recommendation:**
1. **Persist replay IDs** in Anypoint MQ or CloudHub ObjectStore (persistent). On reconnect, subscribe from last known replay ID.
2. **Implement a reconciliation job**: daily batch query of SF ContactPointTypeConsent WHERE ConsentStatus = 'Opt In Pending' AND LastModifiedDate < NOW()-24h → re-trigger via exp-api.
3. **Add TC-29**: test that after subscriber reconnection, events published during disconnect are replayed.
4. **Add monitoring alert**: count of 'Opt In Pending' records older than 4 hours → trigger investigation.

---

### F-02 — Idempotency ObjectStore TTL and Cluster Consistency Not Defined

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Data Integrity |
| AC Impacted | AC-07 |
| Source | 03-tdd.md TC-13, TC-14 |
| Phase Impacted | Implementation |

**Description:**
AC-07 requires idempotency based on ConsentId + timestamp composite key stored in ObjectStore. The design does not specify:

1. **TTL (Time-to-Live):** How long is the idempotency key retained? Too short (< 1 hour) and a retry storm from SF could cause duplicates. Too long (> 30 days) and ObjectStore growth is unbounded, eventually hitting CloudHub storage limits.
2. **Cluster consistency:** CloudHub 2.0 workers share ObjectStore, but in multi-worker deployments, there's a propagation delay. Two workers processing the same event simultaneously could both pass the idempotency check if the store-then-check pattern is not atomic.
3. **Key format:** Is the key `ConsentId:ConsentTimestamp` or a hash? Timestamps with timezone offsets could create false-negative duplicates (same event, different TZ representation).

**Evidence:**
- 03-tdd.md TC-13: Tests duplicate rejection but does not verify ObjectStore TTL behavior.
- 03-tdd.md TC-14: Tests same-ConsentId-different-timestamp acceptance — but what if timestamps differ only by milliseconds?
- Architecture: "idempotency via ConsentId + timestamp" — no TTL, no atomicity, no key normalization specified.

**Impact:**
Without atomic check-and-store, two CloudHub workers processing the same event concurrently could both route to prc-api, resulting in duplicate SMS sends to the patient. Conversely, if the ObjectStore TTL is too aggressive, legitimate re-consent events (same ConsentId, months later) would be incorrectly rejected as duplicates.

**Recommendation:**
1. **Set TTL to 7 days.** SF platform events are retained 72 hours; 7-day TTL provides margin for replay scenarios without unbounded growth.
2. **Use ObjectStore `store` with `failIfPresent: true`** for atomic check-and-store. If the key already exists, the store operation fails → return 409 immediately. This is natively atomic in CloudHub ObjectStore.
3. **Normalize the key:** `lower(ConsentId) ++ "|" ++ ConsentTimestamp as DateTime { format: "yyyy-MM-dd'T'HH:mm:ss'Z'" }` — normalize timezone to UTC before hashing.
4. **Add TC-29**: Test ObjectStore TTL expiry — verify that an event submitted after TTL expiry is accepted (not a duplicate).
5. **Add TC-30**: Test concurrent dual-worker idempotency — simulate two simultaneous requests with same key.

---

### F-03 — DLQ Message Format Lacks Operational Replay Context

| Field | Value |
|---|---|
| Severity | **HIGH** |
| Category | Operational Readiness |
| AC Impacted | AC-08 |
| Source | 03-tdd.md TC-15, 02-architecture.md |
| Phase Impacted | Implementation |

**Description:**
AC-08 specifies DLQ routing after 3 failed retries. The design does not define the DLQ message format. For operational replay (an SRE manually re-processing failed messages), the DLQ message must contain:

1. **Original payload** — the full SF consent event.
2. **Failure reason** — HTTP status code, error body, exception class.
3. **Retry count** — how many attempts were made.
4. **Correlation ID** — to trace back to the original request.
5. **Timestamp of last failure** — for SLA tracking (how long was the consent delayed?).
6. **Target endpoint** — which prc-api instance/URL failed.

Without this context, an SRE receiving a DLQ message cannot determine the failure cause, cannot replay without manual investigation, and cannot prioritize (is this a systemic MC outage or a single malformed event?).

**Evidence:**
- 03-tdd.md TC-15: Verifies DLQ publish is called once but does not assert message content.
- 02-architecture.md: "DLQ pattern" mentioned but no message schema defined.
- No DLQ consumer or replay mechanism documented.

**Impact:**
In a MC outage scenario, hundreds of consent events could land in the DLQ. Without structured metadata, replaying them requires an engineer to parse raw payloads, guess failure causes, and manually re-submit each event. Mean Time to Recovery (MTTR) increases from minutes (automated replay) to hours (manual).

**Recommendation:**
1. Define a DLQ message envelope:
```json
{
  "dlqMetadata": {
    "correlationId": "uuid",
    "failureReason": "HTTP 503 from prc-api",
    "retryCount": 3,
    "lastFailureTimestamp": "2026-03-25T21:00:00Z",
    "targetEndpoint": "https://prc-api.cloudhub.io/api/v1/consent/process",
    "originalRequestTimestamp": "2026-03-25T20:59:55Z"
  },
  "originalPayload": { ... full SF consent event ... }
}
```
2. **Add TC-31**: Assert DLQ message contains all 6 metadata fields.
3. **Design a DLQ replay flow**: scheduled job that reads from DLQ, validates the original payload is still relevant (ConsentStatus hasn't changed), and re-submits to prc-api.
4. **Add monitoring**: Anypoint MQ DLQ depth alert when messages > 10 in a 15-minute window.

---

### F-04 — Cross-Layer Contract Drift Risk Between exp-api and prc-api

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Integration Design |
| AC Impacted | AC-05 |
| Source | 02-architecture.md (API-led layers) |
| Phase Impacted | Implementation |

**Description:**
The exp-api transforms SF consent payloads and routes to prc-api (NGASIM-3335). The prc-api then routes to sys-api (NGASIM-3143). Each layer has its own RAML contract. The design does not specify:

1. **Contract versioning strategy:** What happens when prc-api adds a required field? Does exp-api break?
2. **Schema evolution rules:** Are new fields optional-first or required-first?
3. **Consumer-driven contract testing:** No Pact or similar CDC test defined between exp and prc layers.

The risk is amplified because exp-api, prc-api, and sys-api are developed as separate Jira stories (NGASIM-3336, NGASIM-3335, NGASIM-3143) likely by different developers. Without contract tests, a breaking change in prc-api silently breaks exp-api.

**Evidence:**
- 02-architecture.md: "API-Led Connectivity: 3 MuleSoft layers (exp/prc/sys)" — no contract versioning strategy.
- 03-tdd.md: Integration tests mock prc-api responses but do not verify the mock matches prc-api's actual RAML schema.
- No cross-story contract alignment artifact exists.

**Impact:**
A prc-api schema change (e.g., renaming `ConsentId` to `consentIdentifier`) causes exp-api to send unrecognized fields. The prc-api returns 400, exp-api retries 3 times, then DLQ-routes the message. All consent events fail silently until someone checks the DLQ.

**Recommendation:**
1. **Publish prc-api RAML as an Exchange asset.** exp-api imports prc-api's RAML fragment to validate request payloads at design time.
2. **Add a consumer-driven contract test** (TC-32): exp-api publishes expected prc-api request schema. prc-api CI pipeline validates against it. Any breaking change fails prc-api's build.
3. **Adopt RAML versioning:** `/api/v1/consent/process` — pin exp-api to a specific prc-api version. prc-api must maintain backward compatibility within a major version.
4. **Document the inter-API contract** in a shared Confluence page referenced by all three stories.

---

### F-05 — Consent Status Transition Validation is Stateless — No State Machine Enforcement

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Business Logic |
| AC Impacted | AC-03 |
| Source | 03-tdd.md TC-05, TC-06 |
| Phase Impacted | Implementation |

**Description:**
AC-03 rejects events where ConsentStatus != 'Opt In Pending'. This is a point-in-time validation, not a state machine enforcement. The exp-api validates the incoming payload's ConsentStatus field but does not check whether the consent record has already transitioned (e.g., a race condition where the SF record changes to 'OptedIn' between event publish and MuleSoft processing).

The ContactPointTypeConsent object supports these status transitions:
- `Not Seen` → `Opt In Pending` → `OptedIn` (happy path)
- `Not Seen` → `Opt In Pending` → `Opted Out` (user declines)
- `OptedIn` → `Opt In Pending` (re-consent after opt-out)

Without state machine awareness, the exp-api could process a stale event (status was 'Opt In Pending' when published but has since moved to 'OptedIn' because the user completed opt-in through another channel).

**Evidence:**
- 03-tdd.md TC-05, TC-06: Validate individual status values but not transition legality.
- 02-architecture.md: No state machine diagram for consent lifecycle.
- ContactPointTypeConsent change events include both old and new values — the exp-api only checks new value.

**Impact:**
Low severity in practice — processing a stale 'Opt In Pending' event when the record is already 'OptedIn' results in a redundant MC double opt-in SMS. The user receives an unnecessary message but no data corruption occurs. However, at scale this creates confusion and poor user experience.

**Recommendation:**
1. **Log a warning** when processing an event where ConsentStatus is 'Opt In Pending' but the idempotency store indicates a prior event for the same ConsentId was already processed. This indicates a re-consent or stale event.
2. **Consider adding a SF callout** from the exp-api to verify current consent status before routing to prc-api. Trade-off: adds latency (200-300ms) and a dependency on SF API availability. Only warranted if stale event volume is significant.
3. **Document the state machine** in the RAML description and architecture artifact for cross-team understanding.

---

### F-06 — RAML Contract Missing Error Response Schemas

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | API Design |
| AC Impacted | AC-01, AC-06 |
| Source | 03-tdd.md TC-02 through TC-06, TC-22 |
| Phase Impacted | Design |

**Description:**
The RAML contract defines the success response (202 Accepted) and likely the request schema, but error response schemas (400, 401, 403, 409, 429, 500, 503) are not verified in the test suite. APIkit generates default error responses, but these may not match the expected format for upstream consumers (the Salesforce Named Credential or platform event subscriber expects a specific error structure for retry decisions).

A well-defined error schema enables:
- Upstream consumers to parse error reasons programmatically.
- Monitoring tools to categorize errors by type.
- DLQ replay logic to decide between retry and discard.

**Evidence:**
- 03-tdd.md: Tests assert status codes but not error response body structure beyond `payload.error` string.
- No RAML `responses` block for 400, 409, 500, 503 documented in architecture.

**Impact:**
Without standardized error schemas, different callers may interpret the same error differently. If Salesforce retry logic expects `{"errorCode": "...", "message": "..."}` but MuleSoft returns `{"error": "..."}`, retries may fail or produce unexpected behavior.

**Recommendation:**
1. Define a standard error schema in RAML:
```yaml
types:
  ErrorResponse:
    properties:
      errorCode: string
      message: string
      correlationId: string
      timestamp: datetime
```
2. Apply this schema to all non-2xx responses in the RAML spec.
3. Update TC-02 through TC-06 to assert the full error response structure, not just the presence of an error string.

---

### F-07 — PII Handling in DLQ Messages — Phone Number Stored in Plain Text

| Field | Value |
|---|---|
| Severity | **MEDIUM** |
| Category | Security / Compliance |
| AC Impacted | AC-08, AC-12 |
| Source | 03-tdd.md TC-15, TC-20 |
| Phase Impacted | Implementation |

**Description:**
AC-12 requires PII (phone numbers) not be logged in plain text. TC-20 tests that logs do not contain unmasked phone numbers. However, the DLQ message (AC-08) contains the **original payload**, which includes the unmasked phone number. The DLQ is an Anypoint MQ queue — messages are at-rest, persisted, and accessible via the Anypoint Platform UI.

If an SRE opens the DLQ to investigate failures, they see plain-text phone numbers for every failed consent event. This violates the PII protection requirement and potentially TCPA regulations (phone numbers used for SMS marketing are PII under TCPA).

**Evidence:**
- F-03 recommendation includes `"originalPayload": { ... }` in DLQ envelope — this payload contains `Phone`.
- TC-20 tests log masking but does not test DLQ message content.
- No Anypoint MQ encryption-at-rest configuration mentioned.

**Impact:**
Plain-text phone numbers in DLQ expose PII to anyone with Anypoint Platform access (which may include contractors, offshore support). TCPA and internal data governance require phone number masking or encryption for at-rest data.

**Recommendation:**
1. **Mask phone in DLQ payload:** Replace `"+15551234567"` with `"+1555***4567"` in the DLQ originalPayload. The masked value is sufficient for debugging; the full value can be retrieved from SF ContactPointTypeConsent if needed.
2. **Enable Anypoint MQ encryption-at-rest** for the DLQ queue.
3. **Add TC-33:** Assert that DLQ message payload does not contain a full unmasked phone number matching the pattern `\+[0-9]{10,15}`.
4. **Document PII handling policy** for MuleSoft queues in the operational runbook.

---

### F-08 — No Monitoring or Alerting Design for exp-api Operational Health

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Operational Readiness |
| AC Impacted | AC-09, AC-10 |
| Source | 03-tdd.md TC-25, TC-26 |
| Phase Impacted | Post-deployment |

**Description:**
The health check endpoint (AC-10) enables liveness probing, and correlation IDs (AC-09) enable tracing. However, no operational monitoring design exists for:

1. **Error rate alerting:** What percentage of 4xx/5xx responses triggers an alert?
2. **DLQ depth monitoring:** How many messages in DLQ before an alert fires?
3. **Throughput anomaly detection:** Sudden drop in event volume could indicate SF trigger failure.
4. **Latency monitoring:** p95 response time degradation.
5. **Circuit breaker state changes:** Alert when circuit opens (MC outage) or closes (recovery).

**Evidence:**
- 02-architecture.md: No monitoring section.
- 03-tdd.md TC-25, TC-26: Test health check but no operational alerting tests.
- No Anypoint Monitoring or external APM integration specified.

**Impact:**
Without monitoring, failures are discovered only when users report missing opt-in SMS messages — potentially days after the failure began. The DLQ silently absorbs failures; no one reviews it unless alerted.

**Recommendation:**
1. Define alerting thresholds in Anypoint Monitoring or integrate with existing APM (Datadog, Splunk).
2. **Error rate:** Alert if 5xx rate > 5% over 5-minute window.
3. **DLQ depth:** Alert if DLQ depth > 10 messages in 15 minutes.
4. **Throughput:** Alert if event volume drops > 50% compared to same hour previous day.
5. **Circuit breaker:** Log and alert on every state transition (CLOSED→OPEN, OPEN→HALF_OPEN, HALF_OPEN→CLOSED).

---

### F-09 — ObjectStore Capacity Planning for Idempotency Keys Not Addressed

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Scalability |
| AC Impacted | AC-07 |
| Source | 03-tdd.md TC-13 |
| Phase Impacted | Implementation |

**Description:**
The idempotency check stores ConsentId+timestamp keys in CloudHub ObjectStore. With a 7-day TTL (per F-02 recommendation), the storage requirement depends on consent event volume:

- **Current estimate:** ~500 opt-in events/day × 7 days = ~3,500 keys.
- **Peak (consent campaign):** ~10,000 events/day × 7 days = ~70,000 keys.
- **CloudHub ObjectStore limit (per app):** 100,000 keys (soft limit), 10 MB storage.

At 70,000 keys, the ObjectStore is at 70% capacity. A sustained campaign could breach the limit, causing `ObjectStoreException` and silently breaking idempotency (all events would appear as new).

**Evidence:**
- No capacity analysis in architecture artifacts.
- CloudHub ObjectStore documentation: 100,000 key soft limit per application partition.

**Impact:**
If the ObjectStore exceeds capacity, the idempotency check fails open (all events accepted) or fails closed (all events rejected as duplicates). Either failure mode is unacceptable: duplicates cause double SMS sends; false rejections lose consent events.

**Recommendation:**
1. **Monitor ObjectStore key count** via Anypoint Monitoring custom metric.
2. **Set TTL to 3 days** instead of 7 — SF platform events are retained 72 hours, so a 3-day TTL provides sufficient coverage with lower storage footprint (~1,500 keys at normal volume).
3. **Alert at 80% capacity** (80,000 keys) to trigger TTL reduction or external store migration.
4. For very high volume scenarios, consider migrating idempotency store to Redis (via MuleSoft Redis connector) for higher capacity and sub-millisecond lookup.

---

### F-10 — exp-api Does Not Validate ContactId Existence in Salesforce

| Field | Value |
|---|---|
| Severity | **LOW** |
| Category | Data Integrity |
| AC Impacted | AC-02, AC-04 |
| Source | 03-tdd.md TC-01, TC-07 |
| Phase Impacted | Implementation |

**Description:**
The payload includes a ContactId (used as MC SubscriberKey in TC-07 transformation). The exp-api validates that ContactId is present (AC-02) but does not verify that the ContactId actually exists in Salesforce. A malformed or orphaned ContactId could result in MC creating a subscriber record with an invalid SubscriberKey, which breaks MC↔SF identity alignment.

**Evidence:**
- TC-07: Uses ContactId `"0035g000000DEFGHI"` in test but does not verify it's a real Contact record.
- 02-architecture.md: ContactId is assumed to be valid because the platform event source (SF trigger) provides it from a real record.

**Impact:**
Low in practice — the platform event trigger (NGASIM-3058) fires on a real ContactPointTypeConsent record, which is linked to a real Contact. The ContactId should always be valid. Risk exists only in manual testing or replay scenarios where stale data is used.

**Recommendation:**
1. **Accept the risk** — the source system (SF trigger) guarantees ContactId validity. Adding a callout to verify would add latency and a circular dependency (MuleSoft calling back to SF on every event).
2. **Add a warning log** if ContactId format doesn't match the expected SF ID pattern (18-character alphanumeric starting with `003` for Contact or `001` for Account).
3. Document this design decision as an explicit assumption in the RAML description.

---

### F-11 — No Graceful Shutdown Strategy for In-Flight Consent Events During Deployment

| Field | Value |
|---|---|
| Severity | **INFO** |
| Category | Operational Readiness |
| AC Impacted | AC-01, AC-08 |
| Source | 02-architecture.md |
| Phase Impacted | Operations |

**Description:**
CloudHub 2.0 supports rolling deployments, but the exp-api must handle in-flight requests during the deployment window. If a consent event is mid-processing when a worker shuts down:

- The HTTP response is never sent (SF Named Credential sees a timeout and may retry).
- The ObjectStore write may or may not have completed (idempotency state is ambiguous).
- The DLQ write may not complete (event could be lost entirely).

**Evidence:**
- No graceful shutdown or drain configuration documented.
- CloudHub 2.0 default shutdown timeout is 30 seconds — sufficient for most HTTP requests but not for retry chains (3 retries × 10-second backoff = 30+ seconds).

**Impact:**
During deployments, a small number of events may be processed twice (once by the dying worker, once by the new worker on SF retry) or lost entirely. The idempotency check mitigates double-processing if the ObjectStore write completed, but the ambiguity is operationally concerning.

**Recommendation:**
1. **Configure CloudHub 2.0 graceful shutdown** with a 60-second drain period (exceeds maximum retry chain duration).
2. **Document the deployment procedure:** pause SF platform event subscription → deploy → resume subscription → process replayed events.
3. This is a standard CloudHub operational concern — not unique to this API but should be documented.

---

### F-12 — Test Suite Does Not Cover Malformed JSON or Content-Type Mismatch

| Field | Value |
|---|---|
| Severity | **INFO** |
| Category | Robustness |
| AC Impacted | AC-01, AC-06 |
| Source | 03-tdd.md |
| Phase Impacted | Implementation |

**Description:**
The test suite validates correct payloads, missing fields, and wrong values, but does not test:

1. **Malformed JSON:** `{"ConsentId": "abc", "broken` (truncated body).
2. **Wrong Content-Type:** `Content-Type: text/xml` with a JSON body.
3. **Empty body:** POST with no payload.
4. **Oversized payload:** A payload exceeding CloudHub's default 10 MB HTTP request limit.

APIkit may handle these gracefully by default, but explicit tests ensure consistent error responses.

**Evidence:**
- 03-tdd.md: 28 test cases, none covering malformed input at the HTTP transport level.
- APIkit default behavior returns 400 for JSON parse errors but the response format may not match the defined error schema.

**Impact:**
Low — APIkit handles these cases. The risk is that the error response format differs from the standard error schema (F-06), confusing upstream retry logic.

**Recommendation:**
1. Add 3 additional test cases: TC-34 (malformed JSON), TC-35 (wrong Content-Type), TC-36 (empty body).
2. These are low priority — defer to implementation phase.

---

## Anti-Pattern Analysis (10 Gates)

| # | Anti-Pattern Gate | Status | Evidence |
|---|---|---|---|
| 1 | Treats Salesforce as generic custom app platform | **PASS** | Uses platform-native ContactPointTypeConsent and Change Events — not custom objects |
| 2 | Defaults to custom build without OOTB comparison | **PASS** | Architecture evaluated MC Connect managed package (et4ae5__) as OOTB option; rejected because it doesn't support double opt-in workflow |
| 3 | Uses async as hand-wave for scale without analysis | **PASS** | Async pattern (202 Accepted) is justified: consent event processing is not latency-sensitive, and MC Classic API is rate-limited (429). Event-driven decoupling is correct. |
| 4 | Duplicates data without source-of-truth stated | **PASS** | Source of truth is ContactPointTypeConsent in SF. MC receives a projection for activation. ConsentId is the cross-system key. |
| 5 | Proposes MuleSoft layering without clear reuse/governance value | **CONDITIONAL PASS** | Three layers (exp/prc/sys) follow API-led orthodoxy. The exp-api adds validation, idempotency, and DLQ — genuine value. However, the prc-api (NGASIM-3335) value vs direct exp→sys routing should be explicitly justified. See Platform Fit Notes below. |
| 6 | Places Data Cloud without ingestion/federation rationale | **N/A** | Data Cloud not in scope for this story |
| 7 | Assumes Marketing Cloud activation without data freshness check | **PASS** | ConsentTimestamp is propagated to MC; exp-api rejects stale events via idempotency. MC activation is triggered by real-time consent, not batch. |
| 8 | Ignores consent, identity, or auditability in cross-cloud flows | **PASS** | Consent is the core domain. ContactId → SubscriberKey mapping ensures identity alignment. Correlation ID provides auditability. PII masking in logs is tested. |
| 9 | Omits operational and observability consequences | **PARTIAL FAIL** | Health check (AC-10) and correlation ID (AC-09) are defined. However, F-08 identifies missing monitoring, alerting, and DLQ operational procedures. |
| 10 | Avoids stating rejected alternatives | **PASS** | Architecture rejected: (a) direct SF→MC via MC Connect, (b) SF Flow-based HTTP callout, (c) polling-based integration. Reasons documented. |

---

## Platform Fit Notes — Why MuleSoft API-Led Is Correct Here

The MuleSoft API-led connectivity pattern (exp → prc → sys) is the correct architectural choice for this consent event flow. Alternatives were considered and rejected:

### Alternative 1: Direct SF→MC via MC Connect Managed Package
**Rejected because:** MC Connect (et4ae5__) provides one-way data sync and triggered sends but does not support the double opt-in workflow natively. The managed package's SMS send capability triggers immediate delivery — it has no concept of "Opt In Pending" status requiring a confirmation SMS before final opt-in. Custom development on top of MC Connect would be more fragile than the MuleSoft approach.

### Alternative 2: SF Flow HTTP Callout to MC Classic API
**Rejected because:** Flow-based HTTP callouts lack retry, DLQ, circuit breaker, and idempotency capabilities that MuleSoft provides natively. Flow governor limits (per-transaction callout limits, 60-second timeout) make it unsuitable for high-volume event processing. Flows cannot persist replay IDs for platform event recovery.

### Alternative 3: Polling-Based Integration (MuleSoft polls SF for consent changes)
**Rejected because:** Polling introduces latency (polling interval = minimum delay before consent event is processed). Real-time is required — a patient opting in expects the double opt-in SMS within seconds, not minutes. Polling also adds unnecessary load on SF API (repeated SOQL queries even when no new events exist).

### Why 3 Layers Instead of 2?
The prc-api (NGASIM-3335) orchestrates MC-specific business logic: subscriber key management, SMS definition lookup, campaign association. The sys-api (NGASIM-3143) encapsulates the MC Classic REST API specifics: auth token management, rate limit handling, API versioning. Collapsing to 2 layers (exp → sys) would push orchestration logic into the exp-api, violating single responsibility and making the exp-api harder to maintain. The prc-api is reusable by other consent types (email opt-in, push notification consent) that share MC activation logic.

---

## Cross-Cloud Implications

| Cloud | Involvement | Contract Risk | Notes |
|---|---|---|---|
| Salesforce (SF) | Source of truth — ContactPointTypeConsent platform event publisher | LOW | Platform event schema is defined by SF standard object. Change events are backward-compatible. |
| MuleSoft | Routing, transformation, resilience — exp/prc/sys layers | MEDIUM | F-04: Cross-layer contract drift. Requires RAML versioning and CDC testing. |
| Marketing Cloud (MC) | Activation — SMS double opt-in send | HIGH | MC Classic REST API is being sunset in favor of MC REST v2. If migration happens mid-project, sys-api must absorb the change. exp-api should be insulated. |
| Data Cloud | Not currently involved | FUTURE | If consent data is federated to Data Cloud for segmentation, the ConsentId → SubscriberKey mapping becomes a shared data model concern. Flag for future architecture review. |

**Key cross-cloud contract:** The ContactId → SubscriberKey mapping must be consistent across all three clouds. If MC uses a different SubscriberKey strategy (e.g., email instead of ContactId), the transformation in exp-api/prc-api must bridge the gap. This mapping should be externalized to configuration, not hardcoded in DataWeave.

---

## Tradeoff Analysis

### Real-Time Event-Driven vs. Batch Processing

| Factor | Real-Time (chosen) | Batch | Rationale |
|---|---|---|---|
| Latency | < 5 seconds | 5-60 minutes | Double opt-in SMS must arrive while user intent is fresh |
| Complexity | Higher (event replay, idempotency, circuit breaker) | Lower (simple batch query + send) | Complexity is justified by UX requirement |
| Failure recovery | DLQ + replay | Batch rerun | DLQ provides per-event granularity; batch is all-or-nothing |
| Scale ceiling | CloudHub worker limits (~50-100 events/second) | SF Bulk API limits (~10,000 records/batch) | Real-time is sufficient for projected volume (~500/day) |
| Cost | CloudHub worker time (always-on) | Scheduled job (runs only during batch window) | Cost difference is minimal at current volume |

**Decision:** Real-time is correct. The marginal complexity of event-driven architecture is justified by the user experience requirement (immediate double opt-in SMS) and the natural fit with SF platform events.

### Synchronous (request-reply) vs. Asynchronous (fire-and-forget)

| Factor | Synchronous | Asynchronous (chosen, 202 Accepted) | Rationale |
|---|---|---|---|
| Caller experience | Immediate confirmation of MC delivery | Confirmation of acceptance, not delivery | SF trigger does not need MC delivery confirmation |
| Coupling | exp-api → prc-api → sys-api → MC synchronous chain | exp-api returns immediately; downstream is decoupled | Decoupling allows independent scaling and failure isolation |
| Failure blast radius | MC outage blocks SF platform event processing | MC outage → DLQ; SF continues publishing events | Async insulates SF from MC availability |
| Traceability | Response includes MC delivery status | Response includes correlation ID; delivery status via async callback or log query | Tradeoff: less immediate visibility, but operationally manageable via monitoring |

**Decision:** Asynchronous (202 Accepted) is correct. The exp-api's job is to accept, validate, and route — not to wait for MC to deliver the SMS.

---

## Recommendations Summary

| # | Action | Priority | Owner | Phase |
|---|---|---|---|---|
| 1 | Implement platform event replay ID persistence (F-01) | **Must** | Dev lead | Implementation |
| 2 | Define ObjectStore TTL (3 days) and use atomic store (F-02) | **Must** | Dev lead | Implementation |
| 3 | Design DLQ message envelope with operational context (F-03) | **Must** | Dev lead + SRE | Implementation |
| 4 | Publish prc-api RAML to Exchange; add CDC contract test (F-04) | Should | Integration architect | Pre-implementation |
| 5 | Document consent status state machine (F-05) | Should | BA | Design |
| 6 | Define RAML error response schemas (F-06) | Should | Dev lead | Design |
| 7 | Mask PII in DLQ messages; enable MQ encryption-at-rest (F-07) | Should | Dev lead + SecOps | Implementation |
| 8 | Define monitoring and alerting thresholds (F-08) | Should | SRE | Post-deployment |
| 9 | Analyze ObjectStore capacity for peak consent campaigns (F-09) | Could | Dev lead | Implementation |
| 10 | Accept ContactId validity assumption; add format validation (F-10) | Could | Dev lead | Implementation |
| 11 | Configure CloudHub graceful shutdown (60s drain) (F-11) | Should | DevOps | Deployment |
| 12 | Add malformed JSON, wrong Content-Type, empty body tests (F-12) | Could | QA | Implementation |

---

## Handoff to BUILD FIX

**Directive:** The build-fix agent must:

1. Produce the RAML API specification for exp-api (`exp-sms-consent-api.raml`) including request schema, all response schemas (202, 400, 401, 409, 429, 500, 503), and the error response type.
2. Produce DataWeave source for `consent-event-validator.dwl` and `sf-to-mc-transformer.dwl`.
3. Produce the MuleSoft project structure (`pom.xml`, `mule-artifact.json`, `global.xml`, main flow XML).
4. Define the ObjectStore configuration with TTL and atomic store pattern.
5. Define the DLQ message envelope schema.
6. Produce pseudo-code for the circuit breaker configuration.
7. Generate the `health-check-flow` implementation.
8. Address F-01 (replay ID), F-02 (ObjectStore TTL), F-03 (DLQ format), F-06 (error schemas), F-07 (PII masking in DLQ).
9. Validate all dependencies (MuleSoft connectors, Anypoint MQ, HTTP requester) for compatibility.
10. Report addressed review findings with status.
