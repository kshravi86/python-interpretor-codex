<#!
.SYNOPSIS
  Fully remove Apple TV (Store app), Apple Devices app, and classic Apple components (iTunes, Bonjour,
  Apple Mobile Device Support, Apple Application Support) from Windows.

.DESCRIPTION
  - Stops Apple services
  - Uninstalls Microsoft Store packages (Apple TV, Apple Devices) for current user and provisioned/all users
  - Attempts silent uninstall of classic Apple components via registry uninstall strings
  - Removes residual folders, registry keys, scheduled tasks, and firewall rules

.PARAMETER Force
  Proceed without confirmation.

.PARAMETER WhatIf
  Simulate actions without changes.

.NOTES
  Run as Administrator. Reboot recommended after removal.
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
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

function Stop-AppleServices {
  $svcNames = @('Apple Mobile Device Service','Bonjour Service')
  foreach ($s in $svcNames) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
      if ($PSCmdlet.ShouldProcess($s,'Stop-Service')) { try { Stop-Service -Name $s -Force -ErrorAction Stop } catch {} }
      if ($PSCmdlet.ShouldProcess($s,'Set-Service Disabled')) { try { Set-Service -Name $s -StartupType Disabled -ErrorAction Stop } catch {} }
    }
  }
}

function Remove-AppxPackages {
  $pkgPatterns = @('AppleInc.AppleDevices','AppleInc.AppleTV')
  foreach ($pat in $pkgPatterns) {
    try {
      $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -match [Regex]::Escape($pat) }
      foreach ($p in $pkgs) {
        if ($PSCmdlet.ShouldProcess($p.PackageFullName,'Remove-AppxPackage -AllUsers')) {
          try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop } catch {}
        }
      }
      # deprovision (for new users)
      $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match [Regex]::Escape($pat) }
      foreach ($dp in $prov) {
        if ($PSCmdlet.ShouldProcess($dp.PackageName,'Remove-AppxProvisionedPackage -Online')) {
          try { Remove-AppxProvisionedPackage -Online -PackageName $dp.PackageName -ErrorAction Stop | Out-Null } catch {}
        }
      }
    } catch {}
  }
}

function Get-UninstallEntries([string[]]$matchNames) {
  $roots = @(
    'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  $entries = @()
  foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $item = Get-ItemProperty $_.PsPath -ErrorAction Stop
        $dn = $item.DisplayName; $us = $item.UninstallString
        if ($dn) {
          foreach ($m in $matchNames) { if ($dn -match $m) { $entries += [pscustomobject]@{DisplayName=$dn; UninstallString=$us; Key=$_.PsPath} } }
        }
      } catch {}
    }
  }
  $entries | Sort-Object DisplayName -Unique
}

function Invoke-Uninstall([string]$displayName,[string]$uninstallString) {
  if (-not $uninstallString) { return $false }
  $exe = $null; $args = ''
  if ($uninstallString.StartsWith('msiexec', 'InvariantCultureIgnoreCase')) {
    $exe = 'msiexec.exe'
    $args = $uninstallString.Substring(7).Trim()
    if ($args -notmatch '/x') { $args = "/x $args" }
    if ($args -notmatch '/qn') { $args += ' /qn /norestart' }
  } else {
    if ($uninstallString.StartsWith('"')) { $exe, $args = $uninstallString -split '"\s+', 2; $exe = $exe.Trim('"') }
    else { $parts = $uninstallString -split '\s+', 2; $exe = $parts[0]; if ($parts.Count -gt 1) { $args = $parts[1] } }
    if ($args -notmatch '(?i)/silent|/verysilent|/S') { $args += ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
  }
  if (-not (Test-Path $exe)) { return $false }
  if ($PSCmdlet.ShouldProcess($displayName, "Uninstall via $exe $args")) {
    try { Start-Process -FilePath $exe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden | Out-Null; return $true } catch { return $false }
  }
  return $false
}

function Remove-Paths([string[]]$paths) {
  foreach ($p in $paths) {
    $ep = $ExecutionContext.InvokeCommand.ExpandString($p)
    if (Test-Path $ep) { if ($PSCmdlet.ShouldProcess($ep,'Remove-Item -Recurse -Force')) { try { Remove-Item -LiteralPath $ep -Recurse -Force -ErrorAction Stop } catch {} } }
  }
}

function Remove-RegistryKeys([string[]]$keys) {
  foreach ($k in $keys) {
    $ek = $ExecutionContext.InvokeCommand.ExpandString($k)
    if (Test-Path $ek) { if ($PSCmdlet.ShouldProcess($ek,'Remove-Item -Recurse -Force')) { try { Remove-Item -Path $ek -Recurse -Force -ErrorAction Stop } catch {} } }
  }
}

function Remove-ScheduledTasks([string[]]$namePatterns) {
  try {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($t in $tasks) {
      foreach ($pat in $namePatterns) {
        if ($t.TaskName -match $pat -or $t.TaskPath -match $pat) {
          if ($PSCmdlet.ShouldProcess($t.TaskName,'Unregister-ScheduledTask -Confirm:$false')) { try { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop } catch {} }
        }
      }
    }
  } catch {}
}

function Remove-FirewallRules([string[]]$namePatterns) {
  try {
    $rules = netsh advfirewall firewall show rule name=all | Out-String
    foreach ($pat in $namePatterns) {
      $lines = ($rules -split "`r?`n") | Where-Object { $_ -match '^Rule Name' -and $_ -match $pat }
      foreach ($l in $lines) {
        $name = ($l -replace 'Rule Name:\s*','').Trim()
        if ($name) { if ($PSCmdlet.ShouldProcess($name,'Delete firewall rule')) { & netsh advfirewall firewall delete rule name="$name" | Out-Null } }
      }
    }
  } catch {}
}

Assert-Admin

if (-not $Force) {
  $res = Read-Host 'This will remove Apple TV / Apple Devices and classic Apple components. Continue? (y/N)'
  if ($res -notin @('y','Y','yes','YES')) { Write-Host 'Aborted.'; exit 1 }
}

Write-Host 'Stopping Apple services...' -ForegroundColor Cyan
Stop-AppleServices

Write-Host 'Removing Microsoft Store apps (Apple TV, Apple Devices)...' -ForegroundColor Cyan
Remove-AppxPackages

Write-Host 'Uninstalling classic Apple components (iTunes, Bonjour, Apple Mobile Device Support, Apple Application Support)...' -ForegroundColor Cyan
$targets = @('(?i)iTunes','(?i)Bonjour','(?i)Apple Mobile Device Support','(?i)Apple Application Support','(?i)Apple Software Update')
$entries = Get-UninstallEntries -matchNames $targets
foreach ($e in $entries) { if ($e.UninstallString) { Invoke-Uninstall -displayName $e.DisplayName -uninstallString $e.UninstallString | Out-Null } }

Write-Host 'Removing residual folders...' -ForegroundColor Cyan
$paths = @(
  '$env:ProgramFiles\iTunes',
  '$env:ProgramFiles(x86)\iTunes',
  '$env:ProgramFiles\Bonjour',
  '$env:ProgramFiles(x86)\Bonjour',
  '$env:ProgramFiles\Common Files\Apple',
  '$env:ProgramFiles(x86)\Common Files\Apple',
  '$env:ProgramData\Apple',
  '$env:LOCALAPPDATA\Apple',
  '$env:APPDATA\Apple',
  '$env:ProgramData\Microsoft\Windows\Start Menu\Programs\iTunes',
  '$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Bonjour'
)
Remove-Paths -paths $paths

Write-Host 'Cleaning registry keys...' -ForegroundColor Cyan
$keys = @(
  'HKCU:\Software\Apple Inc.',
  'HKLM:\Software\Apple Inc.',
  'HKCU:\Software\Apple Computer, Inc.',
  'HKLM:\Software\Apple Computer, Inc.',
  'HKCU:\Software\Classes\Applications\iTunes.exe',
  'HKLM:\Software\Classes\Applications\iTunes.exe'
)
Remove-RegistryKeys -keys $keys

Write-Host 'Removing scheduled tasks and firewall rules...' -ForegroundColor Cyan
Remove-ScheduledTasks -namePatterns @('(?i)Apple','(?i)iTunes','(?i)Bonjour')
Remove-FirewallRules -namePatterns @('(?i)Apple','(?i)iTunes','(?i)Bonjour')

Write-Host 'Done. A reboot is recommended to finalize removal.' -ForegroundColor Green

