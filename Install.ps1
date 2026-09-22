<#
.SYNOPSIS
    One-time setup for Windows/Bazzite dual-boot on the ROG Xbox Ally X.
.DESCRIPTION
    - Detects the Bazzite UEFI firmware entry.
    - Copies runtime scripts to InstallDir (default C:\DualBoot).
    - Creates a desktop shortcut and sets the UAC "run as administrator" bit.
    - Registers the StickyWindowsBoot scheduled task so Windows stays the
      UEFI default after every Bazzite session.
    - Immediately pins Windows as the current UEFI default.
.PARAMETER InstallDir
    Destination for runtime scripts. Default: C:\DualBoot
.EXAMPLE
    .\Install.ps1
.EXAMPLE
    .\Install.ps1 -InstallDir D:\DualBoot
#>
#Requires -RunAsAdministrator

param([string]$InstallDir = 'C:\DualBoot')

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\lib\DualBoot.psm1" -Force

Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '  Dual-Boot Setup — Sticky Boot + Bazzite / SteamOS' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan

# ── 1. Detect Bazzite or SteamOS UEFI entry ────────────────────────────────
Write-Host "`n[1/4] Detecting UEFI boot entries..." -ForegroundColor Yellow
$bazziteGuid = Get-LinuxBootGuid -Target 'Bazzite'
$steamosGuid = Get-LinuxBootGuid -Target 'SteamOS'

if ($bazziteGuid) {
    Write-Host "      Found Bazzite: $bazziteGuid" -ForegroundColor Green
}
if ($steamosGuid) {
    Write-Host "      Found SteamOS: $steamosGuid" -ForegroundColor Green
}
if (-not $bazziteGuid -and -not $steamosGuid) {
    Write-Warning '      Neither Bazzite nor SteamOS entry detected — will search dynamically at runtime.'
}

# ── 2. Install runtime scripts & executables ──────────────────────────────
Write-Host "`n[2/4] Installing runtime files to $InstallDir..." -ForegroundColor Yellow
$libDir = Join-Path $InstallDir 'lib'
$null   = New-Item -ItemType Directory -Path $libDir -Force

# Runtime scripts + module
Copy-Item "$PSScriptRoot\Restart-To-Bazzite.ps1" -Destination $InstallDir -Force
Copy-Item "$PSScriptRoot\Restart-To-SteamOS.ps1" -Destination $InstallDir -Force
Copy-Item "$PSScriptRoot\lib\DualBoot.psm1"       -Destination $libDir    -Force

# Look for compiled binaries
$bazziteExeCandidates = @(
    (Join-Path $PSScriptRoot 'src\RestartToBazzite\bin\Release\net48\RestartToBazzite.exe'),
    (Join-Path $PSScriptRoot 'src\RestartToBazzite\bin\Release\net8.0-windows\RestartToBazzite.exe'),
    (Join-Path $PSScriptRoot 'RestartToBazzite.exe')
) | Where-Object { Test-Path $_ }

$steamosExeCandidates = @(
    (Join-Path $PSScriptRoot 'src\RestartToSteamOS\bin\Release\net48\RestartToSteamOS.exe'),
    (Join-Path $PSScriptRoot 'src\RestartToSteamOS\bin\Release\net8.0-windows\RestartToSteamOS.exe'),
    (Join-Path $PSScriptRoot 'RestartToSteamOS.exe')
) | Where-Object { Test-Path $_ }

$installedBazziteExe = $null
if ($bazziteExeCandidates.Count -gt 0) {
    $installedBazziteExe = Join-Path $InstallDir 'RestartToBazzite.exe'
    Copy-Item $bazziteExeCandidates[0] -Destination $installedBazziteExe -Force
    Write-Host "      Installed: $installedBazziteExe" -ForegroundColor Green

    $sourceIco = Join-Path $PSScriptRoot 'src\RestartToBazzite\RestartToBazzite.ico'
    if (Test-Path $sourceIco) {
        Copy-Item $sourceIco -Destination (Join-Path $InstallDir 'RestartToBazzite.ico') -Force
    }
}

$installedSteamOsExe = $null
if ($steamosExeCandidates.Count -gt 0) {
    $installedSteamOsExe = Join-Path $InstallDir 'RestartToSteamOS.exe'
    Copy-Item $steamosExeCandidates[0] -Destination $installedSteamOsExe -Force
    Write-Host "      Installed: $installedSteamOsExe" -ForegroundColor Green

    $sourceIco = Join-Path $PSScriptRoot 'src\RestartToSteamOS\RestartToSteamOS.ico'
    if (Test-Path $sourceIco) {
        Copy-Item $sourceIco -Destination (Join-Path $InstallDir 'RestartToSteamOS.ico') -Force
    }
}

# Minimal sticky-boot helper called by the scheduled task
Set-Content -Path (Join-Path $InstallDir 'Set-WindowsBootPriority.cmd') -Force -Value @'
@echo off
bcdedit /set {fwbootmgr} default {bootmgr} >nul 2>&1
'@
Write-Host "      Scripts installed to $InstallDir" -ForegroundColor Green

# ── 3. Desktop shortcuts ──────────────────────────────────────────────────
Write-Host "`n[3/4] Creating desktop shortcuts..." -ForegroundColor Yellow
$shell = New-Object -ComObject WScript.Shell

function Create-AppShortcut {
    param([string]$Title, [string]$ExePath, [string]$ScriptPath, [string]$DefaultIcon)
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "$Title.lnk"
    $sc           = $shell.CreateShortcut($shortcutPath)

    if ($ExePath -and (Test-Path $ExePath)) {
        $sc.TargetPath       = $ExePath
        $sc.Arguments        = ''
        $sc.WorkingDirectory = $InstallDir
        $sc.Description      = $Title
        $sc.IconLocation     = "$ExePath,0"
    } else {
        $sc.TargetPath       = 'powershell.exe'
        $sc.Arguments        = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""
        $sc.WorkingDirectory = $InstallDir
        $sc.Description      = $Title
        $sc.IconLocation     = $DefaultIcon
    }
    $sc.Save()

    # Set Run as Administrator in shortcut header
    $bytes       = [IO.File]::ReadAllBytes($shortcutPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [IO.File]::WriteAllBytes($shortcutPath, $bytes)
    Write-Host "      Created: $shortcutPath" -ForegroundColor Green
}

if ($steamosGuid -and -not $bazziteGuid) {
    # SteamOS only system
    Create-AppShortcut 'Restart to SteamOS' $installedSteamOsExe (Join-Path $InstallDir 'Restart-To-SteamOS.ps1') 'shell32.dll,220'
} elseif ($bazziteGuid -and -not $steamosGuid) {
    # Bazzite only system
    Create-AppShortcut 'Restart to Bazzite' $installedBazziteExe (Join-Path $InstallDir 'Restart-To-Bazzite.ps1') 'shell32.dll,220'
} else {
    # Both found or generic — create both
    if ($installedBazziteExe -or (Test-Path (Join-Path $InstallDir 'Restart-To-Bazzite.ps1'))) {
        Create-AppShortcut 'Restart to Bazzite' $installedBazziteExe (Join-Path $InstallDir 'Restart-To-Bazzite.ps1') 'shell32.dll,220'
    }
    if ($installedSteamOsExe -or (Test-Path (Join-Path $InstallDir 'Restart-To-SteamOS.ps1'))) {
        Create-AppShortcut 'Restart to SteamOS' $installedSteamOsExe (Join-Path $InstallDir 'Restart-To-SteamOS.ps1') 'shell32.dll,220'
    }
}

Write-Host "      Tip: Add the .exe from '$InstallDir' to ASUS Armoury Crate SE, Xbox App, or Winhance!" -ForegroundColor Cyan

# ── 4. Scheduled task ─────────────────────────────────────────────────────
Write-Host "`n[4/4] Registering StickyWindowsBoot scheduled task..." -ForegroundColor Yellow
$taskName  = 'StickyWindowsBoot'
$cmdHelper = Join-Path $InstallDir 'Set-WindowsBootPriority.cmd'
$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$cmdHelper`""
$triggers  = @(
    (New-ScheduledTaskTrigger -AtStartup)
    (New-ScheduledTaskTrigger -AtLogOn)
)
$principal = New-ScheduledTaskPrincipal `
    -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask `
    -TaskName  $taskName `
    -Action    $action `
    -Trigger   $triggers `
    -Principal $principal `
    -Settings  $settings | Out-Null
Write-Host "      Task '$taskName' registered." -ForegroundColor Green

# Apply immediately so the current session is also covered
Set-WindowsBootDefault
Write-Host "`nSetup complete. Use your desktop shortcut or handheld launcher to switch OS." -ForegroundColor Green
