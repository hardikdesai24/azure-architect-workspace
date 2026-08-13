# 2026-08-13 — Unused private DNS zones, first sweep review

- **Workspace:** `e:\Repos\Azure`
- **Date:** 2026-08-13
- **Tenant:** Mercyhealth `7d689bf5-26f6-44a2-b080-61689eff65a6`

## User request

Study `Output/2026-08-13-095458-unused-private-dns-zones.json` against `docs/change-plans/2026-08-11-private-dns-zone-cleanup-plan.md`.

## Outcome

First discovery run completed Phases A–C of the plan. **EligibleForDeletion = 0.** No Azure resources were changed.

### Confirmed from the JSON (2026-08-13 04:24:58 UTC)

- Tenant matches the plan.
- 22 subscriptions swept; Stage 2 was performed; 54 ARG candidates; 0 eligible.
- All 54 rows failed Stage 2 (control-plane verification failed or access denied) and Stage 3 (creation time unavailable).
- 53 zones in subscription `818a8b62-…` / `rg-dns-v3nysoeym4kga`, ARG 0 links and 1 record set.
- 1 zone `privatelink.postgres.database.azure.com` in subscription `a0852105-…` / `vitea-mercyhealth-prod-ncus-data-rg`, ARG 0 links and 2 record sets.

### Confirmed from Azure MCP `subscription_list` (same session)

- This identity sees 22 Enabled subscriptions — same count as `SubscriptionsSwept`.
- `818a8b62-…` = `dt-prd-connectivity-oeqrq2jxadm36`
- `a0852105-…` = `dt-prd-vitea-oeqrq2jxadm36`
- Plan’s older connectivity hub id `d93fefb0-…` is not in the current Enabled list.

### Inferences

- Connectivity RG `rg-dns-v3nysoeym4kga` looks like an ALZ/policy private DNS pack. §11 DINE residual risk applies even if a later run marks those zones eligible.
- Vitea postgres zone looks like a spoke duplicate or disconnected PE zone; treat as production.
- ARG `recordSets = 1` on 53 zones supports an SOA-only baseline, but §6a still needs a control-plane calibration.

### Not done

- Plan §6a baseline still blank.
- Phase D soak, Phase E backup, Phase F deletion — not started and not authorized.
- External systems unchanged.

## Follow-up — script fix (same day)

The “access denied” result was not RBAC. Two bugs in `Get-UnusedPrivateDnsZones.ps1`:

1. PowerShell unrolled `[]` from `link vnet list` to `$null`, so every 0-link zone failed Stage 2.
2. `az.cmd` split Stage 3 ARM URLs on `&`, so `$expand`/`$filter` never ran.

Fix applied in `Invoke-AzJson` (`ConvertFrom-AzCliJson` + `Protect-AzCmdUrlArguments`). Live checks: empty link list stays an empty array; record-set list returns SOA; quoted createdTime call returned 70 zones, all with `createdTime`.

First-run JSON/CSV is still the pre-fix report. Re-run the script to produce a decision-grade list. No Azure mutation. No commit of the script fix yet.

## Follow-up — second sweep validation (2026-08-13 07:30:02 UTC)

File: `Output/2026-08-13-130002-unused-private-dns-zones.json`

Matches plan §1 three gates. 53 eligible (connectivity hub, SOA-only, 393 days). 1 excluded (Vitea postgres A+SOA). Stage 2/3 completed; ARG vs verified mismatches=0.

Not ready to delete: Phase D soak, §11 checks, backups, authorization still open. No dt-dev eligible zones, so Wave 1 as written cannot start. §6a baseline observed as SOA-only. No Azure mutation.

## Follow-up — §11 policy dependency check (2026-08-13, live read-only)

User context going in: the team was already aware these zones may come from ALZ, that a pipeline may create them, and that new service onboarding may require manual zone creation. That was institutional recollection, not verified evidence — so it was checked.

### Scope and provenance confirmed

- `818a8b62-…` = `dt-prd-connectivity-oeqrq2jxadm36` — **production** connectivity subscription.
- RG `rg-dns-v3nysoeym4kga` tags: `BusinessCriticality: High`, `Environment: All`, `Workload: All`, `OwnerName: Jeremy Colson`. Zone tags add `DataClassification: Highly Confidential`, `CostCenter: 119008035`.
- Zone census: **70 total — 17 linked, 53 unlinked.** The 53 are the unonboarded remainder of the standard ALZ catalog, not orphans.
- RG deployment history active through **2026-08-05**: AVM modules (`46d3xbcp.res.nw-privdnszonevnetlink.0-1-0.*`) plus `privateDnsLinks-dev` / `privateDnsLinks-test` / `link-kv-prod-*` / `acr-dns-link-shared`. Links are still being added as workloads onboard.

### Two false starts worth recording

1. `az account management-group list` returned `AuthorizationFailed` on `Microsoft.Management/register/action` over the **active subscription** (`dt-dev-app-…`). That is a resource-provider registration failure, **not** an MG permission failure. Misreading it produced a wrong "cannot read MG scope" conclusion. Workaround: call the MG API directly via `az rest`.
2. Policy assignments at MG scope **require a `$filter`** (`FilterNotFound`); without it the call returns HTTP 400. A loop that swallowed the error reported 0 assignments and looked like a clean result. Use `$filter=atExactScope()` and always check `$LASTEXITCODE`.

With both fixed: **18/18 MG scopes queried, 0 failures, 33 assignments.** Identity has Reader at root MG as expected.

### Decisive finding

**`Deploy-Private-DNS-Zones`** assigned at MG `mercyhealth-landingzones-dna`:

- Effect `DeployIfNotExists`, enforcement `Default` (**enforced, not audit**), SystemAssigned identity, no `notScopes`.
- 53 parameters carrying **39 distinct zone IDs**, all in `rg-dns-v3nysoeym4kga`.
- **29 of the 53 zones marked `Eligible` in the second sweep are hardcoded parameters of this assignment.** Deleting any of them breaks DINE remediation for every future private endpoint of that type in the D&A landing zone — plan §11 row 2, now confirmed with resource IDs rather than hypothesised.
- The earlier subscription-scoped check missed this because ALZ assigns at MG scope; the 8 assignments visible on `818a8b62-…` are all Defender/Guest-Config.

### Not cleared

The remaining **24** eligible zones are unreferenced by *this* assignment, but subscription-scoped `Deploy-Private-DNS-Zones` assignments in the other 21 subscriptions were **not** checked. Treat those 24 as unresolved, not safe.

### Recommendation

Close the cleanup at **zero deletions**. The 53 unlinked zones are intentional standing ALZ inventory in a production hub, 29 of them policy-wired. The sweep's three gates in §1 cannot see policy parameters — which is exactly why §11 is a human gate. Note the near miss: all 29 present as maximally deletable on control-plane evidence (0 links, 1 SOA, 393 days) and are the ones that would have caused the most damage.

### Changes made this session

- Plan §6a: baseline recorded as **SOA only (1 record set)**, evidenced across all 53 eligible zones.
- Plan §3: rewritten with live-verified context; corrected the connectivity hub ID (`d93fefb0-…` superseded by `818a8b62-…`, and `d93fefb0-…`'s actual identity is now **Unknown** pending re-check); added MG hierarchy, zone census, lifecycle, and the policy dependency row.
- §11 not amended, ADR not drafted, remaining 21-subscription check not run — all deferred by user decision.
- **No Azure mutation.** All calls were `account show` / `account list` / `group show` / `resource show` / `zone list` / `deployment group list` / `policy assignment list` / `az rest` GETs.

## Follow-up — 21-subscription check on the remaining 24 (2026-08-13, live read-only)

**Supersedes the "Not cleared" note in the previous section.** The 24 are now cleared of policy references specifically.

### Result

Zero of the 24 remaining eligible zones are referenced by any policy assignment at any scope in the tenant. Tenant-wide there is exactly **one** assignment referencing `privateDnsZones` — the `Deploy-Private-DNS-Zones` at `mercyhealth-landingzones-dna` already recorded above. The 24 are absent from its parameters.

### Method — and a third failure worth recording

First attempt used `az policy assignment list --disable-scope-strict-match` across all 22 subscriptions. It returned 76 assignments, **all subscription-scoped**, and reported 0 private-DNS references. That result was worthless: the flag did **not** pull ancestor MG scopes or RG scopes, and the sweep failed to surface `Deploy-Private-DNS-Zones` even for the three subscriptions under `mercyhealth-landingzones-dna` that demonstrably inherit it (`dt-dev-analytics`, `dt-prd-analytics`, `dt-tst-analytics`).

Second attempt used Azure Resource Graph `policyresources`, which indexes assignments at every scope. Validated three ways before the negative was accepted:

| Validation | Result |
|---|---|
| Does the query return the known-positive assignment? | **Yes** — `Deploy-Private-DNS-Zones` surfaced at MG scope |
| ARG MG-scoped count vs. manual MG sweep | **33 = 33** |
| ARG subscription-scoped count vs. manual 22-sub sweep | **76 = 76** |
| RG-scoped assignments | **0 exist** — closes the scope gap the CLI could not reach |

**Process lesson.** Three method attempts this session; **two returned a confident, clean-looking "nothing found" that was wrong** (swallowed `FilterNotFound`; `--disable-scope-strict-match` silently omitting ancestor and RG scopes). Both failed in the direction of "nothing depends on these, safe to delete." On Class 4 work, never accept a "no dependencies found" result until the tool has been proven able to find a dependency known to exist.

### Still open for the 24

Policy is one of four §11 risks. Unchecked: infrastructure-code declarations (**live risk** — active AVM/Bicep deployments into this RG through 2026-08-05), private endpoint DNS zone groups in other subscriptions, and resource locks. None are answerable from the control plane; they need a repository review.

---

## Plain-English summary of findings (2026-08-13)

### What we were doing

We had a report listing 53 private DNS zones that looked safe to delete. All 53 passed every test the cleanup plan defined: nothing was connected to them, they held no real DNS records, and they had been sitting untouched for 393 days. On paper they looked like textbook dead weight.

The job after that was to check the things the automated sweep deliberately does not look at — because the plan's authors knew a zone can look abandoned and still be load-bearing.

### What we found

**These zones live in production, not a sandbox.** The subscription holding them turned out to be `dt-prd-connectivity` — the production connectivity hub for the whole estate. The resource group is tagged "business criticality: high," the zones themselves are tagged "highly confidential," and there is a named owner, Jeremy Colson. An earlier note in the plan had pointed at a different subscription as the connectivity hub, which is part of why this did not stand out sooner.

**The zones are not abandoned — they are stock waiting to be used.** The resource group holds 70 zones. Seventeen are actively in use (Key Vault, container registry, storage, SQL, and so on). The other 53 — our deletion candidates — are the rest of the standard Microsoft catalog, provisioned up front so they are ready when a team onboards a new Azure service. The deployment history confirms this is still an active process: automation was adding connections to this exact resource group as recently as 2026-08-05, about a week before the sweep ran. This matches the team's existing understanding of how the environment works.

**Twenty-nine of the 53 are wired into a live governance policy.** There is a policy called `Deploy-Private-DNS-Zones` running against the Data & Analytics landing zone. Its job is to automatically hook up DNS whenever someone creates a new private connection to an Azure service. It is actively enforced, not just monitoring. That policy contains a hardcoded list of specific zones it depends on — and 29 of our deletion candidates are on that list by exact address. Delete any of them, and every future private connection of that type in Data & Analytics silently gets no DNS and the automation fails. This is not a theoretical concern; it is the first scenario the plan's own risk table warned about, now confirmed with specifics.

**The other 24 are clear of policy — but that is not the same as safe.** Every policy assignment in the tenant was checked, at every level, and none reference those 24. That closes one specific risk. Three others remain open for them: whether the Bicep or Terraform code declares these zones (there is live automation deploying into that resource group, so this is a real possibility), whether any private endpoints elsewhere point at them, and whether any have deletion locks. None of those can be answered from the Azure control plane — they need someone to look at the code repositories.

### Something worth knowing about how the checking went

Three times we tried to answer "is any policy depending on these zones," and **two of those attempts returned a confident, clean-looking 'nothing found' that was simply wrong.** One failed because Azure's API silently rejected the request in a way the script swallowed. The other failed because a command flag did not do what its name implies — it quietly skipped exactly the scopes where the policy lived.

Both wrong answers pointed the same direction: *nothing depends on these, go ahead and delete.* That is the failure mode that matters on irreversible work. It was only caught by testing each method against a dependency already known to exist, and confirming the method could actually find it. If there is one process lesson from this exercise, it is that a "no dependencies found" result on a destructive change should never be trusted until the tool has proven it can find a dependency that is definitely there.

### Bottom line

The sweep worked correctly. It found zones that genuinely have no connections, no records, and no recent activity — because that is exactly what a pre-provisioned zone awaiting its first user looks like. There is no way to tell "abandoned" from "ready and waiting" using the signals the tool measures.

**Recommendation: close this cleanup with zero deletions.** The 53 zones are intentional inventory in a production hub, 29 of them are actively depended upon by governance automation, and the cost of keeping them is trivial next to the disruption of removing them. If anyone still wants to pursue this, the remaining 24 would need a code review first, and all of it would be a production change requiring a change ticket and maintenance window — a lot of risk and process for very little return.

The near miss is worth stating plainly: the 29 most dangerous zones to delete were also, by every automated measure, the ones that looked most obviously safe.

---

## Follow-up — §11 infrastructure-code check (2026-08-13, live read-only)

**Closes the last open §11 risk.** Resolves hard against deletion.

### This repo holds no IaC

`grep -i "privatednszone|privateDnsZone|private-dns-zone"` across `E:\Repos\Azure` returned 9 files — all artifacts we authored ourselves (plan, report JSON/CSV, sweep script, KQL). The repo contains **zero** `.bicep`, `.tf`, `.bicepparam`, or `.tfvars` files and no `infra/` directory. It is a documentation-and-scripts workspace. The §11 check cannot be satisfied here.

### The real IaC

Azure DevOps org `mercyhealthcare` (from `.cursor/mcp.json`), project **`Azure Infrastructure`** — *"all the infrastructure-as-code (Bicep) used to provision the Mercyhealth Azure infrastructure and other landing zones."* Repo **`iac_landing_zone`**, an ALZ-Bicep implementation. Relevant paths:

- `/modules/privateDnsZones/privateDnsZones.bicep` — the zone declarations
- `/modules/privateDnsZoneLinks/privateDnsZoneLinks.bicep`
- `/modules/policy/definitions/lib/policy_set_definitions/policy_set_definition_es_Deploy-Private-DNS-Zones.json`
- `/modules/policy/assignments/alzDefaults/DefaultPolicyAssignments.bicep`

### Decisive reconciliation

`privateDnsZones.bicep` hardcodes a default `paramPrivateDnsZones` array; resolved for `northcentralus` (3 location-templated entries + auto-merged `ncus` backup zone) it yields **67 zones**.

| Comparison | Result |
|---|---|
| Live zones in hub RG | 70 |
| IaC-declared (resolved) | 67 |
| IaC-declared present live | **67 / 67 — zero drift** |
| Eligible-for-deletion zones declared in IaC | **52 of 53** |
| The 24 policy-clear zones declared in IaC | **23 of 24** |

**Deleting any of the 52 is self-reversing churn** — the next pipeline run recreates them from the module declaration. Class 4 destructive action on a production hub, undone automatically.

### The one genuine orphan

**`privatelink.azuredatabricks.net`** — 0 links, SOA only, 393 days old, **not** in the Bicep array, **not** in any policy assignment. The only zone of the 53 that is defensibly deletable.

The other two live zones outside IaC both have 5 active links and are in use: `azure-api.net`, `privatelink.management.azure-api.net`.

### Evidence labels and two corrections

- **Confirmed:** the module declares these zones; live/IaC reconciliation is 67/67.
- **Inferred (strong):** this module is what provisioned them — the resolved default array matches live exactly, including the templated `northcentralus.batch`, `northcentralus.kusto` and `ncus.backup` entries. The orchestration file invoking the module was **not** read, so the possibility of a parameter override is not formally excluded. That residual uncertainty argues further against deletion, not for it.
- **Correction:** `mc-` in `mc-privateDnsZones.parameters.*.json` is **Mooncake** (Azure China — `chinaeast2`, `.cn` zones), an upstream ALZ sample file irrelevant to this estate. It is *not* "Mercyhealth-customised" as first read.
- ADO access was read-only throughout: `core_list_projects`, `search_code`, `repo_file get_content` / `list_directory`. No writes, no pipeline interaction.

### Net position across all verification

The sweep proposed 53 deletions. After verification: **29 policy-wired, 52 IaC-declared, 1 defensible candidate.** Recommend folding the single Databricks zone into normal housekeeping rather than running Phase D–F for one zone, and closing the cleanup otherwise at zero deletions.
