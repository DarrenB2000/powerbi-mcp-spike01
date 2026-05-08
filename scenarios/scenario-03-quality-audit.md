# Scenario 03 -- Model quality audit

Inspect a semantic model for common anti-patterns without modifying it and produce a
structured quality report with prioritized findings. The agent evaluates the model against
its own structure -- no external schema file is required.

---

## Pre-conditions

One of the following must be true before starting the chat session:

- **Local PBIX path (Windows only):** Power BI Desktop is open with a PBIX file loaded
  and `scripts/Get-OpenPbixModel.ps1` has been run so that `config/semantic-model-ids.local.json`
  contains a `localPbix` entry. The Modeling MCP server must be running with `--readonly`.

- **Workspace model path:** `scripts/Select-Workspace.ps1` has been run so that
  `config/semantic-model-ids.local.json` contains a `selectedWorkspace` and `selectedModel`
  entry. The Modeling MCP server must be running with `--readonly`.

Verify the setup: `.\scripts\Test-McpConnectivity.ps1`

---

## Suggested prompt

Paste the following into the GitHub Copilot agent chat window or Claude Code session.

```
You are auditing a Power BI semantic model for quality issues. Do not modify anything.

Active model: [paste model name from config/semantic-model-ids.local.json]

Use the available MCP tools to inspect the model and produce a quality report at
out/quality-report.md. The report must contain the following sections in this order:

## Summary
A four-line table: total issues found, broken down by HIGH / MEDIUM / LOW severity,
and an overall verdict: Clean / Needs review / Action required.

## HIGH severity issues
Items in this category indicate gaps that affect usability or correctness:
- Measures with no description AND no format string
- Tables with no relationships to any other table (isolated tables)
- Columns whose names suggest a key role (contain "Key", "ID", or "Ref") but are not
  part of any relationship

## MEDIUM severity issues
Items in this category indicate documentation or organization gaps:
- Measures with no description (but which do have a format string)
- Measures with no format string (but which do have a description)
- Measures not assigned to any display folder (sitting at the root level)
- Tables with no visible columns (all columns are hidden)

## LOW severity issues
Items in this category indicate style or hygiene improvements:
- Tables whose names contain spaces (prefer underscores or PascalCase)
- Measures whose names start with a lowercase letter

## Clean objects
Count of tables and measures that passed all checks above. One line per category.

For each issue, show: object type (Table / Column / Measure), object name, the specific
check that failed, and the severity label in brackets: [HIGH], [MEDIUM], or [LOW].

Do not fabricate any column or measure names. Use only names returned by the MCP tools.
Save the output to out/quality-report.md.
```

---

## Expected tool sequence

The agent should call tools in roughly this order (exact names depend on the MCP server version):

1. List tables (`get_tables` or equivalent)
2. Get columns for each table (`get_columns`)
3. Get relationships (`get_relationships`)
4. Get measures (`get_measures`)
5. Cross-reference all results to evaluate the checks described above
6. Write report to `out/quality-report.md`

No write tools should be called during this scenario. If the agent attempts to call a write
tool, deny the action and note it in the "Notes" field of the run record.

---

## Validation steps

After the agent completes:

1. Open `out/quality-report.md`.
2. Verify that all five sections are present (Summary, HIGH, MEDIUM, LOW, Clean objects).
3. Spot-check two or three HIGH severity findings against the actual model in Power BI Desktop.
4. Verify that no measure or table name in the report appears to be fabricated (every name
   should be recognizable from the model).
5. Verify that no write tools were called during the session (check the agent tool-call log).

---

## Acceptance criteria

- All five report sections are present.
- Severity labels are applied consistently (HIGH / MEDIUM / LOW in brackets).
- No object names in the report are fabricated.
- No write tools were called during the session.
- The Summary verdict is consistent with the issue counts.
- Wall-clock time is less than `<TBD: see docs/05-validation-results.md Section B>`.

---

## Anti-patterns reference

The checks in this scenario are based on widely documented Power BI modeling best practices.
The severity assignments used here are:

| Check | Severity | Rationale |
|---|---|---|
| Measure: no description AND no format string | HIGH | Unusable for end users without context or formatting |
| Table: no relationships | HIGH | Isolated table cannot participate in cross-filter |
| Column: key-like name not in any relationship | HIGH | Likely a missing relationship |
| Measure: no description | MEDIUM | Documentation gap, usable but undiscoverable |
| Measure: no format string | MEDIUM | Displays raw numbers, confusing for end users |
| Measure: no display folder | MEDIUM | Model becomes hard to navigate at scale |
| Table: all columns hidden | MEDIUM | Table may be unreachable from report visuals |
| Table: name contains spaces | LOW | Causes backtick quoting in DAX expressions |
| Measure: name starts with lowercase | LOW | Inconsistent capitalization style |

Teams may adjust severity assignments by editing the prompt before running the scenario.

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
| HIGH issues found | count |
| MEDIUM issues found | count |
| LOW issues found | count |
| Findings accurate | yes / no |
| No write tools called | yes / no |
| Notes | |
