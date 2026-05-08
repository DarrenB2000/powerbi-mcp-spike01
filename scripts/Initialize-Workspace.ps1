<#
.SYNOPSIS
    Bootstraps workspace configuration files from templates.
.DESCRIPTION
    Copies config template files to their working locations:
      config/mcp.json.example          -> .vscode/mcp.json
      config/copilot-instructions.md   -> .github/copilot-instructions.md
      config/claude-code-mcp.json.example -> .mcp.json
      config/copilot-instructions.md   -> CLAUDE.md
    Creates the out/ output folder. Does not overwrite existing files unless
    -Force is specified. Safe to run multiple times.
.PARAMETER Force
    Overwrite existing destination files.
.PARAMETER WorkspaceRoot
    Override the workspace root directory. Defaults to the parent of the scripts/ folder.
    Used by Measure-AutomatedChecks.ps1 to run against a temporary directory.
.EXAMPLE
    .\Initialize-Workspace.ps1
.EXAMPLE
    .\Initialize-Workspace.ps1 -Force
.EXAMPLE
    .\Initialize-Workspace.ps1 -WorkspaceRoot C:\Temp\spike-test
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$WorkspaceRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}

$WorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path
Write-Host "Workspace root: $WorkspaceRoot" -ForegroundColor Cyan

function Copy-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label
    )
    $srcPath  = Join-Path $WorkspaceRoot $Source
    $destPath = Join-Path $WorkspaceRoot $Destination

    if (-not (Test-Path $srcPath)) {
        Write-Host "  [FAIL] Source not found: $Source" -ForegroundColor Red
        return
    }

    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    if ((Test-Path $destPath) -and -not $Force) {
        Write-Host "  [SKIP] $Label already exists (use -Force to overwrite)" -ForegroundColor Yellow
        return
    }

    Copy-Item -Path $srcPath -Destination $destPath -Force
    Write-Host "  [DONE] $Label -> $Destination" -ForegroundColor Green
}

Write-Host "`n=== Copying configuration templates ===" -ForegroundColor Cyan

Copy-TemplateFile `
    -Source      'config\mcp.json.example' `
    -Destination '.vscode\mcp.json' `
    -Label       'VS Code MCP config'

Copy-TemplateFile `
    -Source      'config\copilot-instructions.md' `
    -Destination '.github\copilot-instructions.md' `
    -Label       'GitHub Copilot instructions'

Copy-TemplateFile `
    -Source      'config\claude-code-mcp.json.example' `
    -Destination '.mcp.json' `
    -Label       'Claude Code MCP config'

Copy-TemplateFile `
    -Source      'config\copilot-instructions.md' `
    -Destination 'CLAUDE.md' `
    -Label       'CLAUDE.md (Claude Code project instructions)'

# Create the output folder
$outDir = Join-Path $WorkspaceRoot 'out'
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Write-Host "  [DONE] Created out/ folder" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] out/ folder already exists" -ForegroundColor Yellow
}

Write-Host "`nInitialization complete." -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. scripts\Get-OpenPbixModel.ps1       (Windows: detect open PBIX file)" -ForegroundColor White
Write-Host "  2. scripts\Connect-PowerBIInteractive.ps1  (sign in to Power BI service)" -ForegroundColor White
Write-Host "  3. scripts\Select-Workspace.ps1            (choose a workspace and model)" -ForegroundColor White
Write-Host "  4. scripts\Test-McpConnectivity.ps1        (verify the full setup)" -ForegroundColor White
