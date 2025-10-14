<#!
.SYNOPSIS
  Fully uninstall Sideloadly from Windows (app, data, shortcuts, registry keys, tasks, firewall rules).

.DESCRIPTION
  Stops Sideloadly process, attempts silent uninstall via registry UninstallString, removes
  residual folders under Program Files/AppData/Start Menu, deletes basic registry keys,
  scheduled tasks and firewall rules matching Sideloadly.

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

function Stop-RelatedProcesses {
  $names = @('Sideloadly')
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
    try { Start-Process -FilePath $exe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden | Out-Null; return $true } catch { return $false }
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
  $res = Read-Host 'This will fully remove Sideloadly. Continue? (y/N)'
  if ($res -notin @('y','Y','yes','YES')) { Write-Host 'Aborted.'; exit 1 }
}

Write-Host 'Stopping Sideloadly...' -ForegroundColor Cyan
Stop-RelatedProcesses

Write-Host 'Attempting silent uninstall (registry)...' -ForegroundColor Cyan
$entries = Get-UninstallEntries -matchNames @('(?i)sideloadly')
foreach ($e in $entries) { if ($e.UninstallString) { Invoke-Uninstall -displayName $e.DisplayName -uninstallString $e.UninstallString | Out-Null } }

Write-Host 'Removing residual folders...' -ForegroundColor Cyan
$paths = @(
  '$env:ProgramFiles\Sideloadly',
  '$env:ProgramFiles(x86)\Sideloadly',
  '$env:LOCALAPPDATA\Sideloadly',
  '$env:APPDATA\Sideloadly',
  '$env:TEMP\Sideloadly',
  '$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Sideloadly'
)
Remove-Paths -paths $paths

Write-Host 'Cleaning registry keys...' -ForegroundColor Cyan
$keys = @(
  'HKCU:\Software\Sideloadly',
  'HKLM:\Software\Sideloadly'
)
Remove-RegistryKeys -keys $keys

Write-Host 'Removing scheduled tasks and firewall rules...' -ForegroundColor Cyan
Remove-ScheduledTasks -namePatterns @('(?i)sideloadly')
Remove-FirewallRules -namePatterns @('(?i)sideloadly')

Write-Host 'Done. A reboot is recommended to finalize removal.' -ForegroundColor Green

