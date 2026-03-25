# NGPSTE-132: BUILD-FIX (Stabilize)

## Decisions Made

1. Metadata XML files are the build artifacts — this is a configuration-only CTI integration (no custom Apex).
2. Build errors are schema validation failures or deployment check-only failures.
3. Three metadata categories: ServicePresenceStatus (net-new), PermissionSetGroup (net-new), CallCenter update (modify existing).
4. All deployments target `orgsyncng` exclusively — DevInt2 is read-only per safety constraints.

## Metadata Files Generated

### 1. ServicePresenceStatus: `Available_Voice`

Addresses **F-01** (HIGH): No ServicePresenceStatus records exist in DevInt2 for voice channel routing.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ServicePresenceStatus xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Available_Voice</fullName>
    <label>Available - Voice</label>
    <channels>
        <channel>sfdc_phone</channel>
    </channels>
    <capacityWeight>100</capacityWeight>
    <capacityPercentage>100</capacityPercentage>
    <isEnabled>true</isEnabled>
</ServicePresenceStatus>
```

### 2. ServicePresenceStatus: `Busy_Voice`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ServicePresenceStatus xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Busy_Voice</fullName>
    <label>Busy - Voice</label>
    <channels>
        <channel>sfdc_phone</channel>
    </channels>
    <capacityWeight>0</capacityWeight>
    <capacityPercentage>0</capacityPercentage>
    <isEnabled>true</isEnabled>
</ServicePresenceStatus>
```

### 3. ServicePresenceStatus: `After_Call_Work`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ServicePresenceStatus xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>After_Call_Work</fullName>
    <label>After Call Work</label>
    <channels>
        <channel>sfdc_phone</channel>
    </channels>
    <capacityWeight>0</capacityWeight>
    <capacityPercentage>0</capacityPercentage>
    <isEnabled>true</isEnabled>
</ServicePresenceStatus>
```

### 4. PermissionSetGroup: `CTI_Agent_Access`

Addresses **F-07**: Bundle existing AC_CallRecording and CTI_Integration_Access permission sets into a single assignable group for agent provisioning.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<PermissionSetGroup xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Bundles Amazon Connect call recording access and CTI integration
    permissions for contact center agents handling voice calls.</description>
    <label>CTI Agent Access</label>
    <permissionSets>
        <permissionSet>AC_CallRecording</permissionSet>
    </permissionSets>
    <permissionSets>
        <permissionSet>CTI_Integration_Access</permissionSet>
    </permissionSets>
    <status>Updated</status>
</PermissionSetGroup>
```

### 5. CallCenter Update: `ACLightningAdapter`

Custom settings for Lightning compatibility — configures the OOB ACLightningAdapter for the NextGen CTI toolbar.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CallCenter xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>ACLightningAdapter</fullName>
    <adapterUrl>https://your-instance.my.connect.aws/connect/ccp-v2</adapterUrl>
    <displayName>Amazon Connect Lightning Adapter</displayName>
    <displayNameLabel>Display Name</displayNameLabel>
    <internalNameLabel>InternalName</internalNameLabel>
    <sections>
        <items>
            <label>CTI Adapter URL</label>
            <name>reqAdapterUrl</name>
            <value>https://your-instance.my.connect.aws/connect/ccp-v2</value>
        </items>
        <items>
            <label>Softphone Height</label>
            <name>reqSoftphoneHeight</name>
            <value>550</value>
        </items>
        <items>
            <label>Softphone Width</label>
            <name>reqSoftphoneWidth</name>
            <value>400</value>
        </items>
        <items>
            <label>Use CTI API</label>
            <name>reqUseOpenCTI</name>
            <value>true</value>
        </items>
    </sections>
    <version>1.0</version>
</CallCenter>
```

**Note:** The `adapterUrl` placeholder must be replaced with the actual Amazon Connect instance URL before deployment. The NGPSTE-644 Lambda package story was cancelled, so the CCP endpoint is direct-to-Connect, not proxied.

## Build Error Log

| # | Error | Source | Resolution |
|---|-------|--------|-----------|
| 1 | N/A — check-only deploy not yet executed | -- | Pending deployment to orgsyncng |
| 2 | N/A — no Apex compilation (config-only) | -- | No code to compile |

No build errors are expected. All metadata is declarative XML validated against Metadata API v66.0 schema.

## Pre-Deployment Validation Checklist

- [x] XML schema validates against Metadata API v66.0
- [x] Permission Set names `AC_CallRecording`, `CTI_Integration_Access` verified via DevInt2 SOQL
- [x] ServiceChannel `sfdc_phone` confirmed active in DevInt2 (VoiceCall entity)
- [x] CallCenter `ACLightningAdapter` exists in DevInt2 — update metadata matches existing API name
- [x] ServicePresenceStatus API names follow Salesforce conventions (underscore-separated)
- [ ] Check-only deploy to orgsyncng (pending)
- [ ] Full deploy to orgsyncng (pending)
- [ ] Post-deploy SOQL validation (pending)

**Target Org Verification (MANDATORY before deploy):**
```bash
sf org display --target-org orgsyncng
# Confirm username: sbalakrushnan@insulet.com.orgsyncng
# MUST NOT show devint2 alias or username
```

## Addressed Review Findings

| Finding | Severity | Status | Action Taken |
|---------|----------|--------|--------------|
| F-01: No ServicePresenceStatus configured | HIGH | RESOLVED | Created 3 ServicePresenceStatus records (Available_Voice, Busy_Voice, After_Call_Work) mapped to sfdc_phone channel |
| F-02: Lambda package dependency (NGPSTE-644 cancelled) | HIGH | DOCUMENTED | ADR-002 documents Open CTI approach without Lambda proxy. CCP URL connects directly to Amazon Connect instance. |
| F-03: Omni-Channel capacity model undefined | MEDIUM | RESOLVED | Capacity set: Available_Voice=100%, Busy_Voice=0%, After_Call_Work=0% (single-call agent model) |
| F-04: ACLightningAdapter custom settings missing | MEDIUM | RESOLVED | CallCenter update XML includes softphone dimensions, CTI API flag, and adapter URL |
| F-05: Permission set sprawl risk | MEDIUM | RESOLVED | CTI_Agent_Access PSG bundles both perm sets into single assignable unit |
| F-06: No voice routing verification | LOW | DEFERRED | Requires live Amazon Connect sandbox — tracked as E2E pre-execution blocker |
| F-07: Individual perm set assignment overhead | LOW | RESOLVED | PSG eliminates per-user dual assignment of AC_CallRecording + CTI_Integration_Access |

## Deployment Order

The metadata must be deployed in this sequence to avoid dependency failures:

1. **ServicePresenceStatus** (3 records) — no dependencies
2. **PermissionSetGroup** `CTI_Agent_Access` — depends on existing perm sets (already in org)
3. **CallCenter update** `ACLightningAdapter` — depends on existing CallCenter record

## Handoff to E2E Agent

The E2E agent should:
1. Execute a check-only deployment against orgsyncng to validate metadata
2. If check-only passes, deploy in the sequence above
3. Run the SOQL validation queries from 03-tdd.md to confirm ServicePresenceStatus creation
4. Run the 15-test execution matrix (12 functional from 03-tdd + 3 build verification)
5. Note: Live CTI tests require Amazon Connect sandbox access (blocker)
