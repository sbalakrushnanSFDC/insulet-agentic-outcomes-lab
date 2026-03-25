# NGASIM-556: TDD (Test-Driven Development)

## Decisions Made

1. **No Apex tests -- this is a configuration-only story.** All deliverables are declarative metadata (Permission Set Group, Compact Layouts, App Navigation). Apex test coverage is N/A.
2. **Test strategy is functional/manual test scripts** validated against the dev sandbox post-deployment.
3. **Permission-based tests use SOQL validation** -- we can verify permission assignments and object access programmatically via SOQL.

## Test Specifications (RED phase)

### TS-01: Mobile App Authentication (AC-1)
**Precondition:** Field Sales user with `Field_Sales_Mobile_PSG` assigned
**Steps:**
1. Install Salesforce Mobile App on iPad
2. Enter org credentials for the Field Sales user
3. Tap Login

**Expected:** User authenticates successfully and sees the mobile home screen.
**Fail criteria:** Login error, "insufficient privileges" message, or Connected App block.

### TS-02: Default Landing Page (AC-2)
**Precondition:** TS-01 passed
**Steps:**
1. Observe the app that loads after login

**Expected:** User lands on `SalesCloudMobile` home page with navigation bar showing: Home, Accounts, Leads, Opportunities, Tasks, Events.
**Fail criteria:** Wrong app loads, missing navigation items, or empty home page.

### TS-03: Account Access (AC-3)
**Steps:**
1. Tap "Accounts" in navigation
2. Verify list view loads with records
3. Tap an Account record
4. Verify record detail page loads with compact layout fields

**Expected:** Account list view shows records. Record detail shows Name, Phone, BillingCity, Owner, Type in compact header.
**Fail criteria:** "Insufficient Privileges" error, empty list, or wrong compact layout fields.

### TS-04: Lead Access (AC-4)
**Steps:**
1. Tap "Leads" in navigation
2. Verify list view loads
3. Tap a Lead record
4. Verify compact layout: Name, Company, Phone, Status, LeadSource

**Expected:** Lead records accessible, compact layout correct.

### TS-05: Opportunity Access (AC-5)
**Steps:**
1. Tap "Opportunities" in navigation
2. Verify list view loads
3. Tap an Opportunity record
4. Verify compact layout: Name, StageName, CloseDate, Amount, Account.Name

**Expected:** Opportunity records accessible, compact layout correct.

### TS-06: Task Management (AC-6)
**Steps:**
1. Tap "Tasks" in navigation
2. Tap "+" to create new Task
3. Fill in Subject, Priority, Status, Due Date
4. Save
5. Verify task appears in list
6. Edit the task, change Status to Completed
7. Save

**Expected:** Task creates, edits, and completes successfully.
**Fail criteria:** Create/edit/save errors, or task not visible after save.

### TS-07: Event Management (AC-7)
**Steps:**
1. Tap "Events" in navigation (or Calendar view)
2. Tap "+" to create new Event
3. Fill in Subject, Start Date/Time, End Date/Time, Location
4. Save
5. Verify event appears in calendar and list
6. Edit the event, change time
7. Save

**Expected:** Event creates and edits successfully. Calendar view accessible.

### TS-08: Log a Call (AC-8)
**Steps:**
1. Navigate to an Account record
2. Tap "Log a Call" quick action
3. Fill in Subject, Comments/Description
4. Save
5. Navigate to Account's Activity timeline
6. Verify the call log appears

**Expected:** "Log a Call" quick action available on mobile, creates Activity record with CallType.
**Fail criteria:** Quick action missing, save error, or activity not associated.

### TS-09: FLS Enforcement (AC-9)
**Steps:**
1. As Field Sales user on mobile, navigate to Account, Lead, Opportunity
2. Verify that only fields permitted by `Field_Sales_Core_Access` + `Field_Sales_Edit` are visible/editable
3. Verify sensitive fields (if any Health Cloud fields are on layout) are NOT visible

**Expected:** FLS properly enforced. No unauthorized field visibility.

### TS-10: Compact Layout Verification (AC-10)
**Steps:**
1. On each object (Account, Lead, Opportunity), open a record on mobile
2. Verify the compact header shows exactly the 5 fields specified in Architecture doc

**Expected:** Compact layouts match specification.

### TS-NEG-01: Negative -- User Without Mobile Permission
**Steps:**
1. Attempt to log into Salesforce Mobile App with a user who does NOT have `SalesCloudMobileUser`

**Expected:** User is blocked from mobile access or sees limited/no functionality.

### TS-NEG-02: Negative -- Non-Field-Sales User on Mobile
**Steps:**
1. Log in as non-Field-Sales user (e.g., Service user) on mobile
2. Attempt to access Accounts, Leads, Opportunities

**Expected:** Access respects that user's permission set, not Field Sales permissions.

## SOQL Validation Queries (automated checks)

```sql
-- Verify PSG exists
SELECT Id, DeveloperName FROM PermissionSetGroup
WHERE DeveloperName = 'Field_Sales_Mobile_PSG'

-- Verify PSG contains correct permission sets
SELECT Id, PermissionSetGroupId, PermissionSetId, PermissionSet.Name
FROM PermissionSetGroupComponent
WHERE PermissionSetGroup.DeveloperName = 'Field_Sales_Mobile_PSG'

-- Verify a Field Sales user has the PSG assigned
SELECT Id, Assignee.Name, PermissionSetGroup.DeveloperName
FROM PermissionSetAssignment
WHERE PermissionSetGroup.DeveloperName = 'Field_Sales_Mobile_PSG'
LIMIT 5
```

## Coverage Estimate

| Type | Coverage | Notes |
|------|----------|-------|
| Apex Unit Test | N/A | No custom Apex in scope |
| Functional/Manual | 12 test cases | 10 positive + 2 negative |
| SOQL Validation | 3 queries | Automated permission checks |

## Implementation Walkthrough (GREEN phase)

Since this is configuration-only, the "implementation" is:
1. Create `Field_Sales_Mobile_PSG` Permission Set Group via metadata XML
2. Create 3 compact layouts via metadata XML
3. Update `SalesCloudMobile` app navigation items
4. Verify Quick Actions on mobile layouts
5. Deploy to dev sandbox (`orgsyncng`)
6. Run TS-01 through TS-10 manually

## Handoff to REVIEW Agent

The REVIEW agent should:
1. Review the metadata XML for correctness before deployment
2. Verify compact layout field selections align with FLS
3. Check that no Health Cloud-sensitive objects leak into mobile navigation
4. Validate the test plan completeness against the 10 ACs
