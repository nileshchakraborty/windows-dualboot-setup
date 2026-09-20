Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Shared functions for Windows/Bazzite dual-boot management.
.DESCRIPTION
    Provides UEFI boot-entry detection and bcdedit wrappers used by both
    Install.ps1 (one-time setup) and Restart-To-Bazzite.ps1 (runtime).
    Invoke-BcdEdit is intentionally kept as a module-private named function
    so Pester can mock it in unit tests without spawning a real process.
#>

# ---------------------------------------------------------------------------
# Private — not listed in Export-ModuleMember
# ---------------------------------------------------------------------------

function Invoke-BcdEdit {
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & bcdedit @Arguments 2>&1
    return @{ Output = [string[]]$output; ExitCode = $LASTEXITCODE }
}

# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

function Find-BazziteGuidInText {
    <#
    .SYNOPSIS
        Pure parser — returns the first UEFI GUID whose entry contains
        'Bazzite', 'fedora', or 'shimx64.efi' (case-insensitive).
    .PARAMETER Text
        Multi-line string output of 'bcdedit /enum firmware'.
    .OUTPUTS
        String GUID like '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}', or $null.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $currentGuid = $null
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^identifier\s+(\{[0-9a-fA-F-]+\})') {
            $currentGuid = $matches[1]
        }
        if ($line -imatch 'Bazzite|fedora|shimx64\.efi' -and $null -ne $currentGuid) {
            return $currentGuid
        }
    }
    return $null
}

function Get-BazziteBootGuid {
    <#
    .SYNOPSIS
        Returns the UEFI GUID for the Bazzite firmware boot entry.
    .OUTPUTS
        String GUID, or $null if no Bazzite entry is present.
    .NOTES
        Throws if bcdedit itself fails (not running as Administrator,
        EFI variables unsupported, etc.).
    #>
    [OutputType([string])]
    param()

    $r = Invoke-BcdEdit '/enum', 'firmware'
    if ($r.ExitCode -ne 0) {
        throw "bcdedit /enum firmware failed (exit $($r.ExitCode)): $($r.Output -join ' ')"
    }
    return Find-BazziteGuidInText ($r.Output -join "`n")
}

function Set-WindowsBootDefault {
    <#
    .SYNOPSIS
        Pins Windows Boot Manager as the persistent UEFI default.
    .NOTES
        Called by the StickyWindowsBoot scheduled task at every logon/startup.
        Requires Administrator. Supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess('{fwbootmgr}', 'Set Windows Boot Manager as UEFI default')) {
        $r = Invoke-BcdEdit '/set', '{fwbootmgr}', 'default', '{bootmgr}'
        if ($r.ExitCode -ne 0) {
            throw "Failed to set Windows as UEFI default (exit $($r.ExitCode)): $($r.Output -join ' ')"
        }
    }
}

function Set-BazziteBootNext {
    <#
    .SYNOPSIS
        Arms Bazzite as the one-time UEFI next-boot entry (bootsequence).
    .PARAMETER Guid
        Bazzite firmware GUID returned by Get-BazziteBootGuid.
    .NOTES
        Uses 'bootsequence' (not 'default') so the change is consumed after
        a single boot and Windows remains the persistent default.
        Requires Administrator. Supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$')]
        [string]$Guid
    )

    if ($PSCmdlet.ShouldProcess($Guid, 'Set as one-time UEFI next boot')) {
        $r = Invoke-BcdEdit '/set', '{fwbootmgr}', 'bootsequence', $Guid
        if ($r.ExitCode -ne 0) {
            throw "Failed to set Bazzite as one-time boot target (exit $($r.ExitCode)): $($r.Output -join ' ')"
        }
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Returns $true if the current session is running as Administrator.
    #>
    [OutputType([bool])]
    param()

    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

Export-ModuleMember -Function `
    Find-BazziteGuidInText, Get-BazziteBootGuid,
    Set-WindowsBootDefault, Set-BazziteBootNext,
    Test-Administrator
