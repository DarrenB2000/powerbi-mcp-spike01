<#
.SYNOPSIS
    Verifies and installs prerequisites for the Power BI MCP spike.
.DESCRIPTION
    Checks VS Code (minimum version 1.99), Node.js, and .NET 8 SDK availability.
    Installs the GitHub Copilot, GitHub Copilot Chat, and Power BI Modeling MCP
    VS Code extensions. Safe to run multiple times.
.PARAMETER SkipExtensions
    Skip VS Code extension installation checks and installs.
.EXAMPLE
    .\Install-PowerBIMcpPrereqs.ps1
.EXAMPLE
    .\Install-PowerBIMcpPrereqs.ps1 -SkipExtensions
#>
[CmdletBinding()]
param(
    [switch]$SkipExtensions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$minVsCodeVersion  = [Version]'1.99.0'
$requiredExtensions = @(
    'GitHub.copilot',
    'GitHub.copilot-chat',
    'Analysis-services.powerbi-modeling-mcp'
)
$failCount = 0
$warnCount = 0

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

#region VS Code
Write-Section 'VS Code'
try {
    $rawVersion = (code --version 2>&1) | Select-Object -First 1
    $vsCodeVersion = [Version]$rawVersion
    if ($vsCodeVersion -ge $minVsCodeVersion) {
        Write-Pass "VS Code $vsCodeVersion meets minimum requirement ($minVsCodeVersion)"
    } else {
        Write-Fail "VS Code $vsCodeVersion is below minimum $minVsCodeVersion -- update at https://code.visualstudio.com/download"
    }
} catch {
    Write-Fail "VS Code not found in PATH -- install from https://code.visualstudio.com/download"
}
#endregion

#region Node.js
Write-Section 'Node.js'
try {
    $nodeVersion = (node --version 2>&1)
    Write-Pass "Node.js $nodeVersion (required for npx-based powerbi-modeling-mcp installation)"
} catch {
    Write-Warn "Node.js not found -- required for the npx installation path. Install from https://nodejs.org/"
}
#endregion

#region .NET SDK
Write-Section '.NET SDK'
try {
    $sdkList = (dotnet --list-sdks 2>&1)
    $dotnet8 = $sdkList | Where-Object { $_ -match '^8\.' }
    if ($dotnet8) {
        Write-Pass ".NET 8 SDK found: $($dotnet8 -join '; ')"
    } else {
        Write-Warn ".NET 8 SDK not detected. Available SDKs: $($sdkList -join '; '). Install from https://dotnet.microsoft.com/download"
    }
} catch {
    Write-Warn ".NET SDK tooling not found in PATH"
}
#endregion

#region VS Code extensions
if ($SkipExtensions) {
    Write-Section 'VS Code extensions'
    Write-Warn 'Extension install skipped (-SkipExtensions)'
} else {
    Write-Section 'VS Code extensions'
    foreach ($extId in $requiredExtensions) {
        try {
            $installedList = (code --list-extensions 2>&1)
            $alreadyInstalled = $installedList -icontains $extId
            if ($alreadyInstalled) {
                Write-Pass "$extId already installed"
            } else {
                Write-Host "  Installing $extId..." -ForegroundColor Cyan
                code --install-extension $extId --force 2>&1 | Out-Null
                Write-Pass "$extId installed"
            }
        } catch {
            Write-Fail "Failed to install $extId -- $($_.Exception.Message)"
        }
    }
}
#endregion

#region Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($failCount -eq 0 -and $warnCount -eq 0) {
    Write-Host "  All checks passed." -ForegroundColor Green
} elseif ($failCount -eq 0) {
    Write-Host "  $warnCount warning(s). Review warnings before proceeding." -ForegroundColor Yellow
} else {
    Write-Host "  $failCount failure(s), $warnCount warning(s). Resolve failures before running the spike." -ForegroundColor Red
}
#endregion

exit $failCount
