# NGASIM-3336: DOCUMENTATION

> **Pipeline Stage:** 09-docs
> **Produced by:** doc-updater agent
> **Input:** All prior artifacts (00-intake through 08-refactor)
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T21:12:00Z
> **Status:** COMPLETE

---

## Decisions Made

1. Documentation deliverables: operational runbook, ADR summary, data flow documentation, API contract documentation, traceability map, cross-cloud integration guide, glossary, change log, and CTA domain coverage summary.
2. Runbook targets Anypoint Platform deployment — not Salesforce metadata deployment (SF side covered by separate pipeline stages for the consent object and platform event configuration).
3. Traceability map connects the full pipeline: Jira stories → acceptance criteria → architecture decisions → test cases → security findings → technical debt items.
4. CTA domain coverage analysis evaluates all 9 domains per REQ/Skills-Outcome-Guidance.md and identifies explicit gaps for follow-up.

---

## 1. Operational Runbook — SMS Double Opt-In exp-api

### 1.1 Deployment Steps (Anypoint Platform / CloudHub)

**Pre-requisites checklist:**

| # | Pre-requisite | Verification | Owner |
|---|--------------|-------------|-------|
| PRE-01 | MC Classic API credentials stored in Anypoint Secrets Manager (not application properties) | Verify via Anypoint Runtime Manager → Properties tab — no plaintext `client_secret` visible | MuleSoft Admin |
| PRE-02 | SF Connected App provisioned with OAuth2 JWT bearer for MuleSoft integration user | `sf org display --target-org orgsyncng` confirms integration user exists | SF Admin |
| PRE-03 | Anypoint MQ queues created: `consent-sms-dlq-{env}` | Verify in Anypoint MQ console | MuleSoft Admin |
| PRE-04 | MC Connected App created with minimum OAuth2 scope: `sms_send`, `list_and_subscribers_read`, `list_and_subscribers_write` | MC Admin verifies scope in MC Setup → Installed Packages | MC Admin |
| PRE-05 | CloudHub environment created (dev/staging/prod) with correct vCore allocation | Runtime Manager → Environments | MuleSoft Admin |
| PRE-06 | `ContactPointTypeConsent` platform event channel enabled in SF org | `sf data query --query "SELECT Id, DeveloperName FROM PlatformEventChannelMember WHERE SelectedEntity = 'ContactPointTypeConsentChangeEvent'" --target-org orgsyncng` | SF Admin |
| PRE-07 | Log masking DataWeave module (`pii-log-mask.dwl`) deployed in all 3 MuleSoft apps | Code review confirms import in global error handler | MuleSoft Dev |

**Step 1: Deploy sys-api (bottom-up — system layer first)**

```bash
# From MuleSoft project root
# Verify target environment
anypoint-cli runtime-mgr cloudhub-application describe insulet-mc-classic-sys-api

# Deploy sys-api to CloudHub
mvn clean deploy -DmuleDeploy \
  -Danypoint.platform.client.id=$CLIENT_ID \
  -Danypoint.platform.client.secret=$CLIENT_SECRET \
  -Dcloudhub.environment=dev \
  -Dcloudhub.workerType=MICRO \
  -Dcloudhub.workers=1 \
  -Dapp.name=insulet-mc-classic-sys-api

# Verify deployment
anypoint-cli runtime-mgr cloudhub-application describe insulet-mc-classic-sys-api
# Expected status: STARTED
```

**Step 2: Deploy prc-api (middle layer)**

```bash
mvn clean deploy -DmuleDeploy \
  -Danypoint.platform.client.id=$CLIENT_ID \
  -Danypoint.platform.client.secret=$CLIENT_SECRET \
  -Dcloudhub.environment=dev \
  -Dcloudhub.workerType=MICRO \
  -Dcloudhub.workers=1 \
  -Dapp.name=insulet-consent-sms-prc-api

# Verify
anypoint-cli runtime-mgr cloudhub-application describe insulet-consent-sms-prc-api
```

**Step 3: Deploy exp-api (top layer — starts consuming platform events)**

```bash
mvn clean deploy -DmuleDeploy \
  -Danypoint.platform.client.id=$CLIENT_ID \
  -Danypoint.platform.client.secret=$CLIENT_SECRET \
  -Dcloudhub.environment=dev \
  -Dcloudhub.workerType=MICRO \
  -Dcloudhub.workers=1 \
  -Dapp.name=insulet-consent-sms-exp-api

# Verify
anypoint-cli runtime-mgr cloudhub-application describe insulet-consent-sms-exp-api
```

**Deployment order rationale:** Bottom-up deployment ensures that when the exp-api starts consuming platform events, the downstream layers are already running. If deployed top-down, the exp-api would receive events with no downstream processor, routing all events to DLQ immediately.

### 1.2 Health Check Verification

**Automated health check (run after every deployment):**

| # | Check | Command / Method | Expected Result | Failure Action |
|---|-------|-----------------|-----------------|----------------|
| HC-01 | exp-api application status | `GET https://insulet-consent-sms-exp-api.cloudhub.io/api/v1/health` | `200 OK` with `{"status":"UP","layer":"exp"}` | Check CloudHub worker logs for startup errors |
| HC-02 | prc-api application status | `GET https://insulet-consent-sms-prc-api.cloudhub.io/api/v1/health` | `200 OK` with `{"status":"UP","layer":"prc"}` | Check worker logs |
| HC-03 | sys-api application status | `GET https://insulet-mc-classic-sys-api.cloudhub.io/api/v1/health` | `200 OK` with `{"status":"UP","layer":"sys"}` | Check worker logs |
| HC-04 | SF platform event subscription | Check exp-api logs for `Subscribed to channel /event/ContactPointTypeConsentChangeEvent` | Log message present within 30s of startup | Verify SF Connected App, Named Credential, integration user permissions |
| HC-05 | MC OAuth token acquisition | Check sys-api logs for `MC OAuth token acquired, expires in X seconds` | Token acquired within 10s of startup | Verify MC client credentials in Secrets Manager, MC Connected App status |
| HC-06 | DLQ connectivity | Check exp-api logs for `Anypoint MQ connection established to consent-sms-dlq-{env}` | Connection established | Verify Anypoint MQ queue exists, credentials valid |
| HC-07 | End-to-end smoke test | Create test `ContactPointTypeConsent` record in SF sandbox → verify MC subscriber created | MC subscriber record exists with correct consent status | Full stack troubleshooting (see Failure Modes below) |

### 1.3 Log Monitoring and Alerting

**Log locations:**

| Source | Location | Retention | Access |
|--------|----------|-----------|--------|
| exp-api runtime logs | Anypoint Runtime Manager → Applications → insulet-consent-sms-exp-api → Logs | 30 days (CloudHub default) | MuleSoft Admin/Developer role |
| prc-api runtime logs | Anypoint Runtime Manager → Applications → insulet-consent-sms-prc-api → Logs | 30 days | MuleSoft Admin/Developer role |
| sys-api runtime logs | Anypoint Runtime Manager → Applications → insulet-mc-classic-sys-api → Logs | 30 days | MuleSoft Admin/Developer role |
| Anypoint Monitoring dashboards | Anypoint Monitoring → Custom Dashboards | Per Anypoint subscription tier | MuleSoft Admin |
| Anypoint MQ (DLQ) | Anypoint MQ Console → Queues → consent-sms-dlq-{env} | Per queue TTL (recommend 7 days max per S-04) | MuleSoft Admin only (restricted per S-04) |
| HIPAA audit log export | S3 bucket `insulet-consent-audit-{env}` (TBD — TD-16) | 6 years | Compliance team + DevOps |

**Alerting rules (to be configured in Anypoint Monitoring or external tool):**

| # | Alert | Condition | Severity | Notification Channel |
|---|-------|-----------|----------|---------------------|
| A-01 | DLQ depth threshold | DLQ message count > 50 | WARNING | Slack #mulesoft-alerts |
| A-02 | DLQ depth critical | DLQ message count > 200 | CRITICAL | PagerDuty on-call |
| A-03 | Circuit breaker OPEN | sys-api circuit breaker transitions to OPEN state | WARNING | Slack #mulesoft-alerts |
| A-04 | Token refresh failure | sys-api MC OAuth token refresh returns non-200 | CRITICAL | PagerDuty on-call |
| A-05 | Platform event subscription lost | exp-api SF connector disconnects from CometD channel | CRITICAL | PagerDuty on-call |
| A-06 | Error rate spike | Any layer error rate > 5% over 5-minute window | WARNING | Slack #mulesoft-alerts |
| A-07 | Latency threshold | p95 end-to-end latency > 30 seconds | WARNING | Slack #mulesoft-alerts |
| A-08 | Worker restart | Any CloudHub worker restarts unexpectedly | INFO | Slack #mulesoft-alerts |

### 1.4 Common Failure Modes and Resolution

| # | Failure Mode | Symptoms | Root Cause | Resolution |
|---|-------------|----------|------------|------------|
| FM-01 | MC API returns 401 Unauthorized | sys-api logs: `MC API returned 401`. All consent events routing to DLQ. | MC client secret rotated without updating MuleSoft. Or: MC Connected App deactivated. | (1) Verify MC Connected App is active. (2) Verify client secret in Anypoint Secrets Manager matches MC. (3) If rotated, update Secrets Manager and restart sys-api worker. |
| FM-02 | SF platform event subscription drops | exp-api stops receiving events. No new consent processing. | SF session expired. Or: CometD long-poll timeout. Or: SF maintenance window. | (1) Check exp-api logs for reconnect attempts. (2) If persistent, restart exp-api worker to force re-subscription. (3) After recovery, verify replay ID — check for missed events by comparing SF event count with MuleSoft processed count. |
| FM-03 | DLQ overflow | DLQ reaches max depth. New failed events are dropped (no persistence). | Sustained MC API outage or MC maintenance window exceeding DLQ capacity. | (1) Increase DLQ max depth (Anypoint MQ console). (2) Drain DLQ to external storage (S3) for later reprocessing. (3) Investigate MC API status page for outage. (4) After MC recovery, reprocess DLQ messages. |
| FM-04 | Duplicate consent submissions to MC | MC receives the same consent event twice. Patient gets duplicate confirmation SMS. | Replay ID gap after exp-api restart. Or: platform event replay delivered already-processed events. | (1) sys-api must implement idempotency (check if MC subscriber already has this consent status before submitting). (2) Review replay ID persistence (S-06). (3) MC double opt-in flow should be idempotent — sending a second confirmation SMS is annoying but not harmful. |
| FM-05 | International phone number rejected | prc-api logs: `Phone format validation failed`. Events for international patients routing to DLQ. | DataWeave `phone-normalizer.dwl` assumes US format (10 digits). International numbers have 7-15 digits with country code. | (1) Deploy updated `phone-normalizer.dwl` with E.164 support (S-07 remediation). (2) Reprocess DLQ messages for international patients after fix. |
| FM-06 | Circuit breaker tripped during MC maintenance | exp-api/sys-api logs: `Circuit breaker OPEN — MC API unreachable`. All events routing to DLQ for 5+ minutes. | MC scheduled maintenance window (typically Saturday 12:00-16:00 CT). 5-minute threshold too aggressive. | (1) Verify MC maintenance calendar. (2) After maintenance, circuit breaker transitions to HALF-OPEN → CLOSED automatically. (3) Implement 15-minute threshold (S-08 remediation) to avoid false trips. |
| FM-07 | Consent state validation rejection | prc-api logs: `Invalid consent transition: NotSet → OptedIn`. Event routed to review queue. | SF record created with `OptedIn` status directly, skipping `OptInPending` (double opt-in). Or: out-of-order event delivery. | (1) Investigate SF source: who created the consent record with invalid state? (2) If data migration, use a bypass flag to skip state validation for bulk historical imports. (3) If application bug, fix the consent creation flow in SF. |

### 1.5 Rollback Procedure

**Rollback order: top-down (stop consuming events first)**

| Step | Action | Command | Impact |
|------|--------|---------|--------|
| 1 | Stop exp-api | `anypoint-cli runtime-mgr cloudhub-application stop insulet-consent-sms-exp-api` | Platform events accumulate in SF (24-hour retention). No new consent processing. |
| 2 | Stop prc-api | `anypoint-cli runtime-mgr cloudhub-application stop insulet-consent-sms-prc-api` | No business logic processing. In-flight messages in Anypoint MQ persist. |
| 3 | Stop sys-api | `anypoint-cli runtime-mgr cloudhub-application stop insulet-mc-classic-sys-api` | No MC API submissions. MC subscriber state frozen at last successful update. |
| 4 | Drain DLQ | Export DLQ messages to S3 for later analysis | Preserves failed events for post-mortem. |
| 5 | Redeploy previous version | Use Anypoint Runtime Manager → Manage Application → Deploy from Exchange → select previous version | Restores last known good version. |
| 6 | Resume bottom-up | Start sys-api → prc-api → exp-api | Same deployment order rationale. |

**Rollback triggers:**
- CRITICAL security finding in production (e.g., PII exposure confirmed in logs)
- Sustained error rate > 50% for more than 15 minutes
- Consent data corruption detected (wrong consent status in MC)
- Compliance team requests immediate halt

---

## 2. Architecture Decision Records Summary

| ADR | Title | Decision | Status |
|-----|-------|----------|--------|
| ADR-001 | Integration Pattern for SF→MC Consent Sync | Use MuleSoft API-led connectivity (exp/prc/sys) over direct SF-to-MC via MC Connect managed package or SF Apex HTTP callout. MuleSoft provides business logic layer (state machine), DLQ, retry, and API governance that direct integration lacks. | **ACCEPTED** |
| ADR-002 | Event Notification Mechanism | Use `ContactPointTypeConsentChangeEvent` (Platform Events / Change Data Capture) over Outbound Messages or custom Apex publishing. Platform Events provide declarative, governor-limit-aware event delivery with replay capability and 24-hour retention. CDC on standard `ContactPointTypeConsent` is OOTB — no custom code needed for event publishing. | **ACCEPTED** |
| ADR-003 | MC API Selection | Use MC Classic REST API (`/messaging/v1/sms/messages/` and `/contacts/v1/contacts/`) over MC Transactional Messaging API or SOAP API. Classic REST is stable, well-documented, and available in Insulet's MC environment. Transactional Messaging API is better suited architecturally but may not be provisioned. SOAP API is legacy. **Re-architecture trigger:** if Transactional Messaging API becomes available, evaluate migration. | **ACCEPTED** — with future review trigger |
| ADR-004 | Error Handling Strategy | Use DLQ (Anypoint MQ) with exponential backoff retry (1s base, 5 max retries) and circuit breaker (threshold TBD — S-08 recommends 15 min) over synchronous retry only or SF custom object store-and-forward. DLQ provides persistence, visibility, and decoupled retry. SF store-and-forward was rejected because it creates circular dependency (SF → MuleSoft → failure → store in SF → retry from SF → MuleSoft). | **ACCEPTED** |

---

## 3. Data Flow Documentation

### End-to-End Field Mapping

```
STAGE 1: Salesforce → Platform Event
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ContactPointTypeConsent (DML: Insert/Update)
  │
  │ Automatic CDC Platform Event
  ▼
ContactPointTypeConsentChangeEvent
  ├── ChangeEventHeader.recordIds[]     → SF Record IDs (array)
  ├── ChangeEventHeader.changeType      → CREATE | UPDATE
  ├── ChangeEventHeader.changedFields[] → List of modified fields
  ├── ChangeEventHeader.commitTimestamp → Epoch ms of DML commit
  ├── ChangeEventHeader.transactionKey  → SF transaction identifier
  ├── PartyId                           → PersonAccount/Contact ID
  ├── ContactPointId                    → ContactPointPhone ID
  ├── PrivacyConsentStatus              → OptedIn | OptedOut | NotSeen | Seen
  ├── CaptureDate                       → ISO 8601 datetime
  ├── CaptureSource                     → Channel where consent was captured
  ├── CaptureContactPointType           → Phone | Email | Web | ...
  └── EffectiveFrom                     → When consent becomes active


STAGE 2: Platform Event → exp-api (MuleSoft Experience Layer)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
exp-api receives CDC event via Anypoint SF Connector (CometD)

DataWeave: consent-event-mapper.dwl
  Input (SF CDC event)                   → Output (Canonical Consent Message)
  ────────────────────                     ─────────────────────────────────
  ChangeEventHeader.recordIds[0]         → consentRecordId
  PartyId                                → patientId
  ContactPointId                         → contactPointId
  PrivacyConsentStatus                   → consentStatus (enum: OPTED_IN | OPTED_OUT | PENDING)
  CaptureDate                            → captureTimestamp (ISO 8601)
  CaptureSource                          → captureChannel
  CaptureContactPointType                → contactPointType (must = "Phone" for SMS)
  EffectiveFrom                          → effectiveFrom
  (resolved from ContactPointPhone)      → phoneNumber (E.164 format)
  (generated)                            → correlationId (UUID v4)
  (generated)                            → eventTimestamp (processing time)
  ChangeEventHeader.commitTimestamp      → sourceCommitTimestamp


STAGE 3: exp-api → prc-api (MuleSoft Process Layer)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
prc-api receives Canonical Consent Message via HTTP POST

Processing steps:
  1. Validate contactPointType = "Phone" (reject Email, Web, etc.)
  2. Validate consentStatus transition (state machine — S-03)
  3. Normalize phoneNumber to E.164 (phone-normalizer.dwl — S-07)
  4. Resolve MC subscriber key from patientId (SF Contact ID → MC subscriber key)
  5. Transform to MC subscriber payload

DataWeave: mc-subscriber-mapper.dwl
  Input (Canonical Consent Message)      → Output (MC Subscriber Payload)
  ─────────────────────────────────        ─────────────────────────────
  phoneNumber                            → mobileNumber
  consentStatus (OPTED_IN)               → status: "Active", smsPermission: "OptIn"
  consentStatus (OPTED_OUT)              → status: "Unsubscribed", smsPermission: "OptOut"
  consentStatus (PENDING)                → status: "Active", smsPermission: "PendingDoubleOptIn"
  patientId (SF Contact ID)              → subscriberKey
  captureTimestamp                       → attributes[0]: {"key":"ConsentDate","value":"..."}
  captureChannel                         → attributes[1]: {"key":"ConsentSource","value":"..."}
  correlationId                          → attributes[2]: {"key":"CorrelationId","value":"..."}


STAGE 4: prc-api → sys-api → MC Classic REST API
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
sys-api receives MC Subscriber Payload via HTTP POST

MC API calls (in order):
  1. POST /contacts/v1/contacts
     Body: { "contactKey": "{subscriberKey}", "attributeSets": [...] }
     Purpose: Create or update MC contact with consent attributes

  2. POST /messaging/v1/sms/messages/
     Body: {
       "definitionKey": "{smsDefinitionKey}",
       "recipient": {
         "contactKey": "{subscriberKey}",
         "to": "{mobileNumber}"
       },
       "subscriptions": {
         "sms": { "keyword": "OPTIN" }
       }
     }
     Purpose: Trigger double opt-in SMS confirmation to patient

MC Response:
  200 OK → consent processed successfully, confirmation SMS queued
  400 Bad Request → malformed payload (log, route to DLQ with VALIDATION_ERROR)
  401 Unauthorized → OAuth token expired or invalid (retry token refresh, then retry)
  429 Too Many Requests → rate limited (backoff and retry per exponential schedule)
  500 Internal Server Error → MC system error (route to DLQ with MC_API_ERROR)
```

---

## 4. API Contract Documentation

### exp-api RAML Summary

```yaml
#%RAML 1.0
title: Insulet Consent SMS Experience API
version: v1
baseUri: https://{environment}.api.insulet.com/consent-exp/api/{version}

/consent/sms-optin:
  post:
    description: Receives SMS opt-in consent events from SF platform event channel
    headers:
      X-Correlation-Id:
        type: string
        required: true
        description: UUID v4 correlation ID for end-to-end tracing
      X-Client-Id:
        type: string
        required: true
        description: Anypoint API Manager client ID
    body:
      application/json:
        type: ConsentEvent
    responses:
      202:
        description: Event accepted for async processing
        body:
          application/json:
            example: |
              {
                "status": "ACCEPTED",
                "correlationId": "550e8400-e29b-41d4-a716-446655440000",
                "timestamp": "2026-03-25T21:08:00Z"
              }
      400:
        description: Invalid payload structure
      401:
        description: Authentication failed
      429:
        description: Rate limit exceeded
      500:
        description: Internal processing error

/health:
  get:
    description: Application health check
    responses:
      200:
        body:
          application/json:
            example: |
              {
                "status": "UP",
                "layer": "exp",
                "sfSubscription": "ACTIVE",
                "dlqConnection": "ACTIVE",
                "timestamp": "2026-03-25T21:08:00Z"
              }
```

### Sample Request / Response

**Successful consent processing:**

```json
// POST /consent/sms-optin
// Headers: X-Correlation-Id: 550e8400-e29b-41d4-a716-446655440000
{
  "consentRecordId": "0PN5g00000EXAMPLE",
  "patientId": "0015g00000PATIENT",
  "contactPointId": "0CP5g00000CNTPNT",
  "consentStatus": "OPTED_IN",
  "phoneNumber": "+12065551234",
  "captureTimestamp": "2026-03-25T21:05:00Z",
  "captureChannel": "WebForm",
  "contactPointType": "Phone",
  "effectiveFrom": "2026-03-25T21:05:00Z"
}

// Response: 202 Accepted
{
  "status": "ACCEPTED",
  "correlationId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-03-25T21:08:01Z"
}
```

**Validation failure (invalid consent transition):**

```json
// POST /consent/sms-optin
{
  "consentRecordId": "0PN5g00000EXAMPLE2",
  "patientId": "0015g00000PATIENT2",
  "consentStatus": "OPTED_IN",
  "phoneNumber": "+12065559876",
  "contactPointType": "Phone"
}

// Response: 400 Bad Request
{
  "status": "REJECTED",
  "correlationId": "660e8400-e29b-41d4-a716-446655440001",
  "error": "INVALID_CONSENT_TRANSITION",
  "message": "Consent transition from NotSet to OPTED_IN is invalid. Expected: NotSet → PENDING.",
  "timestamp": "2026-03-25T21:08:02Z"
}
```

---

## 5. Traceability Map

### Jira Stories → Acceptance Criteria → Architecture Decisions

| Jira Story | AC | Architecture Decision | Rationale |
|-----------|----|-----------------------|-----------|
| NGASIM-3336 (exp-api) | AC-01: Platform event consumed | ADR-001 (MuleSoft API-led), ADR-002 (Platform Events) | MuleSoft consumes CDC events natively via Anypoint SF Connector |
| NGASIM-3336 | AC-02: Consent validated before MC submission | ADR-001 (prc-api business logic) | State machine validation in prc-api prevents invalid consent registration |
| NGASIM-3336 | AC-03: MC subscriber updated with consent | ADR-003 (MC Classic REST API) | sys-api abstracts MC API and handles OAuth lifecycle |
| NGASIM-3336 | AC-04: Double opt-in SMS sent | ADR-003 (MC Classic REST API) | MC Classic `/messaging/v1/sms/messages/` triggers double opt-in SMS |
| NGASIM-3336 | AC-05: Failed events routed to DLQ | ADR-004 (DLQ + exponential backoff) | Anypoint MQ DLQ with configurable retry |
| NGASIM-3336 | AC-06: Retry with exponential backoff | ADR-004 | 1s base, 5 max retries, backoff multiplier 2x |
| NGASIM-3336 | AC-07: Circuit breaker on MC API | ADR-004 | Threshold: 15 min (adjusted per S-08) |
| NGASIM-3336 | AC-08: OAuth2 for MuleSoft→MC | ADR-003 | Client credentials grant with auto-refresh |
| NGASIM-3336 | AC-09: PII masked in logs | S-01 remediation | pii-log-mask.dwl applied across all 3 layers |
| NGASIM-3336 | AC-10: Idempotent consent submission | ADR-004 | sys-api checks current MC subscriber state before submitting |

### Architecture Decisions → Test Cases

| ADR | Test Cases | Coverage |
|-----|-----------|----------|
| ADR-001 | TC-01: Platform event received by exp-api; TC-02: exp-api routes to prc-api; TC-03: prc-api routes to sys-api | Positive flow through all 3 layers |
| ADR-002 | TC-04: CDC event fires on ContactPointTypeConsent create; TC-05: CDC event fires on update; TC-06: No event on delete (CDC config) | Event generation scenarios |
| ADR-003 | TC-07: MC subscriber created (new); TC-08: MC subscriber updated (existing); TC-09: MC SMS triggered; TC-10: MC API 401 handled; TC-11: MC API 429 handled; TC-12: MC API 500 handled | MC API positive and negative scenarios |
| ADR-004 | TC-13: DLQ receives failed event; TC-14: Exponential backoff intervals correct; TC-15: Circuit breaker trips at threshold; TC-16: Circuit breaker recovers (HALF-OPEN → CLOSED); TC-17: Idempotent reprocessing of DLQ message | Error handling and recovery |

### Test Cases → Security Findings

| Test Case | Security Finding | Connection |
|-----------|-----------------|------------|
| TC-09 (MC SMS triggered) | S-03 (consent state validation) | TC must verify that only valid consent transitions trigger SMS |
| TC-10 (MC 401 handled) | S-02 (credential storage) | TC validates OAuth token refresh on 401 |
| TC-13 (DLQ receives event) | S-04 (PII in DLQ) | TC must verify phone number is masked in DLQ payload |
| All TCs with logging | S-01 (PII in logs) | All TCs must verify phone numbers are masked in runtime logs |
| TC-07, TC-08 (MC subscriber) | S-05 (MC OAuth scope) | TC verifies minimum scope is sufficient for subscriber operations |
| TC-04, TC-05 (CDC events) | S-06 (replay ID) | TC verifies replay ID persistence and gap detection |

### Security Findings → Technical Debt

| Security Finding | Technical Debt Item | Remediation Phase |
|-----------------|--------------------|--------------------|
| S-01 (PII in logs) | TD-02 | Phase 1 — Immediate |
| S-02 (Credential storage) | TD-01 | Phase 1 — Immediate |
| S-03 (Consent state machine) | TD-03 | Phase 2 — Before staging |
| S-04 (PII in DLQ) | TD-04 | Phase 2 — Before staging |
| S-05 (MC OAuth scope) | (MC admin task — not code debt) | Phase 2 |
| S-06 (Replay ID) | TD-08 | Phase 2 |
| S-07 (Phone format) | TD-09 | Phase 2 |
| S-08 (Circuit breaker) | TD-10 | Phase 3 — Before production |
| S-09 (mTLS) | TD-11 | Phase 3 |
| S-10 (Audit trail) | TD-07 | Phase 3 |

---

## 6. Cross-Cloud Integration Guide

### Connectivity Matrix

| Source | Target | Protocol | Auth | Credential Location | Rotation Schedule |
|--------|--------|----------|------|--------------------|--------------------|
| SF Org | MuleSoft exp-api | CometD (long-poll over HTTPS) | OAuth2 JWT Bearer | SF: Connected App digital certificate. MuleSoft: Secure Properties (consumer key + private key) | 12 months |
| MuleSoft exp-api | MuleSoft prc-api | HTTP/HTTPS (internal CloudHub) | None (same VPC) or Client Credentials (cross-VPC) | Internal routing — no credential | N/A |
| MuleSoft prc-api | MuleSoft sys-api | HTTP/HTTPS (internal CloudHub) | None (same VPC) | Internal routing | N/A |
| MuleSoft sys-api | MC Classic REST API | HTTPS | OAuth2 Client Credentials | MuleSoft: Anypoint Secrets Manager. MC: Connected App (Installed Package) | 12 months |
| MC Classic REST API | Patient SMS | Carrier network | MC-managed | MC-managed | N/A |

### Credential Rotation Procedure

**MC Client Secret Rotation (zero-downtime):**

1. **MC Admin:** In MC Setup → Installed Packages → Connected App → regenerate client secret. **Note the new secret. Do not deactivate old secret yet.**
2. **MuleSoft Admin:** Update Anypoint Secrets Manager with new MC client secret.
3. **MuleSoft Admin:** Restart sys-api worker to pick up new secret: `anypoint-cli runtime-mgr cloudhub-application restart insulet-mc-classic-sys-api`
4. **Verify:** Check sys-api logs for `MC OAuth token acquired` with new credentials.
5. **MC Admin:** Deactivate old client secret in MC Connected App.
6. **Monitor:** Watch for 401 errors for 1 hour after rotation.

**SF Connected App Certificate Rotation:**

1. **SF Admin:** Generate new digital certificate in SF Setup → Certificate and Key Management.
2. **SF Admin:** Update Connected App to use new certificate.
3. **MuleSoft Admin:** Update Secure Properties with new private key.
4. **MuleSoft Admin:** Restart exp-api worker.
5. **Verify:** Check exp-api logs for `Subscribed to channel /event/ContactPointTypeConsentChangeEvent`.
6. **SF Admin:** Revoke old certificate.

### Monitoring Across Clouds

| Metric | SF Source | MuleSoft Source | MC Source | Correlation |
|--------|-----------|----------------|-----------|-------------|
| Event volume | EventLogFile: `PlatformEventPublish` | Anypoint Monitoring: request count on exp-api | MC tracking: SMS send count | SF published = MuleSoft received + DLQ. MuleSoft processed = MC received. |
| Consent status | `ContactPointTypeConsent.PrivacyConsentStatus` | Canonical message `consentStatus` | MC subscriber `smsPermission` | Must match across all 3 systems. Weekly reconciliation job recommended (TD-18). |
| Error rate | N/A (SF does not track platform event delivery failures) | Anypoint Monitoring: error rate per layer | MC API response: 4xx/5xx count | MuleSoft is the primary error visibility point. |
| Latency | Platform event publish timestamp (`ChangeEventHeader.commitTimestamp`) | Processing time per layer | SMS delivery timestamp | End-to-end latency = MC SMS delivery timestamp - SF commit timestamp. Target: < 30 seconds. |

---

## 7. Glossary

| Term | Definition | Context |
|------|-----------|---------|
| **Double Opt-In** | A consent mechanism where the user explicitly requests to receive messages (first opt-in) and then confirms via a second action (e.g., replying YES to a confirmation SMS). Required by TCPA for certain categories of commercial SMS. | The core business process this integration supports. SF captures first opt-in → MuleSoft relays to MC → MC sends confirmation SMS → patient replies YES (second opt-in). |
| **ContactPointTypeConsent** | A standard Salesforce object representing an individual's consent preferences for a specific communication channel (SMS, email, etc.). Part of the Salesforce Consent Data Model (Individual, ContactPointTypeConsent, ContactPointPhone/Email). | The source of truth for consent status. Located in SF. Platform events fire on create/update. |
| **ContactPointTypeConsentChangeEvent** | A Change Data Capture (CDC) platform event that fires automatically when a `ContactPointTypeConsent` record is created, updated, or deleted. Contains the changed fields and metadata. | The event that triggers the MuleSoft integration. Consumed by exp-api via CometD subscription. |
| **Platform Event** | A Salesforce event-driven messaging mechanism. Change Data Capture events are a specific type of platform event generated automatically on standard/custom object DML. 24-hour retention. At-least-once delivery. | The notification mechanism from SF to MuleSoft. Not to be confused with custom platform events (which require explicit publishing). |
| **exp-api (Experience API)** | The MuleSoft experience layer API. Responsible for channel-specific concerns: receiving SF platform events, validating payload structure, rate limiting, and routing to the process layer. | Top layer of the API-led architecture. Faces the external system (SF). |
| **prc-api (Process API)** | The MuleSoft process layer API. Responsible for domain business logic: consent state machine validation, phone number normalization, transformation to MC format. | Middle layer. Contains business rules. System-agnostic. |
| **sys-api (System API)** | The MuleSoft system layer API. Responsible for system-specific concerns: MC Classic REST API authentication (OAuth2), API calls, response handling, retry logic. | Bottom layer. Faces the target system (MC). |
| **API-Led Connectivity** | MuleSoft's prescribed three-layer architecture pattern (Experience → Process → System) for building reusable, governed integrations. Each layer has a distinct responsibility. | The architectural pattern used for the consent integration. See ADR-001. |
| **DLQ (Dead-Letter Queue)** | An Anypoint MQ queue where failed messages are routed after all retry attempts are exhausted. DLQ messages persist for manual review and reprocessing. | Error handling mechanism. Events that fail processing (validation errors, MC API errors, transformation errors) land here. |
| **Circuit Breaker** | A resilience pattern that prevents cascading failures. When the downstream service (MC API) fails repeatedly, the circuit breaker "opens" and stops sending requests, allowing the downstream service to recover. After a timeout, it transitions to "half-open" and tests with a single request. | Applied to the sys-api → MC API connection. Threshold: 15 minutes (adjusted from 5 minutes per S-08). |
| **MC Classic REST API** | Marketing Cloud's REST API for subscriber management, messaging, and data operations. Part of MC's v1 API surface. Separate from the newer MC APIs v2. | The target API for consent submission and SMS triggering. |
| **Named Credential** | A Salesforce feature that stores authentication credentials (OAuth tokens, certificates, passwords) securely and applies them automatically to HTTP callouts from Apex or external service definitions. | Used for SF → MuleSoft authentication. Stores OAuth2 JWT bearer credentials for the MuleSoft integration user. |
| **TCPA** | Telephone Consumer Protection Act. US federal law regulating telemarketing calls, auto-dialed calls, and SMS messages. Requires prior express consent for commercial SMS. Violations carry $500-$1,500 per message in statutory damages. | The primary US regulation governing SMS consent. Double opt-in satisfies the "prior express written consent" requirement. |
| **PHI-Adjacent** | Data that, while not directly containing medical diagnoses or treatment records, relates to a patient's interaction with a medical device or healthcare provider in a way that could identify them as receiving healthcare services. | Phone numbers + consent for medical device communications (Omnipod) is classified as PHI-adjacent because it reveals a patient's relationship with a medical device manufacturer. |
| **E.164** | The international standard for phone number formatting. Format: `+[country code][subscriber number]`. Example: `+12065551234` (US), `+447911123456` (UK). Maximum 15 digits including country code. | The required phone number format for MC SMS delivery and the MuleSoft DataWeave normalization target. |
| **CometD** | A protocol for server-push communication over HTTP long-polling or WebSocket. Used by Salesforce for streaming API and platform event delivery to external subscribers. | The protocol MuleSoft's Anypoint SF Connector uses to subscribe to `ContactPointTypeConsentChangeEvent`. |
| **Anypoint Secrets Manager** | MuleSoft Anypoint Platform's credential management service. Stores secrets (API keys, passwords, certificates) encrypted at rest with per-environment isolation. | The required storage location for MC client credentials (per S-02 remediation). |
| **Replay ID** | A sequence number assigned to each platform event in Salesforce. Used by subscribers to resume event consumption from a specific point after disconnection. Replay IDs are valid for 24 hours. | Critical for event delivery reliability. If the MuleSoft connector disconnects and reconnects, it uses the last known replay ID to avoid missing events or reprocessing. See S-06. |

---

## 8. Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-03-25 | Pipeline Run NGASIM-3336-run-001 | Initial pipeline run. Artifacts 00-intake through 09-docs produced. 15 security findings (S-01 through S-15). 18 technical debt items (TD-01 through TD-18). 10 anti-pattern gates evaluated (8 PASS, 2 EVALUATE). 4 ADRs documented. |

---

## 9. CTA Domain Coverage Summary

### Domain Coverage Matrix

| # | CTA Domain | Coverage Level | Primary Owner | Key Artifacts | Gaps / Follow-Ups |
|---|-----------|---------------|---------------|---------------|-------------------|
| 1 | **Business Architecture** | **STRONG** | ba-context-analyst | 00-intake.md (business context, patient consent lifecycle), 04-review.md (business impact of gaps) | Gap: business KPI for consent conversion rate (what % of opt-in attempts complete double opt-in?) not defined. Follow-up: define success metrics with PO. |
| 2 | **Solution Architecture** | **STRONG** | sf-tech-reviewer | 02-architecture.md (ADR-001 through ADR-004), 08-refactor.md (design quality, anti-pattern gates) | Covered: end-to-end solution shape, alternatives considered (4 ADRs with rejected alternatives). Gap: no solution architecture diagram (draw.io/Lucidchart). Follow-up: create visual architecture diagram. |
| 3 | **Platform Architecture** | **STRONG** | sf-tech-reviewer | 02-architecture.md (MuleSoft CloudHub, Anypoint Platform), 07-security.md (CloudHub worker allocation, Anypoint MQ limits) | Covered: CloudHub deployment model, vCore sizing, Anypoint MQ queuing. Gap: no explicit multitenancy analysis for shared Anypoint Platform (other integrations on same CloudHub). |
| 4 | **Security / Identity** | **COMPREHENSIVE** | sf-tech-reviewer + security-reviewer | 07-security.md (STRIDE, OWASP, PII/PHI, HIPAA, TCPA, GDPR, credential management, trust boundary analysis) | Covered: all 6 STRIDE categories, OWASP API Top 10, PII/PHI classification, HIPAA provisions, consent compliance (TCPA, CAN-SPAM, GDPR). 15 findings. Remediation roadmap. Gap: penetration testing scope not defined (follow-up before production). |
| 5 | **Core Data** | **MODERATE** | sf-tech-reviewer + ba-context-analyst | 02-architecture.md (data flow), 08-refactor.md (data duplication SOT, identity alignment), 09-docs.md (field mapping) | Covered: consent data model (ContactPointTypeConsent), source-of-truth definition (SF), data duplication analysis (MC copy). Gap: no data lifecycle analysis (when are consent records archived? What happens to expired consent?). Gap: consent data quality rules not defined (duplicate phone numbers, format validation at SF level). |
| 6 | **Integration / MuleSoft** | **COMPREHENSIVE** | sf-tech-reviewer | 02-architecture.md (API-led design), 07-security.md (cross-cloud trust boundaries), 08-refactor.md (layering evaluation, DDD boundary analysis), 09-docs.md (API contract, data flow mapping, connectivity guide) | Covered: 3-layer API-led architecture, DLQ/retry/circuit breaker, credential management, deployment runbook, rollback procedure. Anti-pattern gate 5 (MuleSoft layering justified) passed. Gap: API performance benchmarks not defined (max throughput, p95 latency target). |
| 7 | **Application / UX / Automation** | **MODERATE** | sf-tech-reviewer | 02-architecture.md (consent capture flow), 04-review.md (SF consent creation UX) | Covered: consent capture mechanism (web form, agent-assisted). Gap: patient-facing UX for double opt-in confirmation SMS not designed (what does the confirmation SMS look like? What happens if patient does not respond?). Gap: MC Journey Builder flow for double opt-in not documented (MC-side configuration). |
| 8 | **Delivery / Testing / ALM** | **STRONG** | sf-tech-reviewer | 03-tdd.md (test specification), 06-e2e.md (E2E test plan), 09-docs.md (deployment runbook, rollback procedure) | Covered: test cases mapped to ACs and ADRs, deployment procedure (bottom-up), rollback procedure (top-down), health check verification. Gap: CI/CD pipeline definition (GitHub Actions / Jenkins / Anypoint CLI) not specified. Gap: staging environment promotion criteria not defined. |
| 9 | **Cross-Cloud Activation** | **STRONG** | ba-context-analyst + sf-tech-reviewer | 07-security.md (cross-cloud security assessment), 08-refactor.md (anti-pattern gates 7 and 8), 09-docs.md (cross-cloud integration guide, credential rotation) | Covered: SF↔MuleSoft↔MC connectivity, credential rotation, monitoring across clouds. Anti-pattern gate 8 (consent-identity-crosscloud) flagged HIGH RISK with mitigation. Gap: MC → SF reverse sync for STOP keyword not designed (TD-05). Gap: Data Cloud integration path not evaluated (Gate 6 N/A). |

### 10 Mandatory Lenses Coverage

| # | Lens | Covered? | Primary Artifact |
|---|------|----------|-----------------|
| 1 | Business intent | Yes | 00-intake.md — SMS double opt-in for patient consent, TCPA compliance, Omnipod medical device context |
| 2 | Scope boundary | Yes | 00-intake.md, 01-plan.md — exp-api only (prc-api and sys-api are separate stories in NGASIM-28 feature) |
| 3 | Assumptions | Partially | 02-architecture.md — MC Classic API available, CloudHub hosting, SF CDC enabled. Gap: assumption about MC environment provisioning not validated. |
| 4 | Open questions | Yes | 04-review.md — 7 open questions. 07-security.md — evaluation items. 08-refactor.md — technical debt items. |
| 5 | Tradeoffs considered | Yes | ADR-001 through ADR-004 (all with rejected alternatives). 08-refactor.md Expert Context (4 key tradeoffs). |
| 6 | Risks | Yes | 07-security.md — 15 security findings. 08-refactor.md — 18 technical debt items. Remediation roadmap with effort estimates. |
| 7 | Dependencies | Yes | MC Classic API availability, SF org configuration (CDC enabled, integration user provisioned), Anypoint Platform subscription tier, MC Connected App provisioning. |
| 8 | Security / Compliance | Yes | 07-security.md — STRIDE, OWASP, HIPAA, TCPA, CAN-SPAM, GDPR. Comprehensive security review. |
| 9 | Scale / Performance / Latency | Partially | 07-security.md — DoS analysis. 08-refactor.md — CloudHub vCore sizing. Gap: explicit throughput benchmarks and latency SLAs not defined. |
| 10 | Testing / Operational | Yes | 03-tdd.md, 06-e2e.md, 09-docs.md (runbook, health checks, alerting, failure modes, rollback). |

### Expert-Complete Assessment

| Criterion | Met? | Evidence |
|-----------|------|----------|
| Architecturally grounded — platform-native reasoning visible | **Yes** | OOTB `ContactPointTypeConsent` used. Platform Events (CDC) used. MuleSoft Anypoint SF Connector used. No unnecessary custom code. |
| Tradeoffs visible — alternatives stated and justified | **Yes** | 4 ADRs with rejected alternatives. Expert Context in 08-refactor.md documents 4 key tradeoffs. |
| Cloud boundaries clear — cross-cloud responsibilities defined | **Yes** | Trust boundary map in 07-security.md. Cross-cloud integration guide in 09-docs.md. Connectivity matrix with auth and credential rotation. |
| Trust posture clear — security, identity, consent addressed | **Yes** | STRIDE analysis. Cross-cloud trust posture matrix. PII/PHI classification. Consent compliance (TCPA, GDPR). |
| Data and activation model coherent — source-of-truth defined | **Partially** | SOT defined (SF). Data duplication analyzed. Gap: consent divergence reconciliation strategy not fully designed (TD-18). Gap: MC → SF reverse sync (TD-05). |
| Integration and automation supportable — operational readiness addressed | **Yes** | Deployment runbook. Health checks. Alerting rules. Failure modes. Rollback procedure. Credential rotation procedure. |
| Build path realistic — deployment, testing, rollback planned | **Yes** | Bottom-up deployment order. 17 test cases mapped. Rollback procedure documented. |
| Output reflects CTA-level thinking, not generic analysis | **Yes** | HIPAA-adjacent classification specific to Insulet/Omnipod. TCPA analysis specific to SMS consent. MuleSoft layering evaluated against anti-pattern gates. MC Classic API deprecation flagged as re-architecture trigger. |

**Overall: EXPERT-COMPLETE with 3 gaps requiring follow-up:**
1. Consent divergence reconciliation (TD-18) — SF/MC status can diverge
2. MC → SF reverse sync for STOP keyword (TD-05) — compliance risk
3. Performance benchmarks and latency SLAs — not defined

---

## Open Items Tracker (Consolidated from All Stages)

| # | Item | Owner | Priority | Source | Notes |
|---|------|-------|----------|--------|-------|
| OI-01 | Move MC client secret to Anypoint Secrets Manager | MuleSoft Admin | **CRITICAL** | S-02, TD-01 | Must be completed before any deployment. Secret is in plaintext in source control. |
| OI-02 | Rotate MC client secret | MC Admin + MuleSoft Admin | **CRITICAL** | S-02, TD-01 | Existing secret compromised via source control. Rotate immediately after Secrets Manager setup. |
| OI-03 | Implement log masking for phone numbers | MuleSoft Dev | **CRITICAL** | S-01, TD-02 | Create `pii-log-mask.dwl`, deploy in all 3 layers. Production deployment gate. |
| OI-04 | Implement consent state machine validation | MuleSoft Dev | **HIGH** | S-03, TD-03 | Prevent invalid consent transitions (e.g., NotSet → OptedIn). TCPA compliance. |
| OI-05 | Encrypt/mask PII in DLQ messages | MuleSoft Dev | **HIGH** | S-04, TD-04 | Phone numbers must not persist in plaintext in DLQ. |
| OI-06 | Audit MC Connected App OAuth2 scope | MC Admin | **HIGH** | S-05 | Restrict to minimum: `sms_send`, `list_and_subscribers_read`, `list_and_subscribers_write`. |
| OI-07 | Design MC → SF reverse consent sync (STOP keyword) | Integration team | **HIGH** | Gate 7, TD-05 | Without this, patient STOP keyword in MC is not reflected in SF — consent SOT divergence. |
| OI-08 | Define MC subscriber key strategy | Architecture team | **HIGH** | Gate 8, TD-06 | Recommend SF Contact ID (18-char). Must be decided before sys-api implementation. |
| OI-09 | Export MuleSoft logs to 6-year retention store | MuleSoft Admin + Compliance | **HIGH** | HIPAA §164.530(j), TD-16 | CloudHub logs expire in 30 days. HIPAA requires 6 years. |
| OI-10 | Implement replay ID persistence | MuleSoft Dev | **MEDIUM** | S-06, TD-08 | Persist to Anypoint Object Store. Prevents event loss on exp-api restart. |
| OI-11 | Add E.164 international phone format support | MuleSoft Dev | **MEDIUM** | S-07, TD-09 | Omnipod sold in 25+ countries. International phone numbers will fail with US-only format. |
| OI-12 | Adjust circuit breaker threshold to 15 min | MuleSoft Dev | **MEDIUM** | S-08, TD-10 | 5-minute threshold causes false trips during MC maintenance windows. |
| OI-13 | Design consent divergence reconciliation | Integration team | **MEDIUM** | Gate 4, TD-18 | Weekly batch job comparing SF and MC consent status. Alert on divergence. |
| OI-14 | Implement cross-system correlation ID persistence | MuleSoft Dev + SF Dev | **MEDIUM** | S-10, TD-07 | Correlation ID must persist in SF, MuleSoft, and MC for end-to-end audit. |
| OI-15 | Evaluate mTLS between MuleSoft and MC | MuleSoft Admin + MC Admin | **MEDIUM** | S-09, TD-11 | Recommended for PHI-adjacent data. MC Classic API supports mTLS. |
| OI-16 | Build centralized consent processing dashboard | MuleSoft Admin | **MEDIUM** | Gate 9, TD-14 | Anypoint Monitoring custom dashboard: event count, latency, error rate, DLQ depth. |
| OI-17 | Define CI/CD pipeline for MuleSoft deployment | DevOps | **MEDIUM** | CTA Domain 8 gap | GitHub Actions or Jenkins pipeline with secret scanning, test execution, promotion gates. |
| OI-18 | Define performance benchmarks | Architecture team | **MEDIUM** | CTA lens 9 gap | Max throughput (events/second), p95 latency target, CloudHub vCore scaling thresholds. |
| OI-19 | Pin MC Classic API version in sys-api | MuleSoft Dev | **LOW** | S-12, TD-15 | Prevent breaking changes from MC API version updates. |
| OI-20 | Design GDPR erasure flow across SF/MuleSoft/MC | Integration team + Legal | **LOW** | GDPR right to erasure | Manual process initially. Automate when consent volume justifies. |

---

## Documentation Status

| Document | Status | Notes |
|----------|--------|-------|
| Pipeline artifacts (00-intake through 09-docs) | **COMPLETE** | This run. All 10 stages produced. |
| Solution architecture diagram | **NOT YET CREATED** | Recommend draw.io/Lucidchart. Cover SF→MuleSoft→MC data flow, trust boundaries, credential flows. |
| MC Journey Builder configuration | **NOT YET DOCUMENTED** | MC-side double opt-in flow configuration (journey entry, SMS definition, confirmation handling). |
| CI/CD pipeline definition | **NOT YET CREATED** | GitHub Actions or Jenkins for MuleSoft build → test → deploy. |
| Anypoint API catalog registration | **NOT YET DONE** | Register exp-api, prc-api, sys-api in Anypoint Exchange with RAML specs. |
| HIPAA audit log export configuration | **NOT YET CONFIGURED** | S3 bucket, IAM role, log export schedule for 6-year retention. |
| Consent reconciliation runbook | **NOT YET CREATED** | Weekly batch job comparing SF `ContactPointTypeConsent` status with MC subscriber status. |
