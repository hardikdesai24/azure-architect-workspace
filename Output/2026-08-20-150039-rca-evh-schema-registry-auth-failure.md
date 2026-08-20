# RCA: Event Hub Schema Registry authorization failures (DEV)

| Field | Value |
|---|---|
| **Document** | Root Cause Analysis |
| **Incident window** | 2026-08-18 ~13:38 UTC → ongoing (observed through 2026-08-20) |
| **Environment** | `dt-dev-app-oeqrq2jxadm36` / `rg-spoke-appdev-dev-g3kmeu7yyl24w` |
| **Primary resource** | Event Hubs namespace `evhns-dts-shared-dev-ncus`, schema group `dts-apps-sg` |
| **Primary app** | `app-portal-dev-ncus` |
| **Observation time** | 2026-08-20 (UTC) |
| **Classification** | Confirmed for proximate cause; Conditional for why config/code path changed on restart |

---

## 1. Executive summary

Access appeared broken for “Event Hub connect” and “schema read” managed identities. Investigation shows **Event Hub data-plane connectivity and RBAC were healthy**. The failure is **Schema Registry authorization**: the portal app’s schema-read path used the **Event Hub user-assigned identity** (`uai-evh-audit-logs-dev`), which has **Event Hubs Data Sender/Receiver only** and **does not** have Schema Registry Reader/Contributor.

Failures started immediately after an **`app-portal-dev-ncus` restart/redeploy on 2026-08-18 ~12:50–13:38 UTC**.

---

## 2. Impact

| Area | Observation |
|---|---|
| Symptom | Apps fail to emit audit/events that require Avro schema fetch from Schema Registry |
| Error | `Authorization failed for specified action: SchemaGroupRead,SchemaRead` |
| Scope | Schema group `dts-apps-sg` / schema `auditschema` on `evhns-dts-shared-dev-ncus` |
| Metric | Event Hub **UserErrors** rose from **0** (Aug 13–17) to **6 / 32 / 11** (Aug 18 / 19 / 20 partial) — **all on entity `dts-apps-sg`** |
| App evidence | `app-portal-dev-ncus` console logs: `Schema fetch failed` / `Failed to emit event to Event Hub` |
| Residual | Some successful schema fetches still occur when the schema UAI is used; failures dominate after Aug 18 |

---

## 3. Timeline (UTC)

| Time | Event | Evidence label |
|---|---|---|
| Through 2026-08-17 | Portal schema operations succeeding | Confirmed (AppServiceConsoleLogs success counts; UserErrors = 0) |
| 2026-08-18 ~12:50 | `app-portal-dev-ncus` container start / `setup.sh`; env vars set including `EVENT_HUB_*`, `SCHEMA_REGISTRY_*`, `AUDIT_LOG_SCHEMA_REGISTRY_MANAGED_IDENTITY` | Confirmed |
| 2026-08-18 ~13:38 | First hard failure: `SchemaGroupRead,SchemaRead` with `managedIdentityClientId: cb06ef9a-...` | Confirmed |
| 2026-08-18 13:00–14:00 | Event Hub UserErrors begin (2 then 4 in hour buckets) on `dts-apps-sg` | Confirmed |
| 2026-08-19–20 | Repeated schema auth failures on portal; intermittent success when schema UAI used | Confirmed |
| Investigation 2026-08-20 | RBAC/network/identity state reviewed; no recent role removals found | Confirmed |

---

## 4. Identities and intended roles

| Managed identity | Client ID | Intended use | Roles present on EH namespace / hubs |
|---|---|---|---|
| `uai-evh-audit-logs-dev` | `cb06ef9a-ba6e-46e1-8bac-d0839079aba5` | Event Hub send/receive | Azure Event Hubs Data Sender + Receiver on audit/notification hubs |
| `uai-evhns-schema-contributor-dev` | `4b4f56a8-5bec-41a7-ac4f-ba05876e384d` | Schema Registry read/write | Schema Registry Contributor on namespace |
| `uai-evh-notifications-dev` | `54a7a4db-c419-4d37-970b-15cb70ba89b7` | Event Hub notifications | Data Sender + Receiver on notification hub |
| `uai-evhns-schema-contributor-labor-pool-dev` | `29881d49-126f-4e3d-bee3-61f086359168` | Schema (labor pool) | Schema Registry Contributor on namespace |

**Confirmed:** Entra service principals for these UAIs are enabled. No deny assignments on the namespace/RG.

---

## 5. What was ruled out

| Hypothesis | Result | Evidence |
|---|---|---|
| Event Hub network / private endpoint block | Ruled out | VNet connection logs: `Accept Connection` / `Private link ID is accepted` continuously |
| Event Hub Sender/Receiver roles removed | Ruled out | Role assignments present; no recent roleAssignment delete activity found |
| Schema Registry Contributor missing on schema UAI | Ruled out | Role still assigned to `uai-evhns-schema-contributor-dev` and labor-pool schema UAI |
| Managed identity deleted / disabled | Ruled out | UAIs exist; SPs `accountEnabled: true` |
| Broad Event Hub outage | Ruled out | Incoming requests ~stable; messages still flowing; UserErrors confined to schema group entity |

---

## 6. Root cause

### Proximate cause (Confirmed)

**Wrong managed identity used for Schema Registry data-plane operations.**

1. Portal Event Hub emit path requires reading schema `auditschema` from group `dts-apps-sg`.
2. Failing calls authenticate as **`uai-evh-audit-logs-dev`** (`cb06ef9a-ba6e-46e1-8bac-d0839079aba5`).
3. That identity is authorized for **Event Hubs data** only, **not** for `SchemaGroupRead` / `SchemaRead`.
4. Event Hubs returns authorization failure; the app surfaces this as Event Hub emit failure and Schema Registry fetch failure.
5. Metric **UserErrors** on entity **`dts-apps-sg`** is the platform side of the same failure.

### Trigger (Confirmed timing; Conditional mechanism)

**Trigger time is confirmed:** failures begin right after `app-portal-dev-ncus` restart/redeploy on **2026-08-18 ~12:50 UTC**, with first auth error at **~13:38 UTC**.

**Why the wrong identity was selected after restart is Conditional / not fully proven**, because App Settings values could not be read (`Microsoft.Web/sites/config/list` denied for the investigating identity). Leading explanations consistent with evidence:

1. **Config/wiring issue (most likely):** After restart, `setup.sh` loads multiple related settings (`EVENT_HUB_MANAGED_IDENTITY_CLIENT_ID`, `EVENT_HUB_AZURE_UAI_CLIENT_ID`, `SCHEMA_REGISTRY_UAI_CLIENT_ID`, `AUDIT_LOG_SCHEMA_REGISTRY_MANAGED_IDENTITY`). The Schema Registry / Avro client path used the Event Hub client ID instead of the schema UAI client ID.
2. **Code path / credential reuse:** Producer dependency cache (`createEventHubProducerDependencies` / `getCachedDependencies` in stack traces) constructed a Schema Registry client with the Event Hub credential.
3. **Less likely:** RBAC change on Aug 18 — no activity-log evidence of Schema Registry role removal.

Intermittent later successes when logs show schema UAI `4b4f56a8-...` support explanation (1)/(2): the schema role works when the correct identity is used; the broken path uses the Event Hub identity.

### Causal statement

> A portal application restart on 2026-08-18 caused Schema Registry reads to authenticate with the Event Hub managed identity. That identity lacks Schema Registry data-plane permissions, producing `SchemaGroupRead,SchemaRead` failures and Event Hub UserErrors on schema group `dts-apps-sg`. This was not an Event Hub connectivity or Event Hub data-role outage.

---

## 7. Contributing factors

1. **Split-identity design:** Separate UAIs for Event Hub vs Schema Registry increase mis-wiring risk if env vars or SDK clients are swapped.
2. **Symptom ambiguity:** Schema auth failures appear as “Event Hub access broken,” delaying correct diagnosis.
3. **Limited RuntimeAuditLogs signal:** Event Hub diagnostic categories show network accepts and operational retrieve calls; schema auth failures were clearest in **App Service console logs** + **UserErrors** on `dts-apps-sg`.
4. **Secondary hygiene (related pattern, not primary RCA):** `app-labor-pool-dev-ncus` still references deleted `uai-evh-*-test` identities; other apps log `No User Assigned ... Managed Identity found for specified ClientId` — same class of client-ID/attachment mismatch elsewhere.

---

## 8. Corrective actions

### Immediate (restore service)

| Option | Action | Risk |
|---|---|---|
| A. RBAC (fast) | Assign **Schema Registry Reader** (minimum) or Contributor on `evhns-dts-shared-dev-ncus` to `uai-evh-audit-logs-dev` (and notification UAI if same pattern) | Broadens permissions on Event Hub identity; masks config bug |
| B. Config/code (correct) | Ensure Schema Registry client uses only `uai-evhns-schema-contributor-dev` (`4b4f56a8-...`); verify `SCHEMA_REGISTRY_UAI_CLIENT_ID` / `AUDIT_LOG_SCHEMA_REGISTRY_MANAGED_IDENTITY` values after `setup.sh` | Preferred long-term |

### Detection / prevention

1. Alert on Event Hub **UserErrors** where `EntityName == dts-apps-sg` (or schema group names).
2. Alert on App Service console pattern `SchemaGroupRead,SchemaRead`.
3. Startup validation: attempt schema get-by-version with the configured schema UAI; fail fast if unauthorized.
4. Document required pairing: Event Hub UAI → Data Sender/Receiver; Schema UAI → Schema Registry Reader/Contributor; never interchange.
5. Remove dangling deleted UAI attachments (e.g. labor-pool `*-test` identities).

### Validation after fix

1. Portal log: `Schema fetched successfully` without `SchemaGroupRead` errors.
2. UserErrors on `dts-apps-sg` return to ~0.
3. End-to-end audit event emit succeeds.

---

## 9. Evidence sources

- Azure Resource Graph / `az identity` / `az role assignment list` on subscription `eedbfd35-f6c7-4ac2-9730-4d0c4be52821`
- Event Hub metrics: `UserErrors` (dimension `EntityName=dts-apps-sg`), `IncomingMessages`, `IncomingRequests`
- Log Analytics workspace `mercyhealth-log-analytics` (`9d40b718-3269-493c-8539-3d0d79a57e81`):
  - `AppServiceConsoleLogs` for `app-portal-dev-ncus`
  - `AzureDiagnostics` Event Hub VNet connection events
- Activity Log (7–30d): no Schema Registry role removals observed; portal restart correlated via app logs

---

## 10. Unknowns / follow-ups

| Item | Status |
|---|---|
| Exact App Setting values at failure time | Unknown (no `config/list` permission) |
| Whether Key Vault secret feeding `setup.sh` changed on Aug 18 | Unknown — needs secret *metadata*/pipeline change review (not secret values) |
| Whether same mis-wiring exists in TEST/PROD | Partial — similar ClientId-not-found errors seen on other apps; needs scoped check |
| Owner of portal deploy that restarted Aug 18 ~12:50 UTC | Unknown from available activity samples |

---

## 11. Verdict

| Layer | Finding |
|---|---|
| **What broke** | Schema Registry authorization (`SchemaGroupRead`, `SchemaRead`) |
| **Who was denied** | Event Hub UAI `uai-evh-audit-logs-dev` (`cb06ef9a-...`) |
| **Who should have been used** | Schema UAI `uai-evhns-schema-contributor-dev` (`4b4f56a8-...`) |
| **When** | Starting 2026-08-18 ~13:38 UTC after portal restart |
| **Why it looked like Event Hub access failure** | Schema fetch is on the Event Hub emit path; errors bubble as emit failures and UserErrors on the schema-group entity |

**RCA category:** Configuration / identity wiring defect exposed (or introduced) at application restart — **not** a platform Event Hub outage and **not** loss of the Schema Registry Contributor assignment on the schema UAI.
