# Application Development, prd — Service Principal / Managed Identity Mapping

**Prepared:** 2026-09-03 17:15 UTC · **Revised:** 2026-09-04, using a tenant-wide Enterprise
Applications export (`exportServicePrincipals_2026-9-4.csv`, 226 rows) supplied by the user
**Prepared by:** Claude Code session, workspace `D:\codes\Azure`
**Class:** 0 — read-only discovery. Nothing was created, modified, or deleted.
**Companion canvas:** `2026-09-04-spn-identity-mapping-canvas.html`

---

## 1. Bottom line — revised

The original version of this document concluded "every application authenticates exclusively via
managed identity — no classic App Registration was found." **That conclusion was wrong**, not
because the ARM evidence was misread, but because ARM cannot see Entra ID app registrations at
all — and Microsoft Graph was blocked all session. The user-supplied Enterprise Applications export
closes that gap and reveals a second, parallel identity layer this review had completely missed:
one **Microsoft Fabric app registration per line-of-business app** (`spn-fabric-<app>-<env>`),
used for data-pipeline access, sitting alongside the managed identities already mapped.

Three corrections and one new high-severity finding come out of this pass:

1. **Corrected:** the Postgres role I previously reported as `spn-fabric-connect-prd` accessing the
   database is actually **`Defender Open Source Relational Databases`** — a Microsoft Defender for
   Cloud threat-protection role, not a data-read role. Postgres's actual data-plane consumer is
   still unconfirmed.
2. **New, confirmed:** `spn-fabric-tpa-prd` holds `Key Vault Secrets User` on `kv-tpa-prod-ncus` —
   this is almost certainly how the Fabric pipeline retrieves the SQL connection string to extract
   TPA data for analytics.
3. **New, high severity:** one identity — object ID `fcfaf24d-f685-4b6e-9827-1c75ebda655e`, not
   present in the Enterprise Applications export, so most likely a managed identity outside this
   review's two subscriptions — holds **Key Vault Secrets Officer** (read **and** write) on **every
   one of the ten Key Vaults** in `dt-prd-app`, plus the platform `kv-frontdoor-prod-ncus`. One
   identity can rewrite secrets across the entire application tier.
4. **Confirmed, out of scope for "applications":** several identities hold `Owner` or `User Access
   Administrator` at management-group or tenant-root scope. These are platform/tenant admin
   concerns, not application SPNs — listed in §5 for completeness, not investigated further.

## 2. What the export is, and what it still doesn't cover

The CSV is a tenant-wide **Enterprise Applications** export — 226 custom app registrations and
SaaS integrations, columns `id` (Object ID), `displayName`, `appId` (Client ID), plus lifecycle
metadata. Checked directly: it contains **zero** managed identities (system- or user-assigned) —
none of the 19 managed identity Object IDs from the original version of this document appear in it.
This is normal; Enterprise Applications exports typically list app registrations, not managed
identities, which are a distinct Entra ID object type.

So the two sources are complementary, not overlapping:

| Source | Covers | Used for |
|---|---|---|
| ARM (`az identity show`, resource `identity` blocks, `roleAssignments`) | Managed identities — system- and user-assigned | §3 of the original document — App Service ↔ Key Vault ↔ shared platform services |
| User-supplied Enterprise Apps export | Classic app registrations (client ID/secret or cert-based) | §3 below — the Fabric data-pipeline layer, Kinde CIAM, notification/labor-pool apps |

Neither source, even combined, proves there are no *other* app registrations relevant to these
apps that use neither pattern — that would need reading application code or configuration, which
this review does not do.

## 3. The Fabric / classic-app-registration layer — resolved from the export

Searching the export for names matching every app, workload, and environment in the two
subscriptions surfaced a consistent naming convention: **`spn-fabric-<workload>-<env>`**, almost
certainly the credentials Microsoft Fabric (or an equivalent data-pipeline product) uses to pull
each app's data into the Data & Analytics environment.

| App registration | Object ID | Client ID (`appId`) | Created | Matches |
|---|---|---|---|---|
| `spn-fabric-connect-prd` | `6742bf8e-a6ee-4fc3-b696-adb4992b53c6` | `068d9e16-4cf3-4673-ac30-bdc9bd4e5b6a` | 03/05/2026 | Connect Application, prd |
| `spn-fabric-connect-tst` | `3506b02b-4e1e-4903-8b24-3dbaa93b44f1` | `0d73432e-3406-48b4-b021-523e2d8c8090` | 03/05/2026 | Connect Application, tst |
| `spn-fabric-connect-dev` | `3f3cd550-f164-493d-b4e8-3dbc30b9ce6b` | `dbacb90d-cef3-4743-83b5-6f8cc2c2871f` | 03/05/2026 | Connect Application, dev |
| `spn-fabric-connect-postgres` | `4724e11b-4fa3-4ef9-bba8-17a787de2825` | `de12a7c2-3794-4488-827f-083fead2cab1` | 07/31/2026 | Connect Application — Postgres-specific; **no RBAC role found anywhere in `dt-prd-app`** despite existing |
| `spn-fabric-medicaid-screening` | `095f893e-80b2-4111-9767-ba2199fd835e` | `8114bc3a-12c3-4cd4-a587-76f1722fd905` | 07/28/2026 | `app-medicaid-prod-ncus` |
| `spn-fabric-legacy-docs` | `ec191117-9284-448c-9659-996514746033` | `3c17e33a-1445-43f3-a24c-2689ce7d8c41` | 08/07/2026 | `app-legacy-docs-prod-ncus` |
| `spn-fabric-pmm-invoices` | `4aac3cca-1b8b-42d9-967a-d6f780c2a1de` | `5c27bcf9-eada-41f7-8871-b860593393f0` | 05/12/2026 | `app-PMM-prod-ncus` |
| `spn-fabric-peer-reviews` | `2944d51c-e1c1-42f9-9081-b25aeb2eb51a` | `3dd1b396-3229-457e-b82a-8dbac9d08880` | 06/05/2026 | `app-ora-prod-ncus` (APIM path `quality-review`) — name match is **Inferred**, not confirmed by RBAC |
| `spn-sharepoint-hhs-connect` | `a59f482f-d97f-4603-8f20-d21fe63d21d7` | `89a3aea8-c973-4d2a-8cc5-6b52767e0df0` | 04/07/2026 | `app-HHS-prod-ncus` — SharePoint integration, not Fabric |
| `dts-vitea-prod` | `028e1825-cec8-42be-b9af-c0ccebaa4418` | `ecf3113d-10c5-4ed6-8fda-8f83bae45473` | 07/13/2026 | `dt-prd-vitea` (AI Governance, sibling subscription) |
| `Notifications App Prod` | `226ffcac-221f-4a06-a7aa-335aff5d0561` | `bbea0a12-4640-4d14-a8a0-64ce576a469b` | 07/23/2025 | `app-notification-service-prod-ncus` — resolves the gap flagged in the original document |
| `Notifications App Test` / `MercyHealth - Notifications App Development` | `7a1d8014-...` / `0d819608-...` | — | 07/22/2025 / 04/18/2025 | tst / dev counterparts |
| `MercyHealth - LaborPool` | `30dbeb5e-6f91-4524-96e9-3fd82b19420a` | `23badcb5-c3ce-40c8-b5a0-0a081314794f` | 11/14/2025 | `app-labor-pool-prod-ncus` |
| `spn-fabric-tpa-prd` | `147cd523-7f08-40ed-ad1e-35bfbe9850b0` | `1d3753ab-30f8-4fb3-acba-26230f665f7a` | 11/13/2025 | TPA Application, prd — **RBAC-confirmed**, see §4 |
| `spn-fabric-tpa` (no env suffix) | `980dd30e-7aff-4aac-90fd-79425e0ff1dd` | `38115f72-38eb-41cb-acf6-f8921dfca55f` | 05/12/2025 | TPA Application — purpose vs. the env-suffixed one unclear |
| `spn-fabric-tpa-tst` / `spn-fabric-tpa-dev` | `f09f3a8e-...` / `ac5c0855-...` | — | 11/13/2025 / 10/02/2025 | tst / dev counterparts |
| `tpa-kinde-production` | `a4aba313-3223-4e1b-862f-79967df5e3af` | `ec1c41a6-6d92-4eef-871a-cc731ef208e1` | 12/02/2025 | TPA Application — a **third**, separate identity provider (Kinde, a CIAM platform), alongside the Fabric SPN |

**No Fabric or dedicated app registration was found** for `app-portal-prod-ncus`, `app-audit-log-prod-ncus`,
`app-hand-hygiene-prod-ncus`, or `app-HHS-prod-ncus` beyond the SharePoint one — those four rely on
managed identity alone, as the original document described.

**Microsites, confirmed again:** searching the export for `microsites` found `microsites-cms-dev`
and `microsites-cms-test` only — **no prod entry exists**. This is independent corroboration of the
finding that `dt-prd-microsites` holds no deployed application: the identity that would authenticate
a production Microsites app was never created.

## 4. What's actually confirmed by RBAC — the corrected picture

Re-scanning every role assignment in both subscriptions (104 total) against this expanded name map:

| Identity | Role | Scope | Note |
|---|---|---|---|
| `spn-fabric-connect-prd` | Defender Open Source Relational Databases | `pg-dts-shared-prod-ncus` | **Correction from the original document** — this is a Defender for Cloud threat-protection role, not data access. Postgres's actual consumer remains unconfirmed. |
| `spn-fabric-tpa-prd` | Key Vault Secrets User | `kv-tpa-prod-ncus` | New finding — likely how the Fabric pipeline retrieves TPA's SQL credentials |
| `spn-fabric-connect-postgres` | *(none found)* | — | The Postgres-specific-named registration exists but holds no role anywhere checked in `dt-prd-app` |

## 5. High-severity finding — one identity can write secrets to every Key Vault in `dt-prd-app`

Object ID `fcfaf24d-f685-4b6e-9827-1c75ebda655e` holds **Key Vault Secrets Officer** — read *and*
write — on all eleven Key Vaults checked in the subscription:

```
kv-portal-prod-ncus · kv-audit-log-prod-ncus · kv-hand-hygien-prod-ncus · kv-HHS-prod-ncus
kv-labor-pool-prod-ncus · kv-legacy-docs-prod-ncus · kv-medicaid-prod-ncus
kv-notificatio-prod-ncus · kv-ora-prod-ncus · kv-PMM-prod-ncus · kv-frontdoor-prod-ncus
```

It does not appear in the Enterprise Applications export, and a tenant-wide Resource Graph search
across all 22 subscriptions found no User-Assigned Identity with this Object ID either — so it is
most likely a **System-Assigned identity on a resource this review did not enumerate** (a deployment
pipeline agent, a Key Vault-adjacent automation resource, or similar), somewhere outside the scope
of "applications in these three subscriptions." Its name and home resource are **Unknown**.

The pattern itself — one identity, write access, every secret store in the app tier — is exactly
the shape of a CI/CD deployment identity (e.g., a Bicep/Terraform pipeline that provisions secrets
at deploy time) and is unremarkable *if that's what it is*. But an unidentified identity with write
access to every production secret store is worth a name and an owner regardless of how benign it
turns out to be. Resolving it needs either Graph access (blocked this session) or checking Azure
DevOps/GitHub service connection configurations directly.

## 6. Platform and tenant-level role assignments — noted, not investigated

Both subscriptions carry role assignments inherited from management-group or tenant-root scope,
held by identities absent from the Enterprise Applications export (consistent with these being
either Microsoft first-party Defender for Cloud service identities, or Entra ID **groups**, which
an Enterprise Apps export would not include either way):

| Object ID | Role(s) | Scope | Likely nature |
|---|---|---|---|
| `634a3ed0-3eca-4813-b7ab-71a896c1eaad` | Defender Agentless VM Scan | both subscriptions | Microsoft Defender for Cloud built-in |
| `c3e76620-30eb-4a52-bf01-524050bdbe36` | Defender Kubernetes API Access, Defender Containers Sensor, Managed Identity Federated Identity Credential Contributor | `dt-prd-tpa` | Microsoft Defender for Cloud built-in |
| `8d26b589-f9ed-41d9-87b0-4dbf8dfd5b60` | Owner | tenant root `/` | **Root-scope Owner across the entire tenant** — identity unresolved |
| `89c40aa4-79c2-4e80-a7ce-af286cc8e869` | Owner (both subscriptions), User Access Administrator (tenant root MG) | broad | Identity unresolved |
| `755efd8a-2447-4432-8b3f-3016851f8a06` | Contributor + User Access Administrator | `dt-prd-tpa` subscription | Identity unresolved |
| Several others (`f668c979…`, `0f680433…`, `5c260d1a…`, `f7b03e7e…`, `da25145e…`, `5b1d2735…`, `1f33b781…`, `3011e75e…`, `ac0817ed…`, `c55dd373…`, `a0922cc4…`, `2c4f494c…`, `8a4c23e1…`, `2060f160…`, `e6f31e20…`) | Owner / User Access Administrator / Contributor / Reader / various | `mercyhealth`, `mercyhealth-landingzones`, `mercyhealth-landingzones-appdev-connect`, `mercyhealth-landingzones-appdev-tpa` management groups | Identity unresolved |

These are governance-scope, not application-scope, findings — flagged here for completeness because
they surfaced in the same RBAC scan, not because this review investigated them further.

On `kv-tpa-prod-ncus` specifically, four more unresolved identities hold Key Vault roles alongside
`id-prod` and `spn-fabric-tpa-prd`: `51b54302-6697-42de-a771-dc20a40225f3` (Key Vault Administrator,
Secrets Officer, Secrets User, Certificates Officer, **and** User Access Administrator — the single
most privileged identity found on any Key Vault in this review) plus three identities holding only
Key Vault Secrets User (`1e6690d2…`, `f5a3cfac…`, `12bf294b…`). None appear in the Enterprise
Applications export; they may be human users (which the export would not contain) or additional
managed identities outside this review's two subscriptions.

## 7. Reproduce

```powershell
# Cross-reference every role assignment principal against a name map built from:
#   (a) az identity show / resource identity blocks (managed identities)
#   (b) an Enterprise Applications export (Get-MgServicePrincipal, or Entra ID admin center ->
#       Enterprise Applications -> Export)
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
az rest --method get --url "https://management.azure.com/subscriptions/<sub>/providers/Microsoft.Authorization/roleDefinitions/<guid>?api-version=2022-04-01"

# Search for a managed identity by Object ID tenant-wide (Resource Graph)
# query: microsoft.managedidentity/userassignedidentities | where properties.principalId == '<oid>'
```

All read-only.
