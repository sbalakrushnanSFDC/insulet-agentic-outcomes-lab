# NGPSTE-132: ARCHITECTURE

> **Pipeline Stage:** 02-architecture
> **Produced by:** architect agent
> **Input:** 01-plan.md + DevInt2 live metadata
> **Run ID:** NGPSTE-132-run-001
> **Timestamp:** 2026-03-25T00:00:00Z
> **Status:** COMPLETE — handed off to TDD

---

## Architecture Decision Records

### ADR-001: Use Existing ACLightningAdapter Over Custom Lightning CTI Adapter

| Field | Value |
|---|---|
| Status | Accepted |
| Context | DevInt2 contains 5 CallCenter records: ACClassicAdapter, ACConsoleAdapter, ACLightningAdapter, DevInt2ACLightningAdapter, SITACLightningAdapter. NGPSTE-161 (Install Package) is Done. |
| Decision | Use the existing ACLightningAdapter Call Center record as the primary CTI adapter for NextGen Lightning Experience. |
| Rationale | The adapter is already installed, registered, and has been validated by NGPSTE-161 and NGPSTE-833. Creating a custom LWC-based CTI adapter would duplicate functionality with no clear benefit. |
| Alternatives Considered | (A1) Custom LWC CTI adapter — rejected: high effort, no incremental value over OOB adapter. (A2) DevInt2ACLightningAdapter — rejected: environment-specific variant, not portable to production. (A3) SITACLightningAdapter — rejected: SIT-environment scoped. |
| Consequences | Locked to Amazon Connect adapter patterns and versioning. Adapter upgrades depend on Amazon Connect Salesforce package releases. SCV migration would require replacing this adapter. |
| Traces to | AC-01, FR-01, FR-02, PD-01 |

### ADR-002: Use Open CTI (Not Service Cloud Voice) for Call Management

| Field | Value |
|---|---|
| Status | Accepted |
| Context | The Jira description states Amazon Connect is "very customized today" and suggests "consider thinking about Service Cloud Voice." DevInt2 has sfdc_phone ServiceChannel with RelatedEntity VoiceCall, confirming SCV objects are provisioned. |
| Decision | Retain the Open CTI integration pattern for Amazon Connect. Defer SCV migration. |
| Rationale | SCV would require rebuilding Amazon Connect's custom contact flows, Lambda hooks, and routing logic within the SCV telephony provider model. The existing customization depth makes this a multi-quarter effort. Open CTI preserves all existing customizations. |
| Alternatives Considered | (A1) SCV with Amazon Connect as telephony provider — rejected for now: requires contact flow migration, Lambda adapter layer, and potential loss of custom IVR features. Estimated 3–6 month additional effort. (A2) Hybrid approach (Open CTI now, SCV later) — this IS the chosen path, with SCV as a future initiative. |
| Consequences | No Einstein Call Coaching (SCV-only feature). Custom screen pop logic required (SCV provides native screen pop). No native voice transcription. Manual reporting for call metrics. |
| Traces to | AC-02, AC-03, AC-04, FR-03, FR-04, FR-05, PD-04, R-07 |

### ADR-003: Configure Omni-Channel for Voice Routing

| Field | Value |
|---|---|
| Status | Accepted |
| Context | DevInt2 has sfdc_phone ServiceChannel (RelatedEntity: VoiceCall). No ServicePresenceStatus records exist. |
| Decision | Configure Omni-Channel voice routing using the existing sfdc_phone ServiceChannel. Create ServicePresenceStatus records for Available_Voice, Busy_Voice, and AfterCallWork_Voice. |
| Rationale | sfdc_phone ServiceChannel already exists and targets VoiceCall. Omni-Channel provides skills-based routing, capacity management, and presence visibility — all required for a production CTI deployment. |
| Alternatives Considered | (A1) Queue-based routing without Omni-Channel — rejected: no presence management, no capacity-based assignment, no real-time supervisor visibility. (A2) Custom routing Apex — rejected: reinvents Omni-Channel capabilities. |
| Consequences | Requires ServicePresenceStatus creation (Phase 2 task). Requires agent profile configuration to include Omni-Channel presence. Supervisor dashboards will need Omni-Channel Supervisor permission. |
| Traces to | AC-06, AC-07, FR-07, FR-08, PD-02, PD-03, R-05 |

### ADR-004: Extend Existing Permission Sets Over Creating New Ones

| Field | Value |
|---|---|
| Status | Accepted |
| Context | DevInt2 has AC_CallRecording and CTI_Integration_Access permission sets. |
| Decision | Extend assignments of existing permission sets to target user profiles. Do not create new permission sets for CTI access. Consider Permission Set Group to bundle them. |
| Rationale | Permission sets already exist and encode the correct object/field access. Creating new ones risks permission drift and duplication. |
| Alternatives Considered | (A1) New CTI_Agent permission set — rejected: duplicates existing access grants. (A2) Profile-based access — rejected: Salesforce best practice is permission sets over profiles for granular control. |
| Consequences | Must audit existing permission set contents to verify completeness for all AC scenarios. Permission Set Group (bundling AC_CallRecording + CTI_Integration_Access) recommended for assignment simplicity. |
| Traces to | AC-05, AC-08, FR-06, PD-05 |

---

## Component Integration Design

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AMAZON CONNECT                               │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │ Contact   │  │ Lambda       │  │ S3 Call      │  │ Connect   │  │
│  │ Flows     │  │ Functions    │  │ Recordings   │  │ Streams   │  │
│  └─────┬────┘  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘  │
└────────┼───────────────┼────────────────┼────────────────┼─────────┘
         │               │                │                │
         ▼               ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    INTEGRATION LAYER                                │
│  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Named Credential  │  │ Connected App     │  │ Event Relay     │  │
│  │ (AmazonConnect    │  │ (Lambda Auth)     │  │ (CTI Events)    │  │
│  │  _API)            │  │                   │  │                 │  │
│  └────────┬─────────┘  └────────┬──────────┘  └───────┬─────────┘  │
└───────────┼─────────────────────┼──────────────────────┼────────────┘
            │                     │                      │
            ▼                     ▼                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    SALESFORCE LIGHTNING                              │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ CTI ADAPTER LAYER                                            │  │
│  │  ┌─────────────────────┐  ┌──────────────────────────────┐  │  │
│  │  │ ACLightningAdapter  │  │ Open CTI JavaScript API      │  │  │
│  │  │ (CallCenter)        │──│ (sforce.opencti)             │  │  │
│  │  └─────────┬───────────┘  └──────────────┬───────────────┘  │  │
│  └────────────┼─────────────────────────────┼──────────────────┘  │
│               │                             │                      │
│               ▼                             ▼                      │
│  ┌──────────────────────┐  ┌──────────────────────────────────┐   │
│  │ Softphone Utility    │  │ ScreenPopResolver (Apex)         │   │
│  │ (Lightning App Bar)  │  │  - ANI → Contact SOQL lookup     │   │
│  │                      │  │  - Unknown ANI → new Contact form │   │
│  └──────────┬───────────┘  └──────────────────────────────────┘   │
│             │                                                      │
│             ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ OMNI-CHANNEL ROUTING                                        │  │
│  │  ┌─────────────────┐  ┌──────────────────────────────────┐ │  │
│  │  │ sfdc_phone       │  │ ServicePresenceStatus            │ │  │
│  │  │ ServiceChannel   │  │  - Available_Voice               │ │  │
│  │  │ (VoiceCall)      │  │  - Busy_Voice                    │ │  │
│  │  │                  │  │  - AfterCallWork_Voice            │ │  │
│  │  └─────────┬───────┘  └──────────────────────────────────┘ │  │
│  └────────────┼───────────────────────────────────────────────┘  │
│               │                                                    │
│               ▼                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ AGENT DESKTOP                                               │  │
│  │  Contact/Case Record Page + Softphone + Omni-Channel Widget │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Object Model

### Standard Objects (already provisioned)

| Object API Name | Usage | DevInt2 Evidence |
|---|---|---|
| CallCenter | Stores CTI adapter registration | 5 records found (ACLightningAdapter is primary) |
| VoiceCall | Represents a phone call | Referenced by sfdc_phone ServiceChannel RelatedEntity |
| ServiceChannel | Defines Omni-Channel routing channel | sfdc_phone record exists |
| ServicePresenceStatus | Agent availability states | **Not configured** — must create |
| PermissionSet | Access control | AC_CallRecording, CTI_Integration_Access exist |

### Custom Objects / Metadata (to be created)

| Type | API Name | Purpose | Phase |
|---|---|---|---|
| CustomMetadata | CTI_Config__mdt | Store CTI configuration: Connect instance URL, default queue, screen pop behavior | 3 |
| ApexClass | ScreenPopResolver | Resolve inbound ANI to Contact record via SOQL; return screenPop URL | 3 |
| ApexClass | ScreenPopResolverTest | Test class for ScreenPopResolver (80%+ coverage) | 3 |
| NamedCredential | AmazonConnect_API | Secure outbound callout to Connect API (agent status sync, call control) | 3 |

---

## Integration Points

### 1. Amazon Connect → Salesforce (Inbound)

| Aspect | Detail |
|---|---|
| Protocol | Amazon Connect Streams API (JavaScript) embedded in CTI adapter |
| Authentication | Amazon Connect session token (managed by adapter) |
| Data Flow | Inbound call event → CTI adapter → Open CTI onIncomingCall → ScreenPopResolver → Contact page |
| Error Handling | Adapter handles Connect session timeouts. ScreenPopResolver returns fallback (new Contact form) on SOQL failure. |

### 2. Salesforce → Amazon Connect (Outbound)

| Aspect | Detail |
|---|---|
| Protocol | Open CTI `sforce.opencti.makeCall()` → Connect Streams `agent.connect()` |
| Authentication | CTI adapter session (no separate auth needed for click-to-dial) |
| Data Flow | Click phone field → Open CTI dial → Connect initiates outbound → call record created |
| Error Handling | Open CTI error callback → UI toast notification to agent |

### 3. Call Recordings (S3)

| Aspect | Detail |
|---|---|
| Protocol | Amazon S3 pre-signed URLs served via Connect API |
| Authentication | Named Credential (AmazonConnect_API) with IAM role for S3 read access |
| Data Flow | VoiceCall record → "Play Recording" action → Apex callout to Connect → S3 pre-signed URL → audio player |
| Access Control | AC_CallRecording permission set gates the "Play Recording" action |

### 4. Lambda Functions

| Aspect | Detail |
|---|---|
| Protocol | AWS Lambda invoked by Connect contact flows |
| Status | NGPSTE-644 (Lambda package install) was Cancelled. Lambda functions may be deployed outside Salesforce package. |
| Risk | If Lambda functions are not deployed, Contact Flow lookups (e.g., caller identity, routing decisions) will fail silently. |
| Mitigation | Audit AWS Lambda console for existing functions. Document in pre-deployment checklist. |

---

## Metadata Inventory (Deployment Sequence)

| # | Metadata Type | API Name | Phase | Deploy Action | Depends On |
|---|---|---|---|---|---|
| 1 | CallCenter | ACLightningAdapter | 1 | Validate only (already deployed) | — |
| 2 | Layout | Contact-CTI | 1 | Modify: add softphone panel, click-to-dial fields | #1 |
| 3 | Layout | Case-CTI | 1 | Modify: add click-to-dial fields | #1 |
| 4 | FlexiPage | Lightning_CTI_App | 1 | Configure: add Open CTI softphone utility item | #1 |
| 5 | ServiceChannel | sfdc_phone | 2 | Validate only (already deployed) | — |
| 6 | ServicePresenceStatus | Available_Voice | 2 | Create | #5 |
| 7 | ServicePresenceStatus | Busy_Voice | 2 | Create | #5 |
| 8 | ServicePresenceStatus | AfterCallWork_Voice | 2 | Create | #5 |
| 9 | PermissionSet | AC_CallRecording | 3 | Validate + extend assignment | — |
| 10 | PermissionSet | CTI_Integration_Access | 3 | Validate + extend assignment | — |
| 11 | NamedCredential | AmazonConnect_API | 3 | Create | — |
| 12 | CustomMetadata | CTI_Config__mdt | 3 | Create | — |
| 13 | ApexClass | ScreenPopResolver | 3 | Create | #12 |
| 14 | ApexClass | ScreenPopResolverTest | 3 | Create | #13 |
| 15 | PermissionSetGroup | CTI_Agent_Bundle | 3 | Create (bundles #9 + #10) | #9, #10 |

---

## Security Considerations

| Concern | Mitigation |
|---|---|
| Call recording access | Gated by AC_CallRecording permission set. No anonymous access. S3 pre-signed URLs expire. |
| CTI API access | CTI_Integration_Access permission set restricts API invocations to authorized users. |
| Named Credential secrets | Stored in Salesforce Named Credential vault. No hardcoded AWS keys. |
| Cross-origin (CORS) | Amazon Connect Streams API must be allowed in CSP Trusted Sites. |
| Data classification | VoiceCall records may contain PII (caller phone number). Field-level security on Phone fields. |
| SOQL injection | ScreenPopResolver uses parameterized bind variables, never string concatenation. |

---

## Performance Considerations

| Concern | Target | Approach |
|---|---|---|
| Screen pop latency | < 2s from ring to Contact display | Indexed SOQL on Contact.Phone with selective query |
| Omni-Channel routing | < 5s from call arrival to agent assignment | Standard Omni-Channel routing engine (platform SLA) |
| Recording playback | < 3s to start audio | S3 pre-signed URL with CloudFront CDN |
| Softphone load time | < 1s on Lightning page load | Lazy-load CTI adapter via utility bar |

---

## Migration Path: Classic → Lightning

| Step | Description | Risk |
|---|---|---|
| 1 | Export ACClassicAdapter CallCenter XML | Low |
| 2 | Compare Classic adapter settings with ACLightningAdapter | Medium — field mapping differences |
| 3 | Identify Classic-only features (console integration, sidebar) | Medium — may not have Lightning equivalents |
| 4 | Configure Lightning equivalents (utility bar, softphone component) | Low |
| 5 | Test with dual-mode users (Classic + Lightning) | High — CTI adapter conflicts possible |
| 6 | Decommission ACClassicAdapter after full Lightning adoption | Low — clean-up only |

**Gating condition:** NGPSTE-1123 (Classic Dev: Install Package Part 3) must reach Done before step 5.

---

## Handoff to TDD

**Directive:** The tdd-guide agent must:

1. Write test specifications for all 12 ACs (AC-01 through AC-12).
2. Include SOQL validation queries for configuration verification (CallCenter, ServiceChannel, ServicePresenceStatus, PermissionSet).
3. Design ScreenPopResolver test class with positive (known ANI), negative (unknown ANI), and error (SOQL exception) paths.
4. Specify test data factory for Contact records with phone numbers matching test ANIs.
5. Define integration test stubs for Amazon Connect API callouts (HttpCalloutMock).
6. Estimate coverage targets: ScreenPopResolver must reach 80%+.
