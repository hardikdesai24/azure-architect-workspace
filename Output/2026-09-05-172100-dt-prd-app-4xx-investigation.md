# Application HTTP 4xx investigation

**Finding:** Azure App Service Always On requests are the leading explanation for the recurring HTTP 404 and HTTP 401 responses. The exact historical request path, caller and application rejection reason remain **Inferred**, because detailed HTTP logs could not be queried.

## Objective and scope

Investigate the 4xx responses in the performance report for `dt-prd-app-oeqrq2jxadm36`. Historical metrics cover **4 September 2026 05:40 to 5 September 2026 05:40 UTC**, or **4 September 11:10 to 5 September 11:10 IST**. Current configuration observations were collected **5 September 11:51–11:54 UTC**. Current settings are not proof of unchanged historical configuration.

The seven running apps are in resource group `rg-spoke-appdev-prd-4fhxtyumb5wlq`. The existing signed-in Azure context matched the requested enabled subscription. HTTP diagnostic settings point to the central `mercyhealth-log-analytics` workspace in another subscription. The attempted central query was restricted to the original subscription, seven applications and original 24-hour window.

## Confirmed evidence

- All seven apps currently have **Always On enabled**.
- All seven currently have **no App Service Health Check path configured**.
- Microsoft documents that Always On sends a **GET to the application root every five minutes**, equivalent to 288 scheduled requests in 24 hours. [App Service configuration](https://learn.microsoft.com/en-us/azure/app-service/configure-common#configure-general-settings).
- The historical metrics show almost exactly one recurring 404 or 401 per five-minute interval:

| Application | Recurring status | Total | Five-minute intervals with exactly one | Intervals with zero | Intervals with more than one |
|---|---:|---:|---:|---:|---:|
| Portal | 404 | 287 | 283 | 3 | 2 |
| Notification Service | 404 | 287 | 287 | 1 | 0 |
| Hand Hygiene | 404 | 285 | 285 | 3 | 0 |
| Audit Log | 404 | 287 | 287 | 1 | 0 |
| PMM | 401 | 287 | 287 | 1 | 0 |
| Labor Pool | 404 | 288 | 288 | 0 | 0 |
| HHS | 404 | 286 | 286 | 2 | 0 |

Each application has 288 metric intervals. The two Portal intervals with more than one 404 contain four responses in total. These recurring-status counts do not cover every 4xx response.

- PMM currently has **built-in App Service authentication disabled**, verified through the Auth Settings V2 read endpoint. This makes the built-in platform authentication layer an unlikely current source of its historical 401s, subject to the historical-state caveat. [Microsoft API reference](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/get-auth-settings-v-2?view=rest-appservice-2025-03-01).
- All seven apps currently enable HTTP logging and have `AppServiceHTTPLogs` diagnostics enabled to **`mercyhealth-log-analytics`**. The subscription-local workspace inspected in the earlier report is not the configured HTTP-log destination for these apps.
- The central HTTP-log query failed at **2026-09-05 11:53:16 UTC** with **AADSTS53003**, a Conditional Access token-issuance block. It returned no application log rows.
- One unauthenticated GET to each app's default root URL, with response bodies left unread, returned **403** at **11:54:09–11 UTC**. Every app has a deny-by-default access policy, an allow rule labeled `APIM` or `apim-prod`, and a final deny-all rule. The direct checks therefore do not reproduce the historical 404/401 path. Those seven checks occurred after the original reporting window.

## Leading explanation

| Status pattern | Inferred reason | What is still needed for confirmation |
|---|---|---|
| Recurring 404 on six apps | Always On reaches `/`, where the application likely has no matching GET route or deliberately returns 404. | HTTP logs identifying `GET /`, the Always On caller and status 404. Application route configuration would distinguish an absent route from deliberate rejection. |
| Recurring 401 on PMM | An unauthenticated keep-alive request likely reaches application authentication logic and receives 401. | HTTP logs linking the 401s to Always On and `/`, followed by review of the application's authentication middleware or sanitized reason codes. The exact missing/invalid credential condition is not established. |
| Other 4xx responses | May reflect application requests, authentication failures or other probes. | Aggregate HTTP logs by safe route class and status, followed by targeted analysis if authorized. |

The frequency and settings support a specific Always On hypothesis. They do not prove that every error was a probe, that no real users were affected, or that the business application was healthy.

## Risk and business impact

The raw 49.62% HTTP 4xx rate combines requests of different purposes. If the recurring responses are Always On requests, the aggregate rate substantially overstates the failure rate of business traffic. Business-request success rates remain unknown until probe traffic is identified. No HTTP 5xx responses appeared in the original web-app metrics.

## Recommended next action

Run `queries/kql/app-service-4xx-probe-diagnosis.kql` through an approved access path to **`mercyhealth-log-analytics`**, replacing the subscription placeholder with the ID of `dt-prd-app-oeqrq2jxadm36`. The query limits output to aggregate counts, status, method, known probe paths and caller categories. It excludes client identities, IP addresses, request query strings and payloads.

**Acceptance criteria:** the dominant historical 404/401 groups identify `GET /` and caller class `AlwaysOn`. If they do not, investigate the actual safe route/caller groups rather than assuming the hypothesis is correct. Application code or sanitized authentication events are needed to establish why PMM rejects the request.

**Conditional remediation:** if confirmed and consistent with the application's design, consider a minimal root keep-alive handler with a 200 response, while preserving authentication on business APIs. Design an explicit health endpoint separately if operational health checks are required. Do not disable Always On, weaken API authentication or widen network access just to remove 4xx counts. Implementation requires code review, appropriate non-production validation and separately authorized production execution. No change plan has been executed.

## Validation, limitations and execution

- Completed: read-only context verification, seven configuration checks, diagnostic destination discovery, PMM Auth Settings V2 verification, seven access-rule checks, seven body-free root status checks, and historical metric-pattern calculations.
- Not completed: successful HTTP-log query, request-level causality, application source-code review, historical configuration-change review or production remediation.
- The Front Door profile-list command required the absent `cdn` extension and stopped without installation. Front Door probe settings were not assessed. This does not change the independent Always On configuration and cadence evidence.
- Azure configuration, authentication policy and network rules remain unchanged. No software was installed. No credentials or request bodies were retrieved. Ordinary status-check requests may appear in later telemetry.
- Rollback is not applicable to this read-only investigation. Preserve current controls and use an approved log-access path for confirmation.

## Evidence files

All files below share prefix `2026-09-05-172100-dt-prd-app-4xx-` in `Output/`:

- `config.json`: Always On, health-check path and logging flags.
- `patterns.json`: historical five-minute status-count distribution.
- `diagnostics.json`: enabled HTTP logs and central workspace name.
- `pmm-auth.json`: projected non-secret PMM authentication settings.
- `log-query.json`: sanitized central log-query failure.
- `root-checks.json`: status-only direct GET observations.
- `access.json`: access-rule names, priorities, actions and default action, with addresses omitted.

Original metric evidence: `Output/2026-09-05-111000-dt-prd-app-performance-24h-data.json`.
