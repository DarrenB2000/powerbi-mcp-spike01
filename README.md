# Power BI MCP spike

A reproducible technical evaluation of Microsoft's two official Power BI Model Context Protocol
(MCP) servers, validated with both GitHub Copilot agent mode in VS Code and Claude Code.
The repository contains configuration templates, automation scripts, two demonstration scenarios,
and a structured validation log. It is intentionally free of tenant-specific identifiers and
can be replicated by any team with a Power BI tenant and a PBIX file.

Both servers are in **Public Preview** as of the date of writing (May 2026).

---

## The two Power BI MCP servers

| Server | Transport | Purpose | Source |
|---|---|---|---|
| Power BI Modeling MCP | stdio (local process) | Semantic model authoring via the Tabular Object Model | [github.com/microsoft/powerbi-modeling-mcp](https://github.com/microsoft/powerbi-modeling-mcp) |
| Power BI Remote MCP | HTTPS (hosted endpoint) | Natural-language querying of published semantic models | [learn.microsoft.com/power-bi/developer/mcp](https://learn.microsoft.com/en-us/power-bi/developer/mcp/) |

Remote endpoint: `https://api.fabric.microsoft.com/v1/mcp/powerbi`

---

## Repository structure

```
powerbi-mcp-spike/
├── README.md                          -- this file
├── .gitignore
├── docs/
│   ├── 01-spike-report.md             -- executive summary, findings, recommendations
│   ├── 02-configuration-guide.md      -- setup for Copilot and Claude Code
│   ├── 03-architecture.md             -- component model and runtime topology
│   ├── 04-troubleshooting.md          -- common failures and diagnostics
│   └── 05-validation-results.md       -- automated and interactive measurement log
├── config/
│   ├── mcp.json.example               -- VS Code .vscode/mcp.json template
│   ├── claude-code-mcp.json.example   -- Claude Code .mcp.json template
│   ├── semantic-model-ids.json        -- committed placeholder model catalog
│   ├── expected-gold-schema.json      -- Gold layer view definitions for lineage check
│   └── copilot-instructions.md        -- standing instructions for both clients
├── scenarios/
│   ├── scenario-01-discovery.md       -- read-only documentation generation
│   └── scenario-02-lineage-check.md   -- lineage validation against Gold schema
└── scripts/
    ├── Install-PowerBIMcpPrereqs.ps1  -- verify and install prerequisites
    ├── Initialize-Workspace.ps1       -- bootstrap config files from templates
    ├── Get-OpenPbixModel.ps1          -- detect open PBIX files in Power BI Desktop
    ├── Connect-PowerBIInteractive.ps1 -- browser-based Entra ID login
    ├── Select-Workspace.ps1           -- choose a Power BI workspace and model
    ├── Test-McpConnectivity.ps1       -- full smoke test
    ├── Get-SemanticModelInventory.ps1 -- enumerate accessible semantic models
    ├── Export-ModelDocumentation.ps1  -- post-process scenario 01 output to HTML
    └── Measure-AutomatedChecks.ps1    -- run all non-interactive checks
```

---

## Prerequisites

| Requirement | Windows | macOS / Linux |
|---|---|---|
| VS Code 1.99 or later | Required | Required for Remote MCP only |
| Node.js (for npx) | Required | Required |
| GitHub Copilot subscription | Optional | Optional |
| Power BI Desktop | Required for Modeling MCP local PBIX path | Not supported |
| Power BI tenant (Pro or Premium) | Required for Remote MCP | Required for Remote MCP |

The Modeling MCP server runs as a local stdio process and connects to the Analysis Services
engine that Power BI Desktop spawns when a PBIX file is open. It is a Windows-only workflow.

The Remote MCP server connects to the Power BI service over HTTPS and works on any OS, but
requires a Power BI tenant where a Fabric administrator has enabled the preview tenant setting.

---

## First-time setup

Run the following scripts in order from a PowerShell terminal opened in the repository root.

### Step 1 -- Install prerequisites

```powershell
.\scripts\Install-PowerBIMcpPrereqs.ps1
```

Verifies VS Code (minimum version 1.99), checks Node.js and .NET 8 SDK availability, and
installs the GitHub Copilot, GitHub Copilot Chat, and Power BI Modeling MCP VS Code extensions.
Use `-SkipExtensions` if you prefer to install extensions manually.

### Step 2 -- Bootstrap workspace config files

```powershell
.\scripts\Initialize-Workspace.ps1
```

Copies `config/mcp.json.example` to `.vscode/mcp.json`, copies `config/copilot-instructions.md`
to both `.github/copilot-instructions.md` and `CLAUDE.md`, and copies
`config/claude-code-mcp.json.example` to `.mcp.json`. Creates the `out/` folder. Will not
overwrite existing files unless `-Force` is specified.

### Step 3 -- Detect an open PBIX file (Windows only)

```powershell
.\scripts\Get-OpenPbixModel.ps1
```

Finds running Power BI Desktop instances, reads the dynamic Analysis Services port from each
instance's `msmdsrv.port.txt` file, and extracts the open PBIX file name from the process
window title. Writes the selected entry to `config/semantic-model-ids.local.json` under the
`localPbix` key. Required for the Modeling MCP local path. On macOS and Linux this script exits
cleanly without doing anything.

### Step 4 -- Sign in to Power BI service

```powershell
.\scripts\Connect-PowerBIInteractive.ps1
```

Opens a browser window for Entra ID interactive login using `Connect-PowerBIServiceAccount`
from the `MicrosoftPowerBIMgmt` PowerShell module. Caches a small auth state file at
`config/auth-state.local.json` (gitignored). Required for the Remote MCP path and for
`Select-Workspace.ps1`.

### Step 5 -- Choose a workspace and model

```powershell
.\scripts\Select-Workspace.ps1
```

Lists all Power BI workspaces accessible to the signed-in user and presents a numbered console
menu. After workspace selection, lists the semantic models in that workspace for a second
selection. Persists the choice to `config/semantic-model-ids.local.json`. Use `-Filter` to
pre-filter the workspace list by substring.

### Step 6 -- Run the smoke test

```powershell
.\scripts\Test-McpConnectivity.ps1
```

Verifies the full setup: config files present, auth state valid, workspace and model selected,
Power BI Desktop instance detected (Windows), and HTTPS reachability of the Remote MCP
endpoint. Prints PASS, WARN, or FAIL for each check and exits with a count of FAIL results.

---

## Demo scenarios

| Scenario | Description | File |
|---|---|---|
| 01 -- Discovery | Generate read-only documentation of a semantic model including an erDiagram, table inventory, measure listing, and RLS summary | [scenarios/scenario-01-discovery.md](scenarios/scenario-01-discovery.md) |
| 02 -- Lineage check | Compare the semantic model columns against `config/expected-gold-schema.json` to surface broken references, orphan columns, and upstream additions | [scenarios/scenario-02-lineage-check.md](scenarios/scenario-02-lineage-check.md) |

Both scenarios can target either the local PBIX file (via the Modeling MCP) or a published
workspace model (via the Remote MCP). Configure the active source using `Get-OpenPbixModel.ps1`
or `Select-Workspace.ps1` before starting a scenario.

---

## Recommended models

For **Claude Code**, Claude Sonnet 4.6 handles MCP orchestration well for most scenarios.
Claude Opus 4.7 is recommended when the model is large or when scenario 02 involves many
tables and complex cross-referencing.

For **GitHub Copilot in VS Code**, select the model from the Copilot Chat panel. Consult
[docs.github.com/en/copilot](https://docs.github.com/en/copilot) for currently available
models on your plan.

---

## Status and limitations

- Both servers are in Public Preview as of May 2026. Breaking changes to tool schemas,
  authentication flows, and transport formats may occur before general availability.
- The Modeling MCP server requires Power BI Desktop to be running with a PBIX file open.
  It connects to the local Analysis Services instance and does not interact with the Power BI
  service directly.
- The Remote MCP server requires a Fabric administrator to enable the tenant setting
  "Users can use the Power BI Model Context Protocol server endpoint (preview)".
- The `--readonly` flag on the Modeling MCP server prevents all write operations. Authoring
  scenarios require the server to be restarted without `--readonly`.
- See [docs/04-troubleshooting.md](docs/04-troubleshooting.md) for known issues.

---

## Further reading

- [What are the Power BI MCP servers?](https://learn.microsoft.com/en-us/power-bi/developer/mcp/mcp-servers-overview)
- [Get started with the remote Power BI MCP server](https://learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started)
- [Power BI Modeling MCP GitHub repository](https://github.com/microsoft/powerbi-modeling-mcp)
- [MCP servers in VS Code](https://code.visualstudio.com/docs/copilot/customization/mcp-servers)
- [Claude Code MCP documentation](https://docs.anthropic.com/en/docs/claude-code/mcp)
