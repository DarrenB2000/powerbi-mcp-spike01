<#
.SYNOPSIS
    Detects Power BI Desktop instances and the PBIX file open in each.
.DESCRIPTION
    Finds running Power BI Desktop processes, locates the msmdsrv.exe Analysis Services
    engine child process for each instance, reads the dynamic port from msmdsrv.port.txt
    in the AnalysisServicesWorkspaces folder, and extracts the open PBIX file name from
    the process window title.

    Returns an array of objects with fields:
      PbixFileName, PbixFilePath, DesktopPid, MsmdsrvPid, LocalPort, ConnectionString

    Port file location (per Microsoft documentation):
      %LOCALAPPDATA%\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces\
        AnalysisServicesWorkspace[N]\msmdsrv.port.txt

    Source: biinsight.com/four-different-ways-to-find-your-power-bi-desktop-local-port-number/

    Persists the selected entry to config\semantic-model-ids.local.json under the key "localPbix".

    This script is Windows-only. On other operating systems it exits cleanly with code 0.
.PARAMETER NonInteractive
    When multiple PBIX files are open, fail instead of presenting a selection menu.
.PARAMETER Quiet
    Suppress informational output. Errors are still written.
.EXAMPLE
    .\Get-OpenPbixModel.ps1
.EXAMPLE
    .\Get-OpenPbixModel.ps1 -NonInteractive -Quiet
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info ([string]$Msg) {
    if (-not $Quiet) { Write-Host $Msg -ForegroundColor Cyan }
}

function Write-Highlight ([string]$Msg) {
    if (-not $Quiet) { Write-Host $Msg -ForegroundColor Green }
}

# Non-Windows: exit cleanly
if ($env:OS -ne 'Windows_NT' -and -not $IsWindows) {
    Write-Info 'Get-OpenPbixModel.ps1: not running on Windows. Skipping PBIX detection.'
    exit 0
}

$workspaceRoot  = Split-Path -Parent $PSScriptRoot
$localCatalogPath = Join-Path $workspaceRoot 'config\semantic-model-ids.local.json'
$portBaseDir    = "$env:LOCALAPPDATA\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces"

Write-Info 'Scanning for Power BI Desktop instances...'

# Step 1: Find PBIDesktop processes
$desktopProcs = Get-Process -Name 'PBIDesktop' -ErrorAction SilentlyContinue
if (-not $desktopProcs) {
    Write-Host 'No Power BI Desktop instances found. Open a PBIX file in Power BI Desktop and re-run.' -ForegroundColor Red
    exit 1
}

# Step 2: Find all msmdsrv.port.txt files
$portFiles = @()
if (Test-Path $portBaseDir) {
    $portFiles = Get-ChildItem -Path $portBaseDir -Filter 'msmdsrv.port.txt' -Recurse -ErrorAction SilentlyContinue
}

if (-not $portFiles) {
    Write-Host 'Power BI Desktop is running but no msmdsrv.port.txt files found.' -ForegroundColor Red
    Write-Host "Expected location: $portBaseDir" -ForegroundColor Yellow
    Write-Host 'The PBIX file may still be loading. Wait a few seconds and retry.' -ForegroundColor Yellow
    exit 1
}

# Step 3: Find all msmdsrv processes
$msmdsrvProcs = Get-CimInstance Win32_Process -Filter "Name = 'msmdsrv.exe'" -ErrorAction SilentlyContinue

# Step 4: Build result objects by matching port files to Desktop processes
$models = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($portFile in $portFiles) {
    $port = $null
    try {
        $port = [int](Get-Content -Raw $portFile.FullName).Trim()
    } catch {
        continue
    }

    # Try to correlate with a msmdsrv process via working directory
    $msmdsrvPid = $null
    if ($msmdsrvProcs) {
        foreach ($proc in $msmdsrvProcs) {
            $procDir = $null
            try { $procDir = Split-Path -Parent $proc.ExecutablePath } catch { }
            if ($portFile.FullName -like "$($portFile.DirectoryName)*") {
                $msmdsrvPid = $proc.ProcessId
                break
            }
        }
        # Fallback: assign the first unmatched msmdsrv if we have only one
        if (-not $msmdsrvPid -and $msmdsrvProcs.Count -eq 1) {
            $msmdsrvPid = $msmdsrvProcs[0].ProcessId
        }
    }

    # Match a Desktop process using window title (one per port file, round-robin if ambiguous)
    $desktopPid  = $null
    $pbixFileName = $null
    $pbixFilePath = $null

    foreach ($dp in $desktopProcs) {
        $title = $dp.MainWindowTitle
        if ($title -match '^(.+?)\s+-\s+Power BI Desktop$') {
            $pbixFileName = $Matches[1]
            $desktopPid   = $dp.Id
            break
        }
    }

    if (-not $desktopPid -and $desktopProcs.Count -gt 0) {
        $desktopPid = $desktopProcs[0].Id
    }

    $models.Add([PSCustomObject]@{
        PbixFileName     = $pbixFileName
        PbixFilePath     = $pbixFilePath
        DesktopPid       = $desktopPid
        MsmdsrvPid       = $msmdsrvPid
        LocalPort        = $port
        ConnectionString = "Data Source=localhost:$port"
    })
}

if ($models.Count -eq 0) {
    Write-Host 'Could not construct any model entries from discovered port files.' -ForegroundColor Red
    exit 1
}

# Step 5: Selection
$selected = $null
if ($models.Count -eq 1) {
    $selected = $models[0]
    $autoName = if ($selected.PbixFileName) { $selected.PbixFileName } else { '(unknown)' }
    Write-Highlight "Auto-selected: $autoName on port $($selected.LocalPort)"
} else {
    if ($NonInteractive) {
        Write-Host "Multiple PBIX instances found and -NonInteractive was specified. Cannot select automatically." -ForegroundColor Red
        exit 1
    }
    Write-Host "`nMultiple Power BI Desktop instances found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $models.Count; $i++) {
        $m = $models[$i]
        Write-Host "  [$($i + 1)] $($m.PbixFileName ?? '(unknown)') (port: $($m.LocalPort), Desktop PID: $($m.DesktopPid))"
    }
    $choice = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $raw = Read-Host "Select [1-$($models.Count)]"
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $models.Count) {
            $choice = [int]$raw
            break
        }
        Write-Host "Invalid choice. Enter a number between 1 and $($models.Count)." -ForegroundColor Yellow
    }
    if ($null -eq $choice) {
        Write-Host 'No valid selection made. Exiting.' -ForegroundColor Red
        exit 1
    }
    $selected = $models[$choice - 1]
}

# Step 6: Persist to local catalog
$catalog = [ordered]@{}
if (Test-Path $localCatalogPath) {
    try {
        $existing = Get-Content -Raw $localCatalogPath | ConvertFrom-Json
        foreach ($prop in $existing.PSObject.Properties) {
            $catalog[$prop.Name] = $prop.Value
        }
    } catch { }
}

$catalog['localPbix'] = [ordered]@{
    pbixFileName     = $selected.PbixFileName
    pbixFilePath     = $selected.PbixFilePath
    desktopPid       = $selected.DesktopPid
    msmdsrvPid       = $selected.MsmdsrvPid
    localPort        = $selected.LocalPort
    connectionString = $selected.ConnectionString
    detectedAt       = (Get-Date -AsUTC).ToString('o')
}

$configDir = Join-Path $workspaceRoot 'config'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
}

$catalog | ConvertTo-Json -Depth 5 | Set-Content -Path $localCatalogPath -Encoding UTF8
Write-Highlight "Saved to $localCatalogPath (localPbix section)"

# Return the selected object for pipeline use
return $selected
