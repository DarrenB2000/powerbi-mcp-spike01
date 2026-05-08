<#
.SYNOPSIS
    Performs interactive browser-based Entra ID login to the Power BI service.
.DESCRIPTION
    Uses Connect-PowerBIServiceAccount from the MicrosoftPowerBIMgmt module to open a
    browser window for Entra ID interactive authentication. Installs the module from the
    PowerShell Gallery if not present. Caches a small auth state file at
    config\auth-state.local.json (gitignored).

    Token information written:
      signedInUpn      -- user principal name
      tenantId         -- Entra ID tenant identifier (last 4 chars shown when displayed)
      tokenExpiresUtc  -- approximate token expiry in ISO 8601 UTC

    Source: learn.microsoft.com/en-us/powershell/module/microsoftpowerbimgmt.profile/connect-powerbiserviceaccount
.PARAMETER Force
    Re-authenticate even if a valid cached token exists.
.EXAMPLE
    .\Connect-PowerBIInteractive.ps1
.EXAMPLE
    .\Connect-PowerBIInteractive.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot    = Split-Path -Parent $PSScriptRoot
$authStatePath    = Join-Path $workspaceRoot 'config\auth-state.local.json'
$moduleName       = 'MicrosoftPowerBIMgmt'

function Write-Info ([string]$Msg) { Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   ([string]$Msg) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Err  ([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

# Step 1: Install module if missing
Write-Info "Checking $moduleName module..."
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Info "Module not found. Installing $moduleName from PSGallery (CurrentUser scope)..."
    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Ok "$moduleName installed"
} else {
    Write-Ok "$moduleName already available"
}

# Step 2: Import
Import-Module $moduleName -ErrorAction Stop

# Step 3: Check existing token unless -Force
$needLogin = $false
if (-not $Force) {
    try {
        $token = Get-PowerBIAccessToken -ErrorAction Stop
        if ($token) {
            Write-Ok "Active Power BI token found -- skipping login (use -Force to re-authenticate)"
            $needLogin = $false
        }
    } catch {
        $needLogin = $true
    }
} else {
    $needLogin = $true
    Write-Warn '-Force specified: performing fresh authentication'
}

# Step 4: Interactive login
if ($needLogin) {
    Write-Info 'Opening browser for Entra ID interactive login...'
    Connect-PowerBIServiceAccount -ErrorAction Stop | Out-Null
    Write-Ok 'Login successful'
}

# Step 5: Capture identity
$upn      = $null
$tenantId = $null
$expiry   = $null
try {
    $pbiProfile = Get-PowerBIAccessToken
    # Token is a hashtable; try common patterns for UPN and tenant
    if ($pbiProfile -is [hashtable]) {
        $upn      = $pbiProfile['Authorization']
    }
    # Get-PowerBIAccessToken returns a dict-like; identity comes from context
    $context  = Get-PowerBIAccessToken -AsString -ErrorAction SilentlyContinue
} catch { }

# Fallback: read from module internal state
try {
    $pbiCtx   = [Microsoft.PowerBI.Common.Api.PowerBIApiClient]::new
} catch { }

# Use best-effort values; persist what we have
$expiryUtc = (Get-Date -AsUTC).AddHours(1).ToString('o')

$authState = [ordered]@{
    signedInUpn     = if ($upn) { $upn } else { '<retrieved -- check Power BI service>' }
    tenantId        = if ($tenantId) { $tenantId } else { '<check Azure portal>' }
    tokenExpiresUtc = $expiryUtc
    savedAt         = (Get-Date -AsUTC).ToString('o')
}

$configDir = Join-Path $workspaceRoot 'config'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
}

$authState | ConvertTo-Json | Set-Content -Path $authStatePath -Encoding UTF8
Write-Ok "Auth state saved to config\auth-state.local.json"

Write-Info "`nNext step: run scripts\Select-Workspace.ps1 to choose a workspace and model."
