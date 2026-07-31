# Chat: TPA prod networking security review

- **Date:** 2026-07-21
- **Workspace:** E:\azdevops\Azure

---

## Turn 1

### User

Hello World

### Assistant

Greeting; offered to help with Azure operations/exploration (subscriptions, RGs, costs, topology, Azure DevOps, Bicep, diagrams, Microsoft Learn).

---

## Turn 2

### User

Is there any security vulnerability on the networking side in the tpa prod subscription?

### Assistant

Reviewed networking security in the `dt-prd-tpa-oeqrq2jxadm36` subscription (id `65d61542-8414-46cc-b9c7-c736ac661a03`), main RG `rg-spoke-tpa-prd-imkltpplo5qyg`, region northcentralus. Used Azure MCP Resource Graph + direct Azure REST API calls (ARG had indexing gaps for web/sites/config, route tables, and Front Door sub-resources, so critical findings were verified via REST).

**Answer: Yes.** Key findings:

1. CRITICAL — Both App Services (`app-tpa-prod-frontend-ncus`, `app-tpa-prod-backend-ncus`) are publicly open with no IP access restrictions (main + SCM "Allow all", defaultAction Allow). Front Door reaches them over public hostnames with no Private Link (`sharedPrivateLinkResource:null`) → direct-origin access bypasses Front Door + WAF.
2. HIGH — WAF policy `wafprod` is enabled/Prevention and linked to the AFD endpoint (security policy `afd-waf-security` on `/*`), but `managedRuleSets:[]` (no OWASP CRS / bot rules). Only custom rule blocks `/.env`. Effectively non-protective.
3. MEDIUM — NSG flow logs not enabled on `nsg-snet-tpa-prod-ncus` (flowLogs null).
4. MEDIUM — No route table/UDR in spoke to force egress through Azure Firewall; NSG outbound "Allow-HTTPS-Web" (443→Internet) annotated "FW filters FQDNs" but not enforced from spoke.
5. LOW/MED — DDoS Protection Standard not enabled on `vnet-spoke-tpa-prd` (enableDdos false, no plan).
6. LOW — AFD routes advertise HTTP (httpsRedirect Enabled mitigates); origins enforceCertificateNameCheck=false.

Good posture (no action): SQL/Storage/KeyVault/AppConfig all publicNetworkAccess=Disabled with private endpoints; Storage TLS1_2 + blob public access disabled; NSG well-locked-down (deny RDP/SSH/WinRM/SMB from internet, explicit deny-all in/out); hub-spoke peering with remote gateways; no public IPs; App Service httpsOnly=true.

Front Door detail: profile `az-fd-prod` (Standard_AzureFrontDoor), endpoint `az-ep-prod` (host `az-ep-prod-ghf7e9g2dfd9gva8.a03.azurefd.net`), routes `route-api-prod` (`/api/*`→`og-backend-prod`→backend app) and `az-route-prod` (`/*`→`az-og-prod`→frontend app), custom domain `planalytics-mercycarehealthplans-com`.

Remediation priority: (1) restrict App Service access to AzureFrontDoor.Backend service tag + deny default; tighten SCM; consider Premium + Private Link origins + publicNetworkAccess Disabled. (2) attach Microsoft_DefaultRuleSet + BotManagerRuleSet to WAF. (3) enable NSG flow logs + Traffic Analytics to log-prod. (4) add UDR 0.0.0.0/0 → Azure Firewall on integration/fabric subnets. (5) DDoS Standard on hub VNet.

Caveats: ARG unreliable for nested resources (verified via REST). Did not run full azqr/Defender scan (Excel output). Egress/forced-tunneling depends on connectivity hub sub `d93fefb0-2862-43f5-bb00-f413bc6896cf` (not inspected). Offered follow-ups: run azqr, inspect hub Azure Firewall/routing, or draft Bicep/CLI remediation for findings 1 & 2.
