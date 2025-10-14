<#!
.SYNOPSIS
  Fully remove Sideloadly and 3uTools from Windows (apps, data, shortcuts, tasks, basic registry keys).

.DESCRIPTION
  Stops related processes, attempts silent uninstalls via registry, removes residual folders under
  Program Files/AppData/Start Menu, deletes basic registry keys, scheduled tasks and firewall rules
  that match common names.

.PARAMETER Force
  Proceed without confirmation prompt.

.PARAMETER RemoveAppleDrivers
  Also remove Apple components (Apple Mobile Device Support/iTunes drivers) if present. Not recommended
  unless you plan to reinstall drivers. Disabled by default.

.PARAMETER WhatIf
  Simulate actions without making changes.

.NOTES
  Run as Administrator. Reboot recommended after removal.
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
Param(
  [switch]$Force,
  [switch]$RemoveAppleDrivers
)

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal $id
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Please run this script as Administrator.'
    exit 1
  }
}

function Stop-RelatedProcesses {
  $names = @('Sideloadly','3uTools','i4Tools','AltServer','AppleMobileDeviceHelper')
  foreach ($n in $names) {
    $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
      if ($PSCmdlet.ShouldProcess("$($p.Name) (PID $($p.Id))", 'Stop-Process')) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {}
      }
    }
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
        $dn = (Get-ItemProperty $_.PsPath -ErrorAction Stop).DisplayName
        $us = (Get-ItemProperty $_.PsPath -ErrorAction Stop).UninstallString
        if ($dn) {
          foreach ($m in $matchNames) {
            if ($dn -match $m) { $entries += [pscustomobject]@{DisplayName=$dn; UninstallString=$us; Key=$_.PsPath} }
          }
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
    # Normalize quotes and add common silent flags for Inno/NSIS/InstallShield
    if ($uninstallString.StartsWith('"')) {
      $exe, $args = $uninstallString -split '"\s+', 2
      $exe = $exe.Trim('"')
    } else {
      $parts = $uninstallString -split '\s+', 2
      $exe = $parts[0]
      if ($parts.Count -gt 1) { $args = $parts[1] }
    }
    if ($args -notmatch '(?i)/silent|/verysilent|/S') { $args += ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
  }
  if (-not (Test-Path $exe)) { return $false }
  if ($PSCmdlet.ShouldProcess($displayName, "Uninstall via $exe $args")) {
    try {
      $p = Start-Process -FilePath $exe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
      return $true
    } catch { return $false }
  }
  return $false
}

function Remove-Paths([string[]]$paths) {
  foreach ($p in $paths) {
    $ep = $ExecutionContext.InvokeCommand.ExpandString($p)
    if (Test-Path $ep) {
      if ($PSCmdlet.ShouldProcess($ep, 'Remove-Item -Recurse -Force')) {
        try { Remove-Item -LiteralPath $ep -Recurse -Force -ErrorAction Stop } catch {}
      }
    }
  }
}

function Remove-RegistryKeys([string[]]$keys) {
  foreach ($k in $keys) {
    $ek = $ExecutionContext.InvokeCommand.ExpandString($k)
    if (Test-Path $ek) {
      if ($PSCmdlet.ShouldProcess($ek, 'Remove-Item -Recurse -Force')) {
        try { Remove-Item -Path $ek -Recurse -Force -ErrorAction Stop } catch {}
      }
    }
  }
}

function Remove-ScheduledTasks([string[]]$namePatterns) {
  try {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($t in $tasks) {
      foreach ($pat in $namePatterns) {
        if ($t.TaskName -match $pat -or $t.TaskPath -match $pat) {
          if ($PSCmdlet.ShouldProcess($t.TaskName, 'Unregister-ScheduledTask -Confirm:$false')) {
            try { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop } catch {}
          }
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
        if ($name) { if ($PSCmdlet.ShouldProcess($name, 'Delete firewall rule')) { & netsh advfirewall firewall delete rule name="$name" | Out-Null } }
      }
    }
  } catch {}
}

Assert-Admin

if (-not $Force) {
  $res = Read-Host 'This will remove Sideloadly and 3uTools (apps, data, tasks, basic registry keys). Continue? (y/N)'
  if ($res -notin @('y','Y','yes','YES')) { Write-Host 'Aborted.'; exit 1 }
}

Write-Host 'Stopping related processes...' -ForegroundColor Cyan
Stop-RelatedProcesses

Write-Host 'Attempting silent uninstalls (registry) ...' -ForegroundColor Cyan
$targets = @('(?i)sideloadly','(?i)3u\s*tools','(?i)i4Tools')
$entries = Get-UninstallEntries -matchNames $targets
foreach ($e in $entries) {
  if ($e.UninstallString) {
    $ok = Invoke-Uninstall -displayName $e.DisplayName -uninstallString $e.UninstallString
    Write-Host "Uninstall $($e.DisplayName): $ok"
  }
}

Write-Host 'Removing residual folders...' -ForegroundColor Cyan
$paths = @(
  '$env:ProgramFiles\Sideloadly',
  '$env:ProgramFiles(x86)\Sideloadly',
  '$env:LOCALAPPDATA\Sideloadly',
  '$env:APPDATA\Sideloadly',
  '$env:TEMP\Sideloadly',
  '$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Sideloadly',
  '$env:ProgramFiles\3uTools',
  '$env:ProgramFiles(x86)\3uTools',
  '$env:LOCALAPPDATA\3uTools',
  '$env:APPDATA\3uTools',
  '$env:ProgramData\Microsoft\Windows\Start Menu\Programs\3uTools'
)
Remove-Paths -paths $paths

Write-Host 'Cleaning registry keys...' -ForegroundColor Cyan
$keys = @(
  'HKCU:\Software\Sideloadly',
  'HKLM:\Software\Sideloadly',
  'HKCU:\Software\3uTools',
  'HKLM:\Software\3uTools',
  'HKCU:\Software\WOW6432Node\3uTools',
  'HKLM:\Software\WOW6432Node\3uTools'
)
Remove-RegistryKeys -keys $keys

Write-Host 'Removing scheduled tasks and firewall rules...' -ForegroundColor Cyan
Remove-ScheduledTasks -namePatterns @('(?i)sideloadly','(?i)3u')
Remove-FirewallRules -namePatterns @('(?i)sideloadly','(?i)3u')

if ($RemoveAppleDrivers) {
  Write-Warning 'Removing Apple Mobile Device/iTunes drivers as requested (-RemoveAppleDrivers).'
  $apple = Get-UninstallEntries -matchNames @('(?i)Apple Mobile Device Support','(?i)iTunes','(?i)Apple Application Support','(?i)Bonjour')
  foreach ($a in $apple) {
    if ($a.UninstallString) { Invoke-Uninstall -displayName $a.DisplayName -uninstallString $a.UninstallString | Out-Null }
  }
}

Write-Host 'Done. A reboot is recommended to finalize removal.' -ForegroundColor Green

