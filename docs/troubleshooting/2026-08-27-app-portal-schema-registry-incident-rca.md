# Root Cause Analysis: Production portal Schema Registry authorization crash loop

## Document control

| Field | Value |
|---|---|
| Incident date | 2026-08-27 |
| Environment | Production |
| Application | `app-portal-prod-ncus` |
| Resource group | `rg-spoke-appdev-prd-4fhxtyumb5wlq` |
| Subscription alias | `dt-prd-app-oeqrq2jxadm36` |
| Region | North Central US |
| App Service plan | `asp-portal-prod-ncus` — Basic B1, one worker |
| Incident window | 2026-08-27 10:51:53–13:30:37 UTC |
| Post-recovery validation window | 2026-08-27 13:30:38–14:30:00 UTC |
| RCA status | Evidence-backed RCA; application-source confirmation items remain open |
| Prepared | 2026-08-27 |
| External changes made by this document | None |

> **Critical finding:** The application did not first restart and then randomly select a different identity. A Schema Registry authorization failure occurred immediately before the first confirmed process exit. The unhandled Promise rejection terminated the main application process with exit code 1; App Service then restarted the container. The same deterministic credential and initialization path repeated, producing a 16-exit crash loop.

## Executive summary

The production portal became slow and its post-Entra-login application bootstrap failed because the application repeatedly crashed while initializing its Event Hubs Schema Registry dependency.

The production code used `DefaultAzureCredential`. The available evidence indicates with high confidence that the credential chain selected an environment-backed service principal, `spn-fabric-legacy-docs`, before reaching managed identity. This is expected credential-chain behavior when the environment credential is completely configured: `EnvironmentCredential` is evaluated before `ManagedIdentityCredential`, and the chain stops after the first credential successfully obtains a token.

The service principal could authenticate to Microsoft Entra ID and receive an Event Hubs access token, but it had no applicable data-plane role granting `SchemaGroupRead` and `SchemaRead`. Authentication therefore succeeded and authorization failed later at Schema Registry. `DefaultAzureCredential` did not fall back to managed identity after that RBAC rejection because token acquisition had already succeeded.

The Schema Registry call failed in `getSchemaByVersion`, propagated through `createEventHubProducerDependencies` and `getCachedDependencies`, and reached the runtime boundary as an unhandled Promise rejection. At 10:51:53 UTC the main container exited with code 1. App Service stopped and recreated the site container. Because neither credential resolution nor error handling had changed, the same failure recurred after restart. Sixteen exit-code-1 events were confirmed through 13:26:46 UTC.

The recovery release completed at 13:30:37 UTC and replaced the ambiguous production credential chain with explicitly targeted `ManagedIdentityCredential` instances. Post-release sign-in evidence showed the intended user-assigned managed identities being used. From 13:30:38 through 14:30 UTC, there were no Schema Registry authorization signatures, no unhandled Promise signatures, and no further container exits.

Identity attribution to the service principal is **high confidence**, based on its successful Event Hubs token acquisitions during the incident, its lack of applicable RBAC, the incident-team account of the App Service environment configuration, and the documented credential-chain order. The exact principal embedded in the first 10:51 request was not exposed in the count-only application-log query and remains an application-telemetry confirmation item.

## Objective

Determine:

1. Why the application container restarted.
2. Why `DefaultAzureCredential` selected an environment credential instead of the intended managed identity.
3. Why the Schema Registry authorization exception terminated the application.
4. Whether Azure platform health, capacity, deployment, configuration, or a manual restart initiated the incident.
5. Which corrective controls are required to prevent recurrence.

## Scope

### In scope

- Production App Service application and plan behavior.
- App Service platform and console telemetry.
- Event Hubs and Schema Registry identity/RBAC path.
- Service-principal and managed-identity sign-in evidence.
- Deployment history, Azure Activity Log, Resource Health, and Service Health.
- Runtime behavior relevant to unhandled Promise rejections.
- Recovery validation and prevention recommendations.

### Out of scope

- Retrieval of secret values, tokens, connection strings, or application payloads.
- Production mutations, RBAC changes, secret rotation, scaling, or deployment.
- Application-source changes; the application source was not available in this repository.
- Exact impacted-user count; no user-level dataset was retrieved.

## Active context and observation time

Azure observations were made read-only against the explicitly scoped production subscription alias `dt-prd-app-oeqrq2jxadm36`. The active CLI default subscription was not relied upon. Critical health state was last observed at 2026-08-27 14:34:12 UTC. Incident telemetry covered 09:00–13:30 UTC, with focused post-recovery validation through 14:30 UTC.

No secret values, raw tokens, tenant IDs, subscription IDs, principal object IDs, user email addresses, or application message bodies are recorded in this RCA.

## Customer and business impact

### Confirmed

- Microsoft Entra interactive sign-in could complete, but the portal's internal application bootstrap/session path failed after sign-in.
- The only production worker repeatedly terminated, so there was no second healthy instance to absorb traffic.
- The application produced elevated latency and HTTP errors during the crash loop.
- The initial broad investigation window recorded 1,148 requests, including 451 HTTP 4xx and 24 HTTP 5xx responses.
- Ten five-minute intervals had average response times above 50 seconds. The highest five-minute average was 203.77 seconds, with a maximum observed request duration of 345.87 seconds.

### Unknown

- Exact number of users and transactions affected.
- Whether every route depended on the failed Schema Registry initialization or only routes sharing the affected dependency/bootstrap path.
- Whether any audit events were delayed or lost. This must be checked against the application's audit-delivery requirements without retrieving sensitive event bodies.

### Business impact statement

The incident caused a production availability and performance degradation. Users could reach the identity-provider sign-in flow, but successful Entra authentication did not guarantee a usable application session. The single-worker topology converted a process-level dependency failure into an application-wide outage pattern.

## Detection

The incident was initially detected through user reports of slow portal behavior and failed internal authentication after Entra sign-in. Broad metrics showed latency, HTTP errors, and high plan utilization, but those symptoms did not identify the initiating event.

The decisive detection signal was the application error:

```text
Uncaught (in promise) RestError: Authorization failed for specified action: SchemaGroupRead,SchemaRead
```

The accompanying stack identified the failure path:

```text
getSchemaByVersion
createEventHubProducerDependencies
getCachedDependencies
```

App Service platform logs then established that the main container exited with code 1 immediately after this error class and that App Service restarted the site.

## Incident timeline

All timestamps are UTC on 2026-08-27.

| Time | Classification | Event and evidence |
|---|---|---|
| 03:09:06 | **Confirmed** | The application container instance that later failed started. |
| 10:51 | **Confirmed** | Console-log classification found one unhandled-Promise signature and one Schema Registry authorization signature. No out-of-memory or termination-signal signature was present. |
| 10:51:53 | **Confirmed** | App Service platform log: the main application container finished with exit code 1. |
| 10:51:53–10:51:59 | **Confirmed** | Platform logs show container termination, stop, deletion, and `Site container ... terminated. Stopping the entire site.` The site entered stopped state. |
| 10:52:39 | **Confirmed** | The App Service managed-identity sidecar started as part of site recovery. |
| 10:52:56–10:52:57 | **Confirmed** | The built-in Node 22 application image started and warm-up began. |
| 10:53:13 | **Confirmed** | First service-principal Event Hubs token acquisition visible in the supplied sign-in export. Result type 0 means the token was issued. This timestamp may reflect log timing, aggregation, or token reuse and is not direct proof of the principal on the 10:51 request. |
| 10:57:54–13:26:46 | **Confirmed** | Fifteen additional exit-code-1 events occurred. Each exit minute also contained both the unhandled-Promise and Schema Registry authorization signatures. |
| 12:49–13:32 | **Confirmed** | Further successful Event Hubs token acquisitions were recorded for `spn-fabric-legacy-docs` during the incident/recovery boundary. |
| 13:05:44 | **Confirmed** | A supplied application error recorded the unhandled Schema Registry authorization exception. |
| 13:05:45 | **Confirmed** | The platform recorded exit code 1 one second after the supplied error. |
| 13:30:24 | **Confirmed** | Recovery deployment began. |
| 13:30:37 | **Confirmed** | Recovery deployment completed and became active. It explicitly targeted managed identities instead of using the default credential chain. |
| 13:32:10 | **Confirmed** | Last service-principal Event Hubs token acquisition visible in the supplied export. It is close to the deployment boundary and may represent an in-flight request or token/log timing. |
| 13:37:27 | **Confirmed** | First post-release Event Hubs token acquisition by `uai-evh-audit-logs-prod`. |
| 13:39:19 | **Confirmed** | First post-release Event Hubs token acquisition by `uai-evhns-schema-contributor-prod`. |
| 13:30:38–14:30:00 | **Confirmed** | No unhandled-Promise signature, Schema Registry authorization signature, out-of-memory signature, or App Service exit event was observed. |
| 14:34:12 | **Confirmed** | Resource Health reported the application as Available. |

### Confirmed exit-code-1 events

The platform lifecycle query returned exactly 16 main-container exits:

```text
10:51:53  10:57:54  11:01:28  11:06:06
11:17:21  11:49:07  11:52:54  12:45:44
12:49:30  12:57:39  13:01:35  13:05:45
13:10:27  13:18:09  13:21:57  13:26:46
```

## Evidence collected

| Evidence source | Scope and time range | Observation | Interpretation |
|---|---|---|---|
| App Service platform logs | Application, 09:00–13:30 UTC | Sixteen main-container exits with code 1 and corresponding stop/delete/start lifecycle events | **Confirmed:** the process exited and App Service subsequently restarted it |
| App Service console logs, count-only classification | Application, focused around each exit | Every exit minute contained one unhandled-Promise and one Schema Registry authorization signature | **Confirmed:** the same exception class was temporally coupled to every crash; content retrieval was deliberately minimized |
| Application error supplied for 13:05:44 | Affected dependency path | `SchemaGroupRead,SchemaRead` authorization failure was uncaught; stack reached schema dependency construction/cache | **Confirmed:** the exception was unhandled in the observed path |
| Microsoft Entra service-principal sign-in export | Event Hubs resource, incident window | `spn-fabric-legacy-docs` received tokens successfully; result type was 0 | **Confirmed:** authentication succeeded; this does not prove RBAC authorization |
| Azure RBAC inventory | Subscription, resource group, Event Hubs namespace/entities | No applicable Schema Registry data-plane role was found for the service principal | **Confirmed:** the service principal lacked the required authorization at the inspected scopes |
| Managed-identity RBAC inventory | Schema Registry scope path | `uai-evhns-schema-contributor-prod` had Schema Registry Contributor; assignment pre-dated the incident | **Confirmed:** the intended schema identity already had the required data actions; this was not a propagation delay |
| Post-release sign-in export | Event Hubs resource, after 13:30:37 UTC | Intended audit and schema user-assigned identities began acquiring tokens | **Confirmed:** identity usage changed after the recovery release |
| App Service metrics | Around first crash and wider incident | Memory and CPU did not show an OOM or saturation trigger before the first exit; CPU increased materially during the restart loop | **Confirmed:** capacity pressure amplified impact but did not initiate the first process exit |
| Activity Log and deployment history | App, plan, identity/config operations | No restart command, configuration/identity/RBAC write, scale operation, or application deployment preceded the first exit | **Confirmed:** no observed control-plane mutation initiated the crash |
| Resource Health and Service Health | Production resource/region | Resource Health was Available after recovery; no relevant Service Health event was returned | **Confirmed for queried scope:** no Azure service incident was found |
| Built-in App Service diagnostics | 09:30–13:30 UTC | Selected detectors returned no dataset; AppLens access returned 401 | **Unknown:** detector silence is not proof that no restart occurred; platform logs provide the authoritative lifecycle evidence |
| Official Azure Identity documentation | JavaScript credential-chain behavior | `EnvironmentCredential` precedes `ManagedIdentityCredential`; a successful token ends the chain | **Confirmed behavior:** selection was deterministic, not random |
| Official Node and Deno runtime documentation | Unhandled rejection behavior | Unhandled Promise rejection can propagate as an uncaught error and terminate the process | **Confirmed behavior:** consistent with the observed exit code 1; exact active handler/configuration remains unverified |

## Findings

### Confirmed findings

1. **The initial restart was caused by the application process exiting, not by an Azure-initiated restart.** The main container exited with code 1 at 10:51:53 UTC. App Service then stopped and recreated the site container.

2. **The Schema Registry authorization failure preceded the first confirmed restart.** The same minute contained the unhandled-Promise and `SchemaGroupRead,SchemaRead` authorization signatures.

3. **The failure repeated deterministically.** All 16 exit minutes contained both signatures. Restarting the container did not change the application's credential/configuration path, so the same initialization failed again.

4. **Authentication and authorization were separate outcomes.** The service principal obtained valid Event Hubs tokens but lacked the necessary Schema Registry data actions. Token issuance did not imply Schema Registry access.

5. **The intended schema managed identity was authorized before the incident.** `uai-evhns-schema-contributor-prod` already held Schema Registry Contributor. The incident was not caused by waiting for a newly created role assignment to propagate.

6. **The first crash was not initiated by CPU exhaustion, memory exhaustion, request queueing, or an OOM kill.** Immediately before the first exit, application memory was declining, CPU time was low, plan CPU was approximately 41%, plan memory was approximately 74%, and HTTP queue length was zero. No OOM or termination-signal signature was observed.

7. **High CPU and latency were consequences and amplifiers.** Plan CPU rose into the 88–97% range after the restart loop began. Repeated initialization/warm-up on a one-worker B1 plan increased latency and reduced recovery capacity.

8. **No relevant Azure control-plane action preceded the first exit.** No application deployment, configuration/identity/RBAC write, manual restart, scaling action, Auto-Heal action, platform health event, or planned maintenance event was found in the queried evidence.

9. **The recovery release stopped the crash signature.** No Schema Registry authorization error, unhandled-Promise signature, or container exit was observed during the one-hour post-release validation window.

### High-confidence inference

`DefaultAzureCredential` selected the environment-backed `spn-fabric-legacy-docs` credential before managed identity. This inference is supported by all of the following:

- The service principal successfully acquired Event Hubs tokens during the incident.
- It had no applicable Schema Registry RBAC role.
- The incident team reported a service-principal credential exposed to the application through Key Vault-backed App Service configuration, including the Azure client identifier setting.
- In the JavaScript Azure Identity chain, `EnvironmentCredential` is evaluated before `ManagedIdentityCredential`.
- The intended managed identities began acquiring tokens only after the recovery release explicitly selected them.

This should be confirmed from the application configuration and Azure Identity diagnostic logs without exposing the secret. Specifically, compare only the non-secret client identifier and credential-source diagnostics.

### Unknowns

- What first exercised or re-exercised the schema-dependent initialization path at 10:51 UTC. Candidate triggers include dependency-cache expiry, a particular request, lazy initialization, or a configuration/reference refresh. There was no corresponding control-plane change in the inspected Activity Log.
- Whether the exact 10:51 Schema Registry request used the service principal, a cached token originally acquired earlier, or another principal. The surrounding sign-ins make the service principal the leading attribution, but the count-only console query did not expose the principal.
- Whether the runtime terminated solely through its default unhandled-rejection behavior or whether an application-level global rejection handler explicitly called an exit function. Source/startup configuration is required to distinguish these.
- Whether a rejected Promise remained cached in `getCachedDependencies`, increasing the probability of repeated failure after initialization. The stack suggests this possibility, but source inspection is required.
- Why a service-principal environment credential was present in the production application and which supported dependency still requires it.
- Exact user and audit-delivery impact.

## Root cause

### Primary technical root cause

The production application used the broad `DefaultAzureCredential` chain for a workload that required a specific user-assigned managed identity. A complete environment-based service-principal credential was available to the process. Because `EnvironmentCredential` precedes `ManagedIdentityCredential`, the environment credential successfully acquired the token and ended credential-chain evaluation. The selected service principal lacked the Event Hubs Schema Registry data-plane permissions required by `getSchemaByVersion`.

### Process-termination root cause

The resulting authorization error was not handled at the Schema Registry dependency boundary. The rejected Promise propagated through dependency creation/cache and reached the runtime boundary. Consistent with Node 22 and Deno unhandled-rejection behavior, the runtime terminated the main process with exit code 1.

### Restart-loop mechanism

App Service correctly treated the terminated main container as failed and restarted the site container. The restart recreated the same code and credential environment, so it repeated the same deterministic credential selection and authorization failure. This created a crash loop rather than recovery.

### Causal chain

```text
Environment-backed service-principal credential is available
    -> DefaultAzureCredential evaluates EnvironmentCredential first
    -> service principal obtains a valid Event Hubs token
    -> Schema Registry rejects SchemaGroupRead/SchemaRead
    -> getSchemaByVersion Promise rejection is not handled
    -> runtime terminates the main process with exit code 1
    -> App Service restarts the only worker
    -> identical initialization and credential path repeats
    -> crash loop, latency, HTTP errors, and failed application bootstrap
```

## Why the behavior was deterministic, not random

`DefaultAzureCredential` does not choose randomly. It attempts credential types in a defined order and stops when one obtains a token. For the JavaScript library, `EnvironmentCredential` is ahead of `ManagedIdentityCredential`.

If the environment contained a complete service-principal credential, the sequence was:

1. `EnvironmentCredential` read the environment configuration.
2. It authenticated the service principal and obtained a valid token.
3. `DefaultAzureCredential` returned that token and did not evaluate managed identity.
4. Event Hubs Schema Registry evaluated the token's principal and rejected the requested data actions.
5. The credential chain did not retry with managed identity because this was a service authorization failure after successful authentication, not a failure to acquire a token.

The restart only made the identity selection appear random because a new process reran initialization. It did not create the initial identity switch. The evidence shows the authorization error immediately before the first restart.

The shared `AZURE_CLIENT_ID` name can also be misleading: it participates in environment-based service-principal configuration when the companion tenant/secret or certificate variables are present, and it can be used as a user-assigned managed-identity selector in other credential configurations. Using a single global variable without selecting an explicit credential class creates ambiguous intent.

## Contributing factors

1. **Ambiguous production authentication abstraction.** `DefaultAzureCredential` allowed credentials unrelated to the intended production identity to participate.

2. **Multiple attached/available identities.** The application had a system-assigned identity and several user-assigned identities, increasing the need for explicit, per-dependency selection.

3. **A secret-backed service-principal credential was available to the application.** This created an earlier successful credential in the default chain and retained the operational burden of a long-lived credential.

4. **Authorization-sensitive dependency initialization was not contained.** A permanent 403-style authorization failure escaped as an unhandled rejection instead of becoming a controlled dependency failure.

5. **The Schema Registry/audit dependency was coupled to application bootstrap/session behavior.** A downstream authorization problem impaired the user-facing application path.

6. **Single-worker Basic plan.** One process failure removed all serving capacity. Repeated warm-up drove plan CPU and latency higher.

7. **Insufficient restart-specific alerting.** User symptoms and aggregate metrics were noticed before the exit/error correlation was established.

8. **Diagnostic access gaps.** AppLens returned 401, and several built-in detectors returned null datasets. Platform and console logs were available, but investigation took longer because the most direct diagnostic surface was inaccessible.

9. **Potential rejected-Promise caching.** The `getCachedDependencies` frame suggests a rejected initialization result may have been cached or shared. This is an inference pending source review.

## Factors ruled out as initiating causes

| Candidate | Assessment | Evidence |
|---|---|---|
| User Entra sign-in failure | Ruled out as the primary cause | Interactive sign-in could complete; failure occurred in a service-to-service Schema Registry path |
| RBAC propagation delay | Ruled out | Intended schema identity's role assignment pre-dated the incident by many months |
| Manual restart | No evidence found | No restart operation preceded 10:51:53 in the inspected control-plane evidence |
| Application deployment | Ruled out for onset | Previous deployment was 2026-07-14; recovery deployment began only at 13:30:24 |
| App configuration or identity write | No evidence found | No relevant write appeared before the first exit in the inspected Activity Log |
| Azure platform/region incident | No evidence found | No relevant Service Health event; Resource Health was Available after recovery |
| Auto-Heal | No evidence found | No Auto-Heal action or supporting detector evidence was returned |
| Out-of-memory termination | Ruled out for first crash | No OOM signature; working set fell before exit; plan memory was not exhausted |
| CPU saturation | Ruled out for first crash; confirmed amplifier | CPU was not saturated before the first exit and increased during the crash loop |
| HTTP queue exhaustion | Ruled out for first crash | Queue length was zero |

## Resolution and recovery validation

### Resolution applied

The recovery application release replaced `DefaultAzureCredential` on the affected paths with explicitly targeted `ManagedIdentityCredential` instances:

- `uai-evhns-schema-contributor-prod` for Schema Registry operations.
- `uai-evh-audit-logs-prod` for audit Event Hub publishing.

The release completed at 13:30:37 UTC.

### Validation evidence

During 13:30:38–14:30:00 UTC:

- Schema Registry authorization signatures: 0.
- Unhandled-Promise signatures: 0.
- Out-of-memory signatures: 0.
- Main-container exit events: 0.
- Intended managed-identity token acquisitions were observed after deployment.
- HTTP 5xx returned to zero in the immediate post-release comparison.
- Average response time improved from an incident-period sample of 111.75 seconds to 5.55 seconds.

Generic `RestError` lines remained in console logs, but they were not accompanied by the Schema Registry authorization signature, an unhandled-Promise signature, or a container exit. They must be triaged separately and must not be counted as recurrence without those correlated signals.

### Recovery confidence

**High for stopping this crash loop.** The error and lifecycle signatures ceased immediately after explicit managed-identity selection, and intended identity sign-ins appeared.

**Not yet sufficient for long-term resilience.** The validation window was one hour, the plan remained a one-worker B1 tier, and source-level error containment had not been independently reviewed in this workspace.

## Corrective and preventive actions

Dates and owners below are deliberately not invented. The service owner and change authority must assign them.

### Completed during incident

| ID | Action | Status | Evidence |
|---|---|---|---|
| C-01 | Replace the affected production `DefaultAzureCredential` paths with explicitly targeted `ManagedIdentityCredential` instances | Completed | Recovery deployment completed at 13:30:37 UTC |
| C-02 | Validate post-release identity use | Completed | Intended schema and audit UAMIs acquired tokens after deployment |
| C-03 | Validate immediate crash-loop cessation | Completed | No schema/unhandled/exit signature through 14:30 UTC |

### Urgent follow-up

| ID | Recommendation | Owner | Due | Acceptance evidence | Change class |
|---|---|---|---|---|---|
| A-01 | Confirm every production Event Hubs and Schema Registry client constructs `ManagedIdentityCredential` with the intended UAMI selector; do not rely on an ambient global default | TBD | TBD | Source review plus non-production identity test and sanitized Azure Identity logs | Local code review; Class 3 to deploy |
| A-02 | Inventory why `spn-fabric-legacy-docs` credentials are exposed to this application. Remove the environment credential if not required | Application and identity owners, TBD | TBD | Dependency map and approved configuration diff | Class 3 production identity/configuration |
| A-03 | After dependency validation, rotate/revoke the service-principal credential that was available to the application and verify no other workload depends on it | Identity owner, TBD | TBD | Approved rotation record and dependency validation; no secret value captured | Class 3 identity/secret operation |
| A-04 | Replace shared/ambiguous identity variables with dependency-specific configuration names such as `SCHEMA_REGISTRY_MI_CLIENT_ID` and `AUDIT_EVENT_HUB_MI_CLIENT_ID` | Application owner, TBD | TBD | Configuration schema and deployment validation show a unique principal per client | Class 3 to deploy/configure |
| A-05 | Add local `try/catch` handling around schema lookup and producer initialization. Map authorization failure to a controlled readiness/dependency state, not an unhandled rejection | Application owner, TBD | TBD | Automated negative authorization test proves the process remains alive or shuts down gracefully by explicit policy | Class 3 to deploy |
| A-06 | Inspect `getCachedDependencies`; never retain a rejected initialization Promise indefinitely. Evict or replace rejected cache entries and use bounded retry only for transient failures | Application owner, TBD | TBD | Unit/integration tests for rejection, cache eviction, and recovery | Class 3 to deploy |
| A-07 | Define the policy for audit dependency failure. If audit is mandatory, fail requests in a controlled and observable manner; if asynchronous operation is permitted, buffer safely and protect ordering/durability | Security, compliance, and application owners, TBD | TBD | Approved decision record and failure-mode tests | Design approval; Class 3 to deploy |

### Near-term resilience and observability

| ID | Recommendation | Owner | Due | Acceptance evidence | Change class |
|---|---|---|---|---|---|
| A-08 | Add alerts for main-container exit code, restart count, the specific Schema Registry authorization signature, unhandled rejection, 5xx rate, latency, CPU, and memory | Operations owner, TBD | TBD | Alert test and linked runbook | Class 3 monitoring change |
| A-09 | Retain and correlate App Service platform logs, application logs, deployment markers, and identity sign-ins with a shared incident timestamp/correlation design | Operations/application owners, TBD | TBD | Query demonstrates error-to-exit-to-restart-to-identity correlation without sensitive payload retrieval | Class 3 diagnostic configuration if changes are needed |
| A-10 | Restore least-privilege diagnostic access to AppLens or document the supported alternative | Platform owner, TBD | TBD | On-call user can run approved read-only diagnostics | Potentially Class 3 RBAC |
| A-11 | Add a health/readiness endpoint that verifies process readiness and critical dependency state without exposing secrets or performing destructive writes | Application owner, TBD | TBD | Health endpoint tests and App Service health-check validation | Class 3 production configuration/deployment |
| A-12 | Add an identity smoke test to the deployment pipeline that verifies the principal used for Schema Registry and audit Event Hub operations | Delivery/application owners, TBD | TBD | Non-production pipeline fails on wrong principal or missing data action | Local/pipeline change; execution approval as applicable |
| A-13 | Enable sanitized Azure Identity diagnostics during controlled troubleshooting so the successful credential class is observable without logging tokens or secrets | Application/security owners, TBD | TBD | Logs record credential type and safe principal alias only | Class 3 production logging/configuration |

### Capacity and architecture follow-up

| ID | Recommendation | Owner | Due | Acceptance evidence | Change class |
|---|---|---|---|---|---|
| A-14 | Evaluate a Standard/Premium tier with at least two healthy instances, health checks, and autoscale against measured demand | Architecture/platform owners, TBD | TBD | Costed design, load test, failure test, and rollback plan | Class 3 capacity/availability change |
| A-15 | Confirm session state is externalized or otherwise safe across instance recycle and multi-instance operation | Application owner, TBD | TBD | Restart and multi-instance session-continuity test | Class 3 to deploy if remediation is required |
| A-16 | Separate capacity remediation from root-cause remediation. Do not treat scaling as a fix for wrong identity selection or unhandled errors | Architecture owner, TBD | TBD | Change plans explicitly identify which failure mode each action mitigates | Design control |

## Recommended implementation sequence

1. **Source and configuration confirmation:** identify every credential constructor and every production identity-related setting; confirm package/runtime versions and the exact unhandled-rejection handler behavior.
2. **Remove ambiguity:** use explicit managed-identity credentials and dependency-specific client-ID settings in all production Azure clients.
3. **Contain dependency failures:** catch authorization errors at the schema/audit boundary, prevent rejected-Promise cache poisoning, and implement the approved audit-failure policy.
4. **Test failure modes in non-production:** wrong principal, missing RBAC, token endpoint unavailable, Schema Registry 401/403, Event Hubs throttling, container recycle, and dependency recovery.
5. **Remove or rotate the legacy credential:** only after dependency analysis and an approved production change plan.
6. **Improve detection:** deploy correlated exit/error/identity alerts and restore supported diagnostic access.
7. **Address availability/capacity separately:** validate multi-instance readiness and then evaluate tier/instance changes with a cost and rollback plan.

## Validation and acceptance criteria

The incident should be considered fully remediated only when all applicable criteria are met:

- [ ] Production code uses an explicit credential class for every Azure-hosted dependency.
- [ ] Schema Registry calls use only `uai-evhns-schema-contributor-prod` or a formally approved replacement.
- [ ] Audit Event Hub publishing uses only `uai-evh-audit-logs-prod` or a formally approved replacement.
- [ ] No service-principal secret is exposed to the application unless a documented, approved dependency requires it.
- [ ] A missing/incorrect Schema Registry role produces a controlled error and does not create an unhandled Promise rejection.
- [ ] A rejected dependency-initialization Promise can recover after the dependency is restored.
- [ ] A container recycle does not change credential selection.
- [ ] A container recycle does not invalidate application sessions beyond the agreed service objective.
- [ ] No `SchemaGroupRead,SchemaRead` authorization errors occur during an agreed soak period.
- [ ] No unexpected exit-code-1 event occurs during the soak period.
- [ ] 5xx rate, response time, CPU, and memory remain within the agreed production baseline.
- [ ] Alerts fire for a staged negative test and link to a usable runbook.
- [ ] Audit-delivery integrity is reconciled for the incident window without exposing event contents.

Suggested minimum validation windows are one hour immediately after change, 24 hours under normal traffic, and one representative peak-traffic period. The service owner must define the final acceptance period.

## Rollback and recovery plan for follow-up changes

Any future production code, configuration, identity, RBAC, secret, monitoring, or capacity change requires an exact reviewed plan and explicit execution authorization.

### Application release rollback

- Retain the current explicitly targeted managed-identity release as the known recovered baseline.
- Roll back only to a build that also preserves explicit identity selection and controlled error handling.
- Do **not** restore the prior `DefaultAzureCredential` production behavior merely to match an older artifact.
- If a new remediation release regresses service, redeploy the recovered baseline, verify intended managed-identity sign-ins, and re-run the exit/error queries.

### Identity/configuration rollback

- Before removing or rotating the service-principal credential, document dependent workloads and preserve a separately authorized recovery path.
- If an unknown dependency breaks, restore only the minimum required credential reference for that dependency while keeping the portal's Event Hubs clients explicitly bound to managed identity.
- Never print or copy a credential value into tickets, logs, this repository, or chat.

### Emergency containment

A narrowly scoped temporary Schema Registry role for the actually used runtime identity could restore authorization, but it is not the preferred correction because it preserves ambiguous credential selection and a secret-backed identity. If considered, it requires Class 3 approval, an expiry/removal plan, and proof that scope is limited to the required schema group.

Scaling the plan may reduce user impact during a crash loop but cannot correct the identity or exception-handling defect. Treat it only as conditional containment after verifying session and multi-instance behavior.

## Approvals required

This RCA is a local documentation artifact and caused no Azure, Azure DevOps, Git remote, or delivery-system mutation.

The following follow-up work is Class 3 under the repository operating contract and requires current-state evidence, exact scope, impact analysis, preflight/validation results, rollback, and explicit final authorization:

- Production application deployment.
- App Service configuration or managed-identity changes.
- Service-principal credential removal, rotation, or revocation.
- RBAC changes.
- Diagnostic settings, alert rules, health-check configuration, scaling, tier, or instance-count changes.
- Production pipeline execution or release approval.

## Residual risk

| Risk | Current assessment | Required treatment |
|---|---|---|
| Other code paths still use `DefaultAzureCredential` | Unknown | Complete source/configuration inventory and negative identity tests |
| Legacy service-principal credential remains available | Unknown/current-state confirmation required | Dependency review followed by approved removal/rotation |
| Authorization failures can still terminate the process elsewhere | Unknown | Global source search plus fault-injection tests |
| Single-worker availability | Confirmed | Costed multi-instance design after session-state validation |
| Residual high CPU/memory after recovery | Observed initially | Establish a longer baseline; investigate independently if sustained |
| Generic `RestError` messages after recovery | Confirmed | Classify separately; do not conflate with this incident without matching signatures |
| Audit event loss/delay | Unknown | Metadata-only reconciliation aligned to compliance requirements |
| Limited direct diagnostics | Confirmed | Restore least-privilege access or document alternate queries |

## Lessons learned

- A token acquisition success answers “who authenticated,” not “what that principal is authorized to do.”
- Credential-chain fallback applies to credential acquisition failures; it does not provide RBAC fallback after a token is accepted by the target service.
- Production workloads with a known identity should use a specific credential implementation and an explicit identity selector.
- A platform restart can be a consequence of an application failure. Establish the error/exit/restart ordering before attributing the cause to the platform.
- Aggregate CPU and latency can be downstream symptoms of a crash loop. Inspect the first failure before treating saturation as the root cause.
- Noncritical or supporting dependencies must not be allowed to fail the whole process accidentally. If policy requires fail-closed behavior, it must still be controlled, observable, and testable.
- Single-worker plans magnify process failures into complete service unavailability.

## Evidence limitations

- AppLens was unavailable to the investigating identity with HTTP 401.
- Several built-in App Service detectors returned null datasets. This does not outweigh the explicit lifecycle events in platform logs.
- Application-log analysis used count-only classification to minimize sensitive-data retrieval; therefore the exact principal was not extracted from the 10:51 error event.
- The supplied sign-in export's first visible service-principal record was 10:53:13 UTC, after the 10:51:53 exit. Sign-in log timing, export scope, aggregation, and token caching can account for this, but it prevents a direct one-record attribution for the first request.
- Application source, startup command, package lock, and runtime flags were not available in this workspace. Exact code-line and handler-level conclusions remain open.
- No user-level or application-payload data was retrieved, so impacted-user count and audit-event reconciliation are unknown.

## Reproducible investigation approach

The following describes the query logic used. Keep the time range narrow and do not retrieve message bodies unless separately authorized.

1. **Platform lifecycle:** query `AppServicePlatformLogs` for the application and incident time range; count or project events containing main-container exit code, termination, stop, delete, start, and warm-up indicators.
2. **Console classification:** query `AppServiceConsoleLogs` by minute and calculate counts for `Uncaught (in promise)`, `SchemaGroupRead`, `SchemaRead`, `RestError`, out-of-memory indicators, and termination-signal indicators. Return counts and timestamps rather than full messages.
3. **Correlation:** join or compare exit minutes with console classification minutes. For this incident, every exit minute matched both the unhandled-Promise and schema-authorization categories.
4. **Metrics:** inspect `CpuTime`, `MemoryWorkingSet`, requests, HTTP status classes, response time, plan CPU/memory, and HTTP queue length around the first exit before reviewing later saturation.
5. **Control plane:** inspect Activity Log and deployment history for app configuration, identity, RBAC, restart, scale, deployment, Auto-Heal, and plan operations.
6. **Identity:** inspect service-principal and managed-identity sign-in metadata for the Event Hubs audience/resource; record principal alias, time, result, and resource only. Do not retrieve tokens.
7. **Authorization:** enumerate applicable role assignments from the narrowest target resource upward and verify the role definition's data actions.
8. **Health:** check Resource Health and Service Health for the incident time and region.
9. **Post-change:** repeat the error, exit, identity, HTTP, and performance checks over an agreed validation window.

## References

- [Credential chains in the Azure Identity library for JavaScript](https://learn.microsoft.com/en-us/azure/developer/javascript/sdk/authentication/credential-chains) — documents credential order, stop-on-token behavior, and production guidance.
- [Authentication best practices with the Azure Identity library for JavaScript](https://learn.microsoft.com/en-us/azure/developer/javascript/sdk/authentication/best-practices) — recommends a specific credential in production and demonstrates `ManagedIdentityCredential`.
- [Azure Identity client library for JavaScript](https://learn.microsoft.com/en-us/javascript/api/overview/azure/identity-readme?view=azure-node-latest) — credential types and Azure-hosted managed-identity support.
- [ManagedIdentityCredential class for JavaScript](https://learn.microsoft.com/en-us/javascript/api/%40azure/identity/managedidentitycredential?view=azure-node-latest) — explicit user-assigned identity selectors.
- [Node.js 22 `--unhandled-rejections` behavior](https://nodejs.org/download/release/v22.21.0/docs/api/cli.html#--unhandled-rejectionsmode) — default `throw` behavior for an unhandled rejection.
- [Deno program lifecycle](https://docs.deno.com/api/deno/about/) — unhandled-rejection propagation and program termination behavior.

## Final root-cause statement

**The production portal entered a crash loop because an unhandled Event Hubs Schema Registry authorization rejection terminated its main process. The available evidence indicates with high confidence that the authorization rejection occurred because the application used `DefaultAzureCredential`, which deterministically accepted an earlier environment-backed service-principal credential that could obtain a token but lacked Schema Registry data-plane rights. App Service then restarted the exited single container, reproducing the unchanged credential and exception path 16 times. Explicitly selecting the authorized managed identities stopped the error and exit sequence.**
