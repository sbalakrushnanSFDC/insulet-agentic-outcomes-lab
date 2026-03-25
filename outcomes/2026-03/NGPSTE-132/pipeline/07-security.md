# NGPSTE-132: SECURITY REVIEW

## Decisions Made

1. Security review scope: declarative CTI configuration plus external integration surface (Amazon Connect APIs, S3 storage, Connect Streams JS).
2. Primary concerns: PII in call recordings, API callout security, FLS enforcement on VoiceCall, and Content Security Policy for embedded CCP.
3. No custom Apex to review for injection or SOQL injection — but external integration boundaries require careful scrutiny.

## Security Findings

| # | Severity | Category | Finding | Recommendation |
|---|----------|----------|---------|----------------|
| S-01 | HIGH | Data Privacy | Call recording S3 bucket encryption policy not documented. Recordings may contain PII (SSN, date of birth, medical device serial numbers, insurance information). HIPAA and Insulet data classification policy require encryption at rest (AES-256) and in transit (TLS 1.2+). No evidence of S3 bucket policy review. | Require AWS S3 bucket policy audit: (1) SSE-S3 or SSE-KMS encryption at rest, (2) Bucket policy denies unencrypted uploads, (3) VPC endpoint or private link for SF-to-S3 traffic, (4) Lifecycle policy for recording retention (90-day minimum, 7-year max per compliance). Escalate to Information Security team. |
| S-02 | HIGH | API Security | Amazon Connect API endpoint must use a Salesforce Named Credential. The CallCenter XML references a direct URL (`your-instance.my.connect.aws`). If the Connect Streams JS or any server-side callout uses hardcoded credentials or API keys, this violates the Named Credential requirement. Verify callout whitelisting in Remote Site Settings or CSP Trusted Sites. | (1) Create Named Credential for Amazon Connect API endpoint, (2) Add Connect instance URL to CSP Trusted Sites (script-src, connect-src), (3) Verify no API keys are embedded in CallCenter XML or Visualforce pages, (4) Use OAuth 2.0 for server-to-server authentication between SF and Connect. |
| S-03 | MEDIUM | Permission Scope | CTI_Integration_Access permission set scope not fully audited. This permission set exists in DevInt2 but its object and field permissions have not been enumerated. It may grant broader access than necessary for CTI agents. | Run SOQL against orgsyncng post-deploy: `SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete FROM ObjectPermissions WHERE Parent.Name = 'CTI_Integration_Access'`. Verify minimum-necessary principle. |
| S-04 | MEDIUM | FLS | VoiceCall object contains sensitive call metadata: CallerNumber (ANI), CalleeNumber, CallDurationInSeconds, CallDisposition. If FLS is not restricted, any user with VoiceCall Read can see caller phone numbers. Medical device support calls may have PHI context in call notes. | Restrict VoiceCall field access: (1) CallerNumber — Read only for agents during active call, hidden post-call, (2) CallDisposition — editable by agents, read-only for managers, (3) Custom fields for call notes — apply FLS to restrict to Care Agent profile and above. |
| S-05 | MEDIUM | CSP | Amazon Connect Streams JavaScript (connect-streams.js) loads in an iframe within the Lightning utility bar. This requires CSP exceptions for the Connect instance domain. If the domain is not explicitly trusted, Chrome will block the iframe with a mixed-content or CSP violation. Conversely, over-broad CSP exceptions (e.g., `*.amazonaws.com`) create XSS risk. | Add the exact Connect instance domain to CSP Trusted Sites: `https://your-instance.my.connect.aws` (frame-src, script-src, connect-src). Do NOT use wildcard `*.amazonaws.com`. Verify with Chrome DevTools Console that no CSP violations occur during softphone load. |
| S-06 | LOW | Future Risk | No call transcription is currently planned. If Amazon Connect Contact Lens or a third-party transcription service is added later, PII masking is mandatory. Transcripts of medical device support calls will contain PHI (device serial numbers, patient symptoms, dosing information). | Document as architectural constraint: any future transcription feature must implement PII redaction before storage. Reference HIPAA Safe Harbor de-identification standard. Flag for ADR if transcription is added to backlog. |

## CRUD/FLS Verification Matrix

### VoiceCall Object Access

| Profile | Create | Read | Update | Delete | FLS Restrictions |
|---------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| Customer Care Agent | No | Yes | Yes | No | CallerNumber: Read, CallDisposition: Read+Edit, CallDurationInSeconds: Read |
| TTEC Agent | No | Yes | Yes | No | Same as Customer Care Agent — verify via CTI_Integration_Access perm set |
| Customer Care Manager | No | Yes | Yes | No | All VoiceCall fields readable, CallDisposition editable |
| Sales User | No | No | No | No | No VoiceCall access — CTI is care-only |

### CallCenter Object Access

| Profile | Create | Read | Update | Delete | Notes |
|---------|--------|------|--------|--------|-------|
| System Administrator | Yes | Yes | Yes | Yes | Manages CallCenter configuration |
| Customer Care Agent | No | Yes | No | No | Read-only — sees assigned CallCenter |
| TTEC Agent | No | Yes | No | No | Read-only — assigned via CallCenter membership |

### ServicePresenceStatus Access

| Profile | Create | Read | Update | Delete | Notes |
|---------|--------|------|--------|--------|-------|
| System Administrator | Yes | Yes | Yes | Yes | Manages presence statuses |
| Customer Care Agent | No | Yes | No | No | Can set own status from available options |
| TTEC Agent | No | Yes | No | No | Same as Customer Care Agent |

## OWASP Mobile Top 10 Checklist (Telephony = Mobile Context)

| # | Risk | Applicability | Assessment | Status |
|---|------|--------------|------------|--------|
| M1 | Improper Credential Usage | HIGH — Connect API credentials | Named Credentials required for all Amazon Connect API callouts. Hardcoded keys in CallCenter XML or JS is a critical violation. | PENDING — verify Named Credential exists |
| M2 | Inadequate Supply Chain Security | MEDIUM — Connect Streams JS | connect-streams.js is loaded from Amazon CDN. Verify version pinning and SRI (Subresource Integrity) hash. | PENDING — verify SRI hash on script tag |
| M3 | Insecure Authentication/Authorization | LOW — OAuth 2.0 via Connected App | Standard Salesforce session auth. Connect uses IAM roles for server-side. No custom auth flow. | NOT APPLICABLE — no custom Connected App for CTI |
| M4 | Insufficient Input/Output Validation | MEDIUM — ANI/caller ID parsing | Caller ANI arrives as E.164 format (`+1XXXXXXXXXX`). Verify no script injection via caller ID spoofing in screen pop display. | PASS — E.164 format is clean integer; Lightning framework auto-escapes output |
| M5 | Insecure Communication | HIGH — CTI traffic | TLS 1.2+ mandatory for all traffic: SF ↔ Connect API, agent browser ↔ CCP, CCP ↔ Connect instance. WebRTC (SRTP) for voice media. | PASS — enforced by platform (SF requires TLS 1.2, Connect requires TLS 1.2, WebRTC uses SRTP) |
| M6 | Inadequate Privacy Controls | HIGH — call recordings contain PHI | Recordings stored in S3 must be encrypted, access-controlled, and retention-managed. See S-01. | PENDING — S3 bucket policy audit required |
| M7 | Insufficient Binary Protections | N/A | No custom binary or mobile app — using standard SF Lightning in browser. | N/A |
| M8 | Security Misconfiguration | MEDIUM — CSP, Remote Site Settings | CSP must allow Connect instance domain but not wildcards. Remote Site Settings must include Connect API endpoint. | PENDING — CSP configuration required (see S-05) |
| M9 | Insecure Data Storage | LOW | VoiceCall records stored in Salesforce with standard platform encryption. No local browser caching of call data. | PASS |
| M10 | Insufficient Cryptography | LOW | Platform-managed encryption for data at rest (Shield optional). S3 encryption for recordings. | PENDING — verify S3 encryption (see S-01) |

## Named Credential Requirements

The Amazon Connect integration requires the following Named Credentials:

| Named Credential | Purpose | Auth Type | Endpoint |
|-----------------|---------|-----------|----------|
| Amazon_Connect_API | Server-side Connect API calls (agent status, queue management) | OAuth 2.0 (JWT Bearer) | `https://your-instance.my.connect.aws/connect/api` |
| Amazon_Connect_CCP | Client-side CCP iframe (Connect Streams) | Session-based (IAM federation) | `https://your-instance.my.connect.aws/connect/ccp-v2` |

## Recommendations Summary

1. **CRITICAL ACTION (S-01):** Audit S3 bucket encryption and access policy for call recordings before any voice traffic flows. Escalate to InfoSec.
2. **CRITICAL ACTION (S-02):** Create Named Credential for Amazon Connect API. Remove any hardcoded endpoints from CallCenter XML before production deployment.
3. **HIGH (S-04):** Implement FLS restrictions on VoiceCall — CallerNumber should be restricted post-call to prevent ANI harvesting.
4. **HIGH (S-05):** Configure CSP Trusted Sites with exact Connect instance domain. Test with Chrome DevTools.
5. **MEDIUM (S-03):** Audit CTI_Integration_Access permission set scope — enumerate all object and field permissions.
6. **LOW (S-06):** Document PII masking requirement as pre-condition for any future transcription feature.

## CSP Configuration Required

The Amazon Connect CCP iframe requires explicit Content Security Policy exceptions in Salesforce. Without these, the softphone will fail to load in Lightning Experience.

**Required CSP Trusted Sites entries:**

| Directive | Domain | Purpose |
|-----------|--------|---------|
| frame-src | `https://your-instance.my.connect.aws` | CCP iframe embedding in Lightning utility bar |
| script-src | `https://your-instance.my.connect.aws` | Connect Streams JS execution |
| connect-src | `https://your-instance.my.connect.aws` | WebSocket and XHR for real-time agent events |
| media-src | `https://your-instance.my.connect.aws` | WebRTC media streams for voice audio |

**Anti-patterns to avoid:**
- Do NOT add `*.amazonaws.com` — this is overly broad and exposes all AWS services
- Do NOT add `*.amazon.com` — unrelated to Connect and opens unnecessary surface area
- Do NOT use `unsafe-inline` or `unsafe-eval` in script-src — Connect Streams does not require them

## Integration Boundary Security Assessment

| Boundary | Protocol | Authentication | Encryption | Risk |
|----------|----------|---------------|------------|------|
| Agent Browser → SF Lightning | HTTPS | SF Session (OAuth 2.0) | TLS 1.2+ | LOW |
| SF Lightning → CCP iframe | HTTPS (postMessage) | Same-origin policy + CSP | TLS 1.2+ | MEDIUM (CSP must be configured) |
| CCP → Amazon Connect | HTTPS + WebRTC | IAM federation via SAML/OAuth | TLS 1.2+ (signaling), SRTP (media) | LOW (AWS-managed) |
| Connect → S3 (recordings) | Internal AWS | IAM role-based | SSE-S3 or SSE-KMS | HIGH (see S-01) |
| SF → Connect API (server-side) | HTTPS | Named Credential (OAuth 2.0 JWT) | TLS 1.2+ | HIGH (see S-02) |

## Handoff to REFACTOR Agent

The REFACTOR agent should:
1. Review CallCenter XML for hardcoded URLs that should be environment-parameterized
2. Check naming consistency across all 3 ServicePresenceStatus records
3. Verify PermissionSetGroup naming follows org convention
4. Flag DevInt2-specific CallCenter records that should be excluded from migration
