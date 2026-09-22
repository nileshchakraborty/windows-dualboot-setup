<#
.SYNOPSIS
    Boots into SteamOS for a single session, then returns to Windows.
.DESCRIPTION
    Arms the SteamOS UEFI entry as a one-time boot target (bootsequence)
    and immediately reboots.
.NOTES
    Requires Administrator.
#>
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\lib\DualBoot.psm1" -Force

Write-Host 'Searching for SteamOS UEFI entry...' -ForegroundColor Cyan
$guid = Get-SteamOSBootGuid

if (-not $guid) {
    $guid = Get-LinuxBootGuid
}

if (-not $guid) {
    Write-Error 'SteamOS UEFI boot entry not found. Verify SteamOS is installed.'
    exit 1
}

Write-Host "Arming one-time boot to SteamOS ($guid)..." -ForegroundColor Cyan
Set-SteamOSBootNext -Guid $guid

Write-Host 'Restarting into SteamOS...' -ForegroundColor Green
shutdown /r /t 0
