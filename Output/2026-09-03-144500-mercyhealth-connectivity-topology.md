# Mercyhealth — End-to-End Connectivity Topology (`dt-prd-connectivity`)

**Prepared:** 2026-09-03 14:24 UTC
**Prepared by:** Claude Code session, workspace `D:\codes\Azure`
**Class:** 0 — read-only discovery. Nothing was created, modified, or deleted.
**Companion canvas:** `2026-09-03-144500-mercyhealth-connectivity-canvas.html`

---

## 1. Bottom line

One secured Virtual WAN hub in North Central US fronts sixteen spoke VNets spread across sixteen
subscriptions. **Routing Intent is enabled for both `Internet` and `PrivateTraffic`, so every flow —
east-west, north-south and hybrid — is inspected by a single Azure Firewall.** There are zero
spoke-to-spoke peerings, so no path avoids it.

Two consequences dominate:

1. That firewall has **no availability zones**. It is a single-zone dependency for the whole fabric.
2. The "HA" VPN pair is **not redundant** — both sites terminate on the same on-premises IP.

## 2. Scope and context

| Item | Value |
|---|---|
| Subscription | `dt-prd-connectivity-oeqrq2jxadm36` |
| Resource group | `rg-vwan-v3nysoeym4kga` |
| Region | North Central US |
| Virtual WAN | `mercyhealth-vwan-northcentralus` — Standard, branch-to-branch enabled |
| Virtual hub | `mercyhealth-vhub-northcentralus` — `172.25.0.0/24`, Standard, Provisioned |
| Hub router | ASN 65515, router IPs `172.25.0.68` / `172.25.0.69` |
| Azure Firewall | `mercyhealth-azfw-northcentralus` — AZFW_Hub / Standard, private `172.25.0.132`, public `20.25.217.244` |
| Firewall policy | `mercyhealth-azfwpolicy-northcentralus` — Standard, threat intel `Alert` |
| VPN gateway | `mercyhealth-vpngw-northcentralus` — 1 scale unit, ASN 65515, BGP peers `172.25.0.15` / `.14` |
| ExpressRoute | **None** |
| Point-to-site | **None** |

Subscription and tenant GUIDs are omitted — `Output/` is not gitignored and CLAUDE.md §6.2 prohibits
committing them.

## 3. Routing Intent (the mechanism)

```
routingIntent/hubRoutingIntent
  policy "Internet"        destinations [Internet]        nextHop -> mercyhealth-azfw-northcentralus
  policy "PrivateTraffic"  destinations [PrivateTraffic]  nextHop -> mercyhealth-azfw-northcentralus
```

Resulting hub route tables:

| Route table | Associated | Propagating | Routes |
|---|---|---|---|
| `DefaultRouteTable` | 18 (16 VNet + 2 VPN) | 0 | `0.0.0.0/0 → AzFW`; `10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 → AzFW` |
| `noneRouteTable` | 0 | 18 | none |

Associating every connection to `DefaultRouteTable` while propagating only to `noneRouteTable` is the
standard Routing Intent signature. No connection learns another spoke's prefix directly; they all learn
the two policy routes that point at the firewall.

## 4. Traffic paths (Confirmed)

| Flow | Path | Inspected |
|---|---|---|
| Spoke → Internet | spoke → hub router → AzFW → SNAT `20.25.217.244` → internet | Yes |
| Internet → Spoke | no DNAT rule collection exists — no published inbound path | No path |
| Spoke → Spoke (east-west) | spoke → hub router → AzFW → hub router → spoke | Yes |
| Spoke → On-prem | spoke → hub router → AzFW → VPN gateway → IPsec | Yes |
| On-prem → Spoke | IPsec → VPN gateway → hub router → AzFW → spoke | Yes |

The "no inbound path" row is **Inferred**, on two pieces of evidence: the policy has exactly three rule
collection groups (`Allowed-Sites`, `Allowed-Network`, `Denied-Network`) and none is a NAT collection;
and the prior deny-log export recorded `AZFWNatRule` as having 0 rows all-time. Rule *contents* were not
read, so a DNAT rule hidden inside another group cannot be fully excluded.

## 5. Spoke VNets (Confirmed)

All 16 are carved from `172.25.0.0/16`, each in its own subscription, each with exactly one peering
(`RemoteVnetToHubPeering_…` → managed hub VNet), all `Connected`, all `useRemoteGateways=true`, all with
`enableInternetSecurity=true` on the hub connection.

| VNet | CIDR | Subscription | Family |
|---|---|---|---|
| `vnet-spoke-vmss-azuredevops` | `172.25.1.0/25` | dt-prd-azuredevops | Platform |
| `vnet-spoke-dna-dev` | `172.25.8.0/24` | dt-dev-analytics | Data & Analytics |
| `vnet-spoke-dna-tst` | `172.25.9.0/24` | dt-tst-analytics | Data & Analytics |
| `vnet-spoke-dna-prd` | `172.25.10.0/24` | dt-prd-analytics | Data & Analytics |
| `vnet-spoke-mgt` | `172.25.13.0/24` | dt-prd-management | Platform |
| `vnet-spoke-appdev-dev` | `172.25.16.0/20` | dt-dev-app | Connect Application |
| `vnet-spoke-appdev-tst` | `172.25.32.0/20` | dt-tst-app | Connect Application |
| `vnet-spoke-appdev-prd` | `172.25.48.0/20` | dt-prd-app | Connect Application |
| `vnet-spoke-tpa-dev` | `172.25.64.0/20` | dt-dev-tpa | TPA |
| `vnet-spoke-tpa-tst` | `172.25.80.0/20` | dt-tst-tpa | TPA |
| `vnet-spoke-tpa-prd` | `172.25.96.0/20` | dt-prd-tpa | TPA |
| `vnet-spoke-microsites-shr` | `172.25.112.0/24` | dt-shr-microsites | Microsites |
| `vnet-spoke-microsites-dev` | `172.25.128.0/20` | dt-dev-microsites | Microsites |
| `vnet-spoke-microsites-tst` | `172.25.144.0/20` | dt-tst-microsites | Microsites |
| `vnet-spoke-microsites-prd` | `172.25.160.0/20` | dt-prd-microsites | Microsites |
| `vnet-spoke-vitea` | `172.25.176.0/20` | dt-prd-vitea | AI Governance |

Six subscriptions hold no VNet: `dt-shr-tpa`, `dt-workday`, `dt-prd-deployments-001`, `dt-prd-logging`,
`dt-sandbox`, and `dt-prd-connectivity` itself (the hub VNet is Microsoft-managed).

## 6. Hybrid edge

| Site | Link | On-prem endpoint | Address space | Vendor |
|---|---|---|---|---|
| `Azure-Mercyhealth` | `Mercyhealth` | `198.190.160.161` | `10.0.0.0/8`, `192.168.0.0/16` | Cisco |
| `MHTC-HA` | `JVL-Egress` | `198.190.160.161` | `10.0.0.0/8`, `192.168.0.0/16` | Cisco |

IPsec on `JVL-Egress`: IKEv2, phase 1 AES-256 / SHA-256 / DH Group 14; phase 2 AES-256 / SHA-256 /
**PFS None**, SA lifetime 28800 s.

### Tunnel state — contradictory sources

| Source | `JVL-Egress` | `Mercyhealth` |
|---|---|---|
| `vpnGateways` object (gateway-level) | `NotConnected`, counters 0 | blank, counters 0 |
| `vpnConnections/{name}` (direct) | `Connected`, 232 MB cumulative | persistent `GatewayError` on every retry |
| Azure Monitor metrics, 30 d | 68.08 MB across 16 active days | **no timeseries at all** |

Reconciliation: the metrics are the reliable view. `JVL-Egress` is a functioning tunnel carrying very
little — silent 20–30 Aug, active 31 Aug (18.0 MB in / 6.7 MB out), 1 Sep (22.7 MB / 1.7 MB), 2 Sep
(0.3 MB / 0.3 MB), and zero for the six hours before this report. The `Mercyhealth` tunnel has produced
no metric datapoint in 30 days and its ARM object cannot be read; its state is **Unknown**, though the
evidence is consistent with never having established.

## 7. Findings

| # | Finding | Label | Severity |
|---|---|---|---|
| 1 | Both VPN sites terminate on the same on-prem IP `198.190.160.161` — no path diversity despite the `-HA` name | Confirmed | High |
| 2 | `Mercyhealth` tunnel: no metrics in 30 d, ARM read fails persistently | Unknown | High |
| 3 | ARM reports tunnel status three inconsistent ways; control-plane status fields on this gateway are unreliable | Confirmed | Medium |
| 4 | Azure Firewall has no availability zones, and Routing Intent makes it a hard dependency for all traffic classes | Confirmed | High |
| 5 | Firewall and policy are Standard — no IDPS, no TLS inspection; threat intel is `Alert` only, not `Alert and Deny` | Confirmed | Medium |
| 6 | All 16 spokes share one egress IP `20.25.217.244` — shared SNAT capacity and shared reputation across dev and production | Confirmed | Medium |
| 7 | IPsec phase 2 uses `PFS None` | Confirmed | Medium |
| 8 | `dt-shr-tpa` has no VNet although the other three TPA environments do | Confirmed | Low |
| 9 | VPN gateway is 1 scale unit; no ExpressRoute exists, so all hybrid traffic depends on internet-based IPsec | Confirmed | Medium |

None of these is authorised for remediation. Items 1, 4 and 9 are design changes requiring a change plan;
items 5 and 7 need coordinated changes (Premium tier cost, Cisco-side PFS match).

## 8. Not covered

Firewall rule contents (only collection group names were read), NSGs and UDRs inside spokes, private
endpoints and Private DNS zones, subnet design, Front Door / Application Gateway, RBAC, and cost. No
shared keys, certificates, or secrets were retrieved.

## 9. Reproduce

```powershell
$cid='<connectivity-subscription-id>'; $rg='rg-vwan-v3nysoeym4kga'; $hub='mercyhealth-vhub-northcentralus'
$b="https://management.azure.com/subscriptions/$cid/resourceGroups/$rg/providers/Microsoft.Network/virtualHubs/$hub"
az rest --method get --url "$b/routingIntent?api-version=2023-09-01"
az rest --method get --url "$b/hubRouteTables?api-version=2023-09-01"
az rest --method get --url "$b/hubVirtualNetworkConnections?api-version=2023-09-01"
az rest --method get --url "https://management.azure.com/subscriptions/$cid/providers/Microsoft.Network/vpnSites?api-version=2023-09-01"
```

VNet inventory used Azure Resource Graph via `POST /providers/Microsoft.ResourceGraph/resources`
(no CLI extension required). Tunnel history used
`GET <vpnGateway>/providers/microsoft.insights/metrics` with `metricnames=TunnelIngressBytes,TunnelEgressBytes`
and `$filter=ConnectionName eq '*'`.

All read-only.
