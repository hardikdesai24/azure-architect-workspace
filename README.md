# azure-architect-workspace

A daily working repository for **Azure architecture, engineering, operations, governance, and troubleshooting** — driven mainly through natural language in Codex, Cursor, or Claude Code on Windows, using **Azure CLI** (and Azure DevOps CLI where needed) with the signed-in user credentials.

This is **not** an application repository and **not** an IaC deployment repository. It holds the operating contract for AI agents and the durable artifacts they produce: assessments, audit exports, architecture diagrams, and session history. It is also **not** an autonomous production operator — agents investigate broadly and prepare changes, but do not mutate cloud or delivery systems without the authorization gates in [AGENTS.md](AGENTS.md).

---

## Table of contents

- [Start here: AGENTS.md](#start-here-agentsmd)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [What is in this repository](#what-is-in-this-repository)
- [Conventions for new artifacts](#conventions-for-new-artifacts)
- [Working agreements in brief](#working-agreements-in-brief)

---

## Start here: AGENTS.md

[AGENTS.md](AGENTS.md) is the operating contract for any AI agent working in this repo, and the best summary of how the workspace is meant to be used. Read it before running anything. Key sections:

| Section | Topic |
|---|---|
| [§1–2](AGENTS.md#1-role-and-mission) | Role, mission, and instruction priority |
| [§3](AGENTS.md#3-protected-operating-principles) | Protected principles: read first, don't guess cloud context, evidence over confidence, least privilege, no silent mutation |
| [§4](AGENTS.md#4-interpreting-natural-language-requests) | How natural-language verbs map to authorization ("check" vs. "deploy" vs. "delete") |
| [§5](AGENTS.md#5-change-authority-and-approval-gates) | Risk classes 0–4, approval gates, and stop conditions |
| [§7](AGENTS.md#7-tool-routing-policy) | Tool-routing policy — prefer Azure CLI / PowerShell / Resource Graph / KQL |
| [§8](AGENTS.md#8-data-plane-and-secret-boundaries) | Data-plane and secret boundaries |
| [§9](AGENTS.md#9-azure-architect-routine-work) | Routine architect workflows (discovery, incident, security, network, identity, cost, DR, drift) |
| [§12–16](AGENTS.md#12-bicep-standards) | Standards for Bicep, PowerShell, Azure CLI, KQL / Resource Graph, Azure DevOps |
| [§18](AGENTS.md#18-repository-artifact-locations) | Where artifacts belong |
| [§20–21](AGENTS.md#20-validation-matrix) | Validation matrix, rollback and recovery requirements |
| [§23](AGENTS.md#23-common-playbooks) | Playbooks for common requests |
| [§24–26](AGENTS.md#24-prohibited-behavior) | Prohibited behavior, completion criteria, first-use behavior |

---

## Prerequisites

| Requirement | Used for |
|---|---|
| Windows + PowerShell 7 | Primary shell; the workspace is Windows-first |
| Codex, [Cursor](https://cursor.com), or [Claude Code](https://claude.com/claude-code) | Interaction surface |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Interactive sign-in and all Azure control-plane work |
| Azure DevOps CLI extension (`az devops`) when needed | Azure DevOps read/write operations via CLI |
| Azure RBAC and Azure DevOps permissions | Access already granted to the signed-in user |

This workspace no longer ships repo-scoped MCP server configs for Cursor, Claude Code, or Codex. Agents should use Azure CLI / Azure PowerShell / local files instead.

## Setup

**1. Sign in interactively once with Azure CLI.** Use the same user that has access to the required Azure subscriptions and Azure DevOps organization:

```powershell
az login
az account show --output table
az account set --subscription '<subscription-id-or-name>'
```

If the Azure subscription or Azure DevOps organization is associated with a specific tenant, use `az login --tenant '<tenant-id>'`. Do not commit tenant or subscription IDs to this repository unless explicitly required and approved.

**2. Verify with read-only checks only.** Per [AGENTS.md §26](AGENTS.md#26-first-use-behavior-for-a-new-repository), never use a cloud or Azure DevOps *write* as a connection test:

```powershell
az account list --output table
az group list --output table
# Optional, when Azure DevOps CLI is configured:
# az devops project list --organization https://dev.azure.com/<org> --output table
```

### Do I need to authenticate every time?

Normally, no. Run `az login` once; Azure CLI stores a refresh token and obtains new short-lived access tokens when needed. You must sign in again only when the cached session is missing or invalidated—for example after `az logout`, credential-cache removal, account/tenant changes, token revocation, or a Conditional Access/MFA policy requiring reauthentication.

## What is in this repository

```text
AGENTS.md               # Operating contract for AI agents (read first)
chat-history/           # Durable per-session summaries
chat-conversation.md    # Message-only export of the 2026-07-20 session
Output/                 # Generated reports and deliverables
lucid/                  # Legacy Lucid diagram specifications (JSON)
temp/                   # Scratch payloads from ad-hoc queries
```

Notable artifacts:

- **End-to-end traffic flow for a production TPA spoke** — a Mermaid page at [Output/dt-prd-tpa-traffic-flow.html](Output/dt-prd-tpa-traffic-flow.html), which loads Mermaid from a CDN, so it needs network access to render. The same diagram exists as a Lucid document specification in [lucid/dt-prd-tpa-traffic-flow/](lucid/dt-prd-tpa-traffic-flow/) (`document.json` plus a minified variant). Covers Front Door → WAF → App Services → VNet integration → private endpoints → hub peering.
- **Well-Architected audit export** — [Output/ImpactedResources.csv](Output/ImpactedResources.csv) and a companion workbook hold APRL and AZQR findings for a production spoke, categorized by impact, resource type, and recommendation.
- **Session history** — [chat-history/](chat-history/) keeps one Markdown file per session or topic. These exist so multi-step work survives outside chat history. [chat-conversation.md](chat-conversation.md) is a longer message-level export of the same 2026-07-20 session that `chat-history/` summarizes.
- **Query scratch** — [temp/fabric-sku.json](temp/fabric-sku.json) is a Cost Management query payload kept from a reservation SKU investigation.

## Conventions for new artifacts

Folders below are created **on demand**, not up front — [AGENTS.md §18](AGENTS.md#18-repository-artifact-locations) explicitly says not to create empty structure for appearance. Only the paths listed in [What is in this repository](#what-is-in-this-repository) exist today; the rest is the target layout.

```text
docs/            architecture/ · assessments/ · change-plans/ · decisions/
                 handoffs/ · repository-discovery/ · runbooks/ · troubleshooting/
infra/bicep/     modules/ · environments/
scripts/         powershell/
queries/         resource-graph/ · kql/
config/          architect-context.example.yaml
chat-history/    saved session context
Output/          generated reports and deliverables
evidence/        raw collected evidence (intended to be gitignored)
```

Naming and content rules:

- **Chat history** — `chat-history/YYYY-MM-DD-<short-topic>.md`, with date, workspace path, and a turn-by-turn summary. Prefer durable summaries over raw tool-call dumps. ([§18.1](AGENTS.md#181-chat-context-persistence))
- **Generated output** — `Output/YYYY-MM-DD-HHmmss-<short-description>.<ext>`. The timestamp is required so repeat runs don't overwrite each other. ([§18.2](AGENTS.md#182-generated-reports-and-output-files))
- **Handoffs** — for multi-step work, maintain `docs/handoffs/CURRENT_STATE.md`, `TASKS.md`, and `DECISIONS.md` so another session on another machine can continue. ([§18](AGENTS.md#18-repository-artifact-locations), [§25](AGENTS.md#25-completion-criteria))
- **Redaction** — omit secrets, tokens, PATs, and connection strings from every committed file, and redact sensitive values before writing anything to `Output/`. See [§8](AGENTS.md#8-data-plane-and-secret-boundaries) and [§18.1](AGENTS.md#181-chat-context-persistence) for the boundary this repo is expected to hold.

> This repository contains findings and identifiers from real Azure environments. Keep it private and apply the redaction rules above to anything added.

## Working agreements in brief

The full rules are in [AGENTS.md](AGENTS.md); this is the shape of them.

**Risk classes and what each requires** ([§5.1](AGENTS.md#51-risk-classes)):

| Class | Scope | Gate |
|---|---|---|
| 0 — Read-only | Inventory, queries, health checks, log analysis, assessment | Proceed within authorized scope |
| 1 — Local workspace | Markdown, Bicep, scripts, queries, pipeline YAML, diagrams | Edit locally on request; no push, no deploy |
| 2 — Reversible non-prod | Dev/test config, non-prod deployment or pipeline run | Explicit execution instruction after the plan is clear |
| 3 — High-impact / production | Any prod mutation; identity, network, policy, Key Vault, data, monitoring, capacity, pipeline permissions | Evidence, scope, blast radius, plan, validation, rollback, and explicit final authorization |
| 4 — Destructive / irreversible | Deletion, purge, disabling soft delete, history rewrite, force push, broad deny policy | Explicit final confirmation naming exact targets; prefer a human-operated runbook |

**Evidence labels used in every assessment** ([§3.3](AGENTS.md#33-evidence-over-confidence)): `Confirmed` (directly observed) · `Inferred` (implied by confirmed facts) · `Conditional` (true under a stated condition) · `Unknown` (not verified) · `Recommendation` (proposed, not current state).

**The habits that matter most:**

- Read first — establish scope, inspect current state, map dependencies, then plan with validation and rollback.
- Never guess tenant, subscription, environment, or production status. If production status is uncertain, treat the target as production.
- No silent mutation of Azure, Azure DevOps, Git, external diagram services, or local tooling configuration.
- Generating a script is not authorization to run it; editing files is not authorization to push them.
- Never fabricate tool output, test results, or evidence. Report exactly what ran and what did not.
