# Requires Administrator privileges
# This script configures Windows to set Windows Boot Manager as the primary boot entry on boot,
# ensuring that waking from Sleep / Hibernate (S4) always resumes Windows.
# It also creates a "Restart to Bazzite" desktop shortcut to switch back to Bazzite.

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Dual-Boot Sticky Boot & Sleep/Hibernate Setup" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Verify Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Please run this script in PowerShell as Administrator!"
    Exit 1
}

# 2. Identify Bazzite Firmware Entry
Write-Host "[1/4] Detecting Bazzite UEFI entry in BCD..." -ForegroundColor Yellow
$firmwareEntries = bcdedit /enum firmware
$bazziteGuid = $null
$currentGuid = $null

foreach ($line in ($firmwareEntries -split "`r?`n")) {
    if ($line -match "^identifier\s+({[0-9a-fA-F-]+})") {
        $currentGuid = $matches[1]
    }
    if ($line -match "(Bazzite|fedora|shimx64\.efi)" -and $currentGuid) {
        $bazziteGuid = $currentGuid
        break
    }
}

if ($bazziteGuid) {
    Write-Host "      Found Bazzite entry: $bazziteGuid" -ForegroundColor Green
} else {
    Write-Warning "      Could not auto-detect Bazzite entry. 'Restart to Bazzite' will dynamically search at runtime."
}

# 3. Create C:\DualBoot Folder
$dualBootDir = "C:\DualBoot"
if (-not (Test-Path $dualBootDir)) {
    New-Item -ItemType Directory -Path $dualBootDir -Force | Out-Null
}

# 4. Create Set-WindowsBootPriority.cmd
$setBootCmdPath = Join-Path $dualBootDir "Set-WindowsBootPriority.cmd"
$setBootCmdContent = @"
@echo off
:: Ensure Windows is default UEFI boot entry while Windows is running
bcdedit /set {fwbootmgr} default {bootmgr} >nul 2>&1
"@
Set-Content -Path $setBootCmdPath -Value $setBootCmdContent -Force
Write-Host "[2/4] Created $setBootCmdPath" -ForegroundColor Green

# 5. Create Restart-To-Bazzite.ps1 and launcher .cmd
$restartPs1Path = Join-Path $dualBootDir "Restart-To-Bazzite.ps1"
$restartPs1Content = @'
# Find Bazzite entry dynamically
$firmware = bcdedit /enum firmware
$bazzite = $null
$current = $null
foreach ($line in ($firmware -split "`r?`n")) {
    if ($line -match "^identifier\s+({[0-9a-fA-F-]+})") {
        $current = $matches[1]
    }
    if ($line -match "(Bazzite|fedora|shimx64\.efi)" -and $current) {
        $bazzite = $current
        break
    }
}

if ($bazzite) {
    Write-Host "Setting next boot target to Bazzite ($bazzite)..." -ForegroundColor Cyan
    bcdedit /set {fwbootmgr} bootsequence $bazzite
    Write-Host "Restarting device into Bazzite..." -ForegroundColor Green
    shutdown /r /t 0
} else {
    Write-Error "Bazzite boot entry could not be found in UEFI firmware!"
    Pause
}
'@
Set-Content -Path $restartPs1Path -Value $restartPs1Content -Force

$restartCmdPath = Join-Path $dualBootDir "Restart-To-Bazzite.cmd"
$restartCmdContent = @"
@echo off
:: Elevate to Administrator if not already elevated
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c `"%~dpnx0`"' -Verb RunAs"
    exit /b
)
powershell -ExecutionPolicy Bypass -NoProfile -File "C:\DualBoot\Restart-To-Bazzite.ps1"
"@
Set-Content -Path $restartCmdPath -Value $restartCmdContent -Force
Write-Host "[3/4] Created $restartCmdPath and $restartPs1Path" -ForegroundColor Green

# 6. Create Desktop Shortcut for "Restart to Bazzite"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Restart to Bazzite.lnk"
$wscriptShell = New-Object -ComObject WScript.Shell
$shortcut = $wscriptShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $restartCmdPath
$shortcut.WorkingDirectory = $dualBootDir
$shortcut.Description = "Restart ROG Ally X into Bazzite"
$shortcut.IconLocation = "shell32.dll,220" # Reboot icon
$shortcut.Save()
Write-Host "      Created desktop shortcut: $shortcutPath" -ForegroundColor Green

# 7. Register Scheduled Task to ensure Windows remains primary on boot
Write-Host "[4/4] Registering Windows Startup Scheduled Task..." -ForegroundColor Yellow
$taskName = "StickyWindowsBoot"
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c C:\DualBoot\Set-WindowsBootPriority.cmd"
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerStartup, $triggerLogon) -Principal $principal -Settings $settings | Out-Null
Write-Host "      Scheduled Task '$taskName' successfully registered." -ForegroundColor Green

# 8. Apply current priority now
bcdedit /set {fwbootmgr} default {bootmgr}
Write-Host "`nSetup complete! Your Ally X will now always resume into Windows on wake/hibernate." -ForegroundColor Green
