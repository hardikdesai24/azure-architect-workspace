# Application Development, prd — User-Connection Paths

**Prepared:** 2026-09-03 15:10 UTC
**Prepared by:** Claude Code session, workspace `D:\codes\Azure`
**Class:** 0 — read-only discovery. Nothing was created, modified, or deleted.
**Companion canvas:** `2026-09-03-161000-mercyhealth-appdev-prd-user-connection-canvas.html`

---

## 1. Scope

The three **prd** subscriptions under **Landing Zones → Application Development**:

| Subscription | Workload | Resources examined |
|---|---|---|
| `dt-prd-app-oeqrq2jxadm36` | Connect Application | 106 |
| `dt-prd-tpa-oeqrq2jxadm36` | TPA Application | 39 |
| `dt-prd-microsites-oeqrq2jxadm36` | Microsites | 3 |

148 resources total, via Azure Resource Graph across all three. Traced from public domain name to
data store: Front Door → WAF → (APIM \| Static Web App) → App Service → data tier, for each
subscription independently.

## 2. dt-prd-app — Connect Application

**Entry.** Two custom domains on one Front Door Premium profile (`afd-dts-global`):

| Domain | AFD endpoint | Route | Origin group | Origin |
|---|---|---|---|---|
| `connect.mercyhealthcare.org` | `prod-connect-mercyhealthcare` | `/*` | `portal-prod-frontend` | Static Web App `swa-portal-prod-ncus` |
| `api.connect.mercyhealthcare.org` | `portal-backend-prod` | `/*` | `portal-prod-backend` | API Management `apim-dts-gateway-prod-ncus-1` |

WAF `WAFGlobalAzureManagedWithGeoRestrictionsAndRateLimiting` (Premium tier) is associated to both
endpoints but its policy mode is **Detection**, not Prevention — it logs, it does not block.

**API Management → App Services.** APIM has 11 APIs (10 real + the `echo-api` sample). Each real
API path-routes by name to one dedicated App Service:

| API path | App Service | Key Vault |
|---|---|---|
| `portal` | `app-portal-prod-ncus` | `kv-portal-prod-ncus` |
| `audit-log` | `app-audit-log-prod-ncus` | `kv-audit-log-prod-ncus` |
| `hand-hygiene` | `app-hand-hygiene-prod-ncus` | `kv-hand-hygien-prod-ncus` |
| `hhs` | `app-HHS-prod-ncus` | `kv-HHS-prod-ncus` |
| `labor-pool` | `app-labor-pool-prod-ncus` | `kv-labor-pool-prod-ncus` |
| `legacy-docs` | `app-legacy-docs-prod-ncus` | `kv-legacy-docs-prod-ncus` |
| `medicaid` | `app-medicaid-prod-ncus` | `kv-medicaid-prod-ncus` |
| `notification-service` | `app-notification-service-prod-ncus` | `kv-notificatio-prod-ncus` |
| `quality-review` | `app-ora-prod-ncus` | `kv-ora-prod-ncus` |
| `pmm-invoices` | `app-PMM-prod-ncus` | `kv-PMM-prod-ncus` |

All 10 App Services: Linux, B1 Basic, VNet-integrated. All 10 restrict inbound traffic to APIM's
outbound IP (`172.214.234.155/32`) with an explicit deny-all fallback — confirmed via
`config/web` IP security restrictions on every one. Each also carries its own inbound private
endpoint (`sites` subresource) as a separate, VNet-only access path. Each reaches its own Key
Vault over a private endpoint (`vault` subresource).

**Shared platform tier.** Reached asynchronously, not on the live request path:

- `evhns-dts-shared-prod-ncus` (Event Hub Namespace, Standard, private endpoint). Confirmed
  publishers via RBAC: identities named for `audit-log` and `notification-service` hold roles on
  it.
- `func-dlq-processor-internal-prod-ncus` (Function App, Linux, Flex Consumption). Public network
  access **disabled**. Its sole assigned identity, `uai-dlq-processor-prod`, holds a role on the
  Event Hub — confirming it consumes from there. The **same identity holds no role on the shared
  Storage account** — so this review found no confirmed evidence the function writes there,
  despite the naming suggesting it should. Storage's actual confirmed callers are
  `uai-blob-shared-prod` and `uai-evh-audit-logs-dlq-prod`; the latter name suggests `audit-log`
  may handle its own dead-lettering independently of the shared function.
- `blobdtssharedprodncus` (Storage Account, StorageV2/LRS, private endpoint).
- `pg-dts-shared-prod-ncus` (PostgreSQL Flexible Server). Public access disabled, VNet-delegated
  subnet — correctly isolated. No managed identity in the subscription holds an RBAC role on it;
  its consumer is **Unknown**, most likely wired via a connection string in one of the ten Key
  Vaults, which this review did not open.

Outside the request path entirely: `kv-frontdoor-prod-ncus` and `log-dts-shared-1-prod-ncus`
(platform/observability), plus a stray test-tier App Service Plan, `asp-asp-hhs-test-ncus-test-ncus`,
sitting in this prod subscription (its doubled name also suggests a templating error at creation).

## 3. dt-prd-tpa — TPA Application

**Entry.** One custom domain, one Front Door Standard profile (`az-fd-prod`), one endpoint
(`az-ep-prod`), WAF `wafprod` (Standard tier) correctly in **Prevention** mode:

| Route | Pattern | Origin group | Origin |
|---|---|---|---|
| `az-route-prod` | `/*` | `az-og-prod` | `app-tpa-prod-frontend-ncus` |
| `route-api-prod` | `/api/*` | `og-backend-prod` | `app-tpa-prod-backend-ncus` |

Domain `planalytics.mercycarehealthplans.com` confirmed directly on the custom domain resource.
Both App Services share one App Service Plan, `asp-tpa-prod-ncus` (P1v3).

**Finding — Front Door is optional, not mandatory.** Both App Services carry two IP security
restriction rules:

```
Allow-FrontDoor   priority=100         action=Allow  tag=AzureFrontDoor.Backend/ServiceTag
Allow all         priority=2147483647  action=Allow  ipAddress=Any
```

The second rule means `app-tpa-prod-backend-ncus.azurewebsites.net` and
`app-tpa-prod-frontend-ncus.azurewebsites.net` are reachable directly from the internet, with no
WAF inspection — confirmed by reading `config/web` on both apps directly (not inferred).

**Backend data tier**, all via private endpoint in `vnet-spoke-tpa-prd` (`172.25.96.0/20`):

| Resource | Type | Private endpoint |
|---|---|---|
| `sql-prod-fwubq55usdsyk` → database `db-config` | SQL Server / Database (Standard) | `pe-sql-prod` |
| `kv-tpa-prod-ncus` | Key Vault | `pe-kv-prod` |
| `appcs-prod-3dv5vnwo5uxsi` | App Configuration (Standard) | `pe-appconfig-prod` |
| `sttpaprodfwubq55usdsyk` | Storage Account (StorageV2, RAGRS) | `pe-storage-prod` (blob) |

**Two resources outside every path found:**

- `appcs-prod-fwubq55usdsyk` — a second App Configuration store, public access disabled, but no
  private endpoint targets it. Unreachable by any network path this review found.
- `stfwubq55usdsyk` — a second Storage Account, no private endpoint, default network ACL is
  `Allow`. Not confirmed wired to either app.

## 4. dt-prd-microsites — no user-connection path exists

Confirmed two independent ways: Azure Resource Graph and a direct `az resource list` both return
exactly the same three resources — `vnet-spoke-microsites-prd` (`172.25.160.0/20`, peered to the
hub, unused), `NetworkWatcher_northcentralus`, and the `ExportToWorkspace` Defender automation. No
compute, no Front Door, no data store.

This is not a visibility gap: the account used holds Reader at the tenant root management group
(confirmed via role assignment lookup), so it can see everything in this subscription.

## 5. Findings

| # | Finding | Label | Severity |
|---|---|---|---|
| 1 | Both TPA App Services accept direct internet traffic on `*.azurewebsites.net`, bypassing Front Door and WAF, due to an `Allow all` network rule | Confirmed | High |
| 2 | The Premium Front Door's WAF (`WAFGlobalAzureManagedWithGeoRestrictionsAndRateLimiting`) is in Detection mode — not blocking anything, in front of ten line-of-business apps | Confirmed | High |
| 3 | Two TPA storage/config resources (`appcs-prod-fwubq55usdsyk`, `stfwubq55usdsyk`) sit outside every confirmed traffic path | Confirmed | Low |
| 4 | Connect Application's ten backend apps are correctly isolated — APIM-only ingress with deny-all fallback, the opposite of finding 1 | Confirmed | — (positive) |
| 5 | A test-tier App Service Plan (`asp-asp-hhs-test-ncus-test-ncus`) lives in the `dt-prd-app` production subscription | Confirmed | Low |
| 6 | Neither the shared Postgres server's consumer, nor the DLQ function's write path to shared Storage, could be confirmed via RBAC | Unknown | Medium |

None of these is authorized for remediation.

## 6. Not covered

APIM policy XML (rate limiting, transformation, auth validation), WAF custom rule contents, App
Service application settings and connection strings, SQL/Postgres firewall rules beyond network
isolation, DNS resolution paths, and cost. No app setting, connection string, or secret value was
read at any point — shared-service wiring was established entirely through RBAC role assignments
on named managed identities and private-endpoint target resolution.

## 7. Reproduce

```powershell
# Front Door topology (repeat per profile/resource group)
$b = "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Cdn/profiles/<profile>"
az rest --method get --url "$b/afdEndpoints?api-version=2024-02-01"
az rest --method get --url "$b/originGroups?api-version=2024-02-01"
az rest --method get --url "$b/afdEndpoints/<endpoint>/routes?api-version=2024-02-01"
az rest --method get --url "$b/securityPolicies?api-version=2024-02-01"

# APIM API-to-backend mapping
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<apim>/apis?api-version=2022-08-01"

# App Service network posture
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<app>/config/web?api-version=2023-12-01"

# Private endpoint target resolution — Resource Graph
# query: privateendpoints | mv-expand privateLinkServiceConnections | project groupIds, privateLinkServiceId

# RBAC role assignments (bypasses az role assignment list's Graph dependency, which hit
# AADSTS53003 Conditional Access in this session)
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/<resourceType>/<name>/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
```

All read-only.
