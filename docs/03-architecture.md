# Architecture

---

## MCP component model

The Model Context Protocol separates concerns into three roles:

- **Host:** the application that starts and manages MCP client connections (VS Code in this
  spike).
- **Client:** the AI agent or chat interface that discovers tools and makes tool calls
  (GitHub Copilot Chat in agent mode, or Claude Code).
- **Server:** the process or endpoint that exposes tools. A server declares its tool catalog
  on connection and executes tool calls on demand.

Protocol transport:
- **stdio:** the client launches a child process and communicates over stdin/stdout. Used by
  the Modeling MCP server.
- **HTTP (server-sent events):** the client connects to an HTTPS endpoint. Used by the Remote
  MCP server.

---

## Runtime topology

```
+-------------------------------------------------------------+
|  VS Code (host process)                                     |
|                                                             |
|  +---------------------------+  +------------------------+  |
|  |  GitHub Copilot Chat      |  |  Claude Code (CLI /    |  |
|  |  (agent mode)             |  |   VS Code extension)   |  |
|  |  MCP client               |  |  MCP client            |  |
|  +----------+----------------+  +----------+-------------+  |
|             |                              |                 |
+-------------|------------------------------|----------------+
              |  stdio (both clients)        |  stdio
              |                              |
              v                              v
+--------------------------------------------------+
|  powerbi-modeling-mcp (local Node.js process)    |
|  launched via: npx @microsoft/powerbi-modeling-mcp|
|  flags: --start --readonly                       |
+---------------------------+----------------------+
                            |
                            |  TCP, dynamic port
                            |  (e.g., localhost:54321)
                            v
+--------------------------------------------------+
|  msmdsrv.exe                                     |
|  Analysis Services engine spawned by             |
|  Power BI Desktop (Windows only)                 |
|  Port written to msmdsrv.port.txt                |
+---------------------------+----------------------+
                            |
                            |  In-process
                            v
+--------------------------------------------------+
|  PBIX file (open in Power BI Desktop)            |
+--------------------------------------------------+


[Both clients also connect to the Remote MCP server]

              |  HTTPS
              v
+--------------------------------------------------+
|  api.fabric.microsoft.com/v1/mcp/powerbi         |
|  Power BI Remote MCP server (hosted)             |
|  Authenticates via Entra ID OAuth                |
+---------------------------+----------------------+
                            |
                            |  Power BI REST API
                            v
+--------------------------------------------------+
|  Power BI service                                |
|  Semantic models in workspaces                   |
+--------------------------------------------------+
```

The two clients are alternatives; only one runs in any given session. VS Code loads both
configurations but each chat session uses only the client that originated the session.

---

## Where MCP fits in a medallion / Fabric architecture

A typical Fabric analytics platform uses a Bronze-Silver-Gold medallion pattern:

```
Bronze layer          Silver layer          Gold layer
(raw ingest)    -->   (cleansed views)  --> (aggregated views)
                                                  |
                                                  v
                                       Power BI semantic model
                                         (Import / DirectQuery)
                                                  |
                                                  v
                                       Power BI reports / Copilot
```

The Modeling MCP server operates on the semantic model layer. It can read from and (when not
`--readonly`) write to the model definition: tables, columns, measures, relationships, and
security roles. It does not have direct access to the Bronze or Silver layers.

The Remote MCP server executes DAX queries against published models in the Gold layer. It can
surface insights from aggregated data but cannot modify the model or access upstream layers.

Lineage validation (scenario 02) bridges the Gold view definitions (stored in
`config/expected-gold-schema.json`) with the current model columns, using the agent to compare
them and report discrepancies.

---

## Trust and security

### Tool discovery

When a client connects to an MCP server, the server responds with a list of available tools
(name, description, input schema). The client uses this catalog to decide which tools to call.
Neither GitHub Copilot nor Claude Code calls tools without user direction or explicit tool-use
authorization.

### Tool invocation

- **GitHub Copilot in agent mode:** On the first use of each tool in a session, Copilot
  presents a confirmation dialog. The user can allow once, allow always for the session, or
  deny. This is VS Code-level gating, not MCP-level.
- **Claude Code:** Claude Code requests user approval before using project-scoped MCP servers
  for the first time. Approvals are stored per project.
- **Modeling MCP elicitation:** When the Modeling MCP server is running in `--readwrite` mode
  (without `--skipconfirmation`), it implements the MCP elicitation protocol to request
  approval before the first write and before the first query. This is a second gate at the
  server level, independent of the client-level confirmation.

### RBAC

The Modeling MCP server authenticates using the identity of the signed-in Windows user (or
via the `--authmode` flag for service principal). It can only access models that the signed-in
user has Build permission on in Power BI Desktop.

The Remote MCP server authenticates via Entra ID OAuth. The signed-in user's Power BI RBAC
permissions govern which workspaces and models are accessible. Row-level security defined in
the model is enforced by the Power BI engine and is not bypassed by MCP tool calls.

### The `--readonly` flag

The `--readonly` flag is enforced at the Modeling MCP server level: any tool invocation that
would modify the model returns an error. It is not a client-side hint; it is a server-side
constraint. This makes it safe to point `--readonly` configurations at production models
during evaluation without risk of accidental changes.

### Network exposure

The Modeling MCP server listens only on localhost and is not exposed to the network.
The Remote MCP server is a public HTTPS endpoint but requires Entra ID authentication for
every request. No PBIX data leaves the local machine via the Modeling MCP path.

---

## Operational notes

- Power BI Desktop must remain open while the Modeling MCP server is in use. Closing Desktop
  terminates the Analysis Services engine and all subsequent tool calls will fail with a
  connection error.
- The local Analysis Services port is dynamic. If the PBIX file is closed and reopened, the
  port changes and `scripts/Get-OpenPbixModel.ps1` must be re-run to update
  `config/semantic-model-ids.local.json`.
- The Modeling MCP server process is started by VS Code when it reads `.vscode/mcp.json`. If
  VS Code restarts, it will restart the server process. There is no persistent daemon.
- The Remote MCP server is stateless from the client's perspective. Each HTTP session
  authenticates independently. Token expiry causes 401 errors; re-running
  `scripts/Connect-PowerBIInteractive.ps1` refreshes the token.
