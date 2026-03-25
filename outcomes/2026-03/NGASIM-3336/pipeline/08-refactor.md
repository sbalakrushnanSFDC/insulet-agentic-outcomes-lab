# NGASIM-3336: REFACTORING ANALYSIS

> **Pipeline Stage:** 08-refactor
> **Produced by:** refactor-cleaner agent
> **Input:** 07-security.md (S-01 through S-15), 02-architecture.md (ADR-001 through ADR-004), 04-review.md findings
> **Run ID:** NGASIM-3336-run-001
> **Timestamp:** 2026-03-25T21:10:00Z
> **Status:** COMPLETE — handed off to DOCS

---

## Decisions Made

1. Refactoring scope covers API-led layering design quality, anti-pattern gate evaluation, naming audit for RAML/DataWeave/MuleSoft project artifacts, config externalization needs, reusability for other consent types, and technical debt register.
2. The MuleSoft exp-api is not yet deployed — refactoring recommendations apply to the design and initial implementation. This is preventive refactoring, not corrective.
3. Cross-reference with security findings (S-01 through S-15) drives several refactoring priorities, especially around log masking infrastructure, credential externalization, and state machine design.
4. Anti-pattern gate evaluation applies the 10 gates from REQ/Skills-Outcome-Guidance.md to the MuleSoft integration design specifically.

---

## Design Quality Assessment

### API-Led Layering Evaluation

| Layer | Responsibility (As Designed) | Correct Separation? | Notes |
|-------|------------------------------|---------------------|-------|
| **exp-api** | Receive SF platform event, validate payload structure, enforce rate limiting, route to prc-api | **PASS** — experience layer handles channel-specific concerns (SF event format) and does not contain business logic | The exp-api correctly adapts the SF-specific event format into a canonical consent message. It should not validate consent state transitions (that is prc-api business logic). |
| **prc-api** | Validate consent state transitions, apply business rules (double opt-in eligibility, international phone handling), transform canonical consent into MC-ready format | **PASS** — process layer contains domain logic, not channel logic | The prc-api correctly owns the consent state machine validation (recommended in S-03). It should not know about SF platform event format or MC API specifics. |
| **sys-api** | Authenticate to MC Classic API, submit consent/subscriber payload, handle MC-specific response codes, manage OAuth2 token lifecycle | **PASS** — system layer encapsulates MC API specifics | The sys-api correctly shields upper layers from MC API versioning, endpoint changes, and authentication details. It should expose a simple "submit consent" interface to prc-api. |
| **DLQ (cross-cutting)** | Store failed events for retry/manual review | **EVALUATE** — DLQ is shared across layers | The DLQ should distinguish between exp-api failures (event parsing), prc-api failures (business validation), and sys-api failures (MC API errors). A single DLQ makes it difficult to triage root cause. Consider separate error queues per failure category, or a single DLQ with a `failureLayer` attribute. |

### Separation of Concerns Score

| Principle | Score | Rationale |
|-----------|-------|-----------|
| Channel isolation (exp-api) | 9/10 | SF platform event specifics are contained in exp-api. Deducted 1 for potential leakage of SF field names into canonical format. |
| Domain logic centralization (prc-api) | 8/10 | Consent validation logic is correctly placed. Deducted 2 because state machine validation is not yet implemented (S-03) and phone format handling spans exp-api DataWeave and prc-api validation. |
| System abstraction (sys-api) | 9/10 | MC API is fully abstracted. Deducted 1 because MC API version is not pinned (S-12), creating a hidden coupling to MC API evolution. |
| Error handling consistency | 6/10 | DLQ exists but lacks error categorization. Retry logic is in sys-api but exponential backoff parameters are hardcoded. Circuit breaker threshold is aggressive (S-08). |
| Observability | 5/10 | Correlation ID exists in headers but is not persisted across all three systems (S-10). Log masking is absent (S-01). Structured logging format is not standardized (S-14). |

**Overall Design Quality: 7.4/10** — Architecturally sound layering with implementation gaps in observability and error categorization.

---

## Anti-Pattern Gate Results

### Gate 1: no-generic-platform
**Result: PASS**

MuleSoft is used as an integration platform connecting Salesforce and Marketing Cloud — its intended purpose. The exp-api is not a generic REST endpoint; it serves a specific business function (consent event relay). The API-led layering follows MuleSoft's prescribed architecture pattern. MuleSoft is not being used as a general-purpose middleware or message broker — it is an integration orchestrator connecting two Salesforce clouds with business logic in the process layer.

**Evidence:** ADR-001 specifies MuleSoft as the integration layer because: (a) existing MuleSoft license/infrastructure at Insulet, (b) native SF connector for platform events, (c) API Manager for governance, (d) CloudHub for managed hosting. Alternative considered: direct SF-to-MC integration via MC Connect — rejected due to lack of business logic layer and DLQ capabilities.

### Gate 2: ootb-before-custom
**Result: PASS**

| Decision | OOTB Option | Custom Option | Choice | Justification |
|----------|-------------|---------------|--------|---------------|
| Consent data model | `ContactPointTypeConsent` (standard object) | Custom `SMS_Consent__c` object | **OOTB** | Standard object provides consent lifecycle fields, Change Data Capture support, and ISV ecosystem compatibility. No custom object needed. |
| Event notification | Platform Events (standard) via Change Data Capture | Custom Apex publishing to external endpoint | **OOTB** | CDC/Platform Events provide declarative, governor-limit-aware event delivery. No custom Apex trigger needed to notify MuleSoft. |
| MC subscriber management | MC Classic REST API (standard) | Custom MC data extension + SSJS processing | **Standard API** | MC Classic REST API is the supported interface for subscriber management. Data extensions are for data storage, not subscriber lifecycle. |
| MuleSoft SF connectivity | Anypoint SF Connector (standard) | Custom HTTP connector with manual OAuth | **OOTB** | Anypoint SF Connector handles OAuth, CometD subscription, replay ID management natively. Custom HTTP connector would reimplement existing capabilities. |

**No OOTB option was bypassed without documented justification.**

### Gate 3: no-async-handwave
**Result: PASS**

The async architecture (platform events → MuleSoft → MC) has specific, documented failure handling:

| Async Concern | Design Response | Specificity Level |
|--------------|----------------|-------------------|
| Event delivery guarantee | SF platform events: at-least-once delivery. MuleSoft connector persists replay ID. | Specific — replay ID persistence mechanism identified (S-06 recommends external store). |
| Message ordering | Platform events are ordered within a transaction but not across transactions. Consent events for the same patient could arrive out of order. | Specific — consent state machine (S-03) validates transition order. Out-of-order events rejected and queued for review. |
| Failure handling | DLQ with exponential backoff retry. Circuit breaker on MC API. | Specific — retry intervals defined (1s, 2s, 4s, 8s, max 5 retries). Circuit breaker threshold: 5 min (S-08 recommends 15 min). |
| Throughput limits | CloudHub vCore capacity. MC API rate limits. | Specific — need to define max events/second based on CloudHub allocation and MC API limits (API4 in OWASP assessment). |
| Data loss scenarios | Replay ID gap detection. DLQ overflow alerting. 24-hour SF event retention. | Specific — S-06 recommends replay ID reconciliation. DLQ overflow is a gap (needs alerting threshold). |

**Async is not used as a hand-wave. Each concern has a specific mechanism, though some mechanisms have implementation gaps flagged in 07-security.md.**

### Gate 4: data-duplication-sot
**Result: PASS WITH CAVEAT**

| Data Element | Source of Truth | Duplicate Location | Acceptable? | Consequence Documented? |
|-------------|----------------|-------------------|-------------|------------------------|
| Consent status | **SF** (`ContactPointTypeConsent.PrivacyConsentStatus`) | MC (subscriber consent status) | **Yes** — MC needs a local copy to control SMS sends. MC cannot query SF in real-time for every SMS decision. | **Partially.** ADR-002 documents that SF is the consent SOT. However, the consequence of SF/MC consent status divergence is not documented. If MC shows OptedIn but SF shows OptedOut (due to a failed sync), MC will continue sending SMS in violation of the patient's opt-out. |
| Phone number | **SF** (`ContactPointPhone`) | MC (subscriber phone number) | **Yes** — MC needs the phone number to send SMS. | **Yes.** Phone number changes in SF trigger a new platform event, which updates MC. |
| Patient identity | **SF** (PersonAccount/Contact) | MC (subscriber key mapped to SF Contact ID) | **Yes** — MC subscriber key links back to SF. | **Partially.** The subscriber key mapping strategy is not documented. If MC uses email as subscriber key but consent is on phone, the identity link is fragile. |

**Caveat:** The consent status divergence consequence (SF OptedOut but MC still OptedIn) must be explicitly documented in the integration runbook with a reconciliation strategy. This is the highest-risk data duplication scenario.

### Gate 5: mulesoft-layering-justified
**Result: PASS**

| Layer | Distinct Responsibility | Reuse Potential | Would Removing This Layer Lose Value? |
|-------|------------------------|----------------|--------------------------------------|
| exp-api | SF event format adaptation, rate limiting, authentication | Yes — any SF platform event consumer can reuse the event adapter pattern | Yes — without exp-api, prc-api would need to understand SF event format directly |
| prc-api | Consent business rules, state machine, transformation | Yes — consent validation logic reusable across any consent source (web form, mobile app, IVR) | Yes — without prc-api, business logic would be split between exp-api and sys-api |
| sys-api | MC API abstraction, token management, retry | Yes — any MuleSoft flow sending to MC can reuse the sys-api MC connector | Yes — without sys-api, every consumer of MC API would implement OAuth token management independently |

**All three layers have distinct responsibilities and reuse potential. No layer is a passthrough or redundant.**

### Gate 6: data-cloud-pattern-justified
**Result: N/A**

No Data Cloud involvement in the current consent flow. However, future consideration: if Insulet activates Data Cloud for patient identity resolution or consent unification, the consent event flow may need to route through Data Cloud's ingestion API instead of (or in addition to) MC Classic API. This is a re-architecture trigger — see Expert Context section.

### Gate 7: marketing-cloud-freshness
**Result: EVALUATE — LATENCY IMPLICATIONS EXIST**

| Scenario | Expected Latency | Acceptable? | Risk |
|---------|-----------------|-------------|------|
| Patient opts in via web form → SF record → platform event → MuleSoft → MC → confirmation SMS | 5-30 seconds (platform event delivery + MuleSoft processing + MC API + SMS provider) | **Yes** — patient expects near-real-time confirmation | If MC Classic API response time exceeds 10 seconds, the patient may navigate away, re-submit, or call support. |
| Patient opts out via STOP keyword → MC processes STOP → ??? → SF consent record update | MC processes STOP natively. **But:** there is no reverse sync from MC to SF. | **NO — GAP** | When a patient sends STOP to MC, MC unsubscribes the phone number. But SF `ContactPointTypeConsent` still shows OptedIn. This creates a divergence where SF shows consent but MC has revoked it. The next time SF syncs to MC, it may re-subscribe the patient. **This is a TCPA violation risk.** |
| Batch consent migration (historical opt-ins) | Minutes to hours depending on volume | **Acceptable for batch** | Batch processing should use a separate MuleSoft flow with higher throughput and different circuit breaker settings. |

**Critical gap identified:** No MC → SF reverse consent sync. When a patient opts out via SMS STOP keyword, MC processes the opt-out but SF is not notified. This creates a consent SOT divergence. The reverse sync (MC → SF) must be designed as a companion flow.

### Gate 8: consent-identity-crosscloud
**Result: HIGH RISK — IDENTITY ALIGNMENT REQUIRED**

| System | Patient Identifier | Format | Alignment Strategy |
|--------|-------------------|--------|-------------------|
| SF | PersonAccount.Id or Contact.Id | 18-char SF ID | Master identity |
| SF | ContactPointTypeConsent.PartyId → PersonAccount | Lookup relationship | SF-internal identity link |
| MuleSoft | Canonical patient identifier in consent message | SF Contact ID (passed through) | Passthrough — no MuleSoft-native identity |
| MC | Subscriber Key | **UNKNOWN — must be defined** | If subscriber key = SF Contact ID: aligned. If subscriber key = email: **misaligned** (consent is on phone, not email). If subscriber key = phone number: partially aligned but fragile (phone number changes break identity link). |

**The MC subscriber key strategy is the single most critical identity alignment decision.** If the wrong identifier is used as subscriber key, consent cannot be reliably linked between SF and MC.

**Recommendation:** Use SF Contact ID (18-char) as MC subscriber key. This creates a durable, immutable identity link. Phone number and email are attributes on the subscriber, not the identity.

### Gate 9: operational-observability
**Result: EVALUATE — GAPS IN CENTRALIZED OBSERVABILITY**

| Observability Need | Current Design | Gap |
|-------------------|----------------|-----|
| Request tracing across 3 layers | Correlation ID in HTTP headers | Not persisted in SF or MC (S-10). MuleSoft logs only. |
| Error alerting | Circuit breaker state change | No alerting configuration defined. No PagerDuty/OpsGenie integration. |
| Performance monitoring | Anypoint Monitoring (default) | No custom dashboards for consent processing latency, throughput, error rate. |
| DLQ monitoring | Anypoint MQ console | No alerting on DLQ depth. No automated DLQ drain process. |
| Consent processing audit | MuleSoft runtime logs | 30-day retention — insufficient for HIPAA (S-10, HIPAA §164.530(j)). |
| MC delivery confirmation | MC tracking | No feedback loop from MC to MuleSoft confirming SMS delivery. |

**Centralized observability dashboard needed:** A single view showing consent event count (SF), processing count (MuleSoft), delivery count (MC), error count (DLQ), and latency percentiles (p50, p95, p99) across the full flow.

### Gate 10: rejected-alternatives-stated
**Result: PASS**

| Decision | Chosen | Rejected Alternative 1 | Rejected Alternative 2 | Justification Documented |
|----------|--------|----------------------|----------------------|-------------------------|
| Integration pattern | MuleSoft API-led (3 layers) | Direct SF-to-MC via MC Connect managed package | SF Apex HTTP callout directly to MC | Yes — ADR-001 |
| Event mechanism | Platform Events (CDC) | Outbound Messages (workflow) | Change Data Capture (CDC entity events) | Yes — ADR-002 |
| MC API | MC Classic REST API | MC Transactional Messaging API | MC SOAP API | Yes — ADR-003 |
| Error handling | DLQ + exponential backoff | Synchronous retry only | Store-and-forward in SF custom object | Yes — ADR-004 |

**All four ADRs document rejected alternatives with reasons. Gate passes.**

---

## Naming Audit

### RAML Resource Paths

| Current Name | Convention Check | Recommendation |
|-------------|-----------------|----------------|
| `/api/v1/consent/sms-optin` | RESTful, versioned, hyphenated, resource-oriented | **PASS** — follows REST naming convention |
| `/api/v1/consent/sms-optin/{eventId}` | Path parameter for specific event lookup | **PASS** — if GET endpoint exists for event status lookup |
| `/api/v1/health` | Standard health check endpoint | **PASS** — but must require authentication in production (S-05 OWASP assessment) |

**Recommendation:** Ensure the RAML base URI uses environment-aware variables: `https://{environment}.api.insulet.com/consent-exp/api/v1/`. Do not hardcode `cloudhub.io` URLs in the RAML — use API autodiscovery with Anypoint API Manager.

### DataWeave Module Naming

| Module | Purpose | Convention Check | Recommendation |
|--------|---------|-----------------|----------------|
| `consent-event-mapper.dwl` | Transform SF platform event → canonical consent format | Hyphenated, descriptive | **PASS** |
| `mc-subscriber-mapper.dwl` | Transform canonical consent → MC subscriber payload | Hyphenated, descriptive | **PASS** |
| `phone-normalizer.dwl` | Normalize phone format (E.164) | Hyphenated, descriptive | **PASS** — but should handle international format (S-07) |
| `error-handler.dwl` | Standard error response formatting | Hyphenated, descriptive | **EVALUATE** — should be `consent-error-handler.dwl` to distinguish from other API error handlers |
| `log-sanitizer.dwl` | Mask PII in log output | N/A (does not exist yet) | **CREATE** — required for S-01 remediation. Name: `pii-log-mask.dwl` |

### MuleSoft Project Naming

| Project | Anypoint Name | Convention Check | Recommendation |
|---------|--------------|-----------------|----------------|
| exp-api | `insulet-consent-sms-exp-api` | Org-prefix, domain, channel, layer | **PASS** — follows Insulet MuleSoft naming convention |
| prc-api | `insulet-consent-sms-prc-api` | Same pattern | **PASS** |
| sys-api | `insulet-mc-classic-sys-api` | Org-prefix, target system, layer | **EVALUATE** — should be `insulet-consent-mc-sys-api` to include domain (consent). A generic `mc-classic-sys-api` could conflict with other MC integrations. |

**Recommendation for sys-api naming:** If the sys-api is intended to be reused by other MC consumers (email consent, transactional messages), keep the generic name. If it is consent-specific, rename to include the domain. Decision depends on reusability strategy (see Reusability Analysis below).

---

## Config Debt Detection

### Hardcoded Values Requiring Externalization

| Value | Current Location | Environment-Specific? | Externalization Target | Priority |
|-------|-----------------|----------------------|----------------------|----------|
| MC REST API base URL | sys-api application properties | **Yes** — different per MC sandbox/production | Anypoint Secure Configuration Properties per environment | **HIGH** |
| MC OAuth token endpoint | sys-api application properties | **Yes** — different subdomain per MC account | Anypoint Secure Configuration Properties | **HIGH** |
| MC Client ID | sys-api application properties | **Yes** — different per MC Connected App | Anypoint Secrets Manager (S-02) | **CRITICAL** |
| MC Client Secret | sys-api application properties | **Yes** — different per MC Connected App | Anypoint Secrets Manager (S-02) | **CRITICAL** |
| SF Connected App Consumer Key | exp-api Secure Properties | **Yes** — different per SF org | Already externalized — PASS | N/A |
| Circuit breaker threshold (5 min) | exp-api or sys-api code | **No** — should be consistent, but tunable | Anypoint Configuration Properties | **MEDIUM** |
| Retry count (5) | sys-api code | **No** — but should be tunable without redeployment | Anypoint Configuration Properties | **MEDIUM** |
| Exponential backoff base (1s) | sys-api code | **No** — but should be tunable | Anypoint Configuration Properties | **LOW** |
| DLQ name (`consent-sms-dlq`) | exp-api/prc-api/sys-api code | **Yes** — different queue per environment | Anypoint Configuration Properties per environment | **MEDIUM** |
| Platform event polling interval | exp-api SF connector config | **No** — but may need tuning in production | Anypoint Configuration Properties | **LOW** |
| MC SMS Definition ID | prc-api code or config | **Yes** — different SMS definition per MC sandbox/production | Anypoint Configuration Properties per environment | **HIGH** |
| MC Business Unit ID | sys-api code or config | **Yes** — different BU per MC environment | Anypoint Configuration Properties per environment | **HIGH** |

**Total externalization items: 12. Critical: 2. High: 4. Medium: 3. Low: 3.**

### Environment Configuration Matrix

| Property | Dev | Staging | Production |
|----------|-----|---------|------------|
| MC API Base URL | `https://YOUR_DEV_SUBDOMAIN.rest.marketingcloudapis.com` | `https://YOUR_STAGING_SUBDOMAIN.rest.marketingcloudapis.com` | `https://YOUR_PROD_SUBDOMAIN.rest.marketingcloudapis.com` |
| MC OAuth Endpoint | `https://YOUR_DEV_SUBDOMAIN.auth.marketingcloudapis.com` | `https://YOUR_STAGING_SUBDOMAIN.auth.marketingcloudapis.com` | `https://YOUR_PROD_SUBDOMAIN.auth.marketingcloudapis.com` |
| SF Org | orgsyncng (dev sandbox) | SIT sandbox | Production org |
| DLQ Name | `consent-sms-dlq-dev` | `consent-sms-dlq-staging` | `consent-sms-dlq-prod` |
| Log Level | DEBUG | INFO | WARN |
| CloudHub Workers | 0.1 vCore | 0.2 vCore | 1.0 vCore (minimum for PHI-adjacent) |

---

## Reusability Analysis

### Can the consent event listener pattern be reused?

| Future Consent Type | Reuse Level | Changes Needed | Effort |
|--------------------|-------------|----------------|--------|
| **Email consent** (patient opts in to email communications) | **High** — same `ContactPointTypeConsent` object, same platform event, same MuleSoft exp-api pattern | (1) New DataWeave mapper for email-specific fields. (2) New MC API call for email subscriber (different endpoint). (3) prc-api consent state machine reusable as-is. | 40% of original effort |
| **Provider consent** (HCP opts in to communications) | **Medium** — different consent context (provider vs patient). Same object but different `CaptureContactPointType` values. | (1) New exp-api channel or shared exp-api with routing by contact point type. (2) New prc-api rules for provider-specific validation (NPI verification, credential check). (3) Possibly different MC Business Unit for provider communications. | 60% of original effort |
| **Push notification consent** (patient opts in to mobile push) | **Low** — different delivery mechanism (push via mobile SDK, not MC). `ContactPointTypeConsent` may not be the right object (push consent is device-specific). | (1) Different sys-api target (push notification service, not MC). (2) prc-api consent state machine partially reusable. (3) exp-api event listener reusable. | 70% of original effort |
| **Data Cloud consent sync** (consent replicated to Data Cloud for unified profile) | **Medium** — Data Cloud ingestion API replaces MC Classic API as the target. | (1) New sys-api for Data Cloud Ingestion API. (2) exp-api reusable as-is. (3) prc-api transformation changes for Data Cloud DMO format. | 50% of original effort |

### Reusability Enablers (Design Now, Implement Later)

| Enabler | Description | Implementation Approach | Priority |
|---------|------------|------------------------|----------|
| **Canonical consent message format** | Define a system-agnostic consent message schema that all consent types share | JSON Schema in a shared MuleSoft domain project. Fields: `patientId`, `consentType` (SMS/Email/Push), `consentStatus`, `contactPoint`, `captureDate`, `captureSource`. | **HIGH** — design now |
| **Consent type routing in exp-api** | Route different consent types to different processing flows | `CaptureContactPointType` field in the platform event drives routing. SMS → SMS prc-api, Email → Email prc-api, etc. Single exp-api, multiple prc-api consumers. | **MEDIUM** — design the routing interface now, implement when needed |
| **MC sys-api as shared utility** | Single sys-api that supports SMS, Email, and Push MC API calls | Expose a multi-operation interface: `POST /subscribers/sms`, `POST /subscribers/email`, `POST /push/register`. Internal routing to different MC API endpoints. | **MEDIUM** — start with SMS-only, design for extensibility |
| **Consent state machine as reusable library** | Extract state machine logic into a MuleSoft custom module or shared library | MuleSoft custom Java module or DataWeave library. State machine rules configurable per consent type. | **LOW** — implement after SMS consent is proven |

---

## Technical Debt Register

| # | Category | Description | Severity | Source | Remediation Approach | Estimated Effort |
|---|----------|-------------|----------|--------|---------------------|-----------------|
| TD-01 | Security | MC client secret in plaintext application properties | **CRITICAL** | S-02 | Move to Anypoint Secrets Manager, rotate secret | 3 hours |
| TD-02 | Security | PII (phone numbers) visible in MuleSoft runtime logs | **CRITICAL** | S-01 | Implement log masking DataWeave module across all 3 layers | 4 hours |
| TD-03 | Compliance | No consent state machine validation | **HIGH** | S-03 | Implement state machine in prc-api with transition rules | 8 hours |
| TD-04 | Security | DLQ messages contain plaintext PII | **HIGH** | S-04 | Encrypt DLQ payloads, mask phone numbers before DLQ write | 4 hours |
| TD-05 | Integration | No MC → SF reverse consent sync (STOP keyword) | **HIGH** | Gate 7 | Design companion flow: MC webhook/journey → MuleSoft → SF `ContactPointTypeConsent` update | 16 hours |
| TD-06 | Identity | MC subscriber key strategy undefined | **HIGH** | Gate 8 | Define subscriber key = SF Contact ID (18-char). Document in integration runbook. | 2 hours |
| TD-07 | Observability | Fragmented audit trail across 3 systems | **HIGH** | S-10 | Implement correlation ID persistence in SF, MuleSoft, and MC | 8 hours |
| TD-08 | Reliability | Replay ID not persisted externally | **MEDIUM** | S-06 | Persist to Anypoint Object Store or database on each batch | 4 hours |
| TD-09 | Data Quality | International phone format not handled in DataWeave | **MEDIUM** | S-07 | Update `phone-normalizer.dwl` for E.164 (7-15 digits, country code) | 4 hours |
| TD-10 | Availability | Circuit breaker threshold too aggressive (5 min) | **MEDIUM** | S-08 | Increase to 15 min, add MC maintenance window awareness | 2 hours |
| TD-11 | Security | No mTLS between MuleSoft and MC | **MEDIUM** | S-09 | Evaluate MC mTLS support, generate client certificate, configure | 8 hours |
| TD-12 | Config | MC SMS Definition ID hardcoded or not externalized | **MEDIUM** | Config debt | Externalize to Anypoint Configuration Properties per environment | 1 hour |
| TD-13 | Config | MC Business Unit ID not externalized | **MEDIUM** | Config debt | Externalize per environment | 1 hour |
| TD-14 | Observability | No centralized consent processing dashboard | **MEDIUM** | Gate 9 | Build Anypoint Monitoring custom dashboard with consent metrics | 8 hours |
| TD-15 | Naming | sys-api name may conflict with future MC integrations | **LOW** | Naming audit | Rename to `insulet-consent-mc-sys-api` or document as intentionally generic | 1 hour |
| TD-16 | Compliance | MuleSoft consent logs expire after 30 days (HIPAA requires 6 years) | **HIGH** | HIPAA §164.530(j) | Export consent processing logs to S3/Glacier with 6-year retention policy | 8 hours |
| TD-17 | Error Handling | Single DLQ for all failure types (parsing, validation, API) | **MEDIUM** | Design quality | Split into categorized error queues or add `failureLayer` attribute to DLQ messages | 4 hours |
| TD-18 | Data Integrity | Consent SOT divergence consequence not documented | **HIGH** | Gate 4 | Document reconciliation strategy for SF/MC consent status divergence. Implement weekly reconciliation batch job. | 8 hours |

**Total technical debt items: 18. Critical: 2. High: 7. Medium: 7. Low: 2.**
**Total estimated effort: ~94 hours**

---

## Expert Context

### Why This Architecture Fits Salesforce + MuleSoft + Marketing Cloud

The API-led integration pattern (exp/prc/sys) is the prescribed MuleSoft architecture for multi-cloud Salesforce integrations. It provides:

1. **Layer isolation** — SF platform event specifics (CometD, CDC format, replay IDs) are contained in the experience layer. MC API specifics (OAuth2 token lifecycle, Classic REST quirks, rate limits) are contained in the system layer. Business logic (consent validation, state machine, phone normalization) is in the process layer. This means when MC deprecates Classic API in favor of MC APIs v2, only the sys-api changes. When SF changes the platform event format (unlikely but possible), only the exp-api changes.

2. **Anypoint Platform governance** — API Manager policies (rate limiting, client ID enforcement, spike control) apply at the exp-api gateway. This is the correct entry point for governance in an API-led architecture. Applying policies at the sys-api would be incorrect (sys-api is internal).

3. **Native SF connector** — The Anypoint SF Connector handles CometD subscription, replay ID management, and OAuth2 token refresh natively. Building this from scratch in a custom HTTP connector would be 40+ hours of development and testing for parity.

### Key Tradeoffs Accepted

| Tradeoff | Choice | Alternative | Why |
|----------|--------|------------|-----|
| Real-time vs batch consent sync | Real-time (platform events) | Batch (scheduled SOQL query + bulk API) | Real-time provides immediate double opt-in SMS. Batch would introduce minutes-to-hours delay — unacceptable for SMS confirmation UX. |
| MC Classic API vs MC Transactional Messaging API | Classic REST API | Transactional Messaging API (newer, event-driven) | Classic REST API is stable, well-documented, and supported. Transactional Messaging API is newer and better suited for event-driven patterns, but Insulet's MC environment may not have it provisioned. **This is a re-architecture trigger if Transactional Messaging API becomes available.** |
| Single DLQ vs per-layer error queues | Single DLQ (for now) | Separate queues per failure type | Single DLQ is simpler to implement and monitor. Per-layer queues add operational complexity. Accept single DLQ for MVP, migrate to categorized queues if DLQ volume exceeds triage capacity. |
| SF Contact ID as MC subscriber key | SF Contact ID (18-char) | Phone number or email | SF Contact ID is immutable — phone numbers and emails change. Using Contact ID as subscriber key creates a durable cross-cloud identity link. Tradeoff: MC cannot function independently of SF if the subscriber key is an opaque SF ID. |

### Anti-Pattern Being Avoided

**"Integration as plumbing" anti-pattern:** Treating MuleSoft as a dumb pipe that forwards events without validation, transformation, or business logic. The prc-api layer exists specifically to apply consent business rules — state machine validation, phone normalization, double opt-in eligibility. Without prc-api, the exp-api would forward any event to MC, including invalid consent transitions, malformed phone numbers, and duplicate events. The "plumbing" anti-pattern is common in MuleSoft implementations where all three layers are thin passthrough APIs with transformation only. Here, the prc-api has meaningful domain logic.

### What Could Force Re-Architecture

| Trigger | Impact | Likelihood | Timeframe |
|---------|--------|-----------|-----------|
| **MC Classic API deprecation** | sys-api must be rebuilt for MC APIs v2 or Transactional Messaging API. exp-api and prc-api unaffected. | MEDIUM — Salesforce is investing in MC APIs v2 | 2-3 years |
| **Data Cloud activation** | Consent may need to flow to Data Cloud for unified patient profile. New sys-api for Data Cloud Ingestion API. prc-api may need dual-routing. | HIGH — Insulet has Data Cloud in roadmap | 1-2 years |
| **Health Cloud Patient Consent Management** | If Insulet activates Health Cloud's native consent management, `ContactPointTypeConsent` may be replaced by Health Cloud consent objects. exp-api event source changes. | LOW — Health Cloud consent is not yet a standard feature for device manufacturers | 3+ years |
| **Volume scale beyond CloudHub capacity** | If consent volume exceeds CloudHub vCore processing capacity, consider Anypoint Runtime Fabric on self-hosted Kubernetes. Architecture unchanged, deployment model changes. | LOW — current consent volume is well within CloudHub limits | 2+ years |
| **HIPAA compliance reclassification** | If Insulet's compliance team reclassifies consent data as PHI (not PHI-adjacent), all MuleSoft components must run in HIPAA-compliant infrastructure. CloudHub alone may not satisfy BAA requirements. | MEDIUM — depends on compliance audit outcome | 6-12 months |

---

## Cross-Reference: Security Findings Impact on Refactoring

| Security Finding | Refactoring Implication | Action |
|-----------------|------------------------|--------|
| S-01 (PII in logs) | Create shared `pii-log-mask.dwl` DataWeave module. Import in all 3 MuleSoft apps. This is new infrastructure, not refactoring of existing code. | Create DataWeave module, add to domain project, import in exp/prc/sys. |
| S-02 (Credential storage) | Restructure `config.yaml` to use `${secure::}` property placeholders. Move secrets to Secrets Manager. This is config refactoring. | Refactor config files in all 3 apps. |
| S-03 (Consent state machine) | New business logic in prc-api. Not refactoring — net-new implementation. | Design state machine, implement in prc-api. |
| S-04 (DLQ PII) | Modify DLQ write logic to encrypt/mask payload before write. This affects error handling in all 3 layers. | Refactor error handlers in exp/prc/sys to sanitize before DLQ write. |
| S-05 (MC OAuth scope) | MC admin configuration change, not code refactoring. | MC Connected App configuration change. |
| S-06 (Replay ID) | Modify exp-api SF connector configuration to persist replay ID externally. | Refactor exp-api connector config. |
| S-07 (Phone format) | Modify `phone-normalizer.dwl` to handle E.164 international format. | Refactor DataWeave module. |
| S-08 (Circuit breaker) | Configuration change in error handling policy. | Refactor circuit breaker configuration. |
| S-09 (mTLS) | Infrastructure configuration, not code refactoring. | Configure mTLS at CloudHub and MC levels. |
| S-10 (Audit trail) | Requires changes in all 3 layers to persist correlation ID. Cross-cutting concern. | Refactor logging and header propagation across all 3 apps. |

---

## Handoff to DOC Agent

The DOC agent should:
1. Create operational runbook for the SMS Double Opt-In exp-api covering deployment, health check, monitoring, failure modes, and rollback.
2. Summarize ADR-001 through ADR-004 with one-line descriptions and links.
3. Document the end-to-end data flow with field mappings (SF → MuleSoft canonical → MC).
4. Produce API contract documentation (RAML summary, request/response examples).
5. Build traceability map linking Jira stories → ACs → ADRs → test cases → security findings.
6. Create cross-cloud integration guide covering SF/MuleSoft/MC connectivity, credential rotation, and monitoring.
7. Define glossary of key terms for the SMS Double Opt-In domain.
8. Write CTA domain coverage summary — which of the 9 domains were addressed, which are gaps.
