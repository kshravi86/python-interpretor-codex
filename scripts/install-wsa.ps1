<#
    Windows Subsystem for Android (WSA) installation helper

    What it does
    - Verifies Windows version (Windows 11, build >= 22000)
    - Checks virtualization capabilities and Hyper-V requirements
    - Enables required optional features (VirtualMachinePlatform, HypervisorPlatform)
      and attempts Hyper-V (ignored on editions where not available)
    - Ensures hypervisor is set to launch (bcdedit)
    - Installs WSA from Microsoft Store via winget

    Usage (Run PowerShell as Administrator):
      powershell -ExecutionPolicy Bypass -File "<path>\scripts\install-wsa.ps1"

    Reboot behavior:
    - This script never auto-reboots. If enabling features requires a
      reboot, it will print a warning and continue.

    Notes
    - Winget may prompt you to sign into Microsoft Store. Keep the window 
      in the foreground and follow prompts if needed.
    - On Windows 11 Home, full Hyper-V may not be available; this script
      continues if enabling Hyper-V fails.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    # Deprecated: Script no longer auto-reboots. This switch is ignored.
    [switch]$SkipReboot
)

function Write-Info($msg)  { Write-Host "[INFO ] $msg" -ForegroundColor Cyan }
function Write-Warn($msg)  { Write-Host "[WARN ] $msg" -ForegroundColor Yellow }
function Write-ErrorLine($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script in an elevated PowerShell (Run as Administrator)."
    }
}

function Check-WindowsVersion {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $caption = $os.Caption
    if ($build -lt 22000) {
        Write-ErrorLine "Detected: $caption (build $build). Windows Subsystem for Android requires Windows 11 (build >= 22000)."
        Write-Host "If you cannot upgrade to Windows 11, consider using Android Studio's Emulator instead." -ForegroundColor Yellow
        throw "Unsupported OS version for WSA"
    }
    Write-Info "Windows build OK: $build ($caption)"
}

function Check-Virtualization {
    try {
        $ci = Get-ComputerInfo -Property HyperVisorPresent,HyperVRequirement* 2>$null
        if ($null -ne $ci) {
            if (-not $ci.HyperVRequirementVirtualizationFirmwareEnabled) {
                Write-Warn "Virtualization disabled in firmware/BIOS. Enable Intel VT-x/AMD-V in BIOS."
            }
            if (-not $ci.HyperVRequirementSecondLevelAddressTranslation) {
                Write-Warn "CPU lacks SLAT (Second Level Address Translation). WSA requires SLAT."
            }
            if (-not $ci.HyperVRequirementDataExecutionPreventionAvailable) {
                Write-Warn "DEP not available/enabled. Enable DEP in BIOS/UEFI."
            }
            Write-Info ("Hypervisor present: {0}" -f $ci.HyperVisorPresent)
        } else {
            Write-Warn "Could not query Hyper-V requirements (Get-ComputerInfo returned null)."
        }
    } catch {
        Write-Warn "Could not query Hyper-V requirements: $($_.Exception.Message)"
    }
}

function Enable-Feature([string]$Name) {
    Write-Info "Enabling feature: $Name"
    $p = Start-Process -FilePath dism.exe -ArgumentList @('/online','/enable-feature',"/featurename:$Name",'/all','/norestart') -NoNewWindow -PassThru -Wait
    # 0 = success, 3010 = success, restart required
    if ($p.ExitCode -eq 0) { return 0 }
    if ($p.ExitCode -eq 3010) { return 3010 }
    return $p.ExitCode
}

function Ensure-HypervisorLaunchTypeAuto {
    try {
        $current = (bcdedit /enum {current}) 2>$null | Out-String
        if ($current -match 'hypervisorlaunchtype\s+\S+') {
            if ($current -notmatch 'hypervisorlaunchtype\s+Auto') {
                Write-Info "Setting hypervisorlaunchtype to Auto"
                bcdedit /set hypervisorlaunchtype Auto | Out-Null
                return $true
            }
        } else {
            Write-Info "Configuring hypervisorlaunchtype=Auto"
            bcdedit /set hypervisorlaunchtype Auto | Out-Null
            return $true
        }
    } catch {
        Write-Warn "Could not set hypervisorlaunchtype: $($_.Exception.Message)"
    }
    return $false
}

function Ensure-Winget {
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wg) {
        throw "winget (App Installer) not found. Install 'App Installer' from Microsoft Store, then re-run."
    }
    Write-Info "Winget found: $($wg.Path)"
}

function Install-WSA {
    Ensure-Winget
    Write-Info "Updating winget sources"
    winget source update | Out-Null

    Write-Info "Installing Windows Subsystem for Android via winget (msstore)"
    $args = @('install','--id','MicrosoftCorporationII.WindowsSubsystemForAndroid','-e','--source','msstore','--accept-source-agreements','--accept-package-agreements')
    $proc = Start-Process -FilePath winget -ArgumentList $args -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-Warn "winget returned $($proc.ExitCode). If you saw a Microsoft Store prompt, complete it and re-run if needed."
        try {
            Write-Info "Opening Microsoft Store page for WSA (use Install button)"
            Start-Process "ms-windows-store://pdp/?ProductId=9P3395VX91NR" | Out-Null
        } catch {
            Write-Warn "Could not open Microsoft Store link automatically."
        }
    }

    $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
    if ($pkg) {
        Write-Info "WSA installed: $($pkg.Version)"
    } else {
        Write-Warn "WSA not detected after install. It may be region-restricted or require Store sign-in."
        Write-Host "Tip: Ensure you're signed into Microsoft Store and in a supported region. Then try installing from the Store page that opened." -ForegroundColor Yellow
    }
}

try {
    Assert-Admin
    Check-WindowsVersion
    Check-Virtualization

    $needsReboot = $false

    $rc = Enable-Feature 'VirtualMachinePlatform'
    if ($rc -eq 3010) { $needsReboot = $true }
    elseif ($rc -ne 0) { Write-Warn "Enabling VirtualMachinePlatform failed with code $rc" }

    $rc = Enable-Feature 'HypervisorPlatform'
    if ($rc -eq 3010) { $needsReboot = $true }
    elseif ($rc -ne 0) { Write-Warn "Enabling HypervisorPlatform failed with code $rc" }

    # Try enabling Hyper-V (may be unavailable on some editions; ignore failures)
    $rc = Enable-Feature 'Microsoft-Hyper-V-All'
    if ($rc -eq 3010) { $needsReboot = $true }
    elseif ($rc -ne 0) { Write-Warn "Hyper-V not enabled (code $rc). Continuing."
    }

    if (Ensure-HypervisorLaunchTypeAuto) { $needsReboot = $true }

    if ($needsReboot) {
        Write-Warn "A reboot is required before WSA can run. Please reboot manually. (Script will not reboot automatically.)"
    }

    Install-WSA
    Write-Host "\nAll done. If features were just enabled, reboot Windows before using WSA." -ForegroundColor Green
} catch {
    Write-ErrorLine $_
    exit 1
}
