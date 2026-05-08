# Scenario 01 -- Read-only semantic model discovery

Generate structured documentation for a semantic model without modifying it.
The agent reads all tables, columns, measures, relationships, RLS roles, and data sources via
the Modeling MCP server or the Remote MCP server, then produces a Markdown document with a
Mermaid entity-relationship diagram.

---

## Pre-conditions

One of the following must be true before starting the chat session:

- **Local PBIX path (Windows only):** Power BI Desktop is open with a PBIX file loaded,
  and `scripts/Get-OpenPbixModel.ps1` has been run so that `config/semantic-model-ids.local.json`
  contains a `localPbix` entry. The Modeling MCP server must be running (started by VS Code or
  `npx @microsoft/powerbi-modeling-mcp@latest --start --readonly`).

- **Workspace model path:** `scripts/Select-Workspace.ps1` has been run so that
  `config/semantic-model-ids.local.json` contains a `selectedWorkspace` and `selectedModel`
  entry. The Remote MCP server must be reachable (verify with `scripts/Test-McpConnectivity.ps1`).

---

## Suggested prompt

Paste the following into the GitHub Copilot agent chat window or Claude Code session.
Replace the bracketed placeholders with your actual values.

```
You are working with a Power BI semantic model.

Active model: [paste the model name from config/semantic-model-ids.local.json,
or "the open PBIX file" if using the local path]

Use the available MCP tools to inspect the model and produce a Markdown documentation
document with the following sections, in this order:

## Overview
Two to three sentences describing the model: its apparent business domain, number of tables,
total measures, and data source type (DirectQuery, Import, or mixed).

## Entity-relationship diagram
A Mermaid erDiagram block showing all tables and their relationships. Include the cardinality
direction (one-to-many, many-to-many). Use the exact table names from the model.

## Tables
A Markdown table with columns: Table name, Row count (if available), Storage mode, Description
(from the model annotation if present, otherwise leave blank).

## Measures
Group measures by display folder. Within each group, sort alphabetically. For each measure,
show: Name, Expression (truncated to 120 characters), Format string, Description.

## Row-level security
List each RLS role, its DAX filter expression per table, and the tables it filters. If there
are no RLS roles, write "No RLS roles defined."

## Data sources
List each data source: type (SQL Server, Azure SQL, Dataflow, etc.), server or URL (masked to
last 4 characters if it contains a hostname), and the tables that draw from it.

Produce only the Markdown document. Do not include any preamble or closing remarks.
Save the output to out/model-documentation.md.
```

---

## Expected tool sequence

The agent should call tools in roughly this order (exact names depend on the MCP server version):

1. List tables (`get_tables` or equivalent)
2. Get columns for each table (`get_columns`)
3. Get relationships (`get_relationships`)
4. Get measures (`get_measures`)
5. Get RLS roles (`get_security_roles` or equivalent)
6. Get data sources (`get_datasources` or equivalent)
7. Write documentation to `out/model-documentation.md`

---

## Validation steps

After the agent completes:

1. Open `out/model-documentation.md`.
2. Verify that the Mermaid `erDiagram` block renders without syntax errors.
   (Paste the block into [mermaid.live](https://mermaid.live) to check.)
3. Verify that table names in the diagram match the actual tables in the model.
4. Verify that the measure count matches what you see in Power BI Desktop or the service.
5. Verify that no sensitive identifiers (workspace IDs, model IDs, server hostnames) appear
   in full -- they should be masked to the last four characters.

Run `scripts/Export-ModelDocumentation.ps1` to generate an HTML preview:

```powershell
.\scripts\Export-ModelDocumentation.ps1 -InputFile out\model-documentation.md
```

This produces `out/model-documentation.preview.html` and prints a table count and measure
count derived from the Markdown structure.

---

## Acceptance criteria

- The Mermaid diagram renders without error.
- Every table visible in Power BI Desktop appears in the diagram.
- Measure count in the document matches the model (within 1 -- some models have hidden
  system measures that the API may or may not expose).
- The document contains no fabricated data (e.g., invented column names).
- Wall-clock time is less than `<TBD: see section B of docs/05-validation-results.md>`.

---

## Variations

- **Subset documentation:** Add "Document only the tables whose names start with 'Sales'"
  to the prompt to limit scope.
- **Delta documentation:** Run scenario 01 before and after a model change, then diff the
  two output files with `git diff --no-index out/model-documentation-before.md out/model-documentation-after.md`.
- **CI integration:** Call `Export-ModelDocumentation.ps1 -Validate` in a CI step to fail
  the pipeline if the Mermaid block is invalid.

---

## How to record your run

After completing this scenario, fill in the corresponding row in
[docs/05-validation-results.md](../docs/05-validation-results.md) Section B:

| Field | Value |
|---|---|
| Client used | GitHub Copilot / Claude Code |
| Model used | (model name from chat panel) |
| Wall-clock time | measured from first prompt to file write complete |
| Premium requests consumed | (Copilot only -- check quota dashboard) |
| Mermaid diagram valid | yes / no |
| Table count accurate | yes / no |
| Notes | |
