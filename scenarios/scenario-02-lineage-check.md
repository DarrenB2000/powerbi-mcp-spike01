# Scenario 02 -- Lineage validation against Gold schema

Compare the columns currently in the semantic model against the expected Gold layer view
definitions in `config/expected-gold-schema.json`. The agent surfaces three categories of
discrepancy: broken references (model columns that no longer exist in the source views),
orphan model columns (model columns with no counterpart in any Gold view), and upstream
additions (Gold view columns not yet reflected in the model).

---

## Pre-conditions

The same pre-conditions as scenario 01 apply -- either a local PBIX file is active or a
workspace model has been selected via `scripts/Select-Workspace.ps1`.

Additionally:
- `config/expected-gold-schema.json` must contain the Gold layer view definitions for your
  environment. Replace the placeholder entries with your actual views and columns before running.
- The agent needs read access to both the semantic model (via MCP) and the JSON file
  (accessible from the project root).

---

## Suggested prompt

```
You are performing a lineage validation for a Power BI semantic model.

Active model: [paste model name]
Gold schema file: config/expected-gold-schema.json

Step 1 -- Read the Gold schema file and build an index: for each view, record the set of
column names defined there.

Step 2 -- Use the MCP tools to list all tables in the semantic model. For each table, list
all columns (name and source expression if available).

Step 3 -- Compare and produce a report with three sections:

### Broken references (severity: high)
Model columns or measures that reference a column name, table name, or view name that does
not appear in config/expected-gold-schema.json. List each as:
  - Table.Column (or MeasureName): <reason it is broken> [HIGH]

### Orphan model columns (severity: medium)
Columns that exist in the semantic model but have no corresponding column in any view in
config/expected-gold-schema.json. These may be calculated columns, derived columns, or stale
imports. List each as:
  - Table.Column: <type, e.g., calculated / imported> [MEDIUM]

### Upstream additions (severity: low)
Columns defined in config/expected-gold-schema.json that do not appear in any table in the
semantic model. These may represent new source fields not yet modeled. List each as:
  - View.Column: <data type from Gold schema> [LOW]

### Summary
A four-line summary: total broken references, total orphan columns, total upstream additions,
and an overall recommendation (OK to publish / needs review / blocked).

Save the report to out/lineage-report.md.
```

---

## Expected tool sequence

1. Read `config/expected-gold-schema.json` (file read tool or equivalent)
2. List tables in the semantic model (`get_tables`)
3. Get columns for each table (`get_columns`)
4. (Optional) Get measures to check for broken column references in DAX (`get_measures`)
5. Write report to `out/lineage-report.md`

The agent should not call any write tools on the model during this scenario.

---

## How to test the detection logic

To verify that the agent correctly surfaces broken references, temporarily add a clearly
non-existent column to `config/expected-gold-schema.json` (for example, add `"name": "DOES_NOT_EXIST"`
to `vw_sales_fact`) and confirm it appears in the "upstream additions" section of the report.
Then revert the change and re-run to confirm the column disappears from the report.

---

## Validation steps

After the agent completes:

1. Open `out/lineage-report.md`.
2. Verify that the three sections are present and each item has a severity label.
3. Spot-check two or three entries in "Broken references" against the actual model.
4. Verify that "Upstream additions" includes any columns you deliberately added to
   `expected-gold-schema.json` but have not yet added to the model.
5. Verify that no write tools were called during the session.

---

## Acceptance criteria

- The report contains all three sections.
- Severity labels are applied consistently.
- No write tools were called during the session (verify via agent tool-call log).
- The summary recommendation is consistent with the counts.
- Wall-clock time is less than `<TBD: see section B of docs/05-validation-results.md>`.

---

## Recommended next step -- CI integration

This scenario is suitable for CI because it requires only read access and produces a
structured Markdown report. To integrate:

1. Add a CI step that runs `scripts/Measure-AutomatedChecks.ps1` to confirm prerequisites.
2. Invoke the agent programmatically using the Claude API or GitHub Copilot CLI with the
   prompt above.
3. Parse `out/lineage-report.md` with a simple script: fail the pipeline if any HIGH
   severity items are present.

See `scripts/Measure-AutomatedChecks.ps1` for an example of calling scripts from CI.

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
| Broken references found | count |
| Orphan columns found | count |
| Upstream additions found | count |
| Report consistent with model | yes / no |
| Notes | |
