# App Service memory sizing assessment

**Recommendation:** Retain B1 for the current measured workload. Prepare a targeted capacity option for Portal, and reassess when sustained memory pressure, application symptoms, or forecast demand justify it. A subscription-wide upgrade is not supported by the observed memory trend alone.

Scope: `dt-prd-app-oeqrq2jxadm36`, resource group `rg-spoke-appdev-prd-4fhxtyumb5wlq`, North Central US, ten Linux App Service plans associated with the ten inventoried web apps. Each was confirmed as B1 with one worker and one site in the current review. The Function, static web app, and unused HHS test plan are excluded from this memory comparison.

Memory window: **2026-08-29 12:10 to 2026-09-05 12:10 UTC**, equivalent to 17:40 IST on those dates. Collection completed **2026-09-05 12:21:44 UTC**. The earlier performance window was 2026-09-04 05:40 to 2026-09-05 05:40 UTC; its CPU, HTTP, and application working-set findings must not be described as seven-day results.

## Confirmed evidence

Azure Monitor returned all 2,016 expected five-minute `MemoryPercentage` averages for each of ten plans, with successful metric status and no missing samples. The table shows the time average, nearest-rank P95, and highest value of those five-minute averages. These are plan measurements; the peak and P95 are not instantaneous memory readings. Application state refers to the earlier inventory, not continuous state tracking over seven days.

| Application / associated plan | Observed app state | Seven-day mean | P95 of five-minute averages | Highest five-minute average | Longest consecutive bins at or above 80% |
| --- | --- | ---: | ---: | ---: | ---: |
| Portal / `asp-portal-prod-ncus` | Running | 76.98% | 78.8% | 85.6% | 5 min |
| Audit Log / `asp-audit-log-prod-ncus` | Running | 76.78% | 78.6% | 81.4% | 10 min |
| HHS / `asp-asp-hhs-prod-ncus-prod-ncus` | Running | 76.29% | 78.2% | 82.4% | 5 min |
| Hand Hygiene / `asp-hand-hygiene-prod-ncus` | Running | 75.46% | 77.6% | 79.6% | 0 min |
| Notification / `asp-notification-service-prod-ncus` | Running | 75.05% | 77.0% | 81.4% | 5 min |
| Labor Pool / `asp-labor-pool-prod-ncus` | Running | 74.83% | 77.0% | 82.8% | 5 min |
| PMM / `asp-asp-pmm-prod-ncus-prod-ncus` | Running | 73.80% | 76.2% | 79.8% | 0 min |
| Medicaid / `asp-medicaid-prod-ncus` | Stopped | 73.40% | 75.4% | 80.0% | 5 min |
| ORA / `asp-ora-prod-ncus` | Stopped | 72.29% | 74.4% | 79.0% | 0 min |
| Legacy Docs / `asp-legacy-docs-prod-ncus` | Stopped | 72.15% | 74.8% | 79.2% | 0 min |

Only one five-minute bin reached 85% or higher, on Portal. No five-minute average reached 90%. Portal's seven rolling daily averages ranged from 76.66% to 77.41%, with the last day at 76.73%; they do not show a continuing upward trend.

In the **earlier 24-hour window**, running-app plan CPU averaged 15.4–22.8%, web-app HTTP 5xx counters were zero, and returned plan HTTP queue averages were zero. The running applications' average working sets were approximately 40–118 MiB. Plans whose applications were observed stopped still averaged approximately 71–73% memory. These observations do not prove the absence of brief exhaustion, restarts, or user-facing problems.

Microsoft documents that App Service system processes continue consuming resources even when applications are stopped, and that this overhead must be included in capacity planning. Consequently, the plan percentage cannot be attributed entirely to application code. [Microsoft performance FAQ](https://learn.microsoft.com/en-us/troubleshoot/azure/app-service/web-apps-performance-faqs)

## Interpretation and unknowns

**Inferred:** The consistently high baseline, small reported application working sets, and stable daily averages suggest that application growth is not the sole contributor to the plan memory percentage. The exact contribution of platform processes, application processes, containers, and caches is **unknown**; the measurements are not sufficient for a reliable subtraction or attribution.

**Unknown:** Out-of-memory events, recycling, per-process/container memory, request latency percentiles, and the workload expected at the next business peak. The previous query against the central `mercyhealth-log-analytics` workspace was blocked by Conditional Access (AADSTS53003), so detailed logs have not established or excluded memory-related failures. The five-minute aggregation can hide shorter spikes.

**Inferred from the separate 4xx investigation:** Repeated Always On requests are the leading explanation for most recurring 404/401 responses. That cause remains unconfirmed in request logs. The available evidence does not connect those responses to a need for more RAM.

## Capacity options

| SKU | CPU per worker | RAM per worker | Assessment |
| --- | ---: | ---: | --- |
| B1, current | 1 core | 1.75 GB | Retain for the measured workload while tracking pressure and expected demand. |
| B2 | 2 cores | 3.5 GB | First candidate for a straightforward memory increase within Basic. |
| P0v3 | 1 vCPU | 4 GB | Compare when extra memory and Premium scaling capabilities are valuable. |

Hardware values are from [Microsoft's Linux App Service pricing and specifications](https://azure.microsoft.com/en-us/pricing/details/app-service/linux/). Basic supports manual scaling; metric-based autoscale is available from Standard, and App Service automatic scaling from Premium v2 through v4. [Microsoft scaling comparison](https://learn.microsoft.com/en-us/azure/app-service/manage-automatic-scaling)

**Confirmed for Portal only:** The App Service plan selectable-SKU API listed B2 and P0v3 at **2026-09-05 12:19:14 UTC**. This is not a subscription-wide capacity or quota guarantee. Availability must be checked for any other selected plan and again before a change. The current commercial quote, negotiated pricing, and budget impact were not retrieved; no specific cost saving or cost estimate is claimed.

## Recommended decision criteria and next steps

1. Keep B1 at current demand. Use Portal as the first candidate for further memory diagnostics and a capacity pilot because it has the highest observed plan memory and the most web-app requests in the earlier report.
2. Use **85% or higher for 15–30 minutes**, a persistently rising baseline, verified memory-related restarts, or memory-correlated latency/queue growth as proposed reasons to bring an upgrade forward. These are suggested operating thresholds, not Azure service limits. An expected traffic increase can justify adding capacity before these thresholds are reached.
3. Before choosing a SKU, review the memory breakdown and restart evidence through an approved diagnostic access path, assess representative peak demand, and compare the regional B2 and P0v3 quote. If extra RAM is the only requirement, B2 is the initial candidate; Premium capabilities can justify P0v3 separately.
4. If a pilot is justified, prepare the exact plan change and approved maintenance window. Assess startup behavior, network dependencies, capacity availability, and cost before execution. Validate representative application transactions through the approved ingress, memory headroom, latency, queues, and restarts after warm-up and during a business peak.
5. Prepare rollback to the recorded B1 configuration only if the workload still fits and the capacity/features allow it. A rollback can also affect application availability and cannot be assumed safe during ongoing memory exhaustion. A larger single worker does not add a second application instance.

This is a sizing recommendation, not an executable deployment plan. No Azure settings or alerts were changed. Any production resize still requires a concrete plan, preflight validation, rollback assessment, and final authorization for the exact scope.

## Evidence and reproducibility

- [Sanitized seven-day metric series](2026-09-05-app-service-memory-sizing-7d.json)
- [Derived memory summary and daily averages](2026-09-05-app-service-memory-sizing-7d-summary.json)
- [Earlier 24-hour performance report](2026-09-05-111000-dt-prd-app-performance-24h.md)
- [4xx investigation](2026-09-05-172100-dt-prd-app-4xx-investigation.md)

Read-only metrics query used for each named plan:

```powershell
az monitor metrics list `
  --subscription dt-prd-app-oeqrq2jxadm36 `
  --resource <approved-plan-resource-id> `
  --metrics MemoryPercentage `
  --aggregation Average `
  --interval PT5M `
  --start-time 2026-08-29T12:10:00Z `
  --end-time 2026-09-05T12:10:00Z
```

Selectable SKU discovery used the documented read-only App Service plan `/skus` endpoint with API version `2025-05-01`. [Microsoft API reference](https://learn.microsoft.com/en-us/rest/api/appservice/app-service-plans/get-server-farm-skus?view=rest-appservice-2025-05-01)
