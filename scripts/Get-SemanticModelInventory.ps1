<#
.SYNOPSIS
    Enumerates accessible Power BI workspaces and semantic models.
.DESCRIPTION
    Installs MicrosoftPowerBIMgmt if missing, authenticates via Connect-PowerBIInteractive.ps1,
    then lists all workspaces and the semantic models within them. Optionally writes a
    semantic-model-ids.local.json catalog file suitable for use with the spike scripts.
.PARAMETER OutFile
    Path to write the JSON catalog. Defaults to config\semantic-model-ids.local.json.
.PARAMETER WorkspaceFilter
    Case-insensitive substring filter for workspace names.
.EXAMPLE
    .\Get-SemanticModelInventory.ps1
.EXAMPLE
    .\Get-SemanticModelInventory.ps1 -WorkspaceFilter "Sales" -OutFile out\my-catalog.json
#>
[CmdletBinding()]
param(
    [string]$OutFile = '',
    [string]$WorkspaceFilter = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot  = Split-Path -Parent $PSScriptRoot
$moduleName     = 'MicrosoftPowerBIMgmt'

if ([string]::IsNullOrEmpty($OutFile)) {
    $OutFile = Join-Path $workspaceRoot 'config\semantic-model-ids.local.json'
}

function Write-Info ([string]$Msg) { Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   ([string]$Msg) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }

# Install module if missing
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Info "Installing $moduleName..."
    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Ok "$moduleName installed"
}
Import-Module $moduleName -ErrorAction Stop

# Ensure authenticated -- call Connect-PowerBIInteractive.ps1 if needed
try {
    $token = Get-PowerBIAccessToken -ErrorAction Stop
    if (-not $token) { throw 'No token' }
    Write-Ok 'Active token found'
} catch {
    Write-Info 'No active token. Running Connect-PowerBIInteractive.ps1...'
    & (Join-Path $PSScriptRoot 'Connect-PowerBIInteractive.ps1')
}

# Enumerate workspaces
Write-Info 'Retrieving workspaces...'
$allWorkspaces = @(Get-PowerBIWorkspace -All -ErrorAction Stop)
if ($WorkspaceFilter) {
    $allWorkspaces = @($allWorkspaces | Where-Object { $_.Name -ilike "*$WorkspaceFilter*" })
}
Write-Ok "Found $($allWorkspaces.Count) workspace(s)"

# Build catalog
$catalogModels = [System.Collections.Generic.List[object]]::new()
foreach ($ws in $allWorkspaces) {
    Write-Info "  Scanning workspace: $($ws.Name)..."
    $datasets = @(Get-PowerBIDataset -WorkspaceId $ws.Id -ErrorAction SilentlyContinue)
    foreach ($ds in $datasets) {
        $catalogModels.Add([ordered]@{
            name        = $ds.Name
            description = ''
            workspaceId = $ws.Id.ToString()
            modelId     = $ds.Id.ToString()
            workspace   = $ws.Name
            environment = 'service'
        })
    }
}

Write-Ok "Total semantic models found: $($catalogModels.Count)"

# Read existing catalog so we preserve localPbix and selectedWorkspace keys
$existing = [ordered]@{}
if (Test-Path $OutFile) {
    try {
        $raw = Get-Content -Raw $OutFile | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $existing[$p.Name] = $p.Value }
    } catch { }
}

$existing['models'] = $catalogModels
$existing['inventoryGeneratedAt'] = (Get-Date -AsUTC).ToString('o')

$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$existing | ConvertTo-Json -Depth 5 | Set-Content -Path $OutFile -Encoding UTF8
Write-Ok "Catalog written to $OutFile"
