<#!
.SYNOPSIS
  Finds and exports recent iOS crash logs (.ips) from a connected iPhone on Windows.

.DESCRIPTION
  Searches the standard Apple CrashReporter folders populated by iTunes/Apple Devices
  when an iPhone is connected and trusted. You can filter by bundle identifier or
  process name, list the most recent logs, print the header, and optionally copy
  logs to a destination directory.

.PARAMETER BundleId
  Optional bundle identifier to filter logs (e.g., com.venki18.codesnake).

.PARAMETER Process
  Optional process name to filter logs (e.g., CodeSnake).

.PARAMETER DeviceName
  Optional device folder name under CrashReporter\MobileDevice (auto-selects newest if omitted).

.PARAMETER Count
  Number of recent logs to display/copy. Default: 5.

.PARAMETER CopyTo
  Optional folder to copy matching .ips logs into (created if missing).

.PARAMETER ShowHeader
  If set, prints the first ~60 lines of each log for quick inspection.

.EXAMPLE
  # List the last 5 crashes for your app by bundle id
  .\scripts\Get-IOSCrashLogs.ps1 -BundleId com.venki18.codesnake -Count 5 -ShowHeader

.EXAMPLE
  # Copy the last crash to a folder
  .\scripts\Get-IOSCrashLogs.ps1 -BundleId com.venki18.codesnake -Count 1 -CopyTo C:\Temp\ios-crashes

#>
[CmdletBinding()] Param(
  [string]$BundleId = '',
  [string]$Process = '',
  [string]$DeviceName = '',
  [int]$Count = 5,
  [string]$CopyTo = '',
  [switch]$ShowHeader
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-CrashRoot {
  $paths = @(
    Join-Path $env:APPDATA 'Apple Computer\Logs\CrashReporter\MobileDevice'),
    'C:\ProgramData\Apple Computer\Logs\CrashReporter\MobileDevice'
  foreach ($p in $paths) { if (Test-Path $p) { return $p } }
  return $null
}

function Get-DeviceFolder($root, $name) {
  $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
  if (-not $dirs) { return $null }
  if ($name) {
    $match = $dirs | Where-Object { $_.Name -eq $name }
    if ($match) { return $match.FullName }
    Write-Warning "Device '$name' not found under $root. Available: $($dirs.Name -join ', ')"
  }
  # Pick the most recently updated device folder
  return ($dirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Test-LogMatches($path, $bundleId, $proc) {
  if (-not (Test-Path $path)) { return $false }
  try {
    if ($bundleId) {
      if (-not (Select-String -Path $path -Pattern [Regex]::Escape($bundleId) -Quiet)) { return $false }
    }
    if ($proc) {
      if (-not (Select-String -Path $path -Pattern ('^\s*Process:\s*' + [Regex]::Escape($proc)) -Quiet)) { return $false }
    }
    return $true
  } catch {
    return $false
  }
}

$root = Resolve-CrashRoot
if (-not $root) {
  Write-Error "CrashReporter folder not found. Please install iTunes/Apple Devices, connect + trust your iPhone, open the app once, then rerun."
}

$deviceFolder = Get-DeviceFolder -root $root -name $DeviceName
if (-not $deviceFolder) {
  Write-Error "No device folders found under $root. Ensure the phone is connected and synced once."
}

Write-Host "Crash root: $root"
Write-Host "Device folder: $deviceFolder"

$allLogs = Get-ChildItem -Path $deviceFolder -Recurse -File -Filter *.ips -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending

if (-not $allLogs) {
  Write-Warning "No .ips crash logs found under $deviceFolder. Trigger the crash again, then reopen Apple Devices/iTunes and rerun."
  return
}

$filtered = @()
foreach ($f in $allLogs) {
  if (Test-LogMatches -path $f.FullName -bundleId $BundleId -proc $Process) { $filtered += $f }
  if ($filtered.Count -ge $Count) { break }
}

if (-not $filtered -and ($BundleId -or $Process)) {
  Write-Warning "No logs matched filters. Showing latest $Count logs regardless."
  $filtered = $allLogs | Select-Object -First $Count
}

Write-Host "Found $($filtered.Count) log(s):" -ForegroundColor Cyan
foreach ($f in $filtered) {
  Write-Host ("- {0}  ({1})" -f $f.FullName, $f.LastWriteTime)
  if ($ShowHeader) {
    Write-Host "----- BEGIN HEADER -----" -ForegroundColor DarkGray
    try { Get-Content -Path $f.FullName -TotalCount 60 } catch {}
    Write-Host "----- END HEADER -------" -ForegroundColor DarkGray
  }
}

if ($CopyTo) {
  New-Item -ItemType Directory -Force -Path $CopyTo | Out-Null
  $copied = @()
  foreach ($f in $filtered) {
    try {
      $dest = Join-Path $CopyTo $f.Name
      Copy-Item -Path $f.FullName -Destination $dest -Force
      $copied += $dest
    } catch {
      Write-Warning "Failed to copy $($f.FullName): $($_.Exception.Message)"
    }
  }
  if ($copied.Count -gt 0) {
    Write-Host "Copied to: $CopyTo" -ForegroundColor Green
    foreach ($c in $copied) { Write-Host "  - $c" }
  }
}

Write-Host "Done."

