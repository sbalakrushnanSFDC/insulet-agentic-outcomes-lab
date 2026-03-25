# NGPSTE-132: TEST-DRIVEN DEVELOPMENT

> **Pipeline Stage:** 03-tdd
> **Produced by:** tdd-guide agent
> **Input:** 01-plan.md (ACs) + 02-architecture.md (ADRs, object model, integration points)
> **Run ID:** NGPSTE-132-run-001
> **Timestamp:** 2026-03-25T00:00:00Z
> **Status:** COMPLETE — handed off to REVIEW

---

## Test Strategy Overview

NGPSTE-132 is primarily a **configuration-heavy** feature. The only custom Apex is
ScreenPopResolver (and its test class). The majority of verification is through SOQL
validation queries and manual/semi-automated acceptance tests.

| Test Category | Count | Automation Level |
|---|---|---|
| SOQL Validation (config exists) | 8 | Fully automated |
| Apex Unit Tests | 4 | Fully automated |
| Integration Tests (HTTP mock) | 2 | Fully automated |
| Manual Acceptance Tests | 6 | Manual with documented steps |
| **Total** | **20** | |

### Coverage Target

| Class | Target | Rationale |
|---|---|---|
| ScreenPopResolver | 90%+ | Critical path for screen pop; 3 code paths (match, no-match, error) |
| ScreenPopResolverTest | N/A | Test class — not counted |
| Overall project delta | 80%+ | ECC standard |

---

## Test Specifications by Acceptance Criteria

### T-01: CallCenter Registration (AC-01)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-01: CTI adapter is installed and registered as ACLightningAdapter |
| Precondition | DevInt2 or target org accessible |
| Verification Query | See below |
| Pass Criteria | Query returns exactly 1 row with DeveloperName = 'ACLightningAdapter' |
| Failure Action | Install Amazon Connect package if missing |

```sql
SELECT Id, DeveloperName, InternalName, Version
FROM CallCenter
WHERE DeveloperName = 'ACLightningAdapter'
```

**DevInt2 baseline:** ACLightningAdapter exists (confirmed in intake). This test validates post-deployment state matches baseline.

---

### T-02: Inbound Call via Lightning Softphone (AC-02)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-02: Agents can receive inbound calls via Lightning softphone |
| Precondition | Agent logged in to Lightning app with softphone utility bar. Amazon Connect CCP loaded. Agent status: Available_Voice. |
| Steps | 1. Place inbound call to agent's Connect direct inward dial (DID) number. 2. Verify softphone rings in Lightning utility bar. 3. Agent accepts call. 4. Verify VoiceCall record created. |
| Pass Criteria | Softphone rings within 5s. Agent can accept. VoiceCall record created with correct ANI. |
| SOQL Verification | See below |

```sql
SELECT Id, CallType, FromPhoneNumber, ToPhoneNumber, CreatedDate
FROM VoiceCall
WHERE CallType = 'Inbound'
ORDER BY CreatedDate DESC
LIMIT 1
```

---

### T-03: Outbound Click-to-Dial (AC-03)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-03: Agents can make outbound calls from Contact/Case records |
| Precondition | Agent logged in with CTI_Integration_Access permission. Contact record with Phone field populated. |
| Steps | 1. Navigate to Contact record. 2. Click phone number field (click-to-dial icon). 3. Verify softphone initiates outbound call. 4. Verify VoiceCall record created with CallType = 'Outbound'. |
| Pass Criteria | Outbound call initiates within 3s. VoiceCall record created. |

---

### T-04: Screen Pop — Known ANI (AC-04, positive path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-04: Screen pop resolves to correct Contact based on ANI |
| Class Under Test | ScreenPopResolver |
| Method | `resolveContact(String ani)` |

```java
@IsTest
static void testResolveContact_KnownANI_ReturnsContact() {
    Contact testContact = new Contact(
        FirstName = 'Test',
        LastName = 'CTIUser',
        Phone = '+15551234567'
    );
    insert testContact;

    Test.startTest();
    ScreenPopResolver.ScreenPopResult result =
        ScreenPopResolver.resolveContact('+15551234567');
    Test.stopTest();

    System.assertEquals(true, result.matched, 'Should match existing Contact');
    System.assertEquals(testContact.Id, result.contactId, 'Should return correct Contact Id');
    System.assert(result.screenPopUrl.contains(testContact.Id),
        'Screen pop URL should contain Contact Id');
}
```

---

### T-05: Screen Pop — Unknown ANI (AC-11, negative path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-11: Unknown ANI shows new Contact creation form |
| Class Under Test | ScreenPopResolver |
| Method | `resolveContact(String ani)` |

```java
@IsTest
static void testResolveContact_UnknownANI_ReturnsNewContactUrl() {
    Test.startTest();
    ScreenPopResolver.ScreenPopResult result =
        ScreenPopResolver.resolveContact('+15559999999');
    Test.stopTest();

    System.assertEquals(false, result.matched, 'Should not match any Contact');
    System.assertEquals(null, result.contactId, 'Contact Id should be null');
    System.assert(result.screenPopUrl.contains('/lightning/o/Contact/new'),
        'Should redirect to new Contact form');
    System.assert(result.screenPopUrl.contains('Phone='),
        'Should pre-populate Phone field with ANI');
}
```

---

### T-06: Call Recording Access — Authorized (AC-05, positive path)

| Field | Value |
|---|---|
| Type | SOQL Validation + Manual Test |
| AC | AC-05: Call recordings accessible with AC_CallRecording |
| SOQL | See below |
| Manual Steps | 1. Assign AC_CallRecording to test user. 2. Navigate to VoiceCall record. 3. Click "Play Recording" action. 4. Verify audio loads from S3 pre-signed URL. |

```sql
SELECT Id, PermissionSet.Name, AssigneeId, Assignee.Username
FROM PermissionSetAssignment
WHERE PermissionSet.Name = 'AC_CallRecording'
AND Assignee.IsActive = true
```

---

### T-07: Call Recording Access — Unauthorized (AC-05, negative path)

| Field | Value |
|---|---|
| Type | Manual Test |
| AC | AC-05: Users without AC_CallRecording cannot access recordings |
| Steps | 1. Log in as user WITHOUT AC_CallRecording permission set. 2. Navigate to VoiceCall record. 3. Attempt to access recording. 4. Verify access denied or action not visible. |
| Pass Criteria | "Play Recording" action is either hidden or returns insufficient privileges error. |

---

### T-08: Omni-Channel Voice Routing (AC-06, positive path)

| Field | Value |
|---|---|
| Type | SOQL Validation + Manual Test |
| AC | AC-06: Omni-Channel routes voice work items via sfdc_phone |
| SOQL | See below |
| Manual Steps | 1. Agent sets presence to Available_Voice. 2. Inbound call arrives. 3. Omni-Channel routes work item to agent. 4. Verify AgentWork record created with ServiceChannel = sfdc_phone. |

```sql
SELECT Id, DeveloperName, RelatedEntity, IsActive
FROM ServiceChannel
WHERE DeveloperName = 'sfdc_phone'
```

---

### T-09: Agent Presence Status Transitions (AC-07)

| Field | Value |
|---|---|
| Type | SOQL Validation + Manual Test |
| AC | AC-07: Agent presence states configured and functional |
| SOQL | See below |
| Manual Steps | 1. Agent logs in. 2. Set presence to Available_Voice — verify green indicator. 3. Accept call — verify auto-transition to Busy_Voice. 4. End call — verify transition to AfterCallWork_Voice. 5. Complete ACW — verify return to Available_Voice. |

```sql
SELECT Id, DeveloperName, MasterLabel, IsActive
FROM ServicePresenceStatus
WHERE DeveloperName IN (
    'Available_Voice',
    'Busy_Voice',
    'AfterCallWork_Voice'
)
```

**Expected result:** 3 rows returned, all IsActive = true.

**DevInt2 baseline:** Zero rows returned (gap identified in intake). This query validates Phase 2 deliverable.

---

### T-10: CTI_Integration_Access Permission (AC-08, positive path)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-08: CTI_Integration_Access grants API access |
| SOQL | See below |
| Pass Criteria | Permission set exists and includes required object/field permissions for CTI API operations. |

```sql
SELECT Id, Name, Label, Description
FROM PermissionSet
WHERE Name = 'CTI_Integration_Access'
```

```sql
SELECT Id, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit
FROM ObjectPermissions
WHERE ParentId IN (
    SELECT Id FROM PermissionSet WHERE Name = 'CTI_Integration_Access'
)
```

---

### T-11: Classic → Lightning Migration (AC-09)

| Field | Value |
|---|---|
| Type | Regression Test (Manual) |
| AC | AC-09: Classic-to-Lightning migration preserves configuration |
| Precondition | NGPSTE-1123 completed. Both ACClassicAdapter and ACLightningAdapter present. |
| Steps | 1. Export ACClassicAdapter CallCenter XML. 2. Export ACLightningAdapter CallCenter XML. 3. Compare field mappings, adapter URLs, custom settings. 4. Log in via Classic — verify CTI loads. 5. Log in via Lightning — verify CTI loads. 6. Verify same call center settings apply in both modes. |
| Pass Criteria | No configuration loss. Both adapters functional. |
| Blocked By | NGPSTE-1123 (To Do) |

```sql
SELECT Id, DeveloperName, InternalName, Version
FROM CallCenter
WHERE DeveloperName IN ('ACClassicAdapter', 'ACLightningAdapter')
```

---

### T-12: Connect API Outage Handling (AC-12, negative path)

| Field | Value |
|---|---|
| Type | Apex Integration Test (HttpCalloutMock) |
| AC | AC-12: CTI integration handles Connect API outages gracefully |
| Class Under Test | ScreenPopResolver (or future ConnectApiService) |

```java
@IsTest
static void testConnectApiTimeout_HandlesGracefully() {
    Test.setMock(HttpCalloutMock.class, new ConnectApiTimeoutMock());

    Test.startTest();
    ScreenPopResolver.ScreenPopResult result =
        ScreenPopResolver.resolveContact('+15551234567');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null on API failure');
    System.assertEquals(false, result.apiError == null,
        'Should populate error message');
}

private class ConnectApiTimeoutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        CalloutException e = new CalloutException();
        e.setMessage('Read timed out');
        throw e;
    }
}
```

---

### T-13: TTEC Agent CTI Access (AC-10)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-10: TTEC agents can access CTI features |
| Steps | 1. Log in as user with TTEC profile. 2. Verify Lightning app loads with softphone utility bar. 3. Verify Omni-Channel widget shows voice presence options. 4. Place test call — verify softphone rings. |
| Pass Criteria | TTEC agent has full CTI functionality. |

---

### T-14: Screen Pop — Null/Empty ANI (edge case)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-04 (edge case) |
| Class Under Test | ScreenPopResolver |

```java
@IsTest
static void testResolveContact_NullANI_ReturnsNewContactUrl() {
    Test.startTest();
    ScreenPopResolver.ScreenPopResult result =
        ScreenPopResolver.resolveContact(null);
    Test.stopTest();

    System.assertEquals(false, result.matched, 'Null ANI should not match');
    System.assert(result.screenPopUrl.contains('/lightning/o/Contact/new'),
        'Should redirect to new Contact form for null ANI');
}

@IsTest
static void testResolveContact_EmptyANI_ReturnsNewContactUrl() {
    Test.startTest();
    ScreenPopResolver.ScreenPopResult result =
        ScreenPopResolver.resolveContact('');
    Test.stopTest();

    System.assertEquals(false, result.matched, 'Empty ANI should not match');
}
```

---

## SOQL Validation Query Summary

These queries validate configuration state and are runnable against DevInt2 (read-only)
or the target deployment org.

| # | Query Purpose | Expected Result (Post-Deployment) |
|---|---|---|
| SQ-01 | CallCenter ACLightningAdapter exists | 1 row |
| SQ-02 | VoiceCall records created by test calls | >= 1 row (after manual test) |
| SQ-03 | AC_CallRecording assignments | >= 1 row (authorized users) |
| SQ-04 | sfdc_phone ServiceChannel active | 1 row, IsActive = true |
| SQ-05 | ServicePresenceStatus voice states | 3 rows (Available, Busy, ACW) |
| SQ-06 | CTI_Integration_Access exists | 1 row |
| SQ-07 | ObjectPermissions for CTI PS | Rows for VoiceCall, Contact, Case |
| SQ-08 | Classic + Lightning adapters | 2 rows |

---

## Test Data Factory Design

```java
@IsTest
public class CTITestDataFactory {

    public static Contact createContactWithPhone(String phone) {
        Contact c = new Contact(
            FirstName = 'CTI',
            LastName = 'TestContact_' + System.currentTimeMillis(),
            Phone = phone
        );
        insert c;
        return c;
    }

    public static List<Contact> createContactsWithPhones(List<String> phones) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < phones.size(); i++) {
            contacts.add(new Contact(
                FirstName = 'CTI',
                LastName = 'TestContact_' + i,
                Phone = phones[i]
            ));
        }
        insert contacts;
        return contacts;
    }

    public static User createCTIAgentUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'CTI',
            LastName = 'TestAgent',
            Email = 'cti.testagent@test.ngpste132.com',
            Username = 'cti.testagent@test.ngpste132.com.' + System.currentTimeMillis(),
            Alias = 'ctiagnt',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    public static void assignPermissionSet(Id userId, String permSetName) {
        PermissionSet ps = [
            SELECT Id FROM PermissionSet
            WHERE Name = :permSetName LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = ps.Id
        );
    }
}
```

---

## Coverage Estimate

| Class | Methods | Lines (est.) | Covered By | Est. Coverage |
|---|---|---|---|---|
| ScreenPopResolver | resolveContact | ~30 | T-04, T-05, T-12, T-14 | 90%+ |
| CTITestDataFactory | 4 factory methods | ~40 | Utility — used by all tests | 100% |
| ConnectApiTimeoutMock | respond | ~5 | T-12 | 100% |

**Overall custom Apex coverage:** 90%+ (exceeds 80% target).

**Note:** The majority of NGPSTE-132 is configuration, not custom code. Apex coverage is
limited to ScreenPopResolver. Configuration validation relies on SOQL queries (SQ-01 through SQ-08).

---

## Test Execution Plan

| Phase | Tests | Automation | Blocking |
|---|---|---|---|
| Phase 1 | T-01, T-02, T-03 | SQ-01 automated; T-02, T-03 manual | T-01 blocks Phase 2 |
| Phase 2 | T-08, T-09 | SQ-04, SQ-05 automated; routing manual | T-09 blocks Phase 3 |
| Phase 3 | T-04, T-05, T-06, T-07, T-10, T-11, T-12, T-13, T-14 | T-04, T-05, T-12, T-14 automated; rest manual | T-11 blocked by NGPSTE-1123 |

---

## Handoff to REVIEW

**Directive:** The code-reviewer agent must:

1. Review all prior artifacts (00-intake, 01-plan, 02-architecture, 03-tdd) for consistency.
2. Identify gaps between ACs and test coverage.
3. Flag risks from cancelled child stories (NGPSTE-644, NGPSTE-905).
4. Assess ADR quality and completeness.
5. Verify SOQL queries are parameterized and governor-limit safe.
6. Check ScreenPopResolver design for security (SOQL injection, null handling).
7. Recommend remediation for all HIGH/CRITICAL findings.
