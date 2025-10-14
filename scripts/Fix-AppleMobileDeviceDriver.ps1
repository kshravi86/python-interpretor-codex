<#!
.SYNOPSIS
  Fixes Apple Mobile Device USB driver detection for iPhone on Windows.

.DESCRIPTION
  - Verifies Apple Mobile Device driver INF exists.
  - Installs/repairs the driver using pnputil.
  - Restarts the Apple Mobile Device Service.
  - Optionally downloads and installs standalone iTunes (to lay down drivers) if missing.

.PARAMETER DriverDir
  Optional path to the Apple Mobile Device Support\Drivers folder containing usbaapl64.inf/usbaapl.inf.

.PARAMETER InstallITunes
  If set, downloads and installs standalone iTunes for Windows x64 if drivers are missing.

.PARAMETER ITunesUrl
  Override URL to iTunes installer (default: Apple's x64 link).

.PARAMETER SkipServiceRestart
  If set, skips stopping/starting the Apple Mobile Device Service.

.PARAMETER Force
  Proceed without confirmation when installing iTunes.

.NOTES
  Run as Administrator. Disconnect/reconnect iPhone after running. Reboot may be required.
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
Param(
  [string]$DriverDir = '',
  [switch]$InstallITunes,
  [string]$ITunesUrl = 'https://www.apple.com/itunes/download/win64',
  [switch]$SkipServiceRestart,
  [switch]$Force
)

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal $id
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Please run this script as Administrator.'
    exit 1
  }
}

function Find-DriverDir {
  param([string]$hint)
  $candidates = @()
  if ($hint) { $candidates += $hint }
  $candidates += @(
    "$env:ProgramFiles\Common Files\Apple\Mobile Device Support\Drivers",
    "$env:ProgramFiles(x86)\Common Files\Apple\Mobile Device Support\Drivers"
  )
  foreach ($d in $candidates) {
    if ([string]::IsNullOrWhiteSpace($d)) { continue }
    if (Test-Path (Join-Path $d 'usbaapl64.inf') -PathType Leaf -ErrorAction SilentlyContinue) { return $d }
    if (Test-Path (Join-Path $d 'usbaapl.inf') -PathType Leaf -ErrorAction SilentlyContinue) { return $d }
  }
  # Deep search (last resort)
  try {
    $root = "$env:ProgramFiles\Common Files\Apple"
    if (Test-Path $root) {
      $match = Get-ChildItem -Recurse -Filter 'usbaapl*.inf' -Path $root -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($match) { return Split-Path -Path $match.FullName -Parent }
    }
  } catch {}
  return ''
}

function Install-Driver([string]$dir) {
  $inf64 = Join-Path $dir 'usbaapl64.inf'
  $inf32 = Join-Path $dir 'usbaapl.inf'
  $found = @()
  if (Test-Path $inf64) { $found += $inf64 }
  if (Test-Path $inf32) { $found += $inf32 }
  if (-not $found) { return $false }
  $ok = $true
  foreach ($inf in $found) {
    Write-Host "Installing driver: $inf" -ForegroundColor Cyan
    try {
      $p = Start-Process -FilePath pnputil.exe -ArgumentList @('/add-driver', '"' + $inf + '"', '/install') -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
      if ($p.ExitCode -ne 0) { $ok = $false }
    } catch { $ok = $false }
  }
  return $ok
}

function Restart-AMDS {
  param([switch]$skip)
  if ($skip) { return }
  $svcName = 'Apple Mobile Device Service'
  $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
  if ($svc) {
    Write-Host 'Restarting Apple Mobile Device Service...' -ForegroundColor Cyan
    try { if ($svc.Status -ne 'Stopped') { Stop-Service -Name $svcName -Force -ErrorAction Stop } } catch {}
    try {
      Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
      Start-Service -Name $svcName -ErrorAction SilentlyContinue
    } catch {}
  } else {
    Write-Warning 'Apple Mobile Device Service not found. It will be installed with iTunes if missing.'
  }
}

function Ensure-ITunesInstalled {
  param([string]$url,[switch]$force)
  $driverHome = "$env:ProgramFiles\Common Files\Apple\Mobile Device Support\Drivers"
  if (Test-Path (Join-Path $driverHome 'usbaapl64.inf')) { return $true }
  if (-not $InstallITunes) { return $false }
  if (-not $Force) {
    $ans = Read-Host "Download & install iTunes from $url ? (y/N)"
    if ($ans -notin @('y','Y','yes','YES')) { return $false }
  }
  try {
    $tmp = Join-Path $env:TEMP ('iTunes64Setup-' + [Guid]::NewGuid().ToString('N') + '.exe')
    Write-Host "Downloading iTunes..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    Write-Host "Installing iTunes silently..." -ForegroundColor Cyan
    $p = Start-Process -FilePath $tmp -ArgumentList @('/quiet','/norestart') -PassThru -Wait -WindowStyle Hidden
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $true
  } catch {
    Write-Warning "Failed to download/install iTunes: $($_.Exception.Message)"
    return $false
  }
}

Assert-Admin

Write-Host 'Fixing Apple Mobile Device driver...' -ForegroundColor Green

# Locate driver dir
$dir = if ($DriverDir) { $DriverDir } else { Find-DriverDir -hint $DriverDir }
if (-not $dir) {
  Write-Warning 'Apple driver INF not found. Attempting to install iTunes to lay down drivers...'
  $ok = Ensure-ITunesInstalled -url $ITunesUrl -force:$Force
  if ($ok) { $dir = Find-DriverDir -hint '' }
}

if (-not $dir) {
  Write-Error 'Apple Mobile Device driver INF not found. Please install standalone iTunes, then re-run.'
  exit 1
}

Write-Host "Using driver directory: $dir" -ForegroundColor Cyan

Restart-AMDS -skip:$SkipServiceRestart
$res = Install-Driver -dir $dir
if (-not $res) { Write-Warning 'Driver install returned non-zero. It may already be installed; continuing.' }
Restart-AMDS -skip:$SkipServiceRestart

Write-Host 'Done. Disconnect/reconnect iPhone, then reopen Sideloadly.' -ForegroundColor Green

