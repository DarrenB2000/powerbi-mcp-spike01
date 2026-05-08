# Configuration guide

This guide covers configuring both supported MCP clients to connect to the two Power BI MCP
servers. Follow Path A for GitHub Copilot in VS Code, Path B for Claude Code, or both.

---

## Prerequisites (both paths)

- **Node.js** (required to run `npx @microsoft/powerbi-modeling-mcp@latest`)
  Install from [nodejs.org](https://nodejs.org/).
- **Power BI tenant** with at least one semantic model you have Build permission on.
- **Fabric administrator access** (or approval from an admin) to enable the Remote MCP
  tenant setting described in the Remote MCP section below.

---

## Tenant setting for the Remote MCP server

A Fabric administrator must enable the following setting before the Remote MCP endpoint
accepts connections:

> **"Users can use the Power BI Model Context Protocol server endpoint (preview)"**

Location: Fabric admin portal (app.fabric.microsoft.com/admin) under
**Tenant settings > Developer settings**.

Source: [learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started](https://learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started)

Without this setting, all requests to `https://api.fabric.microsoft.com/v1/mcp/powerbi` will
return 403. See [docs/04-troubleshooting.md](04-troubleshooting.md) for resolution steps.

---

## Path A: GitHub Copilot agent mode in VS Code

### 1. Install VS Code

Minimum required version: **1.99** (released March 2025, when MCP support and agent mode
became generally available to all users).

Download from [code.visualstudio.com/download](https://code.visualstudio.com/download).

Verify: `code --version` should output `1.99.0` or later on the first line.

Source: [code.visualstudio.com/updates/v1_99](https://code.visualstudio.com/updates/v1_99)

### 2. Install required extensions

Run this once (or use `scripts/Install-PowerBIMcpPrereqs.ps1`):

```powershell
code --install-extension GitHub.copilot
code --install-extension GitHub.copilot-chat
code --install-extension Analysis-services.powerbi-modeling-mcp
```

The Power BI Modeling MCP extension (`Analysis-services.powerbi-modeling-mcp`) registers the
Modeling MCP server automatically with VS Code. You do not need to configure the stdio server
manually if you use the extension; however, the `.vscode/mcp.json` template in this repository
uses the NPX path so the configuration is explicit and version-pinnable.

### 3. Configure MCP servers

Copy the template to your workspace:

```powershell
.\scripts\Initialize-Workspace.ps1
```

This creates `.vscode/mcp.json` from `config/mcp.json.example`. The resulting file registers
both servers:

```jsonc
{
  "servers": {
    "powerbi-modeling-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@microsoft/powerbi-modeling-mcp@latest", "--start", "--readonly"]
    },
    "powerbi-remote": {
      "type": "http",
      "url": "https://api.fabric.microsoft.com/v1/mcp/powerbi"
    }
  }
}
```

VS Code uses the root key `servers` in `.vscode/mcp.json`.

Source: [code.visualstudio.com/docs/copilot/reference/mcp-configuration](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration)

### 4. Switch Copilot Chat to agent mode

1. Open the Copilot Chat panel (Ctrl+Alt+I or the chat icon in the activity bar).
2. Click the model dropdown at the top of the chat panel and switch from "Ask" or "Edit" mode
   to **"Agent"** mode.
3. Verify that the available tools list shows `powerbi-modeling-mcp` and `powerbi-remote`
   tools. If they do not appear, open the VS Code MCP output channel
   (View > Output > MCP: powerbi-modeling-mcp) for diagnostics.

### 5. Set up custom instructions

The file `.github/copilot-instructions.md` is read by GitHub Copilot as standing instructions
for all agent sessions in the workspace. `Initialize-Workspace.ps1` copies
`config/copilot-instructions.md` to that location. Review and adjust the instructions to
match your model's conventions before running the scenarios.

### 6. Verify

Run the smoke test:

```powershell
.\scripts\Test-McpConnectivity.ps1
```

---

## Path B: Claude Code

### 1. Install Claude Code

Claude Code is available as a CLI, a VS Code extension, and a JetBrains extension. For
current installation instructions, see
[claude.ai/code](https://claude.ai/code) or
[docs.anthropic.com/en/docs/claude-code](https://docs.anthropic.com/en/docs/claude-code).

Verify: `claude --version` should return a version string.

### 2. Configure MCP servers

**Option A -- Copy the template file (recommended for this spike):**

`Initialize-Workspace.ps1` creates `.mcp.json` from `config/claude-code-mcp.json.example`.
Claude Code reads `.mcp.json` from the project root and registers the servers listed under the
`mcpServers` root key.

Claude Code uses the root key `mcpServers` in `.mcp.json`.

Source: [docs.anthropic.com/en/docs/claude-code/mcp](https://docs.anthropic.com/en/docs/claude-code/mcp)

**Option B -- Use the `claude mcp add` CLI:**

```powershell
# Modeling MCP (stdio, read-only)
claude mcp add --scope project --transport stdio powerbi-modeling-mcp -- npx -y "@microsoft/powerbi-modeling-mcp@latest" --start --readonly

# Remote MCP (HTTPS)
claude mcp add --scope project --transport http powerbi-remote https://api.fabric.microsoft.com/v1/mcp/powerbi
```

This writes equivalent entries to `.mcp.json`. Claude Code will prompt for approval the first
time a project-scoped server is used.

### 3. Set up CLAUDE.md

Claude Code reads `CLAUDE.md` from the project root automatically at the start of every
session. `Initialize-Workspace.ps1` copies `config/copilot-instructions.md` to `CLAUDE.md`.

The instructions tell the agent which server to use for authoring vs. querying, enforce the
read-only contract, specify DAX style, and configure documentation output format.

### 4. Select a model

For the scenarios in this spike, Claude Sonnet 4.6 is recommended as the default. Use Claude
Opus 4.7 for large models or when scenario 02 involves deep cross-referencing. Specify the
model at the command line or in the Claude Code settings:

```powershell
claude --model claude-sonnet-4-6
```

### 5. Verify

```powershell
.\scripts\Test-McpConnectivity.ps1
```

---

## Combined configuration: both servers registered in both clients

The spike is designed so that both `.vscode/mcp.json` (VS Code) and `.mcp.json` (Claude Code)
register the same two servers. You can run either client against the same project with no
additional configuration steps.

| Config file | Root key | Client |
|---|---|---|
| `.vscode/mcp.json` | `servers` | VS Code (GitHub Copilot agent mode) |
| `.mcp.json` | `mcpServers` | Claude Code |

Both files are generated by `Initialize-Workspace.ps1` and both are gitignored (except for
`.vscode/mcp.json` which is explicitly unignored so it can be shared with the team).

---

## First-time setup summary

Run these scripts in order:

```powershell
# 1. Install prerequisites (VS Code extensions, verify Node.js and .NET 8)
.\scripts\Install-PowerBIMcpPrereqs.ps1

# 2. Copy config templates to working files
.\scripts\Initialize-Workspace.ps1

# 3. Detect the open PBIX file (Windows only)
.\scripts\Get-OpenPbixModel.ps1

# 4. Sign in to Power BI service (opens browser)
.\scripts\Connect-PowerBIInteractive.ps1

# 5. Select a workspace and model from the service
.\scripts\Select-Workspace.ps1

# 6. Verify the full setup
.\scripts\Test-McpConnectivity.ps1
```

---

## Modeling MCP flags reference

| Flag | Effect |
|---|---|
| `--start` | Required. Starts the MCP server. |
| `--readonly` | Prevents all write operations. Enforced at server level. |
| `--readwrite` | Enables writes with the elicitation confirmation flow (default when `--readonly` is absent). |
| `--skipconfirmation` | Approves all writes without prompting. Use with caution. |
| `--compatibility PowerBI` | Default. Targets Power BI semantic model conventions. |
| `--compatibility Full` | Targets Analysis Services (includes features not available in Power BI). |
| `--authmode interactive` | Default. Uses interactive Entra ID login. |
| `--authmode serviceprincipal` | Uses service principal credentials (for CI/automation). |

Source: [github.com/microsoft/powerbi-modeling-mcp README](https://github.com/microsoft/powerbi-modeling-mcp/blob/main/README.md)
