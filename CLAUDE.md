# Standing instructions for AI agents working with Power BI MCP servers

> This file is used as custom instructions for GitHub Copilot in VS Code.
> Place a copy (or this exact content) at `.github/copilot-instructions.md` for Copilot.
> Place the same content at `CLAUDE.md` in the project root for Claude Code -- Claude Code reads
> CLAUDE.md automatically at the start of every session.

---

## Inspect before modifying

Before calling any write tool on a semantic model, call the appropriate read tool first to
confirm the current state of the object (table, column, measure, relationship). Never assume
the model matches what a previous response described.

## Server selection

Use the **powerbi-modeling-mcp** server for all semantic model authoring tasks:
- Adding, editing, or deleting measures, columns, tables, relationships, and RLS rules.
- Reading model metadata when you need the full TOM (Tabular Object Model) representation.

Use the **powerbi-remote** server for all analytical queries:
- Natural-language questions answered by DAX execution.
- Schema inspection when metadata is sufficient and you do not need to author.
- Generating DAX query results for validation or reporting.

Do not call both servers for the same logical operation. Prefer the modeling server when the
task is about model structure; prefer the remote server when the task is about data retrieval.

## Read-only contract

When the modeling server is configured with `--readonly`, all write tool invocations will be
rejected by the server. Treat this as a hard contract: do not attempt to work around it by
constructing raw XMLA requests or using alternative paths. If a write is needed, ask the user
to restart the server without `--readonly` and confirm they have a backup or version snapshot.

## Model catalog

A catalog of known semantic models is in `config/semantic-model-ids.json` (committed template)
and optionally in `config/semantic-model-ids.local.json` (user-specific, gitignored).
When both exist, prefer the entries in `semantic-model-ids.local.json`. The local file also
contains a `localPbix` section (populated by `scripts/Get-OpenPbixModel.ps1`) and a
`selectedWorkspace` / `selectedModel` section (populated by `scripts/Select-Workspace.ps1`).

Before asking the user for a workspace ID or model ID, read the local catalog file.

## Documentation output style

When producing model documentation (scenario 01 output or similar):
- Use Mermaid `erDiagram` syntax for entity-relationship diagrams.
- Use sentence case for all headings.
- Do not use emojis or em-dashes.
- Group measures by their display folder. Within each group, sort alphabetically.
- Use fenced code blocks for all DAX, SQL, and JSON examples.
- Do not include workspace IDs or model IDs in committed documentation output.

## DAX style

- Use `VAR` / `RETURN` blocks for any measure longer than one expression.
- Use explicit `CALCULATE` filter arguments rather than implicit filter propagation.
- Use `DIVIDE(numerator, denominator, [alternateResult])` instead of the `/` operator.
- Include a brief description comment above each new measure, using `--` syntax.

## Bulk operations and confirmation

Before modifying more than three objects in a single agent turn, list the planned changes and
ask the user to confirm. This applies even when `--skipconfirmation` is in effect at the server
level, because the MCP server confirmation is per-session, not per-operation batch.
