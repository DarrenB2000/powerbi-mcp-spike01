# Spike report: Power BI MCP servers with GitHub Copilot and Claude Code

**Status:** Public Preview evaluation  
**Date:** May 2026  
**Protocol:** Model Context Protocol (MCP)

---

## 1. Executive summary

Microsoft released two official Power BI MCP servers in November 2025 as a Public Preview.
The **Power BI Modeling MCP** server runs locally via stdio and exposes the Tabular Object
Model for semantic model authoring. The **Power BI Remote MCP** server is a hosted HTTPS
endpoint that enables natural-language querying of published semantic models in the Power BI
service.

Both servers were validated against two AI clients: GitHub Copilot agent mode in VS Code
(minimum version 1.99) and Claude Code. The integration is functional at the protocol level.
Key limitations relate to the preview stage: tool schemas may change before general
availability, the remote server requires a per-tenant admin setting, and the local server
requires Power BI Desktop to be running on Windows.

Automated check results and interactive scenario timings are recorded in
[docs/05-validation-results.md](05-validation-results.md).

---

## 2. Background

### What is MCP?

The Model Context Protocol (MCP) is an open standard introduced by Anthropic in November 2024
and subsequently adopted by Microsoft, GitHub, and other vendors. It defines a JSON-RPC-based
protocol for AI agents to discover and call tools provided by external servers. The protocol
is client-agnostic: the same server works with any MCP-compatible client.

### Why this spike?

Power BI semantic models are complex analytical objects with hundreds of measures, dozens of
tables, and intricate DAX logic. Maintaining model documentation, detecting lineage breaks, and
authoring new measures manually is time-consuming. The MCP integration creates a path for AI
agents to perform these tasks using the same Tabular Object Model API that developers already
use, without requiring custom connector code.

This spike assesses whether the current Public Preview state is sufficient for adoption by an
engineering team.

---

## 3. Goals

1. Confirm that both MCP servers function correctly with GitHub Copilot in VS Code and with
   Claude Code using the documented configuration.
2. Demonstrate two practical scenarios: read-only documentation generation and lineage
   validation against an expected Gold schema.
3. Identify blockers, risks, and gaps relevant to a production adoption decision.
4. Provide a reproducible configuration that any team can apply to their own PBIX file and
   Power BI tenant.

---

## 4. Architecture overview

See [docs/03-architecture.md](03-architecture.md) for the full component model and runtime
topology diagrams.

High-level: VS Code acts as the host process. Inside VS Code, either GitHub Copilot Chat or
Claude Code operates as the MCP client. The client connects via stdio to the Modeling MCP
server (a local Node.js process launched by VS Code) and via HTTPS to the Remote MCP server
(the hosted Fabric endpoint). The Modeling MCP server connects to the local Analysis Services
engine that Power BI Desktop spawns, listening on a dynamic port. The Remote MCP server
authenticates via Entra ID OAuth and queries the Power BI service REST API.

```
VS Code (host)
  |
  +-- GitHub Copilot Chat   (or)   Claude Code
        |                                |
        | stdio                          | stdio
        v                                v
  powerbi-modeling-mcp (local npx process)
        |
        | TCP (dynamic port, e.g., localhost:54321)
        v
  msmdsrv.exe (Analysis Services engine spawned by Power BI Desktop)
        |
        v
  PBIX file (open in Power BI Desktop)

  [Both clients also connect via HTTPS]
        |
        | HTTPS
        v
  api.fabric.microsoft.com/v1/mcp/powerbi (Remote MCP server)
        |
        v
  Power BI service (semantic models in workspaces)
```

---

## 5. Validation results

Automated check results (VS Code version, extensions installed, smoke test output, timing
measurements, and PBIX detection) are recorded in
[docs/05-validation-results.md](05-validation-results.md) Section A.

Interactive scenario results (wall-clock time per scenario, premium request consumption,
accuracy assessment) are recorded in
[docs/05-validation-results.md](05-validation-results.md) Section B.

This section does not duplicate those numbers. Refer to the validation document for all
measured values.

---

## 6. Findings

### Strengths

- **Client agnostic:** The same server configuration worked with both GitHub Copilot and
  Claude Code with no server-side changes. The MCP protocol abstraction holds in practice.
- **Read-only enforcement:** The `--readonly` flag on the Modeling MCP server is enforced at
  the server level. Write tool invocations are rejected without any client-side coordination,
  making it safe to evaluate against production models.
- **Elicitation protocol:** When configured without `--skipconfirmation`, the Modeling MCP
  server implements the MCP elicitation protocol to request user approval before the first
  write and before the first query execution. This is documented behavior (microsoft/powerbi-modeling-mcp
  README) and functions correctly with both clients.
- **Tabular Object Model coverage:** The Modeling MCP server exposes a broad set of TOM
  operations: tables, columns, measures, relationships, partitions, hierarchies, perspectives,
  calculation groups, and security roles. Scenario 01 (discovery) can be executed end to end
  without gaps.
- **DAX execution via Remote MCP:** The Remote MCP server can execute DAX queries against
  published models and return tabular results, enabling natural-language Q&A without requiring
  a published report.

### Limitations and risks

- **Public Preview stability:** Both servers carry the disclaimer that "tool definitions,
  request formats, and response schemas may change" before general availability
  (learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started).
  Configuration files written today may require updates after a server version bump.
- **Tenant admin dependency (Remote MCP):** The tenant setting
  "Users can use the Power BI Model Context Protocol server endpoint (preview)" must be
  enabled by a Fabric administrator. This creates a deployment dependency for teams in
  organizations with conservative admin policies.
- **Windows-only local path:** The Modeling MCP server can connect to a PBIX file open in
  Power BI Desktop only on Windows. macOS and Linux users can use the Remote MCP server for
  published models but cannot use the local authoring path.
- **Dynamic port complexity:** Power BI Desktop spawns a new Analysis Services instance on a
  random port each time a PBIX file is opened. The `scripts/Get-OpenPbixModel.ps1` script
  automates port detection, but this must be re-run whenever the file is re-opened.
- **No direct CI support:** The Modeling MCP server requires Power BI Desktop to be running,
  which makes it impractical for headless CI environments. The Remote MCP server is more
  suitable for CI but requires Entra ID service principal authentication (not covered by this
  spike, which uses interactive login).
- **Context window pressure:** Large models (100+ tables, 500+ measures) may produce tool
  responses that approach the context window of the AI client. Mitigation: scope the agent
  request to specific tables or display folders.

---

## 7. Recommendations and next steps

### Immediate actions (if proceeding)

1. Enable the Remote MCP tenant setting in a non-production tenant to allow testing without
   affecting production workloads.
2. Pin the `powerbi-modeling-mcp` NPX version to a specific release tag rather than `@latest`
   to avoid unexpected changes during the preview period.
   Example: `@microsoft/powerbi-modeling-mcp@0.x.x` (check releases on GitHub for the current
   stable tag).
3. Apply `--readonly` in all evaluation configurations. Remove it only in a controlled
   authoring session with a test model.

### Longer-term consideration

- **Service principal authentication for Remote MCP:** For CI/CD and production use, configure
  the Remote MCP server to authenticate using an Entra ID service principal rather than
  interactive login. Microsoft documentation covers this at
  learn.microsoft.com/en-us/power-bi/developer/embedded/embed-service-principal.
- **Drift monitoring:** Schedule scenario 02 (lineage check) in CI to detect Gold schema
  drift automatically. See [scenarios/scenario-02-lineage-check.md](../scenarios/scenario-02-lineage-check.md)
  for guidance on CI integration.

### Pricing considerations (as of May 2026)

**GitHub Copilot:**
- Copilot Pro: USD 10/month per user, includes 300 premium requests/month.
- Copilot Pro+: USD 39/month per user, includes 1,500 premium requests/month.
- Additional premium requests: USD 0.04 each (requires opt-in to paid usage; hard-limited
  by default).
- Note: GitHub announced a move from request-based to usage-based billing starting
  June 1, 2026. Verify current pricing at
  [github.com/features/copilot/plans](https://github.com/features/copilot/plans) before
  budgeting.

**Claude Code:**
- Priced per API token consumption. Costs vary by model (Opus 4.7 vs. Sonnet 4.6) and
  session length. See [anthropic.com/pricing](https://www.anthropic.com/pricing) for current
  rates.

---

## 8. References

The following URLs were verified during this spike (May 2026):

1. [What are the Power BI MCP servers? (Microsoft Learn)](https://learn.microsoft.com/en-us/power-bi/developer/mcp/mcp-servers-overview)
2. [Get started with the remote Power BI MCP server (Microsoft Learn)](https://learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started)
3. [Remote Power BI MCP server tools (Microsoft Learn)](https://learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-tools)
4. [Power BI Modeling MCP -- GitHub repository (microsoft/powerbi-modeling-mcp)](https://github.com/microsoft/powerbi-modeling-mcp)
5. [Add and manage MCP servers in VS Code (code.visualstudio.com)](https://code.visualstudio.com/docs/copilot/customization/mcp-servers)
6. [MCP configuration reference for VS Code (code.visualstudio.com)](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration)
7. [Extending GitHub Copilot Chat with MCP servers (docs.github.com)](https://docs.github.com/en/copilot/customizing-copilot/using-model-context-protocol/extending-copilot-chat-with-mcp)
8. [Connect Claude Code to tools via MCP (docs.anthropic.com)](https://docs.anthropic.com/en/docs/claude-code/mcp)
9. [GitHub Copilot premium requests (docs.github.com)](https://docs.github.com/en/copilot/concepts/billing/copilot-requests)
10. [GitHub Copilot plans and pricing (github.com)](https://github.com/features/copilot/plans)
11. [VS Code March 2025 release notes -- v1.99 (code.visualstudio.com)](https://code.visualstudio.com/updates/v1_99)
12. [Power BI Desktop local port detection (biinsight.com)](https://www.biinsight.com/four-different-ways-to-find-your-power-bi-desktop-local-port-number/)
13. [Connect-PowerBIServiceAccount cmdlet reference (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/module/microsoftpowerbimgmt.profile/connect-powerbiserviceaccount)
