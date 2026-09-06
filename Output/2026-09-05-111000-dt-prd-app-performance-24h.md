# Application performance — last 24 hours

**Subscription:** `dt-prd-app-oeqrq2jxadm36`  
**Window (UTC):** 4 September 2026 05:40 to 5 September 2026 05:40.  
**Window (IST):** 4 September 2026 11:10 to 5 September 2026 11:10.  
**Metrics collected:** 2026-09-05 05:41:33 UTC. Static-site aggregation validation completed later in the same session.  
**Scope:** 10 web apps, one Flex Consumption function app, one static web app, and all 12 App Service plans discovered in the subscription. Web apps, function and plans are in North Central US; the static web app is in Central US. Resource group: `rg-spoke-appdev-prd-4fhxtyumb5wlq`.

## Findings

- **Confirmed:** Web apps recorded **4,095 requests**, **2,032 HTTP 4xx responses (49.62%)**, and **zero HTTP 5xx responses**. HTTP 2xx responses totaled 2,063. Four running apps had 100% HTTP 4xx responses in their recorded traffic.
- **Confirmed:** Notification Service and Labor Pool traffic was entirely HTTP 404; PMM traffic was entirely HTTP 401. Audit Log recorded 287 HTTP 404 responses and one other HTTP 4xx response. Successful business transactions cannot be inferred from their low average response times.
- **Inferred:** The roughly 287–288 requests per day seen across several apps are consistent with periodic probes. Request paths and callers were not examined, so probe traffic and user impact remain unverified.
- **Confirmed:** Hand Hygiene had the highest 24-hour average web-app response time, 321 ms. Its highest five-minute average was 1.37 seconds. These values cover all recorded responses, including HTTP errors.
- **Confirmed:** Among plans returning CPU and memory data, mean CPU was 13.77–22.82%; the highest five-minute average CPU was 56.20% on Audit Log. Mean memory was 70.78–76.81%; the highest five-minute average memory was 82.80% on Portal. All returned HTTP queue averages were zero. These rollups cannot rule out shorter spikes.
- **Unknown:** p95/p99 latency, dependency timings, exceptions, detailed request causes and end-to-end availability could not be verified. No Application Insights components were returned by subscription inventory, and the aggregated HTTP log query was blocked by Conditional Access (AADSTS53003).

## Web-app request performance

| Application | Current state | Requests | HTTP 4xx | 4xx rate | HTTP 5xx | Avg response (ms) | Highest 5-min avg (ms) |
|---|---|---:|---:|---:|---:|---:|---:|
| app-portal-prod-ncus | Running | 2,031 | 305 | 15.02% | 0 | 201.3 | 1,145.0 |
| app-hand-hygiene-prod-ncus | Running | 517 | 289 | 55.90% | 0 | 321.5 | 1,368.0 |
| app-HHS-prod-ncus | Running | 397 | 288 | 72.54% | 0 | 146.2 | 918.0 |
| app-audit-log-prod-ncus | Running | 288 | 288 | 100.00% | 0 | 69.6 | 1,305.0 |
| app-labor-pool-prod-ncus | Running | 288 | 288 | 100.00% | 0 | 37.0 | 396.0 |
| app-notification-service-prod-ncus | Running | 287 | 287 | 100.00% | 0 | 26.0 | 348.0 |
| app-PMM-prod-ncus | Running | 287 | 287 | 100.00% | 0 | 38.0 | 333.0 |
| app-medicaid-prod-ncus | Stopped | 0 | 0 | N/A | 0 | No data | No data |
| app-legacy-docs-prod-ncus | Stopped | 0 | 0 | N/A | 0 | No data | No data |
| app-ora-prod-ncus | Stopped | 0 | 0 | N/A | 0 | No data | No data |

The stopped apps are ORA, Legacy Docs and Medicaid. Their state is a current observation; their entire 24-hour state history was not queried. Azure reported zero requests and zero app working-set memory over this window, and no response-time observations.

## App resource consumption

| Application | Total app CPU (seconds) | Avg app memory (MiB) | Highest 5-min avg memory (MiB) | Data in (MiB) | Data out (MiB) |
|---|---:|---:|---:|---:|---:|
| app-portal-prod-ncus | 141.31 | 118.0 | 145.1 | 3.69 | 1.17 |
| app-hand-hygiene-prod-ncus | 76.82 | 84.9 | 127.7 | 0.75 | 1.40 |
| app-HHS-prod-ncus | 87.65 | 117.7 | 151.6 | 0.48 | 0.29 |
| app-audit-log-prod-ncus | 507.17 | 102.4 | 125.8 | 0.25 | 0.09 |
| app-labor-pool-prod-ncus | 47.50 | 64.3 | 96.9 | 0.25 | 0.08 |
| app-notification-service-prod-ncus | 61.28 | 77.2 | 88.2 | 0.27 | 0.07 |
| app-PMM-prod-ncus | 46.77 | 39.9 | 56.1 | 0.24 | 0.18 |
| app-medicaid-prod-ncus | 0.00 | 0.0 | 0.0 | No data | 0.00 |
| app-legacy-docs-prod-ncus | 0.00 | 0.0 | 0.0 | No data | 0.00 |
| app-ora-prod-ncus | 0.00 | 0.0 | 0.0 | No data | 0.00 |

CPU seconds measure accumulated application CPU time. Plan CPU percentages below measure worker utilization and should not be treated as per-app CPU percentages. Working-set memory is converted from returned bytes using 1 MiB = 1,048,576 bytes. [Microsoft App Service metric definitions](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-web-sites-metrics).

## App Service plan utilization

| Plan | SKU / current workers | Sites | Avg CPU | Highest 5-min avg CPU | Avg memory | Highest 5-min avg memory | Highest 5-min avg HTTP queue |
|---|---|---:|---:|---:|---:|---:|---:|
| asp-asp-hhs-prod-ncus-prod-ncus | B1 / 1 | 1 | 15.42 | 40.00 | 76.00 | 79.80 | 0.00 |
| asp-asp-hhs-test-ncus-test-ncus | B1 / 1 | 0 | No data | No data | No data | No data | 0.00 |
| asp-asp-pmm-prod-ncus-prod-ncus | B1 / 1 | 1 | 21.26 | 42.80 | 72.45 | 79.60 | 0.00 |
| asp-audit-log-prod-ncus | B1 / 1 | 1 | 22.82 | 56.20 | 76.40 | 78.80 | 0.00 |
| asp-func-dlq-fc-prod-ncus | FC1 / 0 | 1 | No data | No data | No data | No data | 0.00 |
| asp-hand-hygiene-prod-ncus | B1 / 1 | 1 | 20.13 | 40.20 | 74.89 | 78.40 | 0.00 |
| asp-labor-pool-prod-ncus | B1 / 1 | 1 | 18.34 | 41.60 | 73.80 | 82.20 | 0.00 |
| asp-legacy-docs-prod-ncus | B1 / 1 | 1 | 13.77 | 42.00 | 70.78 | 75.40 | 0.00 |
| asp-medicaid-prod-ncus | B1 / 1 | 1 | 15.52 | 40.80 | 73.00 | 77.00 | 0.00 |
| asp-notification-service-prod-ncus | B1 / 1 | 1 | 20.57 | 41.80 | 74.18 | 77.20 | 0.00 |
| asp-ora-prod-ncus | B1 / 1 | 1 | 17.40 | 40.00 | 71.96 | 76.80 | 0.00 |
| asp-portal-prod-ncus | B1 / 1 | 1 | 18.16 | 45.20 | 76.81 | 82.80 | 0.00 |

CPU and memory columns are percentages. The B1 plans each have one current worker. The HHS test-named plan has zero sites; the Flex Consumption plan has no returned plan CPU/memory samples. No data is not zero. Stopped applications can coexist with an allocated App Service plan. [Microsoft App Service plan metric definitions](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-web-serverfarms-metrics).

## Function and static web app

- **Confirmed:** `func-dlq-processor-internal-prod-ncus` is currently Running. Both on-demand and always-ready execution counters sum to **0**, with 288 five-minute values each. Returned function CPU and memory values are also zero. Function execution latency and execution failures were not available from the collected metrics; zero executions do not demonstrate processing health.
- **Confirmed:** `swa-portal-prod-ncus` recorded **10,045 site hits**. BytesSent totaled **545.82 MiB across 125 populated five-minute intervals**; remaining intervals had no values. Site errors, integrated-function hits/errors, CDN request count, CDN latency and CDN HTTP error metrics returned no values. Do not interpret their absence as zero errors or zero latency. Documented Total aggregation for CDN metrics was also checked. [Static Web Apps metrics](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-web-staticsites-metrics).
- Site hits, backend HTTP requests and function executions measure different layers and are not added together.

## Evidence, method and validation

- Source: live Azure CLI account/resource inventory, web-app and function lists, App Service plan list, Azure Monitor metric definitions and metric values. Existing signed-in context matched the requested enabled subscription; tenant and account identifiers are omitted from deliverables.
- Every metric query used the explicit subscription and resource scope, with the same 24-hour UTC window. Requests/errors/CPU time/bytes use Total aggregation at five-minute intervals. Reported 24-hour averages are Azure-provided P1D Average values, not an average of five-minute response averages. Peaks are maxima of five-minute averages, not individual request maxima or percentiles.
- All 10 web apps returned 288 request-count and HTTP-error intervals. HTTP 2xx + 3xx + 4xx + 5xx totals reconcile to Requests for each app. Portal request/error totals were independently checked using a single 24-hour aggregate: 2,031 / 305 / 0.
- All collected metric response time ranges and point timestamps were checked. All returned per-metric error codes indicate Success. Sparse and empty series remain explicit; missing samples are not replaced with zero.
- Response-time samples: Portal, Notification Service and PMM each returned 287 populated five-minute intervals; the other running web apps returned 288. Three stopped apps returned no response-time samples.
- The local CLI rejected FULL interval syntax; PT24H succeeded and Azure returned P1D. The log-query extension was unavailable and was not installed. The documented Logs Query API was attempted, but token issuance was blocked by Conditional Access at 2026-09-05 05:42:05 UTC. No log results or application payloads were retrieved. [Microsoft Logs Query API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/api/request-format).
- No load test, end-user synthetic test, dependency investigation, incident root-cause analysis or availability SLA assessment was performed. No cross-subscription monitoring resources were searched. Inventory is limited to resources visible to the signed-in account.

Example metric query used (substitute an observed app name):

```powershell
az monitor metrics list --subscription dt-prd-app-oeqrq2jxadm36 --resource app-portal-prod-ncus --resource-group rg-spoke-appdev-prd-4fhxtyumb5wlq --resource-type Microsoft.Web/sites --metric Requests Http4xx Http5xx --aggregation Total --start-time 2026-09-04T05:40:00Z --end-time 2026-09-05T05:40:00Z --interval PT5M --output json
```

## Recommended follow-up

**Recommendation:** Verify whether the regular HTTP 404/401 traffic is from configured probes, and confirm intended authenticated application routes. Review memory trends against a normal baseline before considering capacity changes. Use an approved Log Analytics access path to inspect aggregate request latency and response causes; do not change Conditional Access policies merely to run this report.

**Execution and rollback:** This was read-only Azure discovery. No Azure resource, delivery system, security policy or application configuration was changed. No rollback is required. Any remediation would require a separately scoped and authorized change plan.

## Local deliverables

- `2026-09-05-111000-dt-prd-app-performance-24h.md`: this report.
- `2026-09-05-111000-dt-prd-app-performance-24h-summary.json`: app-level summary.
- `2026-09-05-111000-dt-prd-app-performance-24h-data.json`: sanitized metric definitions and five-minute / 24-hour observations, including coverage gaps and the log-query limitation.
