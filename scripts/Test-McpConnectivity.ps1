<#
.SYNOPSIS
    Runs a full smoke test of the Power BI MCP spike setup.
.DESCRIPTION
    Checks all components required for the spike and prints PASS, WARN, or FAIL per check.
    Exits with a count of FAIL results (0 = all passed).

    Checks performed:
      - Required config files present (.vscode/mcp.json, .mcp.json, CLAUDE.md,
        .github/copilot-instructions.md)
      - VS Code minimum version (1.99)
      - Auth state file present and token not expired (config\auth-state.local.json)
      - Workspace and model selected (config\semantic-model-ids.local.json)
      - Power BI Desktop instance detected (Windows only, non-fatal if absent)
      - HTTPS reachability of Remote MCP endpoint (api.fabric.microsoft.com:443)
.EXAMPLE
    .\Test-McpConnectivity.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$workspaceRoot    = Split-Path -Parent $PSScriptRoot
$failCount        = 0
$warnCount        = 0
$minVsCodeVersion = [Version]'1.99.0'
$remoteMcpHost    = 'api.fabric.microsoft.com'
$remoteMcpPort    = 443

function Write-Section ([string]$Title) {
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

function Write-Pass ([string]$Msg) {
    Write-Host "  [PASS] $Msg" -ForegroundColor Green
}

function Write-Warn ([string]$Msg) {
    Write-Host "  [WARN] $Msg" -ForegroundColor Yellow
    $script:warnCount++
}

function Write-Fail ([string]$Msg) {
    Write-Host "  [FAIL] $Msg" -ForegroundColor Red
    $script:failCount++
}

#region Config files
Write-Section 'Configuration files'
$configFiles = @(
    [PSCustomObject]@{ Path = '.vscode\mcp.json';                   Label = 'VS Code MCP config';            Required = $true  }
    [PSCustomObject]@{ Path = '.mcp.json';                          Label = 'Claude Code MCP config';        Required = $true  }
    [PSCustomObject]@{ Path = 'CLAUDE.md';                          Label = 'CLAUDE.md';                     Required = $false }
    [PSCustomObject]@{ Path = '.github\copilot-instructions.md';    Label = 'Copilot instructions';          Required = $false }
)
foreach ($cf in $configFiles) {
    $fullPath = Join-Path $workspaceRoot $cf.Path
    if (Test-Path $fullPath) {
        Write-Pass "$($cf.Label): $($cf.Path)"
    } elseif ($cf.Required) {
        Write-Fail "$($cf.Label) not found: $($cf.Path) -- run scripts\Initialize-Workspace.ps1"
    } else {
        Write-Warn "$($cf.Label) not found: $($cf.Path) -- run scripts\Initialize-Workspace.ps1"
    }
}
#endregion

#region VS Code version
Write-Section 'VS Code version'
try {
    $rawVer = (code --version 2>&1) | Select-Object -First 1
    $ver    = [Version]$rawVer
    if ($ver -ge $minVsCodeVersion) {
        Write-Pass "VS Code $ver (minimum $minVsCodeVersion)"
    } else {
        Write-Fail "VS Code $ver is below minimum $minVsCodeVersion"
    }
} catch {
    Write-Fail 'VS Code not found in PATH'
}
#endregion

#region Auth state
Write-Section 'Auth state (Power BI service login)'
$authStatePath = Join-Path $workspaceRoot 'config\auth-state.local.json'
if (Test-Path $authStatePath) {
    try {
        $authState = Get-Content -Raw $authStatePath | ConvertFrom-Json
        $expiry    = [datetime]::Parse($authState.tokenExpiresUtc).ToUniversalTime()
        $now       = (Get-Date).ToUniversalTime()
        if ($expiry -gt $now) {
            Write-Pass "Cached token expires at $($expiry.ToString('o')) UTC (valid)"
        } else {
            Write-Warn "Cached token expired at $($expiry.ToString('o')) UTC -- run scripts\Connect-PowerBIInteractive.ps1"
        }
    } catch {
        Write-Warn "auth-state.local.json present but could not parse -- run scripts\Connect-PowerBIInteractive.ps1"
    }
} else {
    Write-Warn "Auth state not found -- run scripts\Connect-PowerBIInteractive.ps1 to sign in"
}
#endregion

#region Workspace and model selection
Write-Section 'Workspace and model selection'
$localCatalogPath = Join-Path $workspaceRoot 'config\semantic-model-ids.local.json'
if (Test-Path $localCatalogPath) {
    try {
        $catalog = Get-Content -Raw $localCatalogPath | ConvertFrom-Json
        if ($catalog.selectedWorkspace) {
            $wsId = $catalog.selectedWorkspace.id
            $maskedId = if ($wsId -and $wsId.Length -ge 4) { '...' + $wsId.Substring($wsId.Length - 4) } else { '...' }
            Write-Pass "Workspace selected: $($catalog.selectedWorkspace.name) ($maskedId)"
        } else {
            Write-Warn "No workspace selected in local catalog -- run scripts\Select-Workspace.ps1"
        }
        if ($catalog.selectedModel) {
            $mId = $catalog.selectedModel.id
            $maskedMId = if ($mId -and $mId.Length -ge 4) { '...' + $mId.Substring($mId.Length - 4) } else { '...' }
            Write-Pass "Model selected: $($catalog.selectedModel.name) ($maskedMId)"
        } else {
            Write-Warn "No model selected -- run scripts\Select-Workspace.ps1"
        }
        if ($catalog.localPbix) {
            Write-Pass "Local PBIX entry: $($catalog.localPbix.pbixFileName) (port: $($catalog.localPbix.localPort))"
        }
    } catch {
        Write-Warn "Could not parse semantic-model-ids.local.json"
    }
} else {
    Write-Warn "semantic-model-ids.local.json not found -- run scripts\Select-Workspace.ps1"
}
#endregion

#region PBIX detection (Windows only)
Write-Section 'Power BI Desktop detection (Windows only)'
if ($env:OS -eq 'Windows_NT' -or $IsWindows) {
    $desktopProcs = @(Get-Process -Name 'PBIDesktop' -ErrorAction SilentlyContinue)
    if ($desktopProcs.Count -gt 0) {
        Write-Pass "$($desktopProcs.Count) Power BI Desktop instance(s) running (PID: $($desktopProcs.Id -join ', '))"
    } else {
        Write-Warn 'Power BI Desktop not running -- required for Modeling MCP (local PBIX path only)'
    }
} else {
    Write-Pass 'Non-Windows OS: Modeling MCP local path not applicable'
}
#endregion

#region Remote MCP reachability
Write-Section "Remote MCP endpoint reachability ($remoteMcpHost`:$remoteMcpPort)"
try {
    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    $task      = $tcpClient.ConnectAsync($remoteMcpHost, $remoteMcpPort)
    $completed = $task.Wait(5000)
    if ($completed -and $tcpClient.Connected) {
        Write-Pass "$remoteMcpHost`:$remoteMcpPort is reachable"
    } else {
        Write-Fail "$remoteMcpHost`:$remoteMcpPort unreachable (timeout) -- check network/firewall"
    }
    $tcpClient.Close()
} catch {
    Write-Fail "TCP connection to $remoteMcpHost`:$remoteMcpPort failed: $($_.Exception.Message)"
}
#endregion

#region Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($failCount -eq 0 -and $warnCount -eq 0) {
    Write-Host "  All checks passed." -ForegroundColor Green
} elseif ($failCount -eq 0) {
    Write-Host "  $warnCount warning(s). Review warnings before running scenarios." -ForegroundColor Yellow
} else {
    Write-Host "  $failCount failure(s), $warnCount warning(s). Resolve failures before proceeding." -ForegroundColor Red
}
#endregion

exit $failCount
