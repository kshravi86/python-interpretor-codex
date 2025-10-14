<#!
.SYNOPSIS
  Removes the Microsoft Store iTunes app for all users and deprovisions it so standalone iTunes can install.

.DESCRIPTION
  - Detects iTunes Store package (AppleInc.iTunes) for all users
  - Removes user-installed copies (AllUsers)
  - Deprovisions the package (so new users don’t get it)
  - Optionally signs out other users (manual step recommended)

.PARAMETER Force
  Proceed without confirmation.

.NOTES
  Run as Administrator. After removal, reboot, then run the standalone iTunes installer.
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
Param(
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

Assert-Admin

if (-not $Force) {
  $ans = Read-Host 'This will remove Microsoft Store iTunes for all users and deprovision it. Continue? (y/N)'
  if ($ans -notin @('y','Y','yes','YES')) { Write-Host 'Aborted.'; exit 1 }
}

Write-Host 'Locating iTunes Microsoft Store packages (AppleInc.iTunes)...' -ForegroundColor Cyan
$pkgName = 'AppleInc.iTunes'

try {
  $userPkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $pkgName }
} catch {
  Write-Warning 'Failed to query Appx packages. Ensure you are running as Administrator.'
  $userPkgs = @()
}

if ($userPkgs -and $PSCmdlet.ShouldProcess('All users','Remove-AppxPackage')) {
  foreach ($p in $userPkgs) {
    Write-Host ("Removing user package: {0} ({1})" -f $p.Name,$p.PackageFullName)
    try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop } catch { Write-Warning $_.Exception.Message }
  }
} else {
  Write-Host 'No user iTunes Store packages found (or already removed).'
}

Write-Host 'Deprovisioning iTunes Store package for new users...' -ForegroundColor Cyan
try {
  $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $pkgName }
  foreach ($dp in $prov) {
    Write-Host ("Removing provisioned package: {0}" -f $dp.PackageName)
    try { Remove-AppxProvisionedPackage -Online -PackageName $dp.PackageName -ErrorAction Stop | Out-Null } catch { Write-Warning $_.Exception.Message }
  }
} catch {
  Write-Warning 'Failed to query provisioned packages.'
}

# Attempt user-by-user removal using SIDs (covers stale/offline profiles)
Write-Host 'Enumerating all user profiles to remove per-user packages...' -ForegroundColor Cyan
try {
  $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^S-1-5-21-' }
  foreach ($p in $profiles) {
    $sid = $p.PSChildName
    Write-Host "  Checking user SID: $sid"
    try {
      $pkgs = Get-AppxPackage -User $sid -Name $pkgName -ErrorAction SilentlyContinue
      foreach ($k in $pkgs) {
        Write-Host ("    Removing per-user package: {0}" -f $k.PackageFullName)
        try { Remove-AppxPackage -Package $k.PackageFullName -User $sid -ErrorAction Stop } catch { Write-Warning $_.Exception.Message }
      }
    } catch {}
  }
} catch {}

# DISM deprovision (fallback)
Write-Host 'Running DISM to remove provisioned iTunes package (fallback)...' -ForegroundColor Cyan
try {
  $dismList = (& dism.exe /Online /Get-ProvisionedAppxPackages | Out-String)
  $lines = $dismList -split "`r?`n"
  $curr = $null; $targets = @()
  foreach ($l in $lines) {
    if ($l -match '^PackageName\s*:\s*(.+)$') { $curr = $Matches[1].Trim() }
    if ($l -match '^DisplayName\s*:\s*(.+)$') {
      $dn = $Matches[1].Trim()
      if ($dn -eq $pkgName -and $curr) { $targets += $curr; $curr = $null }
    }
  }
  foreach ($t in $targets) {
    Write-Host ("DISM removing provisioned: {0}" -f $t)
    try { & dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:$t | Out-Null } catch { Write-Warning $_.Exception.Message }
  }
} catch { Write-Warning 'DISM provisioned package enumeration failed.' }

Write-Host 'Resetting Microsoft Store cache (wsreset)...' -ForegroundColor Cyan
try { Start-Process -FilePath wsreset.exe -Wait -WindowStyle Hidden } catch {}

Write-Host 'Done. Please reboot, then run the standalone iTunes installer.' -ForegroundColor Green
