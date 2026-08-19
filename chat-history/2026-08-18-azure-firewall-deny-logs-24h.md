# Chat: Azure Firewall deny logs — last 24 hours

- **Date:** 2026-08-18 (local +05:30) / query run 2026-08-18T11:58:54Z
- **Workspace path:** C:\codes\azure-architect-workspace
- **Class:** 0 — read-only. No Azure or Azure DevOps mutation.

---

## Turn 1

### User

"Pull azure firewall logs for the last 24 hours. Pull only deny logs"

### Assistant

**Context established (read-only discovery):**

- Signed in as `hdesai@mhemail.org`, tenant Mercyhealth (`mh.mercyhealthcare.org`).
- Active subscription `dt-prd-connectivity` (`818a8b62-…`).
- ARG found one Azure Firewall in accessible subscriptions:
  `mercyhealth-azfw-northcentralus`, Standard SKU, `rg-vwan-v3nysoeym4kga`, northcentralus (vWAN hub).
- Diagnostic setting `diag-firewall-log-analytics`, `logAnalyticsDestinationType = Dedicated`
  → resource-specific tables. Legacy `AzureFirewall*` categories are disabled.
- Destination workspace `mercyhealth-log-analytics`
  (`rg-logging-36hqqavhuaga6`, sub `96a01662-…`), customerId `9d40b718-…`, retention 365 days.
- Firewall policy `mercyhealth-azfwpolicy-northcentralus`, Standard, `threatIntelMode = Alert`.

**Result — 3,128 deny events in the 24h window** (UTC 2026-08-17 12:00:52 → 2026-08-18 11:57:16):

| Table | Deny rows |
|---|---|
| AZFWApplicationRule | 3,117 |
| AZFWNetworkRule | 11 |
| AZFWNatRule / AZFWThreatIntel | 0 (0 rows all-time) |

- 100% were **default denies** — no explicit deny rule matched. Verified across all 3,128 rows that
  `Policy` / `RuleCollectionGroup` / `RuleCollection` / `Rule` are empty (Allow rows do carry Policy).
- Top denied FQDNs: `main.vscode-cdn.net` (1,152), `www.bing.com` (1,098), `assets.msn.com` (272),
  `clients2.google.com` (168), plus fwupd / SentinelOne / Ivanti / xboxservices.
- Four hosts `172.25.13.37–40` produced 3,035 of 3,128 denies (97%); traffic profile looks like user
  endpoints, not server workloads.
- All 11 network-rule denies are UDP 123→123 to `168.61.215.74` (NTP inferred from port; the IP was
  **not** resolved to an owner — DNS-proxy logs show no `time`/`ntp` query from those hosts and the
  `AZFWDnsQuery` table has no answer-IP column).

**Deliverables written (not committed):**

- `Output/2026-08-18-172854-azfw-deny-logs-24h.json` (2.3 MB, raw)
- `Output/2026-08-18-172854-azfw-deny-logs-24h.csv` (1.1 MB, 3,128 rows)
- `Output/2026-08-18-172854-azfw-deny-logs-24h-summary.md`
- `queries/kql/azure-firewall-deny-last-24h.kql` (reusable, executed and validated from file)

---

## Lessons / gotchas recorded

1. **`az.cmd` mangles multi-line `--analytics-query` on Windows PowerShell.** A here-string KQL passed
   from the PowerShell tool silently lost everything after the first line — the `where Action ==
   "Deny"` filter and the `project` were dropped, producing a 167k-row / 162 MB Allow+Deny dump that
   looked plausible. Caught by checking row count against a prior scoping `summarize` (3,127 expected).
   Bad files were deleted and the export redone from bash, which passes newlines intact.
   **Rule: run multi-line KQL/az invocations from bash on this machine, and always sanity-check the
   returned row count against an independent count query.**
2. `union ... | summarize by $table` is invalid KQL — use `union withsource=ColName`.
3. Windows Python cannot read git-bash `/tmp` paths; use the scratchpad dir with a Windows path.
4. Passing a resource ID starting with `/` to `az` from git-bash needs `MSYS_NO_PATHCONV=1`,
   otherwise MSYS rewrites it into a Windows path and `az` reports a usage error.

## Open items (not actioned)

- `168.61.215.74` not attributed to a service/owner.
- `172.25.13.x` / `172.25.176.x` hosts not resolved to VM resources or owners.
- No correlation of denies against incidents, Service Health, or application telemetry.
- Repo has **no `.gitignore`**; `Output/` now holds internal IPs, FQDNs and subscription IDs. Not
  committed. Flagged to the user; no `.gitignore` created (not requested).
