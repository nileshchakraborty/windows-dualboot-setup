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
Write-Host '  Dual-Boot Setup — Sticky Boot + Restart to Bazzite' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan

# ── 1. Detect Bazzite UEFI entry ──────────────────────────────────────────
Write-Host "`n[1/4] Detecting Bazzite UEFI entry..." -ForegroundColor Yellow
$bazziteGuid = Get-BazziteBootGuid
if ($bazziteGuid) {
    Write-Host "      Found: $bazziteGuid" -ForegroundColor Green
} else {
    Write-Warning '      Bazzite entry not detected — Restart-To-Bazzite will search dynamically at runtime.'
}

# ── 2. Install runtime scripts ────────────────────────────────────────────
Write-Host "`n[2/4] Installing runtime scripts to $InstallDir..." -ForegroundColor Yellow
$libDir = Join-Path $InstallDir 'lib'
$null   = New-Item -ItemType Directory -Path $libDir -Force

# Runtime script + module (module kept alongside so the script can always find it)
Copy-Item "$PSScriptRoot\Restart-To-Bazzite.ps1" -Destination $InstallDir -Force
Copy-Item "$PSScriptRoot\lib\DualBoot.psm1"       -Destination $libDir    -Force

# Minimal sticky-boot helper called by the scheduled task.
# Intentionally a plain bcdedit one-liner — no PS overhead at logon.
Set-Content -Path (Join-Path $InstallDir 'Set-WindowsBootPriority.cmd') -Force -Value @'
@echo off
bcdedit /set {fwbootmgr} default {bootmgr} >nul 2>&1
'@
Write-Host "      Scripts installed to $InstallDir" -ForegroundColor Green

# ── 3. Desktop shortcut ───────────────────────────────────────────────────
Write-Host "`n[3/4] Creating desktop shortcut..." -ForegroundColor Yellow
$restartScript = Join-Path $InstallDir 'Restart-To-Bazzite.ps1'
$shortcutPath  = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Restart to Bazzite.lnk'
$shell         = New-Object -ComObject WScript.Shell
$sc            = $shell.CreateShortcut($shortcutPath)
$sc.TargetPath       = 'powershell.exe'
$sc.Arguments        = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$restartScript`""
$sc.WorkingDirectory = $InstallDir
$sc.Description      = 'Restart into Bazzite for one boot'
$sc.IconLocation     = 'shell32.dll,220'
$sc.Save()

# Set the "Run as Administrator" flag in the .lnk binary header (byte 0x15, bit 5)
$bytes       = [IO.File]::ReadAllBytes($shortcutPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[IO.File]::WriteAllBytes($shortcutPath, $bytes)
Write-Host "      Created: $shortcutPath" -ForegroundColor Green

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
Write-Host "`nSetup complete. Use the 'Restart to Bazzite' desktop shortcut to switch to Bazzite." -ForegroundColor Green
