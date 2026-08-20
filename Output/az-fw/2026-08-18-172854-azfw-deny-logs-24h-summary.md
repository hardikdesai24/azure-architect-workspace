# Azure Firewall — Deny logs, last 24 hours

- **Generated (local):** 2026-08-18 17:28:54 (+05:30)
- **Query run (UTC):** 2026-08-18T11:58:54Z
- **Data window (UTC, observed):** 2026-08-17 12:00:52Z → 2026-08-18 11:57:16Z
- **Firewall:** `mercyhealth-azfw-northcentralus` (Standard, northcentralus)
  - RG `rg-vwan-v3nysoeym4kga`, subscription `dt-prd-connectivity` — Virtual WAN hub firewall
- **Workspace:** `mercyhealth-log-analytics` (RG `rg-logging-36hqqavhuaga6`, retention 365 days)
- **Diagnostic setting:** `diag-firewall-log-analytics`, destination type **Dedicated** (resource-specific tables)
- **Tables queried:** `AZFWNetworkRule`, `AZFWApplicationRule`, `AZFWNatRule`, `AZFWThreatIntel`
- **Filter:** `Action == "Deny"` only
- **Data files:** `2026-08-18-172854-azfw-deny-logs-24h.csv` / `.json` (3,128 rows)
- **Reusable query:** `queries/kql/azure-firewall-deny-last-24h.kql`

## Totals

| Table | Deny rows |
|---|---|
| AZFWApplicationRule | 3,117 |
| AZFWNetworkRule | 11 |
| AZFWNatRule | 0 (table exists, **0 rows all-time**) |
| AZFWThreatIntel | 0 (table exists, **0 rows all-time**) |
| **Total** | **3,128** |

**Every deny was a default deny — no explicit deny rule fired.**

| Deny reason | Rows |
|---|---|
| `No rule matched. Proceeding with default action` (application) | 3,117 |
| `Default Action` (network) | 11 |

**Confirmed** by checking all 3,128 exported rows: `Policy`, `RuleCollectionGroup`, `RuleCollection`,
and `Rule` are empty on every deny row (0 rows with any of the four populated). Allow rows in the same
tables *do* carry `Policy = mercyhealth-azfwpolicy-northcentralus`, so the contrast is real — denied
traffic fell through to the implicit deny rather than matching a configured deny rule.

## Application-rule denies by destination FQDN

| FQDN | Denies | Distinct sources |
|---|---|---|
| main.vscode-cdn.net | 1,152 | 1 |
| www.bing.com | 1,098 | 3 |
| assets.msn.com | 272 | 3 |
| clients2.google.com | 168 | 3 |
| default.exp-tas.com | 96 | 3 |
| cdn.fwupd.org | 91 | 4 |
| da.xboxservices.com | 90 | 3 |
| mgmt-file-upload-us-east-1-prod.sentinelone.net | 64 | 3 |
| content.ivanti.com | 48 | 3 |
| eafc.nelreports.net | 16 | 3 |
| adl.windows.com | 12 | 1 |
| arc.msn.com | 4 | 2 |
| contracts.canonical.com | 2 | 2 |
| x1.c.lencr.org / x2.c.lencr.org / ye.c.lencr.org / ye1.c.lencr.org | 1 each | 1 |

Protocol split: HTTPS/443 = 3,101; HTTP/80 = 16.

## Source IPs (all denies)

| Source IP | Denies | Distinct targets |
|---|---|---|
| 172.25.13.39 | 1,745 | 11 |
| 172.25.13.40 | 643 | 12 |
| 172.25.13.37 | 606 | 9 |
| 172.25.13.38 | 41 | 4 |
| 172.25.176.125 | 24 | 1 |
| 172.25.176.68 | 24 | 1 |
| 172.25.176.15 | 22 | 1 |
| 172.25.176.100 | 21 | 1 |
| 172.25.1.10 | 1 | 1 |
| 172.25.1.6 | 1 | 1 |

## Network-rule denies (complete list — all 11)

All eleven are outbound **UDP source port 123 to `168.61.215.74:123`**, spread evenly across the four
`172.25.13.x` hosts over the full window.

- **Confirmed:** protocol UDP, source and destination port 123, destination `168.61.215.74`.
- **Inferred:** port 123 both ways is NTP time synchronisation.
- **Unknown:** which service owns `168.61.215.74`. The firewall's DNS proxy is active
  (`AZFWDnsQuery`, 334,568 queries in the window), but a search of that table for the four source
  hosts returned **no** query name containing `time` or `ntp` in 24h, so the name→IP mapping is not
  evidenced here. `AZFWDnsQuery` records `QueryName` but no answer/response IP column, so it cannot
  confirm the mapping either way. The IP was **not** resolved to an owner in this pass.

| Time (UTC) | Protocol | Source | Destination | Port |
|---|---|---|---|---|
| 2026-08-17 12:19:19 | UDP | 172.25.13.39:123 | 168.61.215.74 | 123 |
| 2026-08-17 17:22:19 | UDP | 172.25.13.37:123 | 168.61.215.74 | 123 |
| 2026-08-17 18:03:01 | UDP | 172.25.13.40:123 | 168.61.215.74 | 123 |
| 2026-08-17 18:33:01 | UDP | 172.25.13.40:123 | 168.61.215.74 | 123 |
| 2026-08-17 18:42:13 | UDP | 172.25.13.38:123 | 168.61.215.74 | 123 |
| 2026-08-17 21:25:27 | UDP | 172.25.13.39:123 | 168.61.215.74 | 123 |
| 2026-08-18 02:28:29 | UDP | 172.25.13.37:123 | 168.61.215.74 | 123 |
| 2026-08-18 03:39:11 | UDP | 172.25.13.40:123 | 168.61.215.74 | 123 |
| 2026-08-18 03:48:23 | UDP | 172.25.13.38:123 | 168.61.215.74 | 123 |
| 2026-08-18 06:31:35 | UDP | 172.25.13.39:123 | 168.61.215.74 | 123 |
| 2026-08-18 11:34:39 | UDP | 172.25.13.37:123 | 168.61.215.74 | 123 |

## Observations (not remediation)

- **Confirmed:** No DNAT or threat-intel rows at all — `AZFWNatRule` and `AZFWThreatIntel` both
  resolve as tables but hold **0 rows all-time**, not merely 0 in this window. Firewall policy
  `mercyhealth-azfwpolicy-northcentralus` has `threatIntelMode = Alert`, so a threat-intel match
  would be logged with action `Alert`, never `Deny` — a deny-only filter would not show one anyway.
  Read "no threat-intel activity recorded", not "threat intel blocked nothing".
- **Confirmed:** No IDPS data — IDPS requires the Premium SKU and this firewall is Standard.
- **Confirmed:** The four `172.25.13.37–40` hosts generate 3,035 of 3,128 denies (97%). Their traffic
  pattern (vscode-cdn, bing, msn, xbox services, fwupd, SentinelOne, Ivanti) reads as user/agent
  endpoint traffic, not server workload traffic.
- **Inferred:** The recurring UDP/123 denies suggest those hosts are attempting external time sync
  while the firewall policy has no matching allow rule. Time drift is worth checking on those hosts.
- **Inferred:** `x1/x2/ye/ye1.c.lencr.org` denies are Let's Encrypt CRL/OCSP fetches over HTTP/80.
  Blocked revocation checks can cause TLS handshake delays or soft-fail behaviour on those hosts.
- **Unknown:** Whether any of these denies correspond to a reported application failure. No
  correlation with incidents, Service Health, or app telemetry was performed.
- **Unknown:** Owner and role of the `172.25.13.x` and `172.25.176.x` hosts — not resolved to VMs
  in this pass.

## Scope and coverage caveats

- **Firewall discovery scope:** the Azure Resource Graph query for
  `microsoft.network/azurefirewalls` returned exactly one firewall, but ARG only returns resources in
  subscriptions the signed-in identity can read (`hdesai@mhemail.org`, tenant Mercyhealth). A firewall
  in a subscription outside that access would not appear. Absence is not proof of non-existence.
- **Log source scope:** only the `mercyhealth-log-analytics` workspace was queried. If any firewall
  sends diagnostics elsewhere, those denies are not in this export.
- **Legacy tables:** the `AzureFirewallApplicationRule` / `AzureFirewallNetworkRule` /
  `AzureFirewallDnsProxy` categories (legacy `AzureDiagnostics`) are **disabled** on this diagnostic
  setting, so nothing was missed by querying resource-specific tables only.
- **Window:** `ago(24h)` is relative to query execution (2026-08-18T11:58:54Z). Re-running produces a
  slightly different row count as the window rolls.

No changes were made to Azure. Read-only queries only.
