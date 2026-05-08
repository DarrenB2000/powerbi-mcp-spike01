# Troubleshooting

---

## Setup-time issues

### MCP tools not visible in Copilot Chat

**Symptom:** The Copilot Chat panel shows no MCP tools, or the MCP servers show as
disconnected in the VS Code status bar.

**Likely causes:**
1. Copilot Chat is in "Ask" or "Edit" mode, not "Agent" mode. Agent mode is required for MCP
   tool use. Switch using the dropdown at the top of the chat panel.
2. VS Code version is below 1.99. MCP support in Copilot requires VS Code 1.99 or later.
   Run `code --version` to verify.
3. The GitHub Copilot Chat extension is not installed or not enabled. Run
   `code --list-extensions | findstr copilot-chat` to verify.

---

### `.vscode/mcp.json` is ignored or not loaded

**Symptom:** VS Code does not start the MCP servers defined in `.vscode/mcp.json`.

**Likely cause:** The root key in the file is `mcpServers` instead of `servers`. VS Code
uses `servers` as the root key. Claude Code uses `mcpServers`. These are different files with
different root keys.

**Correct VS Code root key:**
```json
{ "servers": { ... } }
```

**Correct Claude Code root key:**
```json
{ "mcpServers": { ... } }
```

See [docs/02-configuration-guide.md](02-configuration-guide.md) for the full examples.

---

### `.mcp.json` is not loaded by Claude Code

**Symptom:** Claude Code does not show the Power BI MCP tools.

**Check:**
1. Confirm the file is named `.mcp.json` (dot prefix) in the project root, not in a
   subdirectory.
2. Confirm the root key is `mcpServers` (not `servers`).
3. Run `claude mcp list` to see registered servers.
4. If a project-scoped server was never approved, run `claude mcp reset-project-choices` and
   restart Claude Code to re-trigger the approval prompt.

---

### 403 error on the Remote MCP server

**Symptom:** Requests to `https://api.fabric.microsoft.com/v1/mcp/powerbi` return HTTP 403.

**Resolution:** A Fabric administrator must enable the tenant setting
"Users can use the Power BI Model Context Protocol server endpoint (preview)" in the Fabric
admin portal under Tenant settings > Developer settings. Until this setting is enabled, the
endpoint rejects all connections from users in the tenant, regardless of their individual
permissions.

Reference: [learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started](https://learn.microsoft.com/en-us/power-bi/developer/mcp/remote-mcp-server-get-started)

---

### Sign-in loop or repeated authentication prompts

**Symptom:** The browser opens repeatedly for authentication, or `Connect-PowerBIServiceAccount`
does not persist the session.

**Likely causes:**
1. Multi-factor authentication token has expired. Re-run
   `.\scripts\Connect-PowerBIInteractive.ps1 -Force` to force a fresh login.
2. The `MicrosoftPowerBIMgmt` module version is out of date. Run
   `Update-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser` to update.
3. Conditional access policies in your tenant require device compliance. Work with your
   identity administrator to register the device or use a compliant machine.

---

### PBIX detection failures (Windows)

**Symptom:** `Get-OpenPbixModel.ps1` reports "No Power BI Desktop instances found" or fails
to read the port file.

**Check:**
1. Power BI Desktop must be open with a PBIX file loaded, not just started with no file.
   Verify that the Desktop window title shows a file name (e.g., "SalesReport - Power BI
   Desktop") rather than the default "Power BI Desktop" title.
2. Confirm that `msmdsrv.exe` is running. Open Task Manager and search for `msmdsrv`. If not
   present, Power BI Desktop has not yet finished loading the model.
3. The port file path is:
   `%LOCALAPPDATA%\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces\AnalysisServicesWorkspace[N]\msmdsrv.port.txt`
   Run this to check directly:
   ```powershell
   Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces" -Filter msmdsrv.port.txt -Recurse
   ```
4. If multiple PBIX files are open (multiple Desktop windows), run the script without
   `-NonInteractive` so it presents the selection menu.

---

### Multiple Power BI Desktop instances -- selection prompt

**Symptom:** The script outputs "Multiple Power BI Desktop instances found" and exits.

**Resolution:** Run `Get-OpenPbixModel.ps1` without `-NonInteractive`. The script presents a
numbered menu; choose the PBIX file you want to connect to.

---

## Runtime issues

### DAX referencing non-existent columns

**Symptom:** The agent generates a DAX measure that references a column that does not exist in
the model, and the measure fails to evaluate.

**Cause:** The AI model produced a plausible-sounding column name that is not present in the
actual model. This is a language model hallucination, not an MCP server error.

**Mitigation:** The instruction in `config/copilot-instructions.md` says "inspect before
modifying" -- the agent should list columns before generating DAX that references them. If you
observe hallucinated column names, add a standing instruction to your CLAUDE.md or
`.github/copilot-instructions.md` that explicitly names the tables and columns the agent is
allowed to reference.

---

### First write requires elicitation confirmation

**Symptom:** The agent pauses and asks the user to confirm before writing to the model.

**Explanation:** This is expected behavior when the Modeling MCP server is running in
`--readwrite` mode without `--skipconfirmation`. The server implements the MCP elicitation
protocol to request user approval before the first write operation in a session. Accept the
prompt to proceed. To suppress this prompt, restart the server with `--skipconfirmation` (but
only do this intentionally, as it removes a safety gate).

---

### Premium quota exhausted (GitHub Copilot)

**Symptom:** Copilot responds with "Premium request limit reached" and stops generating.

**Context:** Copilot Pro includes 300 premium requests per month; Copilot Pro+ includes 1,500.
Agent mode sessions with MCP tool calls consume premium requests faster than simple completions.

**Options:**
1. Wait until the monthly quota resets.
2. Enable paid overage (USD 0.04 per additional premium request) via the GitHub billing
   settings. The limit is hard-blocked by default -- overage must be explicitly opted into.
3. Switch to Claude Code for the remainder of the evaluation.

Note: GitHub announced a transition to usage-based billing starting June 1, 2026. Check
[github.com/features/copilot/plans](https://github.com/features/copilot/plans) for the
current billing model.

---

### Semantic model not found

**Symptom:** The Remote MCP server returns a "model not found" or "unauthorized" error when
provided a model ID.

**Check:**
1. Confirm the workspace ID and model ID in `config/semantic-model-ids.local.json` match the
   actual IDs from the Power BI service. Open Power BI service, navigate to the model's
   settings page, and copy the IDs from the URL.
2. Confirm the signed-in user has Build permission on the semantic model (not just View).
3. Confirm the workspace is in a Premium or Fabric capacity. Some MCP features require Premium.

---

### Idle disconnects

**Symptom:** After a period of inactivity, the Modeling MCP server stops responding and tool
calls time out.

**Cause:** The local Analysis Services engine may have been idle for too long, or Power BI
Desktop went into a reduced-resource state.

**Resolution:** Close and reopen the PBIX file in Power BI Desktop to restart the Analysis
Services engine, then re-run `Get-OpenPbixModel.ps1` to pick up the new port.

---

## Diagnostics

### VS Code MCP output channel

Open View > Output and select the MCP server channel (e.g., "MCP: powerbi-modeling-mcp") to
see the server startup output, tool registration log, and any error messages from the server
process.

### Claude Code logs

Run `claude --verbose` to increase log detail. The MCP server startup output and tool call
traces appear in the terminal session.

### Modeling MCP local logs

The Modeling MCP server writes logs to the console (captured in the VS Code output channel or
visible in the terminal where it was started). Look for connection refused errors, Analysis
Services port errors, or authentication failures.

### Network reachability test

Run `scripts/Test-McpConnectivity.ps1` to check HTTPS reachability of the Remote MCP
endpoint. The script performs a TCP connection test to `api.fabric.microsoft.com:443`. A FAIL
result indicates a network or firewall issue rather than an authentication problem.

---

## Reset procedure

To start fresh and rebuild all configuration files:

```powershell
# Remove generated config files
Remove-Item -Path .vscode\mcp.json, .mcp.json, CLAUDE.md, .github\copilot-instructions.md `
  -ErrorAction SilentlyContinue

# Remove user-specific local state
Remove-Item -Path config\semantic-model-ids.local.json, config\auth-state.local.json `
  -ErrorAction SilentlyContinue

# Re-initialize
.\scripts\Initialize-Workspace.ps1
.\scripts\Get-OpenPbixModel.ps1
.\scripts\Connect-PowerBIInteractive.ps1
.\scripts\Select-Workspace.ps1
.\scripts\Test-McpConnectivity.ps1
```

---

## Known preview-stage gaps (as of May 2026)

- Tool schemas for both servers may change before general availability. Pin the NPX version
  to avoid unexpected regressions.
- The Remote MCP server does not support service principal authentication in all regions.
  Interactive user login is the documented path for this spike.
- The Modeling MCP server does not support connecting to a remote Analysis Services instance
  (Azure Analysis Services or SSAS on-premises) in the current preview. It only connects to
  the local Power BI Desktop Analysis Services engine.
- Neither server provides a progress or streaming API for long-running operations. Large model
  queries may time out in some clients.
- The MCP elicitation protocol implementation may behave differently across clients; behavior
  in GitHub Copilot may differ from Claude Code for the same server configuration.
