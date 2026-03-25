# NGASIM-76: SECURITY REVIEW

> **Pipeline Stage:** 07-security
> **Produced by:** security-reviewer agent
> **Input:** 05-buildfix.md, 02-architecture.md (ADR-005 through ADR-008), 06-e2e.md, NGPSTE-132 07-security.md
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:46:00Z
> **Status:** COMPLETE — handed off to REFACTOR

---

## Decisions Made

1. Security review scope: Inside Sales-specific Apex classes (InsideSalesScreenPopResolver, VoiceCallActivityHandler, RecordingOptOutController), permission model (IS_CTI_Agent_Access PSG), multi-object data access patterns, and HIPAA compliance for recording opt-out.
2. Primary concerns: Inside Sales agents accessing Lead PII and Patient PHI through screen pop, recording opt-out compliance, Named Credential requirements, and cross-object data exposure in the waterfall search.
3. NGPSTE-132 security findings (S-01 through S-06) remain applicable — this review extends them with Inside Sales-specific risks.

---

## Security Findings

| # | Severity | Category | Finding | Recommendation |
|---|----------|----------|---------|----------------|
| S-01 | HIGH | Data Exposure | **Multi-object screen pop exposes Lead PII and Patient PHI to all Inside Sales agents.** InsideSalesScreenPopResolver searches Lead (Phone, Name, Status, Company), PersonAccount (Phone, Name, PersonHomePhone, PersonMobilePhone), and Contact (Phone, Name, MobilePhone). Any IS agent receiving an inbound call sees the resolved record. If a Patient/PersonAccount is resolved, the agent may see protected health information (medical device serial number, therapy start date, insurance details) on the record page — even if they are calling about a sales inquiry. FLS on the PersonAccount page layout determines visibility, not the screen pop resolver. | (1) Create a dedicated Inside Sales page layout for PersonAccount that hides PHI fields (DeviceSerialNumber, TherapyStartDate, InsuranceProvider, etc.). (2) Apply field-level security on IS_CTI_Base to deny read access to PHI fields on Account/PersonAccount. (3) Consider a screen pop "summary card" instead of full record navigation — show only Name, Phone, Status without navigating to the full record. (4) Log screen pop events for HIPAA access audit trail. |
| S-02 | HIGH | API Security | **RecordingOptOutController requires Named Credential that does not exist.** ADR-008 specifies HTTP callout to Amazon Connect StopContactRecording API via Named Credential `AmazonConnect_API`. This Named Credential has not been created in any org (open item from NGPSTE-132 S-02). Without it, the controller will either fail at runtime or developers may be tempted to hardcode credentials as a workaround. | (1) Create Named Credential `AmazonConnect_API` in orgsyncng before any Apex development begins. (2) Use External Credential with OAuth 2.0 JWT Bearer flow for server-to-server auth. (3) NEVER hardcode API keys, IAM access keys, or session tokens in Apex. (4) Add Named Credential existence as a pre-deploy gate in CI pipeline. (5) Coordinate with AWS team for IAM role creation with least-privilege: `connect:StopContactRecording`, `connect:SuspendContactRecording`, `connect:ResumeContactRecording` only. |
| S-03 | HIGH | HIPAA Compliance | **Recording opt-out audit trail may be insufficient.** VoiceCall.Recording_Opted_Out__c is a checkbox field set by RecordingOptOutController. However, a checkbox alone does not capture: (1) timestamp of opt-out, (2) identity of agent who triggered opt-out, (3) confirmation that Connect API actually stopped recording, (4) whether recording was resumed later. HIPAA requires demonstrable evidence that the patient's verbal request was honored. | (1) Enable Field History Tracking on VoiceCall.Recording_Opted_Out__c to capture timestamp and user. (2) Add VoiceCall.Recording_Opted_Out_At__c (DateTime) field for explicit timestamp. (3) Add VoiceCall.Recording_Opted_Out_By__c (Lookup to User) for explicit agent attribution. (4) Log Connect API response (success/failure) to a Platform Event or custom log object. (5) Create a HIPAA recording opt-out report for compliance team review. |
| S-04 | MEDIUM | Permission Scope | **IS_CTI_Base permission set grants Lead Create — potential data integrity risk.** The IS_CTI_Base permission set (05-buildfix.md) grants Lead Create access because the screen pop "new Lead form" flow requires it. However, Lead Create without validation rules means Inside Sales agents can create duplicate Leads from misidentified screen pops. If an existing Lead's phone number is not indexed or has a formatting mismatch, the agent may create a duplicate instead of using the existing record. | (1) Implement a Lead duplicate rule triggered on Phone/MobilePhone match before create. (2) Add a duplicate matching rule using Phone as the matching field. (3) Alert the agent with a duplicate warning before Lead creation from screen pop. (4) IS_CTI_Base Lead Create access is necessary but must be paired with data quality controls. |
| S-05 | MEDIUM | FLS | **VoiceCall custom fields (Recording_Opted_Out__c, Call_Category__c, True_Connection__c) must be read-only to agents.** 05-buildfix.md sets Recording_Opted_Out__c as `editable: false, readable: true` on IS_CTI_Base, which is correct. However, Call_Category__c is set to `editable: true` — this allows agents to manually change the call category, potentially misclassifying calls for reporting. True_Connection__c should be system-set (>90s duration threshold) not agent-editable. | (1) Change Call_Category__c to `editable: false` on IS_CTI_Base — categories should be set by IVR/system logic, not agents. (2) Change True_Connection__c to `editable: false` — flag should be calculated automatically by trigger/flow based on duration threshold. (3) Only System Administrator should have edit access to these audit/reporting fields. |
| S-06 | MEDIUM | Data Isolation | **VoiceCallActivityHandler creates Tasks visible to all users with Task Read.** When VoiceCallActivityHandler creates a Task from a VoiceCall, the Task inherits the OwnerId of the agent but is visible to anyone with Task Read access. Call notes, disposition, and WhoId (Lead/Patient) on the Task may expose Inside Sales activity data to other departments (Customer Care, Product Support) who have Task visibility. | (1) Set Task sharing model to "Private" for Inside Sales call activity Tasks (requires OWD review). (2) Alternatively, use a Record Type (`IS_Call_Activity`) on the Task and apply sharing rules to restrict visibility to Inside Sales team members. (3) Task.Description should never auto-populate with call content or PII — keep it agent-entered only. |
| S-07 | MEDIUM | Input Validation | **InsideSalesScreenPopResolver normalizes phone input but does not validate format.** The pseudo-code `normalizePhone` method strips non-digit characters but does not validate E.164 format or reject obviously invalid inputs (e.g., single digits, alphabetic strings). A malformed ANI from Connect could cause unexpected SOQL behavior or return incorrect matches. | (1) Add format validation: ANI must be 10-15 digits after normalization. (2) Reject ANIs shorter than 10 digits — return new Lead form instead of querying. (3) Log malformed ANIs to a Platform Event for monitoring. (4) SOQL with bind variables (`:normalizedAni`) is safe against injection — confirmed. |
| S-08 | LOW | CSP / XSS | **Caller ID spoofing could inject display-layer content via screen pop.** ANI (Automatic Number Identification) arrives from Amazon Connect and is passed to InsideSalesScreenPopResolver. While SOQL bind variables prevent injection at the query layer, the ANI is also used in the new Lead form URL: `defaultFieldValues=Phone=` + encodedAni. If an attacker spoofs an ANI containing URL-encoded JavaScript, the pre-populated field could execute in the browser. However, Lightning framework auto-escapes URL parameters, and `EncodingUtil.urlEncode` in the pseudo-code provides server-side encoding. | (1) Verify that `EncodingUtil.urlEncode` is applied to all ANI values used in URL construction — confirmed in pseudo-code. (2) ANI from Connect is E.164 format (digits and `+` only) — inherently safe. (3) Lightning `defaultFieldValues` parameter does not execute JavaScript — confirmed. (4) Risk is theoretical, not practical. No action needed beyond maintaining the current encoding pattern. |

---

## CRUD/FLS Verification Matrix

### Lead Object Access

| Profile | Create | Read | Update | Delete | FLS Restrictions |
|---------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| Inside Sales Agent | Yes | Yes | Yes | No | IS_CTI_Base grants Create/Read/Edit. Phone, Name, Status, Company visible. No Delete. |
| Customer Care Agent | No | Yes | No | No | Profile-level Read only. No Lead edit — Care agents work with Contacts/Cases. |
| HCP Queue Agent | No | Yes | No | No | Read-only. HCP agents may view Leads but do not engage them directly. |
| Sales Manager | Yes | Yes | Yes | No | Full CRUD minus Delete. Manager-level reporting access. |

### PersonAccount Object Access

| Profile | Create | Read | Update | Delete | FLS Restrictions |
|---------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| Inside Sales Agent | No | Yes | No | No | IS_CTI_Base grants Read only. **PHI fields (DeviceSerialNumber, TherapyStartDate, InsuranceProvider) must be hidden via FLS.** Screen pop shows Name/Phone only. |
| Customer Care Agent | No | Yes | Yes | No | Profile + CTI_Integration_Access. Care agents can edit patient records (case context). |
| HCP Queue Agent | No | Yes | No | No | Read-only. Providers calling about patients — agent views but does not edit. |
| Sales Manager | No | Yes | Yes | No | Manager-level read/edit for escalated cases. |

### Contact Object Access

| Profile | Create | Read | Update | Delete | FLS Restrictions |
|---------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| Inside Sales Agent | No | Yes | No | No | IS_CTI_Base does not grant Contact Create/Edit. Screen pop fallback is read-only. |
| Customer Care Agent | No | Yes | Yes | No | Profile + CTI_Integration_Access. Standard Care agent access. |
| HCP Queue Agent | No | Yes | No | No | Read-only. |
| Sales Manager | No | Yes | Yes | No | Manager-level access. |

### VoiceCall Object Access

| Profile | Create | Read | Update | Delete | FLS Restrictions |
|---------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| Inside Sales Agent | No | Yes | Yes | No | IS_CTI_Base: Read + Edit. CallerNumber: Read. Call_Category__c: Read-only (S-05). Recording_Opted_Out__c: Read-only (set by controller). True_Connection__c: Read-only (calculated). |
| Customer Care Agent | No | Yes | Yes | No | Same as IS — VoiceCall access via CTI_Integration_Access. |
| HCP Queue Agent | No | Yes | Yes | No | Same access pattern for voice queue agents. |
| Sales Manager | No | Yes | Yes | No | Manager reporting access. All custom fields readable. |

### Task Object Access

| Profile | Create | Read | Update | Delete | FLS Restrictions |
|---------|--------|------|--------|--------|-----------------|
| System Administrator | Yes | Yes | Yes | Yes | Full access — all fields |
| Inside Sales Agent | Yes | Yes | Yes | No | IS_CTI_Base: Full CRUD minus Delete. Call_Disposition__c: Read + Edit. Call_Duration_Seconds__c: Read-only (system-set). |
| Customer Care Agent | Yes | Yes | Yes | No | Profile-level Task access. Cannot see IS-specific custom fields unless FLS grants it. |
| HCP Queue Agent | Yes | Yes | Yes | No | Standard Task access. |
| Sales Manager | Yes | Yes | Yes | Yes | Manager-level access including Delete for cleanup. |

---

## OWASP Top 10 Checklist (Telephony / CTI Context)

| # | Risk | Applicability | Assessment | Status |
|---|------|--------------|------------|--------|
| M1 | Improper Credential Usage | HIGH — Connect API credentials for RecordingOptOutController | Named Credential required for all Amazon Connect API callouts. Hardcoded keys in Apex, CallCenter XML, or LWC is a critical violation. Must use External Credential with OAuth 2.0 JWT Bearer. | PENDING — Named Credential not yet created (S-02) |
| M2 | Inadequate Supply Chain Security | MEDIUM — Connect Streams JS, CTI Adapter managed package | connect-streams.js loaded from Amazon CDN. ACLightningAdapter is a managed package — verify publisher trust and version pinning. No SRI hash observed in NGPSTE-132 configuration. | PENDING — verify managed package version and CDN SRI |
| M3 | Insecure Authentication/Authorization | MEDIUM — SSO/SAML for Connect CCP | NGPSTE-533 (SSO) is in To Verify status. SAML configuration must use SHA-256 signing. Single logout must be supported to prevent orphaned CCP sessions. | PENDING — SSO/SAML not yet configured (B-07 from E2E) |
| M4 | Insufficient Input/Output Validation | MEDIUM — ANI parsing in InsideSalesScreenPopResolver | ANI arrives as E.164 format. Pseudo-code applies `replaceAll('[^0-9+]', '')` for normalization. `EncodingUtil.urlEncode` for URL construction. SOQL uses bind variables. Lightning auto-escapes output. | PASS — encoding and bind variables provide adequate protection (S-07, S-08) |
| M5 | Insecure Communication | HIGH — CTI traffic across multiple boundaries | TLS 1.2+ mandatory: SF ↔ Connect API (Named Credential enforces), agent browser ↔ CCP (HTTPS), CCP ↔ Connect (WebRTC SRTP). RecordingOptOutController callout must verify TLS certificate. | PASS — enforced by platform (SF requires TLS 1.2, Connect requires TLS 1.2, WebRTC uses SRTP) |
| M6 | Inadequate Privacy Controls | CRITICAL — call recordings contain PHI, screen pop exposes Patient records | S-01: Multi-object screen pop exposes Patient PHI to Inside Sales agents. S-03: Recording opt-out audit trail insufficient. S3 encryption audit still outstanding from NGPSTE-132 S-01. | PENDING — FLS restrictions on Patient PHI required. Recording audit trail fields needed. S3 audit carried forward. |
| M7 | Insufficient Binary Protections | N/A | No custom binary or mobile app — standard SF Lightning in browser. | N/A |
| M8 | Security Misconfiguration | MEDIUM — CSP, permission scope, FLS | CSP configuration carried from NGPSTE-132 (same Connect instance). IS_CTI_Base permission set requires FLS audit (S-04, S-05). IS_Softphone_Layout must not expose admin-only settings. | PENDING — CSP Trusted Sites configuration required. FLS audit on IS_CTI_Base needed. |
| M9 | Insecure Data Storage | LOW — Task records with call disposition | Task records stored in Salesforce with standard platform encryption. Call disposition is business data, not PII. Task.Description is agent-entered — must not auto-populate with call content. | PASS — with caveat: enforce no-PII-in-description policy via validation rule. |
| M10 | Insufficient Cryptography | LOW — platform-managed encryption | Salesforce Shield optional for data at rest. S3 encryption for recordings. No custom cryptographic operations in Apex. | PASS — no custom crypto. S3 encryption audit is infrastructure concern (NGPSTE-132 S-01). |

---

## Named Credential Requirements

The NGASIM-76 integration requires the same Named Credentials as NGPSTE-132, plus increased API scope for recording control:

| Named Credential | Purpose | Auth Type | Endpoint | Required IAM Actions |
|-----------------|---------|-----------|----------|---------------------|
| AmazonConnect_API | Server-side Connect API calls (recording control, agent status) | OAuth 2.0 (JWT Bearer) via External Credential | `https://your-instance.my.connect.aws/connect/api` | `connect:StopContactRecording`, `connect:SuspendContactRecording`, `connect:ResumeContactRecording`, `connect:DescribeContact` |
| AmazonConnect_CCP | Client-side CCP iframe (Connect Streams) | Session-based (IAM federation via SAML) | `https://your-instance.my.connect.aws/connect/ccp-v2` | Standard CCP permissions (agent-level) |

**Least-Privilege Principle:**
The `AmazonConnect_API` Named Credential's IAM role must be scoped to recording control actions ONLY. Do not grant `connect:*` — this would allow creating/deleting Connect instances, users, and routing profiles from Salesforce.

---

## CSP Configuration Required

Same as NGPSTE-132 — shared Connect instance domain. No additional CSP entries needed for NGASIM-76 unless a separate Connect instance is provisioned for Inside Sales.

**Required CSP Trusted Sites entries:**

| Directive | Domain | Purpose |
|-----------|--------|---------|
| frame-src | `https://your-instance.my.connect.aws` | CCP iframe embedding in Lightning utility bar |
| script-src | `https://your-instance.my.connect.aws` | Connect Streams JS execution |
| connect-src | `https://your-instance.my.connect.aws` | WebSocket and XHR for real-time agent events |
| media-src | `https://your-instance.my.connect.aws` | WebRTC media streams for voice audio |

**Anti-patterns to avoid:**
- Do NOT add `*.amazonaws.com` — overly broad, exposes all AWS services
- Do NOT add `*.amazon.com` — unrelated to Connect
- Do NOT use `unsafe-inline` or `unsafe-eval` in script-src — Connect Streams does not require them

---

## Recording Opt-Out HIPAA Compliance Assessment

| Requirement | Current Design | Gap | Recommendation |
|-------------|---------------|-----|----------------|
| Patient can verbally request recording stop | Quick Action backed by RecordingOptOutController (ADR-008) | None — mechanism exists | Implement as designed |
| Recording stops within reasonable time | 2-second latency target (ADR-008) | PENDING — not yet tested | Test with live Connect API. Add timeout handling. |
| Audit trail of opt-out request | VoiceCall.Recording_Opted_Out__c checkbox | INSUFFICIENT — no timestamp, no agent ID, no API confirmation (S-03) | Add DateTime, User lookup, and API response log fields |
| Re-recording prevented | Not addressed | GAP — after opt-out, if recording auto-resumes on transfer, patient's opt-out is violated | Add logic: once Recording_Opted_Out__c = true, any ResumeContactRecording call must be blocked unless patient re-consents |
| Compliance reporting | Not addressed | GAP — no report or dashboard for compliance team | Create HIPAA recording opt-out report: date, agent, patient, call duration, opt-out timestamp |
| Training documentation | Not addressed | OUT OF SCOPE — training is TTEC-managed | Flag for TTEC training materials: agents must offer recording opt-out at call start per policy |

---

## Multi-Object Screen Pop Data Exposure Risk Assessment

| Object | Fields Returned by Screen Pop | PII/PHI Risk | Mitigation |
|--------|------------------------------|-------------|------------|
| Lead | Id, Name, Phone, MobilePhone, Status, Company | MEDIUM — Name + Phone is PII | FLS on IS_CTI_Base: restrict to Phone, Name, Status, Company. Hide email, address. |
| PersonAccount | Id, Name, PersonHomePhone, PersonMobilePhone, Phone | HIGH — PersonAccount may contain PHI (medical device info, therapy dates, insurance) | Dedicated IS page layout hides PHI fields. FLS denies IS_CTI_Base access to PHI fields. Screen pop navigates to record — full page layout is the access boundary. |
| Contact | Id, Name, Phone, MobilePhone | LOW — Contact in fallback position, limited fields | Standard Contact page layout. IS agents have read-only Contact access. |
| Task (created by handler) | Subject, WhoId, WhatId, Call_Disposition__c, Call_Duration_Seconds__c | LOW — business data, not PII | Task.Description must not auto-populate with call content. Disposition is picklist (no free text PII). |
| VoiceCall | CallerNumber, CallDuration, Recording_Opted_Out__c, Call_Category__c | MEDIUM — CallerNumber is PII (phone number) | CallerNumber read-only to agents. Custom fields read-only (set by system). |

---

## Integration Boundary Security Assessment

| Boundary | Protocol | Authentication | Encryption | Risk Level | Notes |
|----------|----------|---------------|------------|------------|-------|
| Agent Browser → SF Lightning | HTTPS | SF Session (OAuth 2.0) | TLS 1.2+ | LOW | Standard platform security |
| SF Lightning → CCP iframe | HTTPS (postMessage) | Same-origin policy + CSP | TLS 1.2+ | MEDIUM | CSP must be configured (same as NGPSTE-132) |
| CCP → Amazon Connect | HTTPS + WebRTC | IAM federation via SAML/OAuth | TLS 1.2+ (signaling), SRTP (media) | LOW | AWS-managed |
| SF Apex → Connect API (RecordingOptOutController) | HTTPS | Named Credential (OAuth 2.0 JWT) | TLS 1.2+ | HIGH | Named Credential not yet created (S-02) |
| Connect → S3 (recordings) | Internal AWS | IAM role-based | SSE-S3 or SSE-KMS | HIGH | S3 audit from NGPSTE-132 S-01 still open |
| InsideSalesScreenPopResolver → SOQL | Internal SF | Session context | N/A (internal) | LOW | Bind variables protect against injection |
| VoiceCallActivityHandler → Task DML | Internal SF | Trigger context (system mode) | N/A (internal) | MEDIUM | Trigger runs in system mode — FLS not enforced. Task visibility depends on OWD/sharing model (S-06). |

---

## Recommendations Summary

1. **CRITICAL ACTION (S-01):** Restrict PersonAccount PHI fields from Inside Sales agents. Create dedicated IS page layout. Apply FLS on IS_CTI_Base to deny PHI field access. This is the highest-risk finding specific to NGASIM-76.
2. **CRITICAL ACTION (S-02):** Create Named Credential `AmazonConnect_API` before any Apex development. Coordinate IAM role with least-privilege scope.
3. **HIGH (S-03):** Enhance recording opt-out audit trail: add DateTime, User, and API response fields. Enable Field History Tracking. Create compliance report.
4. **MEDIUM (S-04):** Implement Lead duplicate rules to prevent screen pop-driven duplicate creation.
5. **MEDIUM (S-05):** Change Call_Category__c and True_Connection__c to read-only for agents. System-set fields must not be agent-editable.
6. **MEDIUM (S-06):** Review Task OWD and sharing model. IS call activity Tasks should not be visible to all departments.
7. **MEDIUM (S-07):** Add ANI format validation (10-15 digits minimum) before SOQL queries.
8. **LOW (S-08):** No action needed — encoding pattern in pseudo-code is correct. Maintain `EncodingUtil.urlEncode` on all ANI-to-URL construction.

---

## Handoff to REFACTOR Agent

The REFACTOR agent should:
1. Audit IS-specific metadata naming for consistency (IS_ prefix convention).
2. Extract call disposition picklist values into a constant class or Custom Metadata Type for maintainability.
3. Review environment exclusion list — any IS-specific metadata that should be in `.forceignore` for environment separation.
4. Flag configuration debt from cancelled stories (NGASIM-2549 NFRs, NGPSTE-531 queues).
5. Cross-reference security findings S-04 and S-05 for permission set refactoring needs.
6. Assess TTEC dependency debt — what Salesforce-side configuration is blocked by external partner.
7. Review OrgSync gap from F-09 — Task custom field mapping debt.
