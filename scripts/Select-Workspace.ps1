<#
.SYNOPSIS
    Lists accessible Power BI workspaces and prompts the user to select one.
.DESCRIPTION
    Enumerates Power BI workspaces via Get-PowerBIWorkspace, presents a numbered console menu,
    and then optionally lists semantic models in the selected workspace via Get-PowerBIDataset
    for a second selection. Persists the choice to config\semantic-model-ids.local.json under
    "selectedWorkspace" and "selectedModel" keys, preserving any existing "localPbix" entry.

    Requires an active Power BI token (run Connect-PowerBIInteractive.ps1 first).
.PARAMETER Filter
    Pre-filter the workspace list by a case-insensitive substring.
.PARAMETER WorkspaceIdOnly
    Skip the semantic model selection step after choosing a workspace.
.EXAMPLE
    .\Select-Workspace.ps1
.EXAMPLE
    .\Select-Workspace.ps1 -Filter "Sales"
.EXAMPLE
    .\Select-Workspace.ps1 -WorkspaceIdOnly
#>
[CmdletBinding()]
param(
    [string]$Filter = '',
    [switch]$WorkspaceIdOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot    = Split-Path -Parent $PSScriptRoot
$localCatalogPath = Join-Path $workspaceRoot 'config\semantic-model-ids.local.json'
$moduleName       = 'MicrosoftPowerBIMgmt'

function Write-Info ([string]$Msg) { Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   ([string]$Msg) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Err  ([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Invoke-NumberedMenu {
    param(
        [string]$Title,
        [object[]]$Items,
        [scriptblock]$LabelBlock
    )
    Write-Host "`n$Title" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $label = & $LabelBlock $Items[$i]
        Write-Host ("  [{0,2}] {1}" -f ($i + 1), $label)
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $raw = Read-Host "Select [1-$($Items.Count)] (or 'q' to quit)"
        if ($raw -eq 'q') { return $null }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $Items.Count) {
            return $Items[[int]$raw - 1]
        }
        Write-Host "  Invalid choice. Enter a number between 1 and $($Items.Count)." -ForegroundColor Yellow
    }
    Write-Err 'No valid selection after 3 attempts.'
    return $null
}

# Verify module
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Err "Module $moduleName not installed. Run scripts\Connect-PowerBIInteractive.ps1 first."
    exit 1
}
Import-Module $moduleName -ErrorAction Stop

# Verify token
try {
    $token = Get-PowerBIAccessToken -ErrorAction Stop
    if (-not $token) { throw 'No token' }
} catch {
    Write-Err "No active Power BI token found. Run scripts\Connect-PowerBIInteractive.ps1 first."
    exit 1
}

# List workspaces
Write-Info 'Retrieving workspace list...'
$workspaces = @(Get-PowerBIWorkspace -All -ErrorAction Stop)

if ($Filter) {
    $workspaces = @($workspaces | Where-Object { $_.Name -ilike "*$Filter*" })
}

if ($workspaces.Count -eq 0) {
    Write-Warn 'No workspaces found matching the filter (or no accessible workspaces).'
    exit 0
}

$selectedWorkspace = Invoke-NumberedMenu `
    -Title 'Available workspaces:' `
    -Items $workspaces `
    -LabelBlock { param($ws) '{0,-40} (id: ...{1})' -f $ws.Name, ($ws.Id.ToString()[-4..-1] -join '') }

if ($null -eq $selectedWorkspace) {
    Write-Info 'Selection cancelled.'
    exit 0
}

Write-Ok "Selected workspace: $($selectedWorkspace.Name)"

# Optionally list models
$selectedModel = $null
if (-not $WorkspaceIdOnly) {
    Write-Info "Retrieving semantic models in workspace '$($selectedWorkspace.Name)'..."
    $models = @(Get-PowerBIDataset -WorkspaceId $selectedWorkspace.Id -ErrorAction Stop)
    if ($models.Count -eq 0) {
        Write-Warn 'No semantic models found in the selected workspace.'
    } else {
        $selectedModel = Invoke-NumberedMenu `
            -Title 'Available semantic models:' `
            -Items $models `
            -LabelBlock { param($m) '{0,-40} (id: ...{1})' -f $m.Name, ($m.Id.ToString()[-4..-1] -join '') }
        if ($selectedModel) {
            Write-Ok "Selected model: $($selectedModel.Name)"
        }
    }
}

# Persist to catalog, preserving any existing localPbix entry
$catalog = [ordered]@{}
if (Test-Path $localCatalogPath) {
    try {
        $existing = Get-Content -Raw $localCatalogPath | ConvertFrom-Json
        foreach ($prop in $existing.PSObject.Properties) {
            $catalog[$prop.Name] = $prop.Value
        }
    } catch { }
}

$catalog['selectedWorkspace'] = [ordered]@{
    name        = $selectedWorkspace.Name
    id          = $selectedWorkspace.Id.ToString()
    selectedAt  = (Get-Date -AsUTC).ToString('o')
}

if ($selectedModel) {
    $catalog['selectedModel'] = [ordered]@{
        name        = $selectedModel.Name
        id          = $selectedModel.Id.ToString()
        workspaceId = $selectedWorkspace.Id.ToString()
        selectedAt  = (Get-Date -AsUTC).ToString('o')
    }
}

$configDir = Join-Path $workspaceRoot 'config'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
}

$catalog | ConvertTo-Json -Depth 5 | Set-Content -Path $localCatalogPath -Encoding UTF8
Write-Ok "Saved to config\semantic-model-ids.local.json"
Write-Info "`nNext step: run scripts\Test-McpConnectivity.ps1 to verify the full setup."
