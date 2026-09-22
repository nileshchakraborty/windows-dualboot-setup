<#
.SYNOPSIS
    Boots into Bazzite for a single session, then returns to Windows.
.DESCRIPTION
    Arms the Bazzite UEFI entry as a one-time boot target (bootsequence)
    and immediately reboots. After that single Bazzite session the firmware
    reverts to the Windows default maintained by the StickyWindowsBoot task.
.NOTES
    Requires Administrator.
    Run Install.ps1 once first to set up the scheduled task and shortcut.
#>
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\lib\DualBoot.psm1" -Force

Write-Host 'Searching for Bazzite / SteamOS UEFI entry...' -ForegroundColor Cyan
$guid = Get-BazziteBootGuid
if (-not $guid) {
    $guid = Get-LinuxBootGuid
}

if (-not $guid) {
    Write-Error 'Bazzite or SteamOS UEFI boot entry not found. Verify your Linux gaming OS is installed and that Install.ps1 has been run.'
    exit 1
}

Write-Host "Arming one-time boot to Bazzite ($guid)..." -ForegroundColor Cyan
Set-BazziteBootNext -Guid $guid

Write-Host 'Restarting into Bazzite...' -ForegroundColor Green
shutdown /r /t 0
