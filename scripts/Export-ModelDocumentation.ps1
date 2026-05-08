<#
.SYNOPSIS
    Post-processes scenario 01 output to an HTML preview.
.DESCRIPTION
    Reads a Markdown file produced by scenario 01 (or any Markdown with an erDiagram block),
    validates the Mermaid erDiagram block, counts tables and measures heuristically, and
    generates an HTML preview using marked.js and mermaid.js loaded from CDN.

    Security note: the Markdown content is JSON-encoded via ConvertTo-Json -Compress before
    being embedded in the script block. Any "</script" sequence is replaced with "<\/script"
    to prevent script-tag injection. The HTML is built as an array of strings to avoid
    PowerShell here-string interpolation hazards.
.PARAMETER InputFile
    Path to the Markdown file to convert. Defaults to out\model-documentation.md.
.PARAMETER OutputFile
    Path for the generated HTML file. Defaults to InputFile with .preview.html extension.
.PARAMETER Validate
    Exit with code 1 if no valid Mermaid erDiagram block is found (for CI use).
.EXAMPLE
    .\Export-ModelDocumentation.ps1
.EXAMPLE
    .\Export-ModelDocumentation.ps1 -InputFile out\model-documentation.md -Validate
#>
[CmdletBinding()]
param(
    [string]$InputFile  = '',
    [string]$OutputFile = '',
    [switch]$Validate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrEmpty($InputFile)) {
    $InputFile = Join-Path $workspaceRoot 'out\model-documentation.md'
}
if ([string]::IsNullOrEmpty($OutputFile)) {
    $OutputFile = [System.IO.Path]::ChangeExtension($InputFile, '.preview.html')
}

function Write-Info ([string]$Msg) { Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   ([string]$Msg) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Err  ([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

if (-not (Test-Path $InputFile)) {
    Write-Err "Input file not found: $InputFile"
    exit 1
}

$markdownContent = Get-Content -Raw $InputFile

# Validate Mermaid erDiagram block
$hasMermaid = $markdownContent -match '```mermaid[\s\S]*?erDiagram[\s\S]*?```'
if ($hasMermaid) {
    Write-Ok 'Mermaid erDiagram block detected'
} else {
    Write-Warn 'No Mermaid erDiagram block found in the document'
    if ($Validate) {
        Write-Err 'Validation failed: erDiagram block required (-Validate)'
        exit 1
    }
}

# Heuristic counts
$tableMatches   = [regex]::Matches($markdownContent, '(?m)^\|\s*\w')
$measureMatches = [regex]::Matches($markdownContent, '(?m)^\|\s*[A-Za-z].*\|.*\|.*MEASURE|(?:DIVIDE|CALCULATE|SUM|AVERAGE|COUNT)\(')
$tableCount     = [math]::Max(0, $tableMatches.Count - 2)  # subtract header rows
$measureCount   = $measureMatches.Count
Write-Info "Heuristic table rows: ~$tableCount  |  measure references: ~$measureCount"

# Encode Markdown safely for embedding in script block
$jsonEncoded = $markdownContent | ConvertTo-Json -Compress
$jsonEncoded = $jsonEncoded -replace '</script', '<\/script'

# Build HTML as array to avoid here-string interpolation issues
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('<!DOCTYPE html>')
$lines.Add('<html lang="en">')
$lines.Add('<head>')
$lines.Add('  <meta charset="UTF-8">')
$lines.Add('  <meta name="viewport" content="width=device-width, initial-scale=1.0">')
$lines.Add('  <title>Model documentation preview</title>')
$lines.Add('  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"><\/script>')
$lines.Add('  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"><\/script>')
$lines.Add('  <style>')
$lines.Add('    body { font-family: system-ui, sans-serif; max-width: 960px; margin: 2rem auto; padding: 0 1rem; }')
$lines.Add('    pre { background: #f5f5f5; padding: 1rem; overflow-x: auto; }')
$lines.Add('    table { border-collapse: collapse; width: 100%; }')
$lines.Add('    th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }')
$lines.Add('    th { background: #f0f0f0; }')
$lines.Add('  <\/style>')
$lines.Add('<\/head>')
$lines.Add('<body>')
$lines.Add('  <div id="content"><\/div>')
$lines.Add('  <script>')
$lines.Add("  var md = $jsonEncoded;")
$lines.Add('  document.getElementById("content").innerHTML = marked.parse(md);')
$lines.Add('  mermaid.initialize({ startOnLoad: true });')
$lines.Add('  mermaid.run({ querySelector: ".language-mermaid" });')
$lines.Add('  <\/script>')
$lines.Add('<\/body>')
$lines.Add('<\/html>')

$htmlContent = $lines -join "`n"
# Restore escaped closing tags to real HTML
$htmlContent = $htmlContent -replace '<\\/', '</'

$outDir = Split-Path -Parent $OutputFile
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

Set-Content -Path $OutputFile -Value $htmlContent -Encoding UTF8
Write-Ok "HTML preview written to $OutputFile"
Write-Info "Open in a browser to view the rendered documentation."
