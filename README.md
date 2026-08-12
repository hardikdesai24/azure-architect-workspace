# azure-architect-workspace

A daily working repository for **Azure architecture, engineering, operations, governance, and troubleshooting** — driven mainly through natural language in Cursor IDE / Cursor CLI or Claude Code on Windows, backed by MCP servers for Azure, Azure DevOps, Microsoft Learn, Bicep, and Lucid.

This is **not** an application repository and **not** an IaC deployment repository. It holds the operating contract for AI agents, the MCP configuration they use, and the durable artifacts they produce: assessments, audit exports, architecture diagrams, and session history. It is also **not** an autonomous production operator — agents investigate broadly and prepare changes, but do not mutate cloud or delivery systems without the authorization gates in [CLAUDE.md](CLAUDE.md).

---

## Table of contents

- [Start here: CLAUDE.md](#start-here-claudemd)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [MCP servers](#mcp-servers)
- [What is in this repository](#what-is-in-this-repository)
- [Conventions for new artifacts](#conventions-for-new-artifacts)
- [Working agreements in brief](#working-agreements-in-brief)

---

## Start here: CLAUDE.md

[CLAUDE.md](CLAUDE.md) is the operating contract for any AI agent working in this repo, and the best summary of how the workspace is meant to be used. Read it before running anything. Key sections:

| Section | Topic |
|---|---|
| [§1–2](CLAUDE.md#1-role-and-mission) | Role, mission, and instruction priority |
| [§3](CLAUDE.md#3-protected-operating-principles) | Protected principles: read first, don't guess cloud context, evidence over confidence, least privilege, no silent mutation |
| [§4](CLAUDE.md#4-interpreting-natural-language-requests) | How natural-language verbs map to authorization ("check" vs. "deploy" vs. "delete") |
| [§5](CLAUDE.md#5-change-authority-and-approval-gates) | Risk classes 0–4, approval gates, and stop conditions |
| [§7](CLAUDE.md#7-tool-routing-policy) | Tool-routing policy — which MCP server or CLI to use for what |
| [§8](CLAUDE.md#8-data-plane-and-secret-boundaries) | Data-plane and secret boundaries |
| [§9](CLAUDE.md#9-azure-architect-routine-work) | Routine architect workflows (discovery, incident, security, network, identity, cost, DR, drift) |
| [§12–16](CLAUDE.md#12-bicep-standards) | Standards for Bicep, PowerShell, Azure CLI, KQL / Resource Graph, Azure DevOps |
| [§18](CLAUDE.md#18-repository-artifact-locations) | Where artifacts belong |
| [§20–21](CLAUDE.md#20-validation-matrix) | Validation matrix, rollback and recovery requirements |
| [§23](CLAUDE.md#23-common-playbooks) | Playbooks for common requests |
| [§24–26](CLAUDE.md#24-prohibited-behavior) | Prohibited behavior, completion criteria, first-use behavior |

---

## Prerequisites

| Requirement | Used for |
|---|---|
| Windows + PowerShell 7 | Primary shell; the workspace is Windows-first |
| [Cursor](https://cursor.com) (IDE or CLI) or [Claude Code](https://claude.com/claude-code) | Interaction surface; each reads its own MCP config |
| Node.js (with `npx`) | Azure MCP Server and Azure DevOps MCP |
| .NET SDK (with `dnx`) | Bicep MCP Server |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Sign-in, read-only discovery, and the credentials Azure MCP reuses |
| Azure RBAC (Reader at minimum) | Any live Azure query |

## Setup

**1. Sign in to Azure.** Azure MCP has no separate login — it reuses credentials from tools already signed in on the machine (Azure CLI, Azure Developer CLI, VS Code):

```powershell
az login
az account show
az account list --output table
az account set --subscription "<subscription-id-or-name>"
```

**2. Load the MCP servers.** Both configs are committed; each client reads its own.

| Client | Config | How it loads |
|---|---|---|
| Cursor | [.cursor/mcp.json](.cursor/mcp.json) | **Settings → Tools & MCP**; reload if the servers don't appear |
| Claude Code | [.mcp.json](.mcp.json) | Read at startup. [.claude/settings.json](.claude/settings.json) pre-approves the five servers, so there is no per-session prompt |

Claude Code does **not** read `.cursor/mcp.json`, and a file at `.claude/mcp.json` is ignored — project servers must live in `.mcp.json` at the repo root. Keep the two files in sync when adding or changing a server.

**3. Adjust the config for your machine.** Both files resolve `npx` and `dnx` from `PATH` rather than
hardcoding absolute paths, so they load on Windows, macOS, and Linux. Two things are still
environment-specific:

- The Azure DevOps server is pinned to a single organization argument.
- `lucid` authorizes per client — Cursor and Claude Code each need their own sign-in.

If a stdio server fails to start on Windows with a "command not found" or `ENOENT` error, the
client could not resolve the `.cmd` shim. Confirm `npx -v` (and `dnx --version` for `bicep`) work in
a normal terminal; if they do and the server still won't start, fall back to an absolute path for
that one entry — `C:\Program Files\nodejs\npx.cmd` — rather than reverting the whole file.

**4. Verify with read-only checks only.** Per [CLAUDE.md §26](CLAUDE.md#26-first-use-behavior-for-a-new-repository), never use a cloud or Azure DevOps *write* as a connection test.

## MCP servers

The same five servers are defined in both [.cursor/mcp.json](.cursor/mcp.json) and [.mcp.json](.mcp.json):

| Server | Transport | Purpose | Auth |
|---|---|---|---|
| `Azure MCP Server` / `azure` | `npx @azure/mcp` | Azure control plane, Resource Graph, cost, monitoring | Reuses local Azure CLI / developer credentials |
| `ado` | `npx @azure-devops/mcp <org>` | Repos, pipelines, work items, PRs, wikis, test plans | Azure DevOps sign-in for the pinned org |
| `microsoft-learn` | Remote HTTP | Current official Microsoft documentation | None |
| `bicep` | `dnx Azure.Bicep.McpServer` | Bicep authoring and resource schema lookup | None |
| `lucid` | Remote HTTP | Architecture diagram creation and editing | Lucid account |

Two differences between the files, both required:

- **Azure server name** — `Azure MCP Server` in Cursor, `azure` in Claude Code, since spaces are awkward in generated tool names.
- **Remote servers** — Cursor infers HTTP from a bare `url`; Claude Code needs an explicit `"type": "http"`.

Everything else is intentionally identical, including the versions. All three stdio servers are
pinned to an exact version in **both** files, so Cursor and Claude Code run identical tooling and a
given commit reproduces the same toolchain:

| Server | Pin | Registry | Why this version |
|---|---|---|---|
| `azure` / `Azure MCP Server` | `@azure/mcp@2.0.5` | npm | Newest **stable**. `latest` points at the `3.0.0-beta` line, so `@latest` is *not* an upgrade — see below |
| `ado` | `@azure-devops/mcp@2.9.0` | npm | Newest stable; here `latest` and newest stable agree |
| `bicep` | `Azure.Bicep.McpServer@0.46.1` | NuGet | Newest release; this package publishes no prereleases |

Do not replace a pin with `@latest` or drop it. For `@azure/mcp` specifically, the npm `latest`
dist-tag resolves to a `3.0.0-beta` prerelease — of 144 published versions, every one above 2.0.5
is part of the unreleased 3.x line — so `@latest` silently moves this workspace onto pre-release
code *and* floats onto a different beta on each launch. Version syntax is `package@version` for
both `npx` and `dnx` (`dnx` follows `dotnet tool exec <PACKAGE_NAME>[@<VERSION>]`).

When bumping, change both files in the same commit and record the reason.

If your client already supplies Azure, Microsoft Learn, or Lucid through a desktop extension or an account-level connector, those load *alongside* the repo entries rather than replacing them, and the tools appear twice. Remove the client-level copy to deduplicate.

### Running in a headless Linux session

This workspace is Windows-first, but the same configs get loaded by Claude Code on the web, devcontainers, and CI — remote Linux containers that lack what the stdio servers assume. Observed in a Claude Code on the web session on 2026-08-12:

| Server | Result | Cause |
|---|---|---|
| `microsoft-learn` | Works | Remote HTTP, no auth |
| `azure` | Starts, registers all 61 tools; every call returns `401` | No Azure credentials in the container |
| `ado` | Starts and completes the MCP handshake; tool calls then hang until the client times out | Default `interactive` auth needs a browser and Azure CLI |
| `bicep` | Never starts | No .NET runtime — `dnx` is not on `PATH` |
| `lucid` | Unavailable | OAuth is interactive and per client |

Do **not** treat these as config bugs. The committed `.mcp.json` and `.cursor/mcp.json` are correct, and the patches that look obvious — pinning a platform binary such as `@azure/mcp-linux-x64`, or forcing `-a pat` on `ado` — would undo the cross-platform resolution and break the Windows setup. Each is an environment gap, so fix it in the environment:

- **Azure credentials** — the container has no Azure CLI, so Setup step 1 cannot run and there is nothing for Azure MCP to reuse. Supply a service principal through `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_CLIENT_SECRET`, scoped no higher than Reader per [CLAUDE.md §3](CLAUDE.md#3-protected-operating-principles). Without them the server still loads its tools, so the failure only appears at call time as `401 ... ChainedTokenCredential failed`.
- **Azure DevOps** — `@azure-devops/mcp` accepts `-a interactive|azcli|env|envvar|pat`, defaulting to `interactive`. Headless, use `pat` and pass the token as an `ADO_MCP_AUTH_TOKEN` environment secret rather than committing the flag. Note the failure mode is a *hang*, not an error: the server reports itself healthy at startup and only stalls once a tool is called.
- **Bicep** — needs the .NET SDK present in the image. Otherwise treat Bicep schema lookups as unavailable and fall back to `microsoft-learn` or the `bicepschema` tool on the `azure` server.
- **Stale `npx` cache** — a partial download in `~/.npm/_npx` makes `azure` fail with `sh: 1: azmcp: not found` and register zero tools, which reads like a broken config but is not. Clear it with `rm -rf ~/.npm/_npx` and relaunch the client.

## What is in this repository

```text
CLAUDE.md               # Operating contract for AI agents (read first)
.cursor/mcp.json        # MCP server configuration (Cursor)
.mcp.json               # MCP server configuration (Claude Code)
.claude/settings.json   # Pre-approves the repo MCP servers for Claude Code
chat-history/           # Durable per-session summaries
chat-conversation.md    # Message-only export of the 2026-07-20 session
Output/                 # Generated reports and deliverables
lucid/                  # Lucid diagram specifications (JSON)
temp/                   # Scratch payloads from ad-hoc queries
```

Notable artifacts:

- **End-to-end traffic flow for a production TPA spoke** — a Mermaid page at [Output/dt-prd-tpa-traffic-flow.html](Output/dt-prd-tpa-traffic-flow.html), which loads Mermaid from a CDN, so it needs network access to render. The same diagram exists as a Lucid document specification in [lucid/dt-prd-tpa-traffic-flow/](lucid/dt-prd-tpa-traffic-flow/) (`document.json` plus a minified variant). Covers Front Door → WAF → App Services → VNet integration → private endpoints → hub peering.
- **Well-Architected audit export** — [Output/ImpactedResources.csv](Output/ImpactedResources.csv) and a companion workbook hold APRL and AZQR findings for a production spoke, categorized by impact, resource type, and recommendation.
- **Session history** — [chat-history/](chat-history/) keeps one Markdown file per session or topic: MCP setup with cost analysis, and a networking security review. These exist so multi-step work survives outside Cursor chat history. [chat-conversation.md](chat-conversation.md) is a longer message-level export of the same 2026-07-20 session that `chat-history/` summarizes.
- **Query scratch** — [temp/fabric-sku.json](temp/fabric-sku.json) is a Cost Management query payload kept from a reservation SKU investigation.

## Conventions for new artifacts

Folders below are created **on demand**, not up front — [CLAUDE.md §18](CLAUDE.md#18-repository-artifact-locations) explicitly says not to create empty structure for appearance. Only the paths listed in [What is in this repository](#what-is-in-this-repository) exist today; the rest is the target layout.

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

- **Chat history** — `chat-history/YYYY-MM-DD-<short-topic>.md`, with date, workspace path, and a turn-by-turn summary. Prefer durable summaries over raw tool-call dumps. ([§18.1](CLAUDE.md#181-chat-context-persistence))
- **Generated output** — `Output/YYYY-MM-DD-HHmmss-<short-description>.<ext>`. The timestamp is required so repeat runs don't overwrite each other. ([§18.2](CLAUDE.md#182-generated-reports-and-output-files))
- **Handoffs** — for multi-step work, maintain `docs/handoffs/CURRENT_STATE.md`, `TASKS.md`, and `DECISIONS.md` so another session on another machine can continue. ([§18](CLAUDE.md#18-repository-artifact-locations), [§25](CLAUDE.md#25-completion-criteria))
- **Redaction** — omit secrets, tokens, PATs, and connection strings from every committed file, and redact sensitive values before writing anything to `Output/`. See [§8](CLAUDE.md#8-data-plane-and-secret-boundaries) and [§18.1](CLAUDE.md#181-chat-context-persistence) for the boundary this repo is expected to hold.

> This repository contains findings and identifiers from real Azure environments. Keep it private and apply the redaction rules above to anything added.

## Working agreements in brief

The full rules are in [CLAUDE.md](CLAUDE.md); this is the shape of them.

**Risk classes and what each requires** ([§5.1](CLAUDE.md#51-risk-classes)):

| Class | Scope | Gate |
|---|---|---|
| 0 — Read-only | Inventory, queries, health checks, log analysis, assessment | Proceed within authorized scope |
| 1 — Local workspace | Markdown, Bicep, scripts, queries, pipeline YAML, diagrams | Edit locally on request; no push, no deploy |
| 2 — Reversible non-prod | Dev/test config, non-prod deployment or pipeline run | Explicit execution instruction after the plan is clear |
| 3 — High-impact / production | Any prod mutation; identity, network, policy, Key Vault, data, monitoring, capacity, pipeline permissions | Evidence, scope, blast radius, plan, validation, rollback, and explicit final authorization |
| 4 — Destructive / irreversible | Deletion, purge, disabling soft delete, history rewrite, force push, broad deny policy | Explicit final confirmation naming exact targets; prefer a human-operated runbook |

**Evidence labels used in every assessment** ([§3.3](CLAUDE.md#33-evidence-over-confidence)): `Confirmed` (directly observed) · `Inferred` (implied by confirmed facts) · `Conditional` (true under a stated condition) · `Unknown` (not verified) · `Recommendation` (proposed, not current state).

**The habits that matter most:**

- Read first — establish scope, inspect current state, map dependencies, then plan with validation and rollback.
- Never guess tenant, subscription, environment, or production status. If production status is uncertain, treat the target as production.
- No silent mutation of Azure, Azure DevOps, Git, Lucid, or local tooling configuration.
- Generating a script is not authorization to run it; editing files is not authorization to push them.
- Never fabricate tool output, test results, or evidence. Report exactly what ran and what did not.
