# Scenario 04 -- Bulk measure description enrichment

Use the Modeling MCP server in write mode to add descriptions to all measures that currently
have none. The agent generates one-sentence descriptions from each measure's name and DAX
expression, presents the full list of planned changes for explicit user approval, and only
writes to the model after the user confirms and the server elicitation gate activates.

This is the first write scenario in this spike. Read the safety section carefully before
starting.

---

## Safety: configure --readwrite before running

The Modeling MCP server must be running without `--readonly` for this scenario. The default
configuration created by `scripts/Initialize-Workspace.ps1` uses `--readonly`. You must change
it before starting.

**Step 1 -- Use a test copy of the PBIX file**

Do not run this scenario against a production PBIX file. Make a copy:

```
MyReport.pbix  ->  MyReport-TEST.pbix
```

Open the test copy in Power BI Desktop. Run `scripts/Get-OpenPbixModel.ps1` to register
the test file as the active model.

**Step 2 -- Change the server flags in VS Code**

Open `.vscode/mcp.json` and change `--readonly` to `--readwrite`:

```jsonc
{
  "servers": {
    "powerbi-modeling-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@microsoft/powerbi-modeling-mcp@latest", "--start", "--readwrite"]
    }
  }
}
```

**Step 3 -- Change the server flags in Claude Code**

Open `.mcp.json` and apply the same change:

```json
{
  "mcpServers": {
    "powerbi-modeling-mcp": {
      "command": "npx",
      "args": ["-y", "@microsoft/powerbi-modeling-mcp@latest", "--start", "--readwrite"]
    }
  }
}
```

**Step 4 -- Restart the MCP server**

In VS Code: open the MCP output panel and click "Restart server". In Claude Code: restart
the Claude Code session so the new server flags take effect.

**Step 5 -- Revert after the scenario**

When the scenario is complete, restore both config files to `--readonly` and restart the
server again. Confirm with `scripts/Test-McpConnectivity.ps1`.

---

## Pre-conditions

- A TEST copy of the PBIX file is open in Power BI Desktop (not the production file).
- The Modeling MCP server is running with `--readwrite` and WITHOUT `--skipconfirmation`.
- `scripts/Get-OpenPbixModel.ps1` has been run and points to the test PBIX.
- The test model contains at least some measures without descriptions (run Scenario 03 first
  to identify them).

---

## Suggested prompt

Paste the following into the GitHub Copilot agent chat window or Claude Code session.

```
You are enriching a Power BI semantic model by adding descriptions to measures that
currently have none. This model is a TEST copy -- not production.

Active model: [paste model name from config/semantic-model-ids.local.json]

Step 1 -- Discovery
Use the MCP tools to list all measures. Filter to those with no description (empty or null).
If there are no measures without descriptions, stop and report that the model is already
fully documented.

Step 2 -- Generate descriptions
For each measure without a description, write a one-sentence plain-English description
(maximum 120 characters) based on the measure's name and DAX expression. Focus on what the
measure calculates, not how. Do not include the DAX expression in the description.

Step 3 -- Confirm before writing
Before writing a single description, output the complete list of planned changes in this
format:

  Measure: [measure name]
  Current description: (none)
  Proposed description: [your generated description]

Then stop and ask: "Do you approve these [N] changes? Respond YES to proceed, NO to cancel."

Step 4 -- Write
Only after the user responds YES: write each description using the appropriate MCP write
tool. The server will request elicitation approval before the first write -- accept it to
proceed.

Step 5 -- Verify
After all writes complete, call get_measures again and confirm that every measure now has
a description. Report how many were updated and flag any that were skipped or failed.
```

---

## Expected tool sequence

1. Get all measures (`get_measures`)
2. Filter to measures with no description (in-context processing, no tool call)
3. Generate descriptions (in-context processing, no tool call)
4. Output proposed changes list and pause for user confirmation
5. [USER confirms YES]
6. [SERVER elicitation gate activates -- user approves in the elicitation prompt]
7. Update each measure description (`update_measure` or equivalent) x N
8. Get all measures again (`get_measures`) to verify

Steps 6 and 7 represent two separate confirmation gates: one from the user in the chat and
one from the server elicitation protocol. Both must activate for writes to proceed.

---

## Validation steps

After the agent completes:

1. Open Power BI Desktop with the test PBIX and check the measure descriptions in the
   Fields pane or Model view. They should match the descriptions the agent generated.
2. Verify that the agent presented the full list of changes BEFORE writing any of them.
3. Verify that the elicitation gate activated (the server should have asked for approval
   before the first `update_measure` call).
4. Verify that no measures that already had descriptions were overwritten.
5. Revert the config files to `--readonly` as described in the Safety section above.

---

## Acceptance criteria

- All measures that previously had no description now have one.
- No measure that already had a description was modified.
- The agent presented the full change list and paused for explicit user approval before
  writing.
- The server elicitation gate activated at least once during the session.
- Descriptions are accurate representations of what each measure calculates (no hallucinated
  column or table names in the description text).
- Wall-clock time is less than `<TBD: see docs/05-validation-results.md Section B>`.

---

## How to configure --skipconfirmation (advanced)

The default for this scenario deliberately omits `--skipconfirmation` to demonstrate the
elicitation protocol. If you want to run the scenario without per-session confirmation gates
(for example in a fully automated context), add `--skipconfirmation` to the server args:

```json
"args": ["-y", "@microsoft/powerbi-modeling-mcp@latest", "--start", "--readwrite", "--skipconfirmation"]
```

Only use this in non-production environments where automated writes are intentional.

---

## How to record your run

After completing this scenario, fill in the corresponding row in
[docs/05-validation-results.md](../docs/05-validation-results.md) Section B:

| Field | Value |
|---|---|
| Client used | GitHub Copilot / Claude Code |
| Model used | (test copy name) |
| Wall-clock time | measured from first prompt to verification complete |
| Premium requests consumed | (Copilot only -- check quota dashboard) |
| Measures updated | count |
| Change list shown before writing | yes / no |
| Elicitation gate activated | yes / no |
| Descriptions accurate | yes / no |
| No unintended overwrites | yes / no |
| Config reverted to --readonly after | yes / no |
| Notes | |
