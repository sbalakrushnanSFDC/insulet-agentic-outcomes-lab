# NGASIM-3336: SECURITY REVIEW

> **Pipeline Stage:** 07-security
> **Produced by:** security-reviewer agent
> **Input:** 04-review.md findings, 02-architecture.md (ADR-001 through ADR-004), NGASIM-28 parent feature context
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T21:08:00Z
> **Status:** PASS_WITH_CAVEATS — handed off to REFACTOR

---

## Security Assessment Summary

**Overall Posture: AMBER**

The MuleSoft experience API for SMS double opt-in consent processing operates in a high-sensitivity corridor: phone numbers (PII) and medical-device consent records (PHI-adjacent under HIPAA) transit across three cloud boundaries (Salesforce → MuleSoft → Marketing Cloud). The API-led layering is architecturally sound, but the current design has three HIGH-severity gaps that must be remediated before production: PII leakage in MuleSoft runtime logs and DLQ payloads, insecure credential storage for MC Classic API, and absence of consent state-machine validation that could allow out-of-order event processing. These gaps are remediable within the existing architecture without re-design — they are implementation hardening, not structural defects.

**Key risk factors:**
- Medical device manufacturer (Insulet/Omnipod) — patients are PHI subjects under HIPAA
- Phone numbers + consent = PHI-adjacent when linked to medical device users
- Three-cloud integration expands the attack surface across trust boundaries
- SMS consent is a regulatory compliance function (TCPA, CAN-SPAM) — failure has legal exposure
- Real-time event-driven architecture means failures propagate quickly

---

## Decisions Made

1. Security scope covers the full data flow from SF `ContactPointTypeConsent` through MuleSoft exp-api/prc-api/sys-api to MC Classic REST API, including all trust boundary crossings.
2. HIPAA-adjacent classification applies because Insulet/Omnipod patients using medical devices are PHI subjects, and phone number + consent status for medical device communications constitutes protected health information when linked to a patient identity.
3. STRIDE threat model targets the consent event flow specifically — not the broader MuleSoft runtime infrastructure.
4. OWASP assessment uses the OWASP API Security Top 10 (2023) rather than web application Top 10, as the exp-api is an API endpoint.
5. Consent compliance analysis covers TCPA (SMS-specific), CAN-SPAM (commercial messaging), and GDPR (data subject rights) as all are applicable to SMS double opt-in for medical device communications.

---

## Threat Model — STRIDE Analysis

### S — Spoofing

| Threat | Attack Vector | Current Mitigation | Gap | Risk |
|--------|--------------|-------------------|-----|------|
| **Spoofed platform events** | Attacker publishes fake `ContactPointTypeConsentChangeEvent` records to the platform event channel | Platform events are published by Apex/Flow within SF org — requires authenticated SF session with appropriate object-level permissions on `ContactPointTypeConsent` | SF session-based authentication is strong. However, any user with Create permission on `ContactPointTypeConsent` can trigger the event chain. No validation that the consent change was initiated by the patient or an authorized agent. | MEDIUM |
| **Spoofed MuleSoft API request** | External caller sends fabricated consent payloads directly to the exp-api endpoint | OAuth2 client credentials for MuleSoft API access. Anypoint Platform API Manager policies for client ID enforcement. | API key/client ID validation must be enforced at the API gateway layer. If the exp-api is exposed on a public CloudHub endpoint without IP restriction, any holder of valid client credentials can submit payloads. | MEDIUM |
| **Man-in-the-middle on SF→MuleSoft** | Attacker intercepts platform event delivery to MuleSoft listener | Named Credentials enforce TLS 1.2+. MuleSoft CloudHub connector for SF uses OAuth 2.0 JWT bearer. | Named Credential configuration must pin to the correct MuleSoft endpoint. DNS hijacking of the MuleSoft CloudHub URL would redirect consent events. Certificate pinning is not natively supported in SF Named Credentials. | LOW |
| **MC API impersonation** | Attacker stands up a fake MC Classic endpoint and redirects sys-api traffic | sys-api uses hardcoded or config-driven MC endpoint URL with OAuth2 token exchange. | If the MC endpoint URL is stored in application properties (not secure vault), an attacker with access to the MuleSoft runtime could redirect consent submissions to a rogue endpoint. Secure vault + TLS certificate validation mitigates this. | MEDIUM |

### T — Tampering

| Threat | Attack Vector | Current Mitigation | Gap | Risk |
|--------|--------------|-------------------|-----|------|
| **Event payload modification** | Attacker modifies consent payload between SF and MuleSoft | TLS encryption in transit. Platform event payloads are serialized JSON. | No payload integrity hash or digital signature on the event. If TLS termination occurs at a proxy/load balancer, the payload could be modified between decryption and re-encryption. MuleSoft CloudHub uses AWS ALB — TLS terminates at the ALB. | MEDIUM |
| **Consent state manipulation** | Attacker changes consent status from `OptIn` to `OptOut` (or vice versa) in flight | No consent state validation in exp-api. The exp-api forwards whatever state it receives. | **HIGH GAP:** The exp-api does not validate that the consent state transition is valid (e.g., `NotSet → OptInPending → OptedIn`). An out-of-order or replayed event could set consent to `OptedIn` when the patient never completed double opt-in. This violates TCPA requirements. | HIGH |
| **DLQ message tampering** | Attacker modifies messages in the dead-letter queue before reprocessing | DLQ is a MuleSoft Anypoint MQ queue with access control. | DLQ messages contain the original consent payload (including phone numbers). If DLQ access is not restricted to operations team only, any MuleSoft developer could view or modify queued messages. | MEDIUM |

### R — Repudiation

| Threat | Attack Vector | Current Mitigation | Gap | Risk |
|--------|--------------|-------------------|-----|------|
| **Consent change without audit trail** | Patient disputes that they opted in to SMS; no evidence of the opt-in event chain | SF: `ContactPointTypeConsent` has `CaptureDate`, `CaptureContactPointType`, `CaptureSource`. MuleSoft: correlation ID in API headers. MC: double opt-in confirmation message timestamp. | The end-to-end audit trail is fragmented across three systems. No single query can reconstruct the full consent journey from patient action → SF record → platform event → MuleSoft processing → MC double opt-in → patient SMS confirmation. A correlation ID exists but is not persisted in all three systems. | HIGH |
| **Agent-initiated consent without patient awareness** | SF agent creates `ContactPointTypeConsent` record without patient's verbal/written consent | SF sharing and FLS control who can create consent records. No additional validation that patient actually consented. | No "consent witness" mechanism. The `CaptureSource` field could be set to any value. For HIPAA-adjacent SMS consent, the consent capture method (verbal, written, electronic) should be recorded and immutable. | MEDIUM |

### I — Information Disclosure

| Threat | Attack Vector | Current Mitigation | Gap | Risk |
|--------|--------------|-------------------|-----|------|
| **PII in MuleSoft runtime logs** | Phone numbers logged in INFO/DEBUG level MuleSoft flow logs | No log masking configured in current design. | **HIGH GAP:** MuleSoft default logging includes full payload at DEBUG level. Phone numbers in the consent event will appear in CloudHub runtime logs, Anypoint Monitoring, and any log aggregation tool (Splunk, ELK). These logs are accessible to all MuleSoft developers with CloudHub admin/developer role. Phone numbers of medical device patients are PHI-adjacent. | CRITICAL |
| **PII in DLQ messages** | Failed consent events persist in DLQ with full payload including phone number | DLQ is an Anypoint MQ queue. Standard access control. | **HIGH GAP:** DLQ messages retain the original payload including `ContactPointPhone` (phone number). DLQ messages may persist for days/weeks depending on TTL configuration. Any user with Anypoint MQ browse permission can read the phone numbers. No encryption at rest for Anypoint MQ messages by default. | HIGH |
| **PII in error responses** | MuleSoft exp-api returns error messages containing phone number or consent details | API error handling returns generic 500 with correlation ID. | Error responses should never include PII in the response body. Verify that DataWeave error handlers do not include the input payload in error payloads. MC API error responses may echo back the request body — sys-api must strip PII before logging. | MEDIUM |
| **PII in API analytics** | Anypoint Platform API analytics captures request/response metadata | API analytics captures URL, headers, status codes. Body capture is configurable. | Ensure API analytics policy does NOT log request/response bodies. URL should not contain phone numbers (they should be in the body, not path parameters). Verify RAML design uses POST with body, not GET with query params. | LOW |

### D — Denial of Service

| Threat | Attack Vector | Current Mitigation | Gap | Risk |
|--------|--------------|-------------------|-----|------|
| **Platform event flood** | Large batch update on `ContactPointTypeConsent` generates thousands of change events simultaneously | MuleSoft SF connector has configurable polling interval and batch size. | A bulk data load (e.g., consent migration) could generate a spike of platform events that overwhelms the exp-api. The circuit breaker at 5-minute threshold may trip prematurely during legitimate batch operations. Rate limiting on the exp-api should distinguish between steady-state and batch scenarios. | MEDIUM |
| **DLQ overflow** | Sustained MC API outage causes all consent events to route to DLQ until queue limit reached | DLQ with retry and exponential backoff. | Anypoint MQ has queue depth limits. If MC is down for an extended period, the DLQ will fill. No alerting configured for DLQ depth approaching limits. No overflow queue or secondary storage for events exceeding DLQ capacity. | MEDIUM |
| **MC Classic API rate limiting** | High-volume consent processing hits MC API rate limits | Retry with exponential backoff in sys-api. | MC Classic REST API has rate limits (not publicly documented per-endpoint). If the sys-api does not implement proper rate-limit response handling (429 status), it will treat rate-limited responses as errors and route to DLQ, causing artificial failure rates. | MEDIUM |

### E — Elevation of Privilege

| Threat | Attack Vector | Current Mitigation | Gap | Risk |
|--------|--------------|-------------------|-----|------|
| **MuleSoft API scope creep** | OAuth2 client credentials grant broader MC API scope than needed | OAuth2 scope configuration in MC Connected App. | The OAuth2 scope for MC Classic API should be limited to the specific endpoints needed for double opt-in (SMS send, subscriber upsert). If the scope includes `email_send`, `data_extension_write`, or `automation_execute`, a compromised MuleSoft credential could be used to send unauthorized messages or modify MC data. | HIGH |
| **SF integration user over-provisioning** | MuleSoft uses a SF integration user with admin-level permissions | Named Credential with dedicated integration user. | The integration user that MuleSoft uses to subscribe to platform events must have ONLY: Read on `ContactPointTypeConsent`, Read on `ContactPointTypeConsentChangeEvent`. No Create/Update/Delete on any object. No Apex execution. No Setup access. | MEDIUM |
| **Cross-layer privilege escalation** | exp-api passes authenticated context to prc-api and sys-api without re-validation | API-led layering with internal communication between layers. | Each MuleSoft layer (exp/prc/sys) should independently validate authorization. The exp-api authenticates the inbound SF event; the prc-api should re-validate that the event is well-formed; the sys-api should use its own dedicated MC credential (not inherit from exp-api). | MEDIUM |

---

## OWASP API Security Top 10 Assessment (2023)

| # | Risk | Applicability | Assessment | Status |
|---|------|--------------|------------|--------|
| API1 | Broken Object-Level Authorization | HIGH — consent records are per-patient | The exp-api processes `ContactPointTypeConsent` events without verifying that the originating user had authorization to modify that specific patient's consent. SF enforces CRUD/FLS but not record-level sharing in platform events — the event fires regardless of the publisher's sharing access. | **EVALUATE** — add consent record ownership validation |
| API2 | Broken Authentication | HIGH — OAuth2 flows across 3 boundaries | SF→MuleSoft: Named Credential with OAuth2 JWT bearer. MuleSoft internal: mTLS or shared secret. MuleSoft→MC: OAuth2 client credentials. Token refresh must handle concurrent requests. If token refresh fails, all three layers halt. | **PASS** with caveat: implement token refresh retry and cache |
| API3 | Broken Object Property-Level Authorization | MEDIUM — consent event contains multiple fields | The `ContactPointTypeConsentChangeEvent` payload includes all changed fields. The exp-api DataWeave transformation should whitelist specific fields (ConsentStatus, ContactPointPhone, CaptureDate) and discard unexpected fields. Mass assignment from event payload to MC subscriber could inject unintended attributes. | **EVALUATE** — verify DataWeave field whitelist |
| API4 | Unrestricted Resource Consumption | MEDIUM — batch consent events could spike | No rate limiting on the exp-api for inbound platform events. The SF connector pulls events at the configured polling interval. Burst handling depends on MuleSoft worker thread capacity. CloudHub vCore allocation determines throughput ceiling. | **EVALUATE** — define max throughput and back-pressure strategy |
| API5 | Broken Function-Level Authorization | LOW — exp-api has single function (consent relay) | The exp-api performs one function: receive consent event and forward to prc-api. No admin endpoints, no CRUD operations, no configuration endpoints. If debug/health endpoints are exposed without authentication, they could leak operational data. | **PASS** — verify no debug endpoints in production |
| API6 | Unrestricted Access to Sensitive Business Flows | HIGH — double opt-in is a compliance flow | The double opt-in flow must not be bypassable. If a caller can submit a consent event directly to the prc-api or sys-api (bypassing exp-api validation), they could register a phone number for SMS without the patient's consent. Each layer must independently validate the consent payload structure. | **EVALUATE** — verify each layer validates independently |
| API7 | Server-Side Request Forgery (SSRF) | LOW — no user-supplied URLs in the flow | The exp-api does not accept URLs as input. The MC endpoint URL is configured server-side. No SSRF vector unless the event payload contains a URL field that the DataWeave transformation follows. | **PASS** — no URL fields in consent event payload |
| API8 | Security Misconfiguration | MEDIUM — multi-layer config surface area | Three MuleSoft applications (exp/prc/sys) each have independent configuration. Misconfiguration in any layer (wrong MC endpoint, incorrect OAuth scope, disabled TLS verification) breaks the security chain. Configuration drift between environments (dev/staging/prod) is a risk. | **EVALUATE** — implement config validation on deployment |
| API9 | Improper Inventory Management | MEDIUM — 3 APIs across 2 clouds | The exp-api, prc-api, and sys-api must be tracked in the Anypoint Platform API catalog. API versioning must be consistent. Deprecated API versions must be decommissioned. If an old version of the sys-api uses a deprecated MC endpoint, consent submissions may silently fail. | **EVALUATE** — verify API catalog registration |
| API10 | Unsafe Consumption of APIs | HIGH — sys-api consumes MC Classic REST API | The sys-api trusts MC API responses without validation. If MC returns unexpected response structure (API version change, deprecation), the sys-api may misinterpret the response. MC Classic API is legacy — Salesforce has signaled migration to MC APIs v2. Response schema validation is critical. | **EVALUATE** — add MC response schema validation |

---

## PII / PHI Analysis

### Data Classification

| Data Element | Classification | Justification | Encryption Requirement |
|-------------|---------------|---------------|----------------------|
| Phone number (`ContactPointPhone`) | **PII** — upgrades to **PHI-adjacent** in this context | Standalone: PII under CCPA/GDPR. In Insulet context: phone number linked to medical device patient identity constitutes information that, combined with other data, identifies a patient receiving healthcare services. | TLS 1.2+ in transit (mandatory). AES-256 at rest in DLQ and logs (required). Field-level encryption in SF via Shield (recommended). |
| Consent status (`ConsentStatus`) | **PHI-adjacent** | Consent to receive SMS about medical device (Omnipod) constitutes information about a patient's relationship with a healthcare product. A patient's opt-in/opt-out status for medical device communications is health-related. | TLS 1.2+ in transit. Standard encryption at rest. |
| Consent capture date (`CaptureDate`) | **Business data** — **PHI-adjacent when combined** | Timestamp alone is not sensitive. Combined with phone number and consent status, it documents when a patient consented to medical device communications. | Standard transit encryption. |
| Patient identity (`ContactPointTypeConsent.PartyId` → Account/Contact) | **PHI** | Direct link to patient record in Salesforce. The `PartyId` resolves to a PersonAccount that contains medical device information, therapy data, and insurance details. | Never include `PartyId` in MuleSoft logs. Strip before DLQ storage. |
| MC Subscriber Key | **PII** | The subscriber key in MC may be an email, phone, or SF Contact ID. If it contains the phone number or a resolvable SF ID, it is PII. | TLS in transit. MC encryption at rest per MC security model. |

### HIPAA Considerations

| HIPAA Provision | Applicability | Current Design | Gap |
|----------------|--------------|----------------|-----|
| **§164.312(a)(1)** — Access control | The exp-api processes PHI-adjacent data. Only authorized systems should access the consent event stream. | MuleSoft integration user has Named Credential access to SF platform events. MuleSoft worker processes consume events. | No access logging for who/what consumed platform events. MuleSoft runtime logs are the only record. Add explicit access audit events. |
| **§164.312(c)(1)** — Integrity controls | Consent event payload must not be altered in transit. | TLS provides transport-layer integrity. | No application-layer integrity check (hash, signature). If TLS is terminated at a load balancer or proxy, the payload could be modified. Consider HMAC signature on the event payload for end-to-end integrity. |
| **§164.312(d)** — Person/entity authentication | The MuleSoft system consuming events must be authenticated. | OAuth2 JWT bearer for SF→MuleSoft. OAuth2 client credentials for MuleSoft→MC. | Authentication is system-to-system. No per-event authentication (events are consumed from a subscription, not individually authenticated). Acceptable for event-driven architecture. |
| **§164.312(e)(1)** — Transmission security | PHI-adjacent data (phone + consent) transmitted across SF→MuleSoft→MC. | TLS 1.2+ on all connections. | mTLS between MuleSoft and MC is not configured. For PHI-adjacent data, mTLS provides additional assurance that both endpoints are authenticated. MC Classic API supports mTLS — evaluate implementation. |
| **§164.530(j)** — Documentation retention | Consent records and audit trails must be retained for 6 years. | SF: `ContactPointTypeConsent` records persist per org retention. MuleSoft: log retention per CloudHub plan (default 30 days). MC: subscriber records persist per MC retention. | **GAP:** MuleSoft logs (which contain the consent processing audit trail) are retained for only 30 days by default. For HIPAA, the consent processing audit trail must be retained for 6 years. Export MuleSoft consent processing logs to a long-term store (S3, Glacier, or a HIPAA-compliant log aggregation service). |
| **§164.528** — Accounting of disclosures | Patients have the right to know who accessed their PHI. | No disclosure tracking in the consent event flow. | **GAP:** When the exp-api relays consent data to MC, that constitutes a disclosure of PHI-adjacent data to a third-party system. An accounting of this disclosure (what data, when, to whom) should be maintained. Log each consent event relay with timestamp, patient identifier (hashed), destination system, and correlation ID. |

### Data Flow PII Exposure Map

```
SF Org (ContactPointTypeConsent)
  │
  │ Platform Event (ContactPointTypeConsentChangeEvent)
  │   Contains: PartyId, ContactPointPhone, ConsentStatus, CaptureDate
  │   PII Risk: Phone number in event payload ← EXPOSURE POINT 1
  │
  ▼
MuleSoft exp-api (CloudHub)
  │ Runtime logs: full payload at DEBUG level ← EXPOSURE POINT 2 (CRITICAL)
  │ Error logs: payload in exception messages ← EXPOSURE POINT 3
  │ DLQ: failed events with full payload ← EXPOSURE POINT 4 (HIGH)
  │ API analytics: request metadata ← EXPOSURE POINT 5 (LOW)
  │
  ▼
MuleSoft prc-api (CloudHub)
  │ DataWeave transformation: phone number in mapping ← EXPOSURE POINT 6
  │ Runtime logs: transformed payload ← EXPOSURE POINT 7
  │
  ▼
MuleSoft sys-api (CloudHub)
  │ MC API request body: phone number + consent ← EXPOSURE POINT 8
  │ MC API response logging ← EXPOSURE POINT 9
  │
  ▼
MC Classic REST API
  │ Subscriber record: phone number persists ← EXPOSURE POINT 10
  │ SMS send log: phone number + message ← EXPOSURE POINT 11
  │
  ▼
Patient receives SMS (double opt-in confirmation)
```

**Total PII exposure points: 11**
**Exposure points requiring immediate remediation: 4 (Points 2, 3, 4, 7)**

---

## Credential Management Assessment

### OAuth2 Flow Inventory

| Connection | OAuth2 Grant | Token Endpoint | Token Lifetime | Refresh Strategy | Storage |
|-----------|-------------|---------------|---------------|-----------------|---------|
| SF → MuleSoft (platform event subscription) | JWT Bearer | SF OAuth token endpoint | 2 hours (SF default) | Auto-refresh by MuleSoft SF connector | MuleSoft Secure Properties (encrypted) |
| MuleSoft exp-api → prc-api | Internal (no OAuth — same CloudHub VPC) | N/A | N/A | N/A | Internal routing — no credential needed if same VPC |
| MuleSoft prc-api → sys-api | Internal (same VPC) or Client Credentials (cross-VPC) | MuleSoft Anypoint token endpoint | Configurable | Auto-refresh by HTTP Requester | Secure Properties |
| MuleSoft sys-api → MC Classic API | Client Credentials | `https://YOUR_SUBDOMAIN.auth.marketingcloudapis.com/v2/token` | 20 minutes (MC default) | Must implement proactive refresh before expiry | **GAP: currently in application properties — must move to Secure Configuration Properties or Anypoint Secrets Manager** |

### Credential Storage Findings

| Credential | Current Storage | Required Storage | Severity |
|-----------|----------------|-----------------|----------|
| MC Client ID | Application properties (`mule-artifact.json` or `config.yaml`) | Anypoint Secrets Manager or Secure Configuration Properties (encrypted at rest, runtime-only decryption) | **HIGH** |
| MC Client Secret | Application properties | Anypoint Secrets Manager (NEVER in source control, NEVER in plaintext properties) | **CRITICAL** |
| SF Connected App Consumer Key | MuleSoft Secure Properties | MuleSoft Secure Properties (acceptable) | PASS |
| SF Connected App Private Key (JWT) | MuleSoft Secure Properties | MuleSoft Secure Properties + key rotation every 12 months | PASS |
| MuleSoft Anypoint Platform credentials | CI/CD pipeline variables | CI/CD secrets (GitHub Actions secrets / Jenkins credentials store) | PASS |

### Token Refresh Failure Scenarios

| Scenario | Impact | Mitigation |
|---------|--------|------------|
| SF JWT token refresh fails | exp-api cannot subscribe to platform events. Events accumulate in SF (24-hour retention). If not resolved within 24 hours, events are lost. | Alert on token refresh failure. Implement retry with exponential backoff (1min, 2min, 4min, 8min). After 30 minutes of failure, page on-call. |
| MC OAuth token refresh fails | sys-api cannot submit consent to MC. Events route to DLQ. Double opt-in SMS not sent. | Alert on token refresh failure. DLQ provides buffer. MC token endpoint availability is MC's SLA. Implement circuit breaker on token endpoint. |
| MC OAuth token endpoint returns 401 (credential rotation) | MC client secret was rotated without updating MuleSoft config. All consent processing halts. | **Credential rotation runbook required.** Coordinate MC secret rotation with MuleSoft Secure Properties update. Zero-downtime rotation: update MuleSoft properties, restart worker, verify new token. |

---

## CRUD/FLS Matrix — Salesforce Side

### ContactPointTypeConsent

| Profile / Permission Set | Create | Read | Update | Delete | FLS Restrictions |
|-------------------------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| MuleSoft Integration User | No | **Yes** | No | No | Read-only. Fields needed: `Id`, `PartyId`, `ContactPointId`, `PrivacyConsentStatus`, `CaptureDate`, `CaptureSource`, `CaptureContactPointType`. **No write access.** |
| Patient Care Agent | No | Yes | Yes | No | Can update consent status when patient requests change via phone. Must log reason in `CaptureSource`. |
| Inside Sales Agent | No | Yes | No | No | Read-only. Inside Sales does not manage consent. |
| Marketing Operations | Yes | Yes | Yes | No | Creates consent records for bulk consent imports. FLS: all fields. |

### ContactPointTypeConsentChangeEvent (Platform Event)

| Profile / Permission Set | Subscribe | Publish | Notes |
|-------------------------|-----------|---------|-------|
| System Administrator | Yes | Yes (implicit — triggers on DML) | Full access |
| MuleSoft Integration User | **Yes** | No | Subscribes via CometD / Streaming API. Only needs Subscribe permission on the event channel. |
| Apex Triggers / Flows | N/A | Yes (implicit) | Platform events fire automatically on `ContactPointTypeConsent` DML. No explicit publish permission needed. |

### et4ae5__SMSDefinition__c (MC Connect Managed Package)

| Profile / Permission Set | Create | Read | Update | Delete | Notes |
|-------------------------|--------|------|--------|--------|-------|
| System Administrator | Yes | Yes | Yes | Yes | Managed package — access via `et4ae5__` namespace |
| MuleSoft Integration User | No | **Yes** | No | No | Read-only — used to resolve SMS definition IDs for MC API calls. May need `et4ae5__` FLS grants. |
| Marketing Operations | Yes | Yes | Yes | No | Manages SMS definitions/templates |

---

## Cross-Cloud Security — Trust Boundary Analysis

### Trust Boundary Map

```
┌─────────────────────────────────────────────────────────┐
│  TRUST ZONE 1: Salesforce Org                           │
│  Auth: SF Session / OAuth 2.0                           │
│  Encryption: SF Shield (optional), TLS 1.2+             │
│  Governance: SF sharing model, FLS, CRUD                │
│                                                         │
│  ContactPointTypeConsent ──► Platform Event Channel     │
└──────────────────────────┬──────────────────────────────┘
                           │
                    TLS 1.2+ / OAuth2 JWT Bearer
                    Named Credential enforced
                           │
┌──────────────────────────▼──────────────────────────────┐
│  TRUST ZONE 2: MuleSoft CloudHub (Anypoint Platform)    │
│  Auth: Anypoint Platform RBAC                           │
│  Encryption: TLS 1.2+ in transit, Secure Properties     │
│  Governance: API Manager policies, Environment access   │
│                                                         │
│  exp-api ──► prc-api ──► sys-api                        │
│      │                       │                          │
│      └── DLQ (Anypoint MQ) ──┘                          │
└──────────────────────────┬──────────────────────────────┘
                           │
                    TLS 1.2+ / OAuth2 Client Credentials
                    mTLS: NOT CONFIGURED (GAP)
                           │
┌──────────────────────────▼──────────────────────────────┐
│  TRUST ZONE 3: Marketing Cloud (MC Classic)             │
│  Auth: MC OAuth2 (MC Connected App)                     │
│  Encryption: MC platform encryption at rest, TLS 1.2+   │
│  Governance: MC Business Unit isolation, role-based      │
│                                                         │
│  MC Classic REST API ──► Subscriber ──► SMS Send        │
└─────────────────────────────────────────────────────────┘
```

### Cross-Cloud Credential Rotation Schedule

| Credential | Rotation Frequency | Rotation Owner | Impact of Missed Rotation |
|-----------|-------------------|----------------|--------------------------|
| SF Connected App Consumer Secret | 12 months (per SF security best practice) | SF Admin + MuleSoft Admin (coordinated) | MuleSoft cannot authenticate to SF. Platform event subscription fails. Consent events accumulate (24hr retention). |
| SF Connected App Digital Certificate (JWT) | 12 months or on certificate expiry | SF Admin + MuleSoft Admin | Same as above — JWT bearer flow fails. |
| MC Client ID / Secret | 12 months (MC best practice) | MC Admin + MuleSoft Admin (coordinated) | MuleSoft cannot submit to MC. Consent events route to DLQ. Double opt-in SMS delayed. |
| MuleSoft Anypoint Platform token | Per CI/CD pipeline rotation policy | DevOps | Deployment pipeline breaks. No impact on running integrations. |

### IP Allowlisting

| Source | Destination | IP Range | Status |
|--------|------------|----------|--------|
| MuleSoft CloudHub (US East) | MC REST API endpoint | CloudHub static IP range (Anypoint VPC Firewall rules) | **EVALUATE** — determine if MC accepts IP allowlisting for REST API access |
| SF Org | MuleSoft CloudHub (exp-api) | SF outbound IP ranges (published by Salesforce) | **EVALUATE** — Named Credential target must be reachable from SF outbound IPs |
| MuleSoft CloudHub | SF Streaming API (platform events) | CloudHub static IP range → SF org | SF Connected App can restrict IP ranges. **Recommend:** enable IP restriction on the SF Connected App to CloudHub static IPs only. |

### mTLS Evaluation

| Connection | mTLS Supported | mTLS Configured | Recommendation |
|-----------|---------------|-----------------|----------------|
| SF → MuleSoft | Yes (Named Credential supports mutual TLS) | No | **Recommend** for PHI-adjacent data. SF Named Credential can present a client certificate. MuleSoft can validate it at the API gateway. |
| MuleSoft exp-api → prc-api | Yes (internal mTLS in Anypoint VPC) | No (same VPC) | Not needed if within same Anypoint VPC and CloudHub DLB. If cross-VPC, implement mTLS. |
| MuleSoft sys-api → MC | Yes (MC REST API supports mTLS) | **No — GAP** | **Recommend** for HIPAA-adjacent context. MC supports mTLS on Classic REST API. Provides bidirectional authentication beyond OAuth2. |

---

## Consent Compliance Assessment

### TCPA (Telephone Consumer Protection Act)

| Requirement | Design Response | Gap |
|------------|----------------|-----|
| **Prior express written consent** required for non-emergency healthcare messages | Double opt-in flow: patient opts in via SF → confirmation SMS sent → patient confirms. The double opt-in pattern satisfies "express written consent" for SMS. | **The exp-api must guarantee delivery to MC.** If an opt-in event is lost (DLQ overflow, unrecoverable error), the patient never receives the confirmation SMS, and the consent journey is incomplete. The patient believes they opted in but never receives confirmation. This is a compliance risk if Insulet later sends marketing SMS based on the SF-side OptIn status without MC-side confirmation. |
| **Opt-out must be honored within 10 business days** (FCC rule) | Opt-out events flow through the same exp-api pipeline. MC processes the opt-out and stops SMS immediately. | The exp-api must process opt-out events with **higher priority than opt-in events**. If the DLQ is full of failed opt-in events and an opt-out arrives, the opt-out must not be delayed. Implement priority queue or separate opt-out channel. |
| **Consent records must be retained** for 5 years after last consent action | SF: `ContactPointTypeConsent` persists in org. MC: subscriber consent status persists. MuleSoft: logs retained 30 days. | **GAP:** The MuleSoft processing audit trail (which connects the SF consent record to the MC subscriber action) is lost after 30 days. For TCPA litigation, the full chain of evidence is needed. |

### CAN-SPAM (Controlling the Assault of Non-Solicited Pornography And Marketing Act)

| Requirement | Design Response | Gap |
|------------|----------------|-----|
| **Commercial messages must include opt-out mechanism** | MC SMS includes opt-out instructions (STOP keyword). MC handles STOP keyword processing natively. | Verify that MC SMS template includes opt-out language. This is MC configuration, not MuleSoft. |
| **Opt-out requests honored within 10 days** | Same as TCPA — opt-out events processed via exp-api. | Same as TCPA — prioritize opt-out events. |

### GDPR (General Data Protection Regulation)

| Requirement | Design Response | Gap |
|------------|----------------|-----|
| **Lawful basis for processing** | Consent (Article 6(1)(a)) — patient explicitly opts in. | The consent record must capture the specific purpose (SMS about Omnipod). Broad consent ("marketing communications") is insufficient under GDPR. Verify `CaptureSource` and any custom fields capture the specific purpose. |
| **Right to erasure (Article 17)** | Patient can request deletion of consent records. | **GAP:** If a patient exercises right to erasure, the `ContactPointTypeConsent` record in SF must be deleted, the MC subscriber record must be deleted, and the MuleSoft processing logs must be purged. No automated erasure flow exists across three systems. Manual process required. |
| **Data minimization** | Only collect phone number and consent status necessary for SMS double opt-in. | Verify that the platform event payload does not include unnecessary fields (patient address, medical info, insurance data). The DataWeave transformation should whitelist only required fields. |

---

## Security Findings

| # | Severity | Category | Finding | Recommendation |
|---|----------|----------|---------|----------------|
| S-01 | **CRITICAL** | PII Exposure | **Phone numbers logged in MuleSoft runtime logs at DEBUG/INFO level.** MuleSoft default logging includes full payload. Phone numbers of medical device patients appear in CloudHub runtime logs, Anypoint Monitoring, and log aggregation tools. Accessible to all MuleSoft developers with CloudHub admin/developer role. In HIPAA-adjacent context, this constitutes unauthorized disclosure of PHI-adjacent data. | (1) Implement log masking in all three MuleSoft layers using `com.mulesoft.extension.mq.logging.mask` or custom DataWeave log sanitizer. (2) Mask phone numbers in logs: replace digits 4-8 with asterisks (`+1***-***-1234`). (3) Set production log level to WARN (not INFO or DEBUG). (4) Disable payload logging in Anypoint Monitoring for the consent API group. (5) Add log masking as a deployment gate — no promotion to production without verified masking. |
| S-02 | **CRITICAL** | Credential Storage | **MC Classic API client secret stored in application properties (plaintext).** The OAuth2 client secret for MC API authentication is stored in `config.yaml` or `mule-artifact.json` as a plaintext property. This file is committed to source control (Anypoint Design Center or GitHub). Any developer with repository access can read the MC API secret. A compromised secret allows sending SMS to any subscriber in the MC Business Unit. | (1) Move MC client secret to Anypoint Secrets Manager immediately. (2) Rotate the current MC client secret — it has been exposed in source control. (3) Use Secure Configuration Properties (`${secure::mc.client.secret}`) with encryption key stored in CloudHub environment variables. (4) Add `.gitignore` rule for any file containing `client_secret`. (5) Implement secret scanning in CI/CD pipeline to prevent future plaintext secret commits. |
| S-03 | **HIGH** | Consent Integrity | **No consent state machine validation in exp-api.** The exp-api forwards consent events to MC without validating state transitions. Valid transitions: `NotSet → OptInPending → OptedIn`, `OptedIn → OptedOut`, `OptedOut → OptInPending → OptedIn`. Invalid: `NotSet → OptedIn` (skips double opt-in), `OptedOut → OptedIn` (skips re-confirmation). An out-of-order or replayed event could register consent in MC without patient confirmation, violating TCPA. | (1) Implement state machine validation in exp-api (or prc-api business logic layer). (2) Query current consent state from SF before forwarding to MC. (3) Reject invalid transitions with a specific error code. Route rejected events to a review queue (not DLQ). (4) Log all rejected transitions with correlation ID for compliance audit. |
| S-04 | **HIGH** | PII Exposure | **DLQ messages contain full payload including phone numbers.** Failed consent events persist in Anypoint MQ DLQ with the original payload. DLQ messages may persist for weeks. Any user with Anypoint MQ browse permission can read phone numbers. No encryption at rest for Anypoint MQ by default. | (1) Encrypt DLQ messages at rest using Anypoint MQ encryption (if available) or implement application-level encryption before DLQ write. (2) Mask phone numbers in DLQ payloads — store a hash of the phone number for correlation, not the plaintext number. (3) Restrict Anypoint MQ browse permission to operations team only. (4) Set DLQ TTL to 7 days maximum. (5) Implement DLQ drain process that logs to HIPAA-compliant long-term store before purging. |
| S-05 | **HIGH** | API Scope | **MC OAuth2 scope may be broader than needed.** If the MC Connected App OAuth2 scope includes permissions beyond SMS send and subscriber upsert, a compromised MuleSoft credential could send unauthorized messages, modify subscriber data, or execute automations in MC. | (1) Audit MC Connected App OAuth2 scope. Restrict to: `sms_send`, `list_and_subscribers_read`, `list_and_subscribers_write`. (2) Remove any scope that includes `email_send`, `data_extension_write`, `automation_execute`, `journeys_execute`. (3) Document the minimum required scope in the integration runbook. (4) Review scope quarterly. |
| S-06 | **MEDIUM** | Replay Attack | **No replay ID tracking for platform event gap detection.** MuleSoft SF connector subscribes to platform events using CometD. If the connector disconnects and reconnects, it resumes from the last known replay ID. If the replay ID is not persisted, the connector may miss events or reprocess events. Missed events = lost consent actions. Reprocessed events = duplicate MC subscriber updates (idempotent if designed correctly). | (1) Persist replay ID to an external store (Anypoint Object Store or database). (2) On reconnect, resume from persisted replay ID. (3) Alert if replay ID gap exceeds threshold (e.g., 100 events between last persisted ID and current). (4) Implement replay ID reconciliation job that compares SF event count with MuleSoft processed count. |
| S-07 | **MEDIUM** | Data Validation | **DataWeave transformation does not handle international phone format.** The consent event `ContactPointPhone` may contain international phone numbers (E.164 format: `+countrycode-number`). If the DataWeave transformation assumes US-only format (10 digits, `+1` prefix), international patient numbers will fail transformation and route to DLQ. Insulet operates globally (Omnipod is sold in 25+ countries). | (1) Implement E.164 format validation in DataWeave: accept `+` followed by 7-15 digits. (2) Do not strip country code — MC needs full international number for SMS delivery. (3) Log format validation failures as WARN (not ERROR) to avoid false alerting. (4) Add test cases for UK (`+44`), Germany (`+49`), Australia (`+61`), and other Omnipod markets. |
| S-08 | **MEDIUM** | Availability | **Circuit breaker threshold (5 min) may cause false positives during MC maintenance.** The circuit breaker trips after 5 minutes of sustained MC API failures. MC Classic API has scheduled maintenance windows (typically Saturday 12:00-16:00 CT). A 5-minute threshold during a maintenance window would trip the circuit breaker, routing all events to DLQ, even though MC will recover. | (1) Increase circuit breaker threshold to 15 minutes for the MC API connection. (2) Implement maintenance window awareness: during known MC maintenance windows, switch to a "maintenance mode" that queues events locally instead of routing to DLQ. (3) Add circuit breaker state (CLOSED/OPEN/HALF-OPEN) to the health check endpoint. (4) Alert on circuit breaker state change (not just on individual failures). |
| S-09 | **MEDIUM** | Encryption | **No mutual TLS between MuleSoft sys-api and MC Classic API.** The connection uses OAuth2 client credentials over standard TLS. For PHI-adjacent data, mTLS provides additional assurance that both endpoints are authenticated at the transport layer, preventing man-in-the-middle attacks even if OAuth2 tokens are compromised. | (1) Evaluate mTLS implementation between MuleSoft and MC. (2) MC Classic API supports client certificate authentication. (3) Generate a client certificate for the MuleSoft sys-api. Configure MC to require the certificate. (4) Store the client certificate private key in Anypoint Secrets Manager (not in application resources). |
| S-10 | **MEDIUM** | Audit Trail | **Fragmented audit trail across three systems.** The consent journey spans SF (consent record), MuleSoft (processing logs), and MC (subscriber + SMS send). No single query reconstructs the full chain. For TCPA litigation or HIPAA audit, proving the end-to-end consent journey requires manual correlation across three systems. | (1) Implement a correlation ID that persists in all three systems: SF `ContactPointTypeConsent.CorrelationId__c`, MuleSoft correlation ID header, MC subscriber custom attribute. (2) Build a consent audit API that queries all three systems by correlation ID. (3) Export the correlation log to a HIPAA-compliant audit store with 6-year retention. |
| S-11 | **LOW** | Header Validation | **Inbound API headers not validated for required fields.** The exp-api should validate that required headers (Content-Type, correlation ID, client ID) are present and correctly formatted before processing. Missing headers should return 400, not 500. | (1) Add API Manager policy for required header validation. (2) Return 400 with descriptive error (no PII in error body) for missing/malformed headers. (3) Log header validation failures at INFO level. |
| S-12 | **LOW** | Version Pinning | **MC Classic API version not pinned in sys-api.** If the sys-api calls the MC Classic REST API without specifying a version, it may use the latest version, which could introduce breaking changes. | (1) Pin the MC Classic API version in the sys-api URL path (e.g., `/v1/messageDefinitionSends`). (2) Document the MC API version in the integration runbook. (3) Test against the pinned version in staging before production deployment. |
| S-13 | **LOW** | CORS | **CORS not applicable but verify no browser-facing endpoints.** The exp-api, prc-api, and sys-api are system-to-system APIs. They should not have CORS enabled. If CORS is accidentally enabled, a browser-based attacker could call the API. | (1) Verify CORS is disabled on all three MuleSoft applications. (2) API Manager policy should explicitly deny browser-origin requests. |
| S-14 | **INFO** | Logging Format | **Standardize log format across three MuleSoft layers.** Inconsistent log formats make correlation difficult. Each layer should log with the same structure: timestamp, correlation ID, layer (exp/prc/sys), log level, message. | (1) Define a shared logging pattern in a MuleSoft domain project. (2) Include correlation ID in every log line. (3) Use structured JSON logging for machine parsing. |
| S-15 | **INFO** | Documentation | **Security architecture diagram not included in integration documentation.** The trust boundary map, credential flow, and PII exposure points should be documented in a security architecture diagram for compliance audits. | (1) Create a security architecture diagram (draw.io or Lucidchart) showing trust zones, credential flows, and PII exposure points. (2) Include in the integration runbook. (3) Update quarterly or on architecture change. |

---

## Trust Posture Assessment — Cross-Cloud Matrix

| Dimension | SF → MuleSoft | MuleSoft Internal (exp→prc→sys) | MuleSoft → MC |
|-----------|--------------|-------------------------------|--------------|
| **Authentication** | OAuth2 JWT Bearer (Named Credential) | Internal VPC routing (no separate auth) | OAuth2 Client Credentials |
| **Authorization** | Integration user with minimal CRUD/FLS | API-led layer separation (no cross-layer access) | MC Connected App scope (needs audit — S-05) |
| **Encryption in transit** | TLS 1.2+ (SF enforced) | TLS within CloudHub VPC | TLS 1.2+ (MC enforced) |
| **mTLS** | Not configured (recommended) | Not needed (same VPC) | Not configured (**recommended** — S-09) |
| **PII masking** | N/A (platform event payload is structured) | **NOT IMPLEMENTED (CRITICAL — S-01)** | N/A (MC needs full phone for SMS) |
| **Credential storage** | Secure Properties (PASS) | N/A | **Plaintext properties (CRITICAL — S-02)** |
| **Audit trail** | SF Field History + Event Log | MuleSoft logs (30-day retention) | MC tracking (limited) |
| **Data residency** | SF data centers (per org config) | CloudHub region (US/EU) | MC data centers (per BU config) |

---

## Remediation Roadmap

### Phase 1 — Immediate (Before Development Starts)

| # | Action | Owner | Effort | Blocks |
|---|--------|-------|--------|--------|
| REM-01 | Move MC client secret to Anypoint Secrets Manager | MuleSoft Admin | 2 hours | S-02 — all MC API calls |
| REM-02 | Rotate MC client secret (exposed in source control) | MC Admin + MuleSoft Admin | 1 hour | S-02 — must follow REM-01 |
| REM-03 | Implement log masking for phone numbers in all 3 layers | MuleSoft Dev | 4 hours | S-01 — production deployment |

### Phase 2 — Before Staging Deployment

| # | Action | Owner | Effort | Blocks |
|---|--------|-------|--------|--------|
| REM-04 | Implement consent state machine validation | MuleSoft Dev | 8 hours | S-03 — consent compliance |
| REM-05 | Encrypt DLQ messages and restrict access | MuleSoft Admin | 4 hours | S-04 — PII in DLQ |
| REM-06 | Audit MC Connected App OAuth2 scope | MC Admin | 2 hours | S-05 — privilege scope |
| REM-07 | Implement replay ID persistence | MuleSoft Dev | 4 hours | S-06 — event reliability |
| REM-08 | Add E.164 phone format handling in DataWeave | MuleSoft Dev | 4 hours | S-07 — international patients |

### Phase 3 — Before Production Deployment

| # | Action | Owner | Effort | Blocks |
|---|--------|-------|--------|--------|
| REM-09 | Adjust circuit breaker to 15-min threshold | MuleSoft Dev | 1 hour | S-08 — false positive reduction |
| REM-10 | Evaluate and implement mTLS for MuleSoft→MC | MuleSoft Admin + MC Admin | 8 hours | S-09 — transport security |
| REM-11 | Implement cross-system correlation ID persistence | MuleSoft Dev + SF Dev | 8 hours | S-10 — audit trail |
| REM-12 | Pin MC API version in sys-api | MuleSoft Dev | 1 hour | S-12 — stability |

### Phase 4 — Post-Launch Hardening

| # | Action | Owner | Effort | Blocks |
|---|--------|-------|--------|--------|
| REM-13 | Build consent audit API (cross-system query) | Integration team | 16 hours | S-10 — compliance reporting |
| REM-14 | Implement GDPR erasure flow across SF/MuleSoft/MC | Integration team | 24 hours | GDPR right to erasure |
| REM-15 | Export MuleSoft consent logs to 6-year retention store | MuleSoft Admin | 8 hours | HIPAA §164.530(j) |

**Total remediation effort estimate: ~95 hours**

---

## Handoff to REFACTOR Agent

The REFACTOR agent should:
1. Evaluate API-led layering design quality — are exp/prc/sys responsibilities correctly separated?
2. Run all 10 anti-pattern gates against the MuleSoft integration design.
3. Audit RAML resource naming, DataWeave module naming, and MuleSoft project naming conventions.
4. Assess config debt: hardcoded values, environment-specific settings, externalization needs.
5. Evaluate reusability: can the consent event listener pattern be reused for Email consent, Provider consent, or other `ContactPointTypeConsent` types?
6. Cross-reference security findings S-01 through S-15 for refactoring implications.
7. Build technical debt register for items that should be tracked beyond this sprint.
