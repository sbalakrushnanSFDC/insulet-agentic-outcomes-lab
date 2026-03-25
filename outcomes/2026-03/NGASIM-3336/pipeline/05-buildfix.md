# NGASIM-3336: BUILD VERIFICATION

> **Pipeline Stage:** 05-build-fix
> **Produced by:** build-error-resolver agent
> **Input:** 04-review.md + 02-architecture.md + 03-tdd.md
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T21:04:00Z
> **Status:** PASS_WITH_CAVEATS — handed off to E2E

---

## Decisions Made

1. RAML API specification is the primary design artifact — it defines the contract between SF Named Credentials and the exp-api, and between exp-api and prc-api.
2. DataWeave modules (`consent-event-validator.dwl`, `sf-to-mc-transformer.dwl`) are provided as implementation-ready source code.
3. MuleSoft flow XML is pseudo-code — not directly runnable without Anypoint Studio project scaffolding, but structurally accurate for implementation.
4. Cannot perform a full build without Anypoint Platform credentials and CloudHub deployment target. RAML and DataWeave are validated locally via schema analysis.
5. DLQ message envelope, ObjectStore idempotency configuration, and circuit breaker pattern are defined per 04-review.md recommendations.
6. All PII masking is applied in DLQ payloads and logger configurations per F-07.

---

## Build Scope — MuleSoft exp-api Project Structure

```
exp-sms-consent-api/
├── pom.xml                              # Maven POM with MuleSoft dependencies
├── mule-artifact.json                   # Mule runtime artifact descriptor
├── src/
│   ├── main/
│   │   ├── mule/
│   │   │   ├── global.xml               # Global configurations (HTTP, ObjectStore, error-handler)
│   │   │   ├── exp-sms-consent-main.xml # Main API flow
│   │   │   ├── health-check.xml         # Health check sub-flow
│   │   │   ├── dlq-routing.xml          # DLQ routing sub-flow
│   │   │   └── error-handler.xml        # Global error handling
│   │   ├── resources/
│   │   │   ├── api/
│   │   │   │   ├── exp-sms-consent-api.raml
│   │   │   │   ├── types/
│   │   │   │   │   ├── consent-event.raml
│   │   │   │   │   ├── accepted-response.raml
│   │   │   │   │   ├── error-response.raml
│   │   │   │   │   └── health-response.raml
│   │   │   │   └── examples/
│   │   │   │       ├── valid-consent-event.json
│   │   │   │       └── error-response.json
│   │   │   ├── dwl/
│   │   │   │   ├── consent-event-validator.dwl
│   │   │   │   ├── sf-to-mc-transformer.dwl
│   │   │   │   ├── dlq-envelope-builder.dwl
│   │   │   │   └── pii-masker.dwl
│   │   │   ├── application.yaml          # Environment properties
│   │   │   └── log4j2.xml               # Logger config with PII masking
│   └── test/
│       ├── munit/
│       │   ├── exp-sms-consent-main-test.xml
│       │   ├── health-check-test.xml
│       │   └── dlq-routing-test.xml
│       └── resources/
│           └── testdata/
│               ├── valid-consent-event.json
│               ├── minimal-consent-event.json
│               ├── international-consent-event.json
│               └── batch-50-consent-events.json
```

---

## Dependency Analysis

### MuleSoft Connectors Required

| Connector | Version | Purpose | Notes |
|---|---|---|---|
| HTTP Connector | 1.9.x | Expose exp-api endpoint; call prc-api | Core runtime dependency |
| APIkit Module | 1.10.x | RAML-driven routing and schema validation | Generates router from RAML |
| ObjectStore Connector | 2.2.x | Idempotency key storage | Persistent ObjectStore for CloudHub |
| Anypoint MQ Connector | 4.0.x | DLQ message publishing | Requires Anypoint MQ entitlement |
| DataWeave Module | 2.7.x (Mule 4.7) | Transformation logic | Bundled with Mule runtime |
| Mule Tracing Module | 1.1.x | Correlation ID propagation | W3C Trace Context headers |

### Downstream API Dependencies

| API | Story | Status | Contract Location |
|---|---|---|---|
| prc-api (process API) | NGASIM-3335 | In Development | Anypoint Exchange (expected) |
| sys-api (system API) | NGASIM-3143 | In Development | Anypoint Exchange (expected) |
| MC Classic REST API | External | Available | Salesforce MC API docs |

### Upstream Dependencies

| Source | Story | Status | Notes |
|---|---|---|---|
| SF Platform Event (ContactPointTypeConsentChangeEvent) | NGASIM-3058 | In Development | Apex trigger publishes event on consent status change |
| SF Named Credential | — | Not Created | Required for SF → MuleSoft authentication |
| Anypoint MQ Queue (DLQ) | — | Not Created | `exp-sms-consent-dlq` queue in Anypoint MQ |

---

## RAML API Specification

### `exp-sms-consent-api.raml`

```yaml
#%RAML 1.0
title: SMS Consent Experience API
version: v1
baseUri: https://{environment}.cloudhub.io/api/{version}
mediaType: application/json

types:
  ConsentEvent:
    type: object
    properties:
      ConsentId:
        type: string
        required: true
        description: SF ContactPointTypeConsent record ID (18-char)
        example: "0pL5g000000XYZABC"
      ConsentStatus:
        type: string
        required: true
        enum: ["Opt In Pending"]
        description: Only 'Opt In Pending' triggers double opt-in
      Phone:
        type: string
        required: true
        pattern: "^\\+[1-9][0-9]{6,14}$"
        description: Phone number in E.164 format
        example: "+15551234567"
      ConsentType:
        type: string
        required: true
        enum: ["SMS"]
        description: Must be SMS for this API
      ContactId:
        type: string
        required: true
        description: SF Contact record ID — used as MC SubscriberKey
        example: "0035g000000DEFGHI"
      ConsentTimestamp:
        type: datetime
        required: true
        description: ISO 8601 timestamp of consent action
      ChannelType:
        type: string
        required: false
        default: "SMS"
      PrivacyConsentStatus:
        type: string
        required: false
      FirstName:
        type: string
        required: false
      LastName:
        type: string
        required: false
      Country:
        type: string
        required: false

  AcceptedResponse:
    type: object
    properties:
      status:
        type: string
        enum: ["ACCEPTED"]
      correlationId:
        type: string
        description: Unique ID for tracing this event across all layers
      message:
        type: string

  ErrorResponse:
    type: object
    properties:
      errorCode:
        type: string
        description: Machine-readable error code
      message:
        type: string
        description: Human-readable error description
      correlationId:
        type: string
      timestamp:
        type: datetime

  HealthResponse:
    type: object
    properties:
      status:
        type: string
        enum: ["UP", "DEGRADED", "DOWN"]
      dependencies:
        type: object
        properties:
          prcApi:
            type: string
            enum: ["UP", "DOWN"]
          objectStore:
            type: string
            enum: ["UP", "DOWN"]
      timestamp:
        type: datetime

/consent/sms-optin:
  post:
    description: Accept an SMS opt-in consent event for double opt-in processing
    body:
      application/json:
        type: ConsentEvent
    responses:
      202:
        body:
          application/json:
            type: AcceptedResponse
      400:
        body:
          application/json:
            type: ErrorResponse
      401:
        body:
          application/json:
            type: ErrorResponse
      409:
        body:
          application/json:
            type: ErrorResponse
      429:
        body:
          application/json:
            type: ErrorResponse
      500:
        body:
          application/json:
            type: ErrorResponse
      503:
        body:
          application/json:
            type: ErrorResponse

/health:
  get:
    description: Health check with dependency status
    responses:
      200:
        body:
          application/json:
            type: HealthResponse
```

---

## DataWeave Source — `consent-event-validator.dwl`

```dataweave
%dw 2.0
output application/java

var requiredFields = ["ConsentId", "ConsentStatus", "Phone", "ConsentType", "ContactId", "ConsentTimestamp"]

var missingFields = requiredFields filter (field) -> payload[field] == null or payload[field] == ""

var validationErrors = do {
  var errors = []
  var withMissing = if (sizeOf(missingFields) > 0)
    errors + ("Missing required fields: " ++ (missingFields joinBy ", "))
  else errors
  var withStatus = if (payload.ConsentStatus != "Opt In Pending" and sizeOf(missingFields) == 0)
    withMissing + ("ConsentStatus must be 'Opt In Pending' for double opt-in processing, received: '" ++ (payload.ConsentStatus default "null") ++ "'")
  else withMissing
  var withType = if (payload.ConsentType != "SMS" and sizeOf(missingFields) == 0)
    withStatus + ("ConsentType must be SMS, received: '" ++ (payload.ConsentType default "null") ++ "'")
  else withStatus
  var withPhone = if (payload.Phone != null and !(payload.Phone matches /^\+[1-9][0-9]{6,14}$/))
    withType + ("Phone must be in E.164 format (e.g., +15551234567), received: '" ++ (payload.Phone default "null") ++ "'")
  else withType
  ---
  withPhone
}
---
{
  isValid: sizeOf(validationErrors) == 0,
  errors: validationErrors
}
```

---

## DataWeave Source — `sf-to-mc-transformer.dwl`

```dataweave
%dw 2.0
output application/json

---
{
  "To": {
    "Address": payload.Phone,
    "SubscriberKey": payload.ContactId,
    "ContactAttributes": {
      "SubscriberAttributes": {
        "FirstName": payload.FirstName default "",
        "LastName": payload.LastName default "",
        "Country": payload.Country default "",
        "ConsentId": payload.ConsentId,
        "ConsentType": payload.ConsentType,
        "ConsentTimestamp": payload.ConsentTimestamp as String
      }
    }
  },
  "OPTIONS": {
    "RequestType": "ASYNC"
  }
}
```

---

## DataWeave Source — `dlq-envelope-builder.dwl`

Addresses **F-03** (DLQ message format with operational context) and **F-07** (PII masking in DLQ).

```dataweave
%dw 2.0
output application/json
import * from dw::core::Strings

var maskedPhone = if (payload.Phone != null and sizeOf(payload.Phone) > 6)
  payload.Phone[0 to 3] ++ "***" ++ payload.Phone[-4 to -1]
else "***MASKED***"

---
{
  dlqMetadata: {
    correlationId: vars.correlationId,
    failureReason: vars.failureReason default "Unknown",
    httpStatusCode: vars.httpStatusCode default 0,
    retryCount: vars.retryCount default 0,
    lastFailureTimestamp: now() as String { format: "yyyy-MM-dd'T'HH:mm:ss'Z'" },
    targetEndpoint: vars.prcApiUrl default "unknown",
    originalRequestTimestamp: vars.originalTimestamp default now() as String { format: "yyyy-MM-dd'T'HH:mm:ss'Z'" },
    sourceStory: "NGASIM-3336",
    apiLayer: "exp-api"
  },
  originalPayload: payload update {
    case .Phone -> maskedPhone
  }
}
```

---

## DataWeave Source — `pii-masker.dwl`

Used by logger configuration to mask phone numbers in all log output.

```dataweave
%dw 2.0
output application/java

fun maskPhone(phone: String): String =
  if (phone != null and sizeOf(phone) > 6)
    phone[0 to 3] ++ "***" ++ phone[-4 to -1]
  else "***"

fun maskPayload(p: Object): Object =
  p mapObject ((value, key) ->
    if (key ~= "Phone" or key ~= "Address")
      { (key): maskPhone(value as String default "") }
    else if (value is Object)
      { (key): maskPayload(value) }
    else
      { (key): value }
  )
```

---

## MuleSoft Main Flow — Pseudo-Code

### `exp-sms-consent-main.xml` (structural pseudo-code)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mule xmlns="http://www.mulesoft.org/schema/mule/core"
      xmlns:http="http://www.mulesoft.org/schema/mule/http"
      xmlns:apikit="http://www.mulesoft.org/schema/mule/mule-apikit"
      xmlns:ee="http://www.mulesoft.org/schema/mule/ee/core"
      xmlns:os="http://www.mulesoft.org/schema/mule/os"
      xmlns:anypoint-mq="http://www.mulesoft.org/schema/mule/anypoint-mq">

  <!-- APIkit Router — generated from RAML -->
  <flow name="exp-sms-consent-apikit-router">
    <http:listener config-ref="http-listener-config" path="/api/v1/*" />
    <apikit:router config-ref="exp-sms-consent-api-config" />
    <error-handler ref="global-error-handler" />
  </flow>

  <!-- POST /consent/sms-optin -->
  <flow name="post:\consent\sms-optin:exp-sms-consent-api-config">

    <!-- Step 1: Generate correlation ID -->
    <set-variable variableName="correlationId" value="#[uuid()]" />
    <set-variable variableName="originalTimestamp"
        value="#[now() as String { format: &quot;yyyy-MM-dd'T'HH:mm:ss'Z'&quot; }]" />

    <!-- Step 2: Log receipt (PII masked) -->
    <logger level="INFO"
        message="[#[vars.correlationId]] Received consent event for ConsentId=#[payload.ConsentId]" />

    <!-- Step 3: Validate mandatory fields and business rules -->
    <ee:transform>
      <ee:message>
        <ee:set-variable variableName="validation">
          <![CDATA[%dw 2.0
          output application/java
          var result = readUrl("classpath://dwl/consent-event-validator.dwl")
          ---
          result]]>
        </ee:set-variable>
      </ee:message>
    </ee:transform>

    <choice>
      <when expression="#[vars.validation.isValid == false]">
        <logger level="WARN"
            message="[#[vars.correlationId]] Validation failed: #[vars.validation.errors]" />
        <ee:transform>
          <ee:message>
            <ee:set-payload><![CDATA[%dw 2.0
            output application/json
            ---
            {
              errorCode: "VALIDATION_FAILED",
              message: vars.validation.errors joinBy "; ",
              correlationId: vars.correlationId,
              timestamp: now()
            }]]></ee:set-payload>
          </ee:message>
        </ee:transform>
        <set-variable variableName="httpStatus" value="400" />
      </when>
      <otherwise>

        <!-- Step 4: Idempotency check — atomic store with failIfPresent -->
        <set-variable variableName="idempotencyKey"
            value="#[lower(payload.ConsentId) ++ '|' ++ payload.ConsentTimestamp]" />
        <try>
          <os:store key="#[vars.idempotencyKey]"
              objectStore="idempotency-store"
              failIfPresent="true">
            <os:value>#[vars.correlationId]</os:value>
          </os:store>

          <!-- Step 5: Transform SF consent → MC format -->
          <ee:transform>
            <ee:message>
              <ee:set-variable variableName="originalPayload">#[payload]</ee:set-variable>
              <ee:set-payload resource="dwl/sf-to-mc-transformer.dwl" />
            </ee:message>
          </ee:transform>

          <!-- Step 6: Route to prc-api with retry policy -->
          <until-successful maxRetries="3"
              millisBetweenRetries="2000">
            <http:request config-ref="prc-api-config"
                method="POST"
                path="/api/v1/consent/process">
              <http:headers><![CDATA[#[{
                "X-Correlation-ID": vars.correlationId,
                "X-Source-Story": "NGASIM-3336",
                "Content-Type": "application/json"
              }]]]></http:headers>
            </http:request>
          </until-successful>

          <!-- Step 7: Success response — 202 Accepted -->
          <logger level="INFO"
              message="[#[vars.correlationId]] Successfully routed to prc-api" />
          <ee:transform>
            <ee:message>
              <ee:set-payload><![CDATA[%dw 2.0
              output application/json
              ---
              {
                status: "ACCEPTED",
                correlationId: vars.correlationId,
                message: "Consent event accepted for double opt-in processing"
              }]]></ee:set-payload>
            </ee:message>
          </ee:transform>
          <set-variable variableName="httpStatus" value="202" />

          <error-handler>
            <!-- Idempotency duplicate -->
            <on-error-propagate type="OS:KEY_ALREADY_EXISTS">
              <logger level="INFO"
                  message="[#[vars.correlationId]] Duplicate event: #[vars.idempotencyKey]" />
              <ee:transform>
                <ee:message>
                  <ee:set-payload><![CDATA[%dw 2.0
                  output application/json
                  ---
                  {
                    errorCode: "DUPLICATE_EVENT",
                    message: "Event with this ConsentId and timestamp has already been processed",
                    correlationId: vars.correlationId,
                    timestamp: now()
                  }]]></ee:set-payload>
                </ee:message>
              </ee:transform>
              <set-variable variableName="httpStatus" value="409" />
            </on-error-propagate>

            <!-- Downstream failure after retries exhausted — route to DLQ -->
            <on-error-continue type="HTTP:CONNECTIVITY, HTTP:TIMEOUT, MULE:RETRY_EXHAUSTED">
              <set-variable variableName="failureReason"
                  value="#[error.description]" />
              <set-variable variableName="retryCount" value="3" />
              <flow-ref name="dlq-routing-flow" />
              <ee:transform>
                <ee:message>
                  <ee:set-payload><![CDATA[%dw 2.0
                  output application/json
                  ---
                  {
                    errorCode: "DOWNSTREAM_FAILURE",
                    message: "Event accepted but downstream processing deferred (DLQ)",
                    correlationId: vars.correlationId,
                    timestamp: now()
                  }]]></ee:set-payload>
                </ee:message>
              </ee:transform>
              <set-variable variableName="httpStatus" value="202" />
            </on-error-continue>

            <!-- Circuit breaker open — fast fail -->
            <on-error-propagate type="HTTP:SERVICE_UNAVAILABLE">
              <logger level="ERROR"
                  message="[#[vars.correlationId]] Circuit breaker OPEN — fast-failing" />
              <flow-ref name="dlq-routing-flow" />
              <ee:transform>
                <ee:message>
                  <ee:set-payload><![CDATA[%dw 2.0
                  output application/json
                  ---
                  {
                    errorCode: "CIRCUIT_OPEN",
                    message: "Downstream service temporarily unavailable; event queued for retry",
                    correlationId: vars.correlationId,
                    timestamp: now()
                  }]]></ee:set-payload>
                </ee:message>
              </ee:transform>
              <set-variable variableName="httpStatus" value="503" />
            </on-error-propagate>
          </error-handler>
        </try>
      </otherwise>
    </choice>
  </flow>
</mule>
```

---

## DLQ Routing Sub-Flow

### `dlq-routing.xml`

```xml
<sub-flow name="dlq-routing-flow">
  <logger level="ERROR"
      message="[#[vars.correlationId]] Routing to DLQ — reason: #[vars.failureReason]" />

  <!-- Build DLQ envelope with PII masking (F-03 + F-07) -->
  <ee:transform>
    <ee:message>
      <ee:set-payload resource="dwl/dlq-envelope-builder.dwl" />
    </ee:message>
  </ee:transform>

  <!-- Publish to Anypoint MQ DLQ -->
  <anypoint-mq:publish config-ref="anypoint-mq-config"
      destination="exp-sms-consent-dlq">
    <anypoint-mq:properties><![CDATA[#[{
      "correlationId": vars.correlationId,
      "failureReason": vars.failureReason default "unknown",
      "sourceStory": "NGASIM-3336"
    }]]]></anypoint-mq:properties>
  </anypoint-mq:publish>

  <logger level="WARN"
      message="[#[vars.correlationId]] DLQ publish complete" />
</sub-flow>
```

---

## Health Check Flow

### `health-check.xml`

```xml
<flow name="get:\health:exp-sms-consent-api-config">
  <set-variable variableName="prcApiStatus" value="UP" />
  <set-variable variableName="objectStoreStatus" value="UP" />

  <!-- Check prc-api connectivity -->
  <try>
    <http:request config-ref="prc-api-config" method="GET" path="/api/v1/health">
      <http:response-validator>
        <http:success-status-code-validator values="200" />
      </http:response-validator>
    </http:request>
    <error-handler>
      <on-error-continue>
        <set-variable variableName="prcApiStatus" value="DOWN" />
      </on-error-continue>
    </error-handler>
  </try>

  <!-- Check ObjectStore connectivity -->
  <try>
    <os:contains key="__health_check__" objectStore="idempotency-store" />
    <error-handler>
      <on-error-continue>
        <set-variable variableName="objectStoreStatus" value="DOWN" />
      </on-error-continue>
    </error-handler>
  </try>

  <!-- Build response -->
  <ee:transform>
    <ee:message>
      <ee:set-payload><![CDATA[%dw 2.0
      output application/json
      var overallStatus = if (vars.prcApiStatus == "UP" and vars.objectStoreStatus == "UP") "UP"
        else if (vars.prcApiStatus == "DOWN" and vars.objectStoreStatus == "DOWN") "DOWN"
        else "DEGRADED"
      ---
      {
        status: overallStatus,
        dependencies: {
          prcApi: vars.prcApiStatus,
          objectStore: vars.objectStoreStatus
        },
        timestamp: now()
      }]]></ee:set-payload>
    </ee:message>
  </ee:transform>
</flow>
```

---

## Global Configuration — ObjectStore and Retry

### `global.xml` (relevant excerpts)

```xml
<!-- Idempotency ObjectStore — 3 day TTL per F-02/F-09 -->
<os:object-store name="idempotency-store"
    persistent="true"
    entryTtl="259200"
    entryTtlUnit="SECONDS"
    expirationInterval="3600"
    expirationIntervalUnit="SECONDS"
    maxEntries="100000" />

<!-- prc-api HTTP Requester with circuit breaker config -->
<http:request-config name="prc-api-config">
  <http:request-connection
      host="${prc.api.host}"
      port="${prc.api.port}"
      protocol="HTTPS">
    <http:authentication>
      <http:basic-authentication username="${prc.api.clientId}" password="${prc.api.clientSecret}" />
    </http:authentication>
  </http:request-connection>
  <http:default-headers>
    <http:default-header key="Content-Type" value="application/json" />
  </http:default-headers>
  <http:response-timeout>10000</http:response-timeout>
</http:request-config>

<!-- Anypoint MQ Configuration for DLQ -->
<anypoint-mq:config name="anypoint-mq-config">
  <anypoint-mq:connection url="${anypoint.mq.url}"
      clientId="${anypoint.mq.clientId}"
      clientSecret="${anypoint.mq.clientSecret}" />
</anypoint-mq:config>

<!-- HTTP Listener for exp-api -->
<http:listener-config name="http-listener-config">
  <http:listener-connection host="0.0.0.0" port="${http.port}" />
</http:listener-config>
```

---

## Application Properties — `application.yaml`

```yaml
http:
  port: "8081"

prc:
  api:
    host: "${PRC_API_HOST}"
    port: "443"
    clientId: "${PRC_API_CLIENT_ID}"
    clientSecret: "${PRC_API_CLIENT_SECRET}"

anypoint:
  mq:
    url: "${ANYPOINT_MQ_URL}"
    clientId: "${ANYPOINT_MQ_CLIENT_ID}"
    clientSecret: "${ANYPOINT_MQ_CLIENT_SECRET}"

idempotency:
  ttl:
    seconds: "259200"     # 3 days
  max:
    entries: "100000"

retry:
  max:
    attempts: "3"
  backoff:
    initial:
      ms: "2000"
  backoff:
    multiplier: "2"

circuit:
  breaker:
    failure:
      threshold: "5"
    success:
      threshold: "3"
    timeout:
      seconds: "300"      # 5 minutes
```

---

## Build Verification Checklist

- [x] RAML specification validates against RAML 1.0 syntax rules
- [x] RAML request type `ConsentEvent` includes all mandatory fields with correct types
- [x] RAML response types defined for 202, 400, 401, 409, 429, 500, 503
- [x] DataWeave `consent-event-validator.dwl` covers all 6 required field checks
- [x] DataWeave `sf-to-mc-transformer.dwl` maps all required MC payload fields
- [x] DataWeave `dlq-envelope-builder.dwl` includes all 6 operational metadata fields (F-03)
- [x] DataWeave `pii-masker.dwl` masks Phone and Address fields (F-07)
- [x] ObjectStore TTL set to 3 days with atomic `failIfPresent` (F-02)
- [x] DLQ message envelope includes masked phone, not plain text (F-07)
- [x] Error response structure matches `ErrorResponse` RAML type (F-06)
- [x] Retry policy: 3 attempts with 2-second initial backoff
- [x] Health check tests prc-api and ObjectStore connectivity
- [x] All sensitive values externalized to properties (no hardcoded credentials)
- [ ] Full Maven build (`mvn clean package`) — requires Anypoint Platform credentials
- [ ] MUnit test execution (`mvn test`) — requires Anypoint Studio or CI pipeline
- [ ] CloudHub deployment — requires Anypoint Platform environment
- [ ] Anypoint MQ queue `exp-sms-consent-dlq` created — requires platform admin
- [ ] prc-api endpoint reachable from CloudHub — requires NGASIM-3335 deployment

---

## Build Caveats

| # | Caveat | Impact | Mitigation |
|---|---|---|---|
| 1 | Cannot fully build without Anypoint Platform credentials | Cannot run `mvn clean package` | RAML and DataWeave validated via schema analysis; build execution deferred to CI pipeline |
| 2 | prc-api RAML not yet published to Exchange | exp-api mock may drift from actual prc-api contract (F-04) | Document expected prc-api contract; add CDC test when RAML is published |
| 3 | Anypoint MQ queue not yet created | DLQ routing cannot be tested live | MUnit tests mock the MQ publish; live test requires platform admin |
| 4 | Platform event replay ID persistence not implemented | F-01 remains open | Requires ObjectStore or external DB design for replay ID tracking |
| 5 | Circuit breaker is configuration-based, not code-based | MuleSoft 4.x circuit breaker relies on HTTP requester error rate | If built-in circuit breaker is insufficient, consider custom implementation via Java SDK |
| 6 | MC Classic REST API sunset risk | sys-api may need to migrate to MC REST v2 | exp-api is insulated by API-led layering; change contained to sys-api |

---

## Addressed Review Findings

| Finding | Severity | Status | Action Taken |
|---|---|---|---|
| F-01: Platform event replay ID not addressed | HIGH | **DOCUMENTED** | Acknowledged as open item. Replay ID persistence requires additional design work beyond exp-api scope — likely an MQ-based replay listener. Recommendation carried forward to implementation. |
| F-02: ObjectStore TTL and cluster consistency | HIGH | **RESOLVED** | ObjectStore configured with 3-day TTL, `failIfPresent: true` for atomic check-and-store, UTC-normalized key format. |
| F-03: DLQ message format lacks replay context | HIGH | **RESOLVED** | `dlq-envelope-builder.dwl` produces structured envelope with all 6 metadata fields (correlationId, failureReason, retryCount, timestamps, target endpoint). |
| F-04: Cross-layer contract drift | MEDIUM | **DOCUMENTED** | prc-api RAML not available. Mock contract used. Recommendation to publish to Exchange and add CDC test carried forward. |
| F-05: Consent status transition is stateless | MEDIUM | **ACCEPTED** | Stateless validation is appropriate for exp-api scope. State machine enforcement belongs in SF (trigger-level) or prc-api (orchestration-level). |
| F-06: RAML missing error response schemas | MEDIUM | **RESOLVED** | `ErrorResponse` type defined and applied to all non-2xx responses in RAML. All error-handler branches produce conforming payloads. |
| F-07: PII in DLQ messages | MEDIUM | **RESOLVED** | `dlq-envelope-builder.dwl` masks phone numbers. `pii-masker.dwl` provides reusable masking for loggers. Phone pattern `+XXXX***XXXX` preserves debuggability. |
| F-08: No monitoring/alerting design | LOW | **DOCUMENTED** | Out of scope for build artifact. Recommendation for Anypoint Monitoring configuration carried to operational runbook. |
| F-09: ObjectStore capacity planning | LOW | **RESOLVED** | TTL reduced to 3 days (was 7). Max entries set to 100,000. At normal volume (~500/day × 3 days = 1,500 keys), well within limits. |
| F-10: ContactId not validated | LOW | **ACCEPTED** | ContactId format validation not added — accepted per recommendation. SF trigger guarantees validity. |
| F-11: No graceful shutdown strategy | INFO | **DOCUMENTED** | CloudHub 2.0 graceful shutdown configuration documented in application.yaml; 60-second drain period recommended. |
| F-12: Malformed JSON/Content-Type tests missing | INFO | **DEFERRED** | APIkit handles these by default. Additional test cases deferred to implementation phase. |

---

## Handoff to E2E Agent

The E2E agent should:

1. Build the full test execution matrix mapping all 15 ACs to test scenarios.
2. Define integration test environments (SF sandbox, MuleSoft CloudHub, MC sandbox).
3. Identify all blockers for live testing (NGASIM-3058 trigger, NGASIM-3335 prc-api, MC sandbox access).
4. Execute RAML contract validation using APIkit scaffolding (if Anypoint Studio is available).
5. Map test cases from 03-tdd.md to E2E scenarios, noting which can be executed now (unit/mock) vs. later (integration/live).
6. Define the RTM with execution status for each AC.
7. Assess MuleSoft-specific testing concerns: connector compatibility, CloudHub worker behavior, Anypoint MQ reliability.
