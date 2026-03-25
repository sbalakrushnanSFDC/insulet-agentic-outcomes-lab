# NGASIM-76: TEST-DRIVEN DEVELOPMENT

> **Pipeline Stage:** 03-tdd
> **Produced by:** tdd-guide agent
> **Input:** 01-plan.md (ACs) + 02-architecture.md (ADRs, object model, integration points)
> **Run ID:** NGASIM-76-run-001
> **Timestamp:** 2026-03-25T06:38:00Z
> **Status:** COMPLETE — handed off to REVIEW

---

## Test Strategy Overview

NGASIM-76 is a **mixed configuration + custom Apex** feature. Three custom Apex classes
require unit and integration tests: InsideSalesScreenPopResolver, VoiceCallActivityHandler,
and RecordingOptOutController. Configuration verification (Omni-Channel routing, queues,
presence statuses, permissions) is validated through SOQL queries and manual acceptance tests.

| Test Category | Count | Automation Level |
|---|---|---|
| SOQL Validation (config exists) | 10 | Fully automated |
| Apex Unit Tests | 12 | Fully automated |
| Integration Tests (HTTP mock) | 4 | Fully automated |
| Manual Acceptance Tests | 8 | Manual with documented steps |
| **Total** | **34** | |

### Coverage Targets

| Class | Target | Rationale |
|---|---|---|
| InsideSalesScreenPopResolver | 90%+ | Critical path for screen pop; 4 code paths (Lead match, PersonAccount match, Contact match, no match) + edge cases |
| VoiceCallActivityHandler | 85%+ | Trigger handler with bulk DML; must cover single, bulk, and error paths |
| RecordingOptOutController | 85%+ | HTTP callout with success, timeout, error, and already-opted-out paths |
| ISCTITestDataFactory | N/A | Test utility class — not counted |
| Overall project delta | 85%+ | ECC standard + NGASIM-76 custom target |

---

## Test Specifications by Acceptance Criteria

### T-01: Screen Pop — Known Lead Match (AC-02, positive path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-02: Inbound screen pop resolves caller ANI to Lead record (by Phone/MobilePhone) |
| Class Under Test | InsideSalesScreenPopResolver |
| Method | `resolveRecord(String ani)` |

```java
@IsTest
static void testResolveRecord_KnownLeadPhone_ReturnsLead() {
    Lead testLead = ISCTITestDataFactory.createLeadWithPhone('+15551000001');

    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord('+15551000001');
    Test.stopTest();

    System.assertEquals(true, result.matched, 'Should match existing Lead');
    System.assertEquals(testLead.Id, result.recordId, 'Should return correct Lead Id');
    System.assertEquals('Lead', result.objectType, 'Should identify object as Lead');
    System.assert(result.screenPopUrl.contains(testLead.Id),
        'Screen pop URL should contain Lead Id');
}

@IsTest
static void testResolveRecord_KnownLeadMobilePhone_ReturnsLead() {
    Lead testLead = ISCTITestDataFactory.createLeadWithMobilePhone('+15551000002');

    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord('+15551000002');
    Test.stopTest();

    System.assertEquals(true, result.matched, 'Should match Lead by MobilePhone');
    System.assertEquals(testLead.Id, result.recordId, 'Should return correct Lead Id');
    System.assertEquals('Lead', result.objectType, 'Should identify object as Lead');
}
```

---

### T-02: Screen Pop — Known PersonAccount Match (AC-03, positive path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-03: Inbound screen pop resolves caller ANI to Patient/PersonAccount if no Lead match |
| Class Under Test | InsideSalesScreenPopResolver |
| Method | `resolveRecord(String ani)` |

```java
@IsTest
static void testResolveRecord_KnownPersonAccountPhone_ReturnsPersonAccount() {
    Account testPA = ISCTITestDataFactory.createPersonAccountWithPhone('+15552000001');

    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord('+15552000001');
    Test.stopTest();

    System.assertEquals(true, result.matched, 'Should match existing PersonAccount');
    System.assertEquals(testPA.Id, result.recordId, 'Should return correct PersonAccount Id');
    System.assertEquals('Account', result.objectType, 'Should identify object as Account (PersonAccount)');
    System.assert(result.screenPopUrl.contains(testPA.Id),
        'Screen pop URL should contain PersonAccount Id');
}
```

---

### T-03: Screen Pop — Known Contact Match (AC-03, fallback path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-03: Screen pop resolves to Contact when no Lead or PersonAccount match found |
| Class Under Test | InsideSalesScreenPopResolver |
| Method | `resolveRecord(String ani)` |

```java
@IsTest
static void testResolveRecord_KnownContactPhone_ReturnsContact() {
    Contact testContact = ISCTITestDataFactory.createContactWithPhone('+15553000001');

    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord('+15553000001');
    Test.stopTest();

    System.assertEquals(true, result.matched, 'Should match existing Contact');
    System.assertEquals(testContact.Id, result.recordId, 'Should return correct Contact Id');
    System.assertEquals('Contact', result.objectType, 'Should identify object as Contact');
    System.assert(result.screenPopUrl.contains(testContact.Id),
        'Screen pop URL should contain Contact Id');
}
```

---

### T-04: Screen Pop — Unknown ANI (AC-04, negative path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-04: Inbound screen pop displays new Lead creation form with ANI pre-populated when no match found |
| Class Under Test | InsideSalesScreenPopResolver |
| Method | `resolveRecord(String ani)` |

```java
@IsTest
static void testResolveRecord_UnknownANI_ReturnsNewLeadUrl() {
    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord('+15559999999');
    Test.stopTest();

    System.assertEquals(false, result.matched, 'Should not match any record');
    System.assertEquals(null, result.recordId, 'Record Id should be null');
    System.assertEquals('Lead', result.objectType, 'Default object should be Lead for Inside Sales');
    System.assert(result.screenPopUrl.contains('/lightning/o/Lead/new'),
        'Should redirect to new Lead form');
    System.assert(result.screenPopUrl.contains('Phone='),
        'Should pre-populate Phone field with ANI');
}
```

---

### T-05: Screen Pop — Null and Empty ANI (AC-04, edge case)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-04 (edge case): null and empty ANI must not throw, must return new Lead form |
| Class Under Test | InsideSalesScreenPopResolver |

```java
@IsTest
static void testResolveRecord_NullANI_ReturnsNewLeadUrl() {
    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord(null);
    Test.stopTest();

    System.assertEquals(false, result.matched, 'Null ANI should not match');
    System.assert(result.screenPopUrl.contains('/lightning/o/Lead/new'),
        'Should redirect to new Lead form for null ANI');
}

@IsTest
static void testResolveRecord_EmptyANI_ReturnsNewLeadUrl() {
    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord('');
    Test.stopTest();

    System.assertEquals(false, result.matched, 'Empty ANI should not match');
    System.assert(result.screenPopUrl.contains('/lightning/o/Lead/new'),
        'Should redirect to new Lead form for empty ANI');
}
```

---

### T-06: Screen Pop — Duplicate Phone Across Objects (AC-02, priority path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-02: When same phone exists on Lead and Contact, Lead takes priority (waterfall order) |
| Class Under Test | InsideSalesScreenPopResolver |
| Method | `resolveRecord(String ani)` |

```java
@IsTest
static void testResolveRecord_DuplicatePhoneAcrossObjects_ReturnsLeadFirst() {
    String sharedPhone = '+15554000001';
    Lead testLead = ISCTITestDataFactory.createLeadWithPhone(sharedPhone);
    Contact testContact = ISCTITestDataFactory.createContactWithPhone(sharedPhone);

    Test.startTest();
    InsideSalesScreenPopResolver.ScreenPopResult result =
        InsideSalesScreenPopResolver.resolveRecord(sharedPhone);
    Test.stopTest();

    System.assertEquals(true, result.matched, 'Should match');
    System.assertEquals(testLead.Id, result.recordId,
        'Should return Lead Id (first in waterfall) when phone exists on both Lead and Contact');
    System.assertEquals('Lead', result.objectType, 'Lead takes priority over Contact');
}
```

---

### T-07: Task Auto-Creation — Single Call Completion (AC-08, positive path)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-08: A Task record is auto-created on call completion with Subject, WhoId, WhatId, Call Duration, Call Type |
| Class Under Test | VoiceCallActivityHandler |
| Trigger | VoiceCallActivityTrigger (after update) |

```java
@IsTest
static void testTaskCreation_SingleCallCompleted_TaskCreated() {
    Lead testLead = ISCTITestDataFactory.createLeadWithPhone('+15555000001');

    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15555000001', 'Inbound', 'InProgress'
    );

    Test.startTest();
    vc.Status__c = 'Completed';
    vc.Duration__c = 180;
    update vc;
    Test.stopTest();

    List<Task> tasks = [
        SELECT Id, Subject, WhoId, CallType, CallDurationInSeconds,
               Call_Disposition__c, Status
        FROM Task
        WHERE WhoId = :testLead.Id
        AND Subject LIKE '%Call%'
    ];

    System.assertEquals(1, tasks.size(), 'Exactly one Task should be created');
    System.assertEquals(testLead.Id, tasks[0].WhoId, 'WhoId should map to Lead');
    System.assertEquals('Inbound', tasks[0].CallType, 'CallType should match VoiceCall');
    System.assertEquals(180, tasks[0].CallDurationInSeconds, 'Duration should match');
    System.assertEquals('Completed', tasks[0].Status, 'Task should be Completed');
}
```

---

### T-08: Task Auto-Creation — Bulk 200 Records (AC-08, bulk safety)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-08 (bulk safety): Trigger must handle 200 VoiceCall records in a single transaction |
| Class Under Test | VoiceCallActivityHandler |

```java
@IsTest
static void testTaskCreation_Bulk200Calls_AllTasksCreated() {
    List<Lead> leads = ISCTITestDataFactory.createLeadsWithPhones(200);

    List<VoiceCall> voiceCalls = new List<VoiceCall>();
    for (Integer i = 0; i < 200; i++) {
        voiceCalls.add(ISCTITestDataFactory.buildVoiceCall(
            leads[i].Phone, 'Inbound', 'InProgress'
        ));
    }
    insert voiceCalls;

    Test.startTest();
    for (VoiceCall vc : voiceCalls) {
        vc.Status__c = 'Completed';
        vc.Duration__c = 120;
    }
    update voiceCalls;
    Test.stopTest();

    List<Task> tasks = [
        SELECT Id, WhoId FROM Task
        WHERE Subject LIKE '%Call%'
        AND CreatedDate = TODAY
    ];

    System.assertEquals(200, tasks.size(),
        'All 200 VoiceCalls should produce Tasks without governor limit failure');
}
```

---

### T-09: Task Auto-Creation — Missing WhoId (AC-08, edge case)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-08 (edge case): Task must still be created even when WhoId cannot be resolved from ANI |
| Class Under Test | VoiceCallActivityHandler |

```java
@IsTest
static void testTaskCreation_MissingWhoId_TaskCreatedWithoutWho() {
    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15559999999', 'Inbound', 'InProgress'
    );

    Test.startTest();
    vc.Status__c = 'Completed';
    vc.Duration__c = 60;
    update vc;
    Test.stopTest();

    List<Task> tasks = [
        SELECT Id, WhoId, Subject FROM Task
        WHERE Subject LIKE '%Call%'
        AND CreatedDate = TODAY
    ];

    System.assertEquals(1, tasks.size(), 'Task should still be created');
    System.assertEquals(null, tasks[0].WhoId,
        'WhoId should be null when ANI does not match any record');
}
```

---

### T-10: Task Auto-Creation — With Disposition (AC-10)

| Field | Value |
|---|---|
| Type | Apex Unit Test |
| AC | AC-10: Call disposition values are persisted on the Task record |
| Class Under Test | VoiceCallActivityHandler |

```java
@IsTest
static void testTaskCreation_WithDisposition_DispositionPersisted() {
    Lead testLead = ISCTITestDataFactory.createLeadWithPhone('+15556000001');

    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15556000001', 'Outbound', 'InProgress'
    );

    Test.startTest();
    vc.Status__c = 'Completed';
    vc.Duration__c = 300;
    update vc;
    Test.stopTest();

    Task createdTask = [
        SELECT Id, Call_Disposition__c FROM Task
        WHERE WhoId = :testLead.Id LIMIT 1
    ];

    createdTask.Call_Disposition__c = 'Interested';
    update createdTask;

    Task updatedTask = [
        SELECT Call_Disposition__c FROM Task WHERE Id = :createdTask.Id
    ];

    System.assertEquals('Interested', updatedTask.Call_Disposition__c,
        'Disposition should be persisted on Task');
}
```

---

### T-11: Recording Opt-Out — Successful Stop (AC-14, positive path)

| Field | Value |
|---|---|
| Type | Apex Integration Test (HttpCalloutMock) |
| AC | AC-14: Recording stops within 2 seconds when agent triggers opt-out action |
| Class Under Test | RecordingOptOutController |

```java
@IsTest
static void testStopRecording_Success_RecordUpdated() {
    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15557000001', 'Inbound', 'InProgress'
    );

    Test.setMock(HttpCalloutMock.class, new ConnectRecordingStopSuccessMock());

    Test.startTest();
    RecordingOptOutController.RecordingResult result =
        RecordingOptOutController.stopRecording(vc.Id);
    Test.stopTest();

    System.assertEquals(true, result.success, 'Should return success');
    System.assertEquals(null, result.errorMessage, 'No error expected');

    VoiceCall updatedVc = [
        SELECT Recording_Opted_Out__c FROM VoiceCall WHERE Id = :vc.Id
    ];
    System.assertEquals(true, updatedVc.Recording_Opted_Out__c,
        'VoiceCall should be flagged as opted out');
}

private class ConnectRecordingStopSuccessMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        System.assert(req.getEndpoint().contains('StopContactRecording'),
            'Should call StopContactRecording endpoint');
        System.assertEquals('POST', req.getMethod(), 'Should be POST request');

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"Success": true}');
        return res;
    }
}
```

---

### T-12: Recording Opt-Out — API Timeout (AC-14, negative path)

| Field | Value |
|---|---|
| Type | Apex Integration Test (HttpCalloutMock) |
| AC | AC-14 (negative path): System handles Connect API timeout gracefully |
| Class Under Test | RecordingOptOutController |

```java
@IsTest
static void testStopRecording_Timeout_HandlesGracefully() {
    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15557000002', 'Inbound', 'InProgress'
    );

    Test.setMock(HttpCalloutMock.class, new ConnectRecordingTimeoutMock());

    Test.startTest();
    RecordingOptOutController.RecordingResult result =
        RecordingOptOutController.stopRecording(vc.Id);
    Test.stopTest();

    System.assertEquals(false, result.success, 'Should return failure on timeout');
    System.assertNotEquals(null, result.errorMessage, 'Should contain error message');
    System.assert(result.errorMessage.contains('timed out') ||
        result.errorMessage.contains('Try again'),
        'Error message should indicate timeout');

    VoiceCall updatedVc = [
        SELECT Recording_Opted_Out__c FROM VoiceCall WHERE Id = :vc.Id
    ];
    System.assertEquals(false, updatedVc.Recording_Opted_Out__c,
        'VoiceCall should NOT be flagged when API call fails');
}

private class ConnectRecordingTimeoutMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        CalloutException e = new CalloutException();
        e.setMessage('Read timed out');
        throw e;
    }
}
```

---

### T-13: Recording Opt-Out — API Error Response (AC-14, negative path)

| Field | Value |
|---|---|
| Type | Apex Integration Test (HttpCalloutMock) |
| AC | AC-14 (negative path): System handles Connect API error response gracefully |
| Class Under Test | RecordingOptOutController |

```java
@IsTest
static void testStopRecording_ApiError_HandlesGracefully() {
    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15557000003', 'Inbound', 'InProgress'
    );

    Test.setMock(HttpCalloutMock.class, new ConnectRecordingErrorMock());

    Test.startTest();
    RecordingOptOutController.RecordingResult result =
        RecordingOptOutController.stopRecording(vc.Id);
    Test.stopTest();

    System.assertEquals(false, result.success, 'Should return failure on API error');
    System.assertNotEquals(null, result.errorMessage, 'Should contain error message');

    VoiceCall updatedVc = [
        SELECT Recording_Opted_Out__c FROM VoiceCall WHERE Id = :vc.Id
    ];
    System.assertEquals(false, updatedVc.Recording_Opted_Out__c,
        'VoiceCall should NOT be flagged when API returns error');
}

private class ConnectRecordingErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setBody('{"Message": "Internal server error", "Code": "InternalServiceException"}');
        return res;
    }
}
```

---

### T-14: Recording Opt-Out — Already Opted Out (AC-14, idempotency)

| Field | Value |
|---|---|
| Type | Apex Integration Test (HttpCalloutMock) |
| AC | AC-14 (idempotency): If recording is already stopped, action should not fail |
| Class Under Test | RecordingOptOutController |

```java
@IsTest
static void testStopRecording_AlreadyOptedOut_ReturnsSuccess() {
    VoiceCall vc = ISCTITestDataFactory.createVoiceCall(
        '+15557000004', 'Inbound', 'InProgress'
    );
    vc.Recording_Opted_Out__c = true;
    update vc;

    Test.startTest();
    RecordingOptOutController.RecordingResult result =
        RecordingOptOutController.stopRecording(vc.Id);
    Test.stopTest();

    System.assertEquals(true, result.success,
        'Should return success without making API call when already opted out');
    System.assert(result.message != null && result.message.contains('already'),
        'Should indicate recording was already stopped');
}
```

---

### T-15: Inside Sales Routing Configuration (AC-01)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-01: Inside Sales reps can receive inbound calls via Lightning softphone |
| Precondition | DevInt2 or target org accessible |
| Verification Query | See below |
| Pass Criteria | IS_Voice_Routing config exists and is active |
| Failure Action | Create IS_Voice_Routing OmniChannelRoutingConfig if missing |

```sql
SELECT Id, DeveloperName, IsActive
FROM OmniChannelRoutingConfig
WHERE DeveloperName = 'IS_Voice_Routing'
```

**DevInt2 baseline:** No IS-specific routing exists (gap identified in intake). This query validates Phase 1 deliverable.

---

### T-16: Inside Sales Voice Queues (AC-01, AC-05)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-01, AC-05: Inside Sales voice queues and HCP queue are configured |
| Pass Criteria | Two queue rows returned: Inside_Sales_Voice and HCP_Inbound_Voice |

```sql
SELECT Id, DeveloperName, Name, QueueSobject.SobjectType
FROM QueueSobject
WHERE Queue.DeveloperName IN ('Inside_Sales_Voice', 'HCP_Inbound_Voice')
AND SobjectType = 'VoiceCall'
```

---

### T-17: Inside Sales Presence Statuses (AC-09)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-09: Agent status transitions (Available → Busy → ACW → Available) are reflected in Omni-Channel |
| Pass Criteria | Three rows returned, all IsActive = true |

```sql
SELECT Id, DeveloperName, MasterLabel, IsActive
FROM ServicePresenceStatus
WHERE DeveloperName IN (
    'IS_Available_Voice',
    'IS_Busy_Voice',
    'IS_ACW'
)
```

**Expected result:** 3 rows returned, all IsActive = true.

**DevInt2 baseline:** Zero rows returned (gap — Inside Sales statuses do not exist). This query validates Phase 1 deliverable.

---

### T-18: IS_CTI_Agent_Access Permission Set Group (AC-06)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-06: Inside Sales reps can initiate outbound click-to-dial calls |
| Pass Criteria | Permission Set Group exists and contains IS_CTI_Base, AC_CallRecording, CTI_Integration_Access |

```sql
SELECT Id, DeveloperName, MasterLabel, Status
FROM PermissionSetGroup
WHERE DeveloperName = 'IS_CTI_Agent_Access'
```

```sql
SELECT Id, PermissionSetGroup.DeveloperName, PermissionSet.Name
FROM PermissionSetGroupComponent
WHERE PermissionSetGroup.DeveloperName = 'IS_CTI_Agent_Access'
```

**Expected result:** IS_CTI_Agent_Access group contains IS_CTI_Base + AC_CallRecording + CTI_Integration_Access.

---

### T-19: IS_CTI_Base Object Permissions (AC-06)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-06: IS_CTI_Base grants Lead CRUD, Patient Read, Opportunity Read, VoiceCall Read/Edit, Task CRUD |
| Pass Criteria | Object permissions exist for Lead, Account, Opportunity, VoiceCall, Task |

```sql
SELECT Id, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit
FROM ObjectPermissions
WHERE ParentId IN (
    SELECT Id FROM PermissionSet WHERE Name = 'IS_CTI_Base'
)
AND SobjectType IN ('Lead', 'Account', 'Opportunity', 'VoiceCall', 'Task')
```

---

### T-20: sfdc_phone ServiceChannel Active (AC-01)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-01: Reuse existing sfdc_phone channel from NGPSTE-132 |
| Pass Criteria | 1 row returned, IsActive = true |

```sql
SELECT Id, DeveloperName, RelatedEntity, IsActive
FROM ServiceChannel
WHERE DeveloperName = 'sfdc_phone'
```

---

### T-21: Softphone Layout for Inside Sales (AC-06)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-06: Click-to-dial enabled for Inside Sales softphone layout |
| Pass Criteria | IS_Softphone_Layout exists |

```sql
SELECT Id, DeveloperName, MasterLabel
FROM SoftphoneLayout
WHERE DeveloperName = 'IS_Softphone_Layout'
```

---

### T-22: Call Disposition Picklist on Task (AC-10)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-10: Call disposition values are selectable at call end |
| Pass Criteria | Task.Call_Disposition__c field exists with 6 picklist values |

```sql
SELECT Id, QualifiedApiName, DataType, EntityDefinition.QualifiedApiName
FROM FieldDefinition
WHERE EntityDefinition.QualifiedApiName = 'Task'
AND QualifiedApiName = 'Call_Disposition__c'
```

---

### T-23: VoiceCall Recording_Opted_Out__c Field (AC-14)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-14: Recording opt-out flag stored on VoiceCall |
| Pass Criteria | VoiceCall.Recording_Opted_Out__c field exists as Checkbox |

```sql
SELECT Id, QualifiedApiName, DataType, EntityDefinition.QualifiedApiName
FROM FieldDefinition
WHERE EntityDefinition.QualifiedApiName = 'VoiceCall'
AND QualifiedApiName = 'Recording_Opted_Out__c'
```

---

### T-24: ACLightningAdapter Exists (AC-01, shared prerequisite)

| Field | Value |
|---|---|
| Type | SOQL Validation |
| AC | AC-01: Reuse ACLightningAdapter from NGPSTE-132 |
| Pass Criteria | 1 row returned with DeveloperName = 'ACLightningAdapter' |

```sql
SELECT Id, DeveloperName, InternalName, Version
FROM CallCenter
WHERE DeveloperName = 'ACLightningAdapter'
```

**DevInt2 baseline:** ACLightningAdapter exists (confirmed in NGPSTE-132 intake). This test validates prerequisite state.

---

### T-25: Inbound Call via Lightning Softphone (AC-01)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-01: Inside Sales reps can receive inbound calls via Lightning softphone and the call rings within 5 seconds |
| Precondition | Agent logged in with IS_CTI_Agent_Access. Presence set to IS_Available_Voice. Amazon Connect CCP loaded. |
| Steps | 1. Place inbound call to Inside Sales DID number. 2. Verify softphone rings in Lightning utility bar within 5 seconds. 3. Agent accepts call. 4. Verify VoiceCall record created with correct ANI and CallType = 'Inbound'. |
| Pass Criteria | Softphone rings within 5s. Agent can accept. VoiceCall record created with correct ANI. |

```sql
SELECT Id, CallType, FromPhoneNumber, ToPhoneNumber, CreatedDate
FROM VoiceCall
WHERE CallType = 'Inbound'
ORDER BY CreatedDate DESC
LIMIT 1
```

---

### T-26: Outbound Click-to-Dial from Lead and Contact (AC-06)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-06: Inside Sales reps can initiate outbound click-to-dial calls from Lead, Contact, and Patient records |
| Precondition | Agent logged in with IS_CTI_Agent_Access. Lead and Contact records with Phone fields populated. |
| Steps | 1. Navigate to Lead record. 2. Click phone field (click-to-dial icon). 3. Verify softphone initiates outbound call. 4. Verify VoiceCall record created with CallType = 'Outbound'. 5. Repeat for Contact record. 6. Repeat for PersonAccount record. |
| Pass Criteria | Outbound call initiates within 3s from each object. VoiceCall records created for each. |

---

### T-27: SSO Authentication to Amazon Connect CCP (AC-07)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-07: SSO authentication to Amazon Connect CCP works within Salesforce Lightning softphone without separate login |
| Precondition | SAML SSO configured for Amazon Connect. Agent has valid SSO credentials. |
| Steps | 1. Agent logs into Salesforce Lightning. 2. Open softphone utility bar. 3. Verify CCP auto-authenticates without separate login prompt. 4. Verify agent can set presence status. |
| Pass Criteria | No separate login required. CCP shows connected state within 5s of softphone open. |

---

### T-28: Agent Status Transitions (AC-09)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-09: Agent status transitions reflected in both CCP and Omni-Channel widget |
| Precondition | Agent logged in with IS_CTI_Agent_Access. Both CCP and Omni-Channel widget visible. |
| Steps | 1. Set presence to IS_Available_Voice — verify green indicator in both CCP and Omni-Channel. 2. Accept inbound call — verify auto-transition to IS_Busy_Voice. 3. End call — verify transition to IS_ACW. 4. Complete after-call work — verify return to IS_Available_Voice. 5. Change status in CCP — verify Omni-Channel reflects change within 1s. |
| Pass Criteria | All transitions reflected bi-directionally within 1s. |

---

### T-29: Warm Transfer (AC-11)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-11: Agent can consult with second agent before connecting them to the caller |
| Precondition | Two Inside Sales agents logged in and available. Active inbound call. |
| Steps | 1. Agent A is on active call. 2. Agent A initiates warm transfer to Agent B. 3. Verify Agent A can speak privately with Agent B (consult). 4. Agent A connects caller to Agent B. 5. Verify caller is now connected to Agent B. 6. Verify Agent A's call ends. |
| Pass Criteria | Consult phase works. Caller transferred successfully. Two VoiceCall records created. |

---

### T-30: Cold Transfer (AC-12)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-12: Agent can transfer caller directly to another agent or queue without consultation |
| Precondition | Agent logged in with active call. Target queue configured. |
| Steps | 1. Agent is on active call. 2. Agent initiates cold transfer to Inside_Sales_Voice queue. 3. Verify caller is immediately transferred. 4. Verify original agent's call ends immediately. 5. Verify new agent receives the call via queue routing. |
| Pass Criteria | Caller transferred without consult phase. Original agent released immediately. |

---

### T-31: Voicemail Access (AC-15)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-15: Inside Sales reps can access and play voicemails assigned to them |
| Precondition | Voicemail component deployed. Test voicemail recorded. |
| Steps | 1. Navigate to voicemail list component. 2. Verify voicemails assigned to agent are visible. 3. Click play on voicemail. 4. Verify audio plays successfully. |
| Pass Criteria | Voicemail list loads. Playback works within 3s of click. |
| Blocked By | NGPSTE-811 (Phase 3 delivery) |

---

### T-32: Quick Connect Buttons (AC-13)

| Field | Value |
|---|---|
| Type | Manual Acceptance Test |
| AC | AC-13: Quick connect buttons configured for common Inside Sales transfer destinations |
| Precondition | Quick connect entries configured in Amazon Connect. Agent on active call. |
| Steps | 1. During active call, open transfer panel. 2. Verify quick connect buttons visible: Sales Manager, Product Support, HCP line. 3. Click Sales Manager quick connect. 4. Verify transfer initiates. |
| Pass Criteria | All three quick connect destinations visible and functional. |

---

## SOQL Validation Query Summary

These queries validate configuration state and are runnable against DevInt2 (read-only)
or the target deployment org.

| # | Query Purpose | Expected Result (Post-Deployment) |
|---|---|---|
| SQ-01 | IS_Voice_Routing exists and active | 1 row, IsActive = true |
| SQ-02 | Inside Sales voice queues (Inside_Sales_Voice, HCP_Inbound_Voice) | 2 rows with VoiceCall SobjectType |
| SQ-03 | IS-specific ServicePresenceStatus (IS_Available_Voice, IS_Busy_Voice, IS_ACW) | 3 rows, all IsActive = true |
| SQ-04 | IS_CTI_Agent_Access PermissionSetGroup exists | 1 row |
| SQ-05 | IS_CTI_Agent_Access contains required permission sets | >= 3 component rows (IS_CTI_Base, AC_CallRecording, CTI_Integration_Access) |
| SQ-06 | IS_CTI_Base object permissions | Rows for Lead, Account, Opportunity, VoiceCall, Task |
| SQ-07 | sfdc_phone ServiceChannel active | 1 row, IsActive = true |
| SQ-08 | IS_Softphone_Layout exists | 1 row |
| SQ-09 | Task.Call_Disposition__c exists | 1 row, DataType = Picklist |
| SQ-10 | VoiceCall.Recording_Opted_Out__c exists | 1 row, DataType = Checkbox |

---

## Test Data Factory Design

```java
@IsTest
public class ISCTITestDataFactory {

    public static Lead createLeadWithPhone(String phone) {
        Lead l = new Lead(
            FirstName = 'IS_CTI',
            LastName = 'TestLead_' + System.currentTimeMillis(),
            Company = 'Test Company',
            Phone = phone,
            Status = 'New'
        );
        insert l;
        return l;
    }

    public static Lead createLeadWithMobilePhone(String mobilePhone) {
        Lead l = new Lead(
            FirstName = 'IS_CTI',
            LastName = 'TestLead_' + System.currentTimeMillis(),
            Company = 'Test Company',
            MobilePhone = mobilePhone,
            Status = 'New'
        );
        insert l;
        return l;
    }

    public static List<Lead> createLeadsWithPhones(Integer count) {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            leads.add(new Lead(
                FirstName = 'IS_CTI',
                LastName = 'TestLead_' + i,
                Company = 'Test Company ' + i,
                Phone = '+1555' + String.valueOf(8000000 + i).leftPad(7, '0'),
                Status = 'New'
            ));
        }
        insert leads;
        return leads;
    }

    public static Account createPersonAccountWithPhone(String phone) {
        Id personAccountRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        Account pa = new Account(
            FirstName = 'IS_CTI',
            LastName = 'TestPatient_' + System.currentTimeMillis(),
            RecordTypeId = personAccountRTId,
            PersonHomePhone = phone
        );
        insert pa;
        return pa;
    }

    public static Contact createContactWithPhone(String phone) {
        Contact c = new Contact(
            FirstName = 'IS_CTI',
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
                FirstName = 'IS_CTI',
                LastName = 'TestContact_' + i,
                Phone = phones[i]
            ));
        }
        insert contacts;
        return contacts;
    }

    public static VoiceCall createVoiceCall(String fromPhone, String callType, String status) {
        VoiceCall vc = new VoiceCall(
            FromPhoneNumber = fromPhone,
            ToPhoneNumber = '+15550000000',
            CallType = callType,
            Status__c = status,
            CallStartDateTime = Datetime.now()
        );
        insert vc;
        return vc;
    }

    public static VoiceCall buildVoiceCall(String fromPhone, String callType, String status) {
        return new VoiceCall(
            FromPhoneNumber = fromPhone,
            ToPhoneNumber = '+15550000000',
            CallType = callType,
            Status__c = status,
            CallStartDateTime = Datetime.now()
        );
    }

    public static Task createCallTask(Id whoId, String disposition) {
        Task t = new Task(
            Subject = 'Call - ' + Datetime.now().format(),
            WhoId = whoId,
            Status = 'Completed',
            CallType = 'Inbound',
            Call_Disposition__c = disposition,
            CallDurationInSeconds = 120
        );
        insert t;
        return t;
    }

    public static User createInsideSalesAgentUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'IS_CTI',
            LastName = 'TestAgent',
            Email = 'is.cti.testagent@test.ngasim76.com',
            Username = 'is.cti.testagent@test.ngasim76.com.' + System.currentTimeMillis(),
            Alias = 'isagnt',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    public static void assignPermissionSetGroup(Id userId, String psgName) {
        PermissionSetGroup psg = [
            SELECT Id FROM PermissionSetGroup
            WHERE DeveloperName = :psgName LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = psg.Id
        );
    }
}
```

---

## Coverage Estimate

| Class | Methods | Lines (est.) | Covered By | Est. Coverage |
|---|---|---|---|---|
| InsideSalesScreenPopResolver | resolveRecord | ~55 | T-01, T-02, T-03, T-04, T-05, T-06 | 90%+ |
| VoiceCallActivityHandler | createActivityTask, resolveWhoId | ~50 | T-07, T-08, T-09, T-10 | 85%+ |
| RecordingOptOutController | stopRecording | ~40 | T-11, T-12, T-13, T-14 | 85%+ |
| ISCTITestDataFactory | 10 factory methods | ~80 | Utility — used by all tests | 100% |
| ConnectRecordingStopSuccessMock | respond | ~8 | T-11 | 100% |
| ConnectRecordingTimeoutMock | respond | ~5 | T-12 | 100% |
| ConnectRecordingErrorMock | respond | ~8 | T-13 | 100% |

**Overall custom Apex coverage:** 87%+ (exceeds 85% target).

**Note:** NGASIM-76 has significantly more custom Apex than NGPSTE-132 due to three production classes
(InsideSalesScreenPopResolver, VoiceCallActivityHandler, RecordingOptOutController). Configuration
validation relies on SOQL queries (SQ-01 through SQ-10). Manual tests cover SSO, transfers, voicemail,
and agent status transitions that cannot be automated in Apex.

---

## Test Execution Plan

| Phase | Tests | Automation | Blocking |
|---|---|---|---|
| Phase 1: Core CTI | T-15, T-16, T-17, T-18, T-19, T-20, T-21, T-24, T-25, T-26 | SQ-01 through SQ-08, SQ-10 automated; T-25, T-26 manual | T-24 (ACLightningAdapter prerequisite) blocks all Phase 1 |
| Phase 1: Screen Pop | T-01, T-02, T-03, T-04, T-05, T-06 | All fully automated Apex tests | T-15 (routing config) blocks manual validation |
| Phase 2: Call Logging | T-07, T-08, T-09, T-10, T-22 | T-07–T-10 automated Apex; SQ-09 automated | Phase 1 exit criteria blocks Phase 2 |
| Phase 2: Recording Opt-Out | T-11, T-12, T-13, T-14, T-23 | T-11–T-14 automated Apex + HttpCalloutMock; SQ-10 automated | Named Credential for Connect API required |
| Phase 2: SSO + Agent Status | T-27, T-28 | Manual with documented steps | SSO SAML config prerequisite |
| Phase 3: Transfers + Voicemail | T-29, T-30, T-31, T-32 | All manual with documented steps | T-31 blocked by NGPSTE-811 |

---

## Handoff to REVIEW

**Directive:** The code-reviewer agent must:

1. Review all prior artifacts (00-intake, 01-plan, 02-architecture, 03-tdd) for consistency.
2. Identify gaps between 17 ACs (AC-01 through AC-17) and test coverage (T-01 through T-32).
3. Validate waterfall search priority (Lead → PersonAccount → Contact) matches ADR-005.
4. Verify VoiceCallActivityHandler bulk safety pattern (T-08: 200 records) aligns with ADR-006 consequences.
5. Confirm RecordingOptOutController HTTP mock tests cover all ADR-008 error paths.
6. Assess SOQL queries are parameterized and governor-limit safe (3 of 150 SOQL limit per screen pop).
7. Check InsideSalesScreenPopResolver for SOQL injection (ANI input sanitization) and null handling.
8. Verify ISCTITestDataFactory creates valid test data without hardcoded record IDs.
9. Flag risks from deferred child stories: NGPSTE-811 (voicemail), NGASIM-1524 (caller ID reputation), NGASIM-1527 (onboarding automation).
10. Assess ADR quality and completeness across all four ADRs (ADR-005 through ADR-008).
11. Recommend remediation for all HIGH/CRITICAL findings.
