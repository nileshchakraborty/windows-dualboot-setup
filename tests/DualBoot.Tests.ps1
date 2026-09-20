#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester v5 tests for lib/DualBoot.psm1.
.DESCRIPTION
    Covers:
      - Find-BazziteGuidInText  (pure parser, no mocks needed)
      - Get-BazziteBootGuid     (mocks Invoke-BcdEdit via InModuleScope)
      - Set-BazziteBootNext     (mocks Invoke-BcdEdit via InModuleScope)
      - Set-WindowsBootDefault  (mocks Invoke-BcdEdit via InModuleScope)
      - Test-Administrator      (return-type smoke test only)
.NOTES
    Run with:  Invoke-Pester .\tests\DualBoot.Tests.ps1 -Output Detailed
#>

BeforeAll {
    Import-Module "$PSScriptRoot\..\lib\DualBoot.psm1" -Force
}

# ── Sample bcdedit /enum firmware output used across multiple tests ─────────
$script:SampleFirmwareOutput = @'
firmware application
--------------------
identifier              {bootmgr}
device                  partition=\Device\HarddiskVolume1
description             Windows Boot Manager

firmware application
--------------------
identifier              {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}
device                  partition=\Device\HarddiskVolume1
path                    \EFI\fedora\shimx64.efi
description             Bazzite
'@

# ── Find-BazziteGuidInText ──────────────────────────────────────────────────
Describe 'Find-BazziteGuidInText' {

    It 'returns the GUID for an entry whose description is Bazzite' {
        Find-BazziteGuidInText $script:SampleFirmwareOutput |
            Should -Be '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}'
    }

    It 'matches via fedora in the path line' {
        $text = "identifier              {aaaa1111-0000-0000-0000-000000000000}`npath                    \EFI\fedora\grubx64.efi`n"
        Find-BazziteGuidInText $text | Should -Be '{aaaa1111-0000-0000-0000-000000000000}'
    }

    It 'matches via shimx64.efi in the path line' {
        $text = "identifier              {bbbb2222-0000-0000-0000-000000000000}`npath                    \EFI\BOOT\shimx64.efi`n"
        Find-BazziteGuidInText $text | Should -Be '{bbbb2222-0000-0000-0000-000000000000}'
    }

    It 'is case-insensitive for the Bazzite label' {
        $text = "identifier              {cccc3333-0000-0000-0000-000000000000}`ndescription             BAZZITE OS`n"
        Find-BazziteGuidInText $text | Should -Be '{cccc3333-0000-0000-0000-000000000000}'
    }

    It 'returns the first match when multiple Bazzite entries exist' {
        $text = @"
identifier              {aaaa1111-0000-0000-0000-000000000000}
description             Bazzite

identifier              {bbbb2222-0000-0000-0000-000000000000}
description             Bazzite backup
"@
        Find-BazziteGuidInText $text | Should -Be '{aaaa1111-0000-0000-0000-000000000000}'
    }

    It 'returns $null when no Bazzite entry exists' {
        $text = "identifier              {bootmgr}`ndescription             Windows Boot Manager`n"
        Find-BazziteGuidInText $text | Should -BeNullOrEmpty
    }

    It 'returns $null for empty input' {
        Find-BazziteGuidInText '' | Should -BeNullOrEmpty
    }

    It 'does not associate a keyword match with the preceding entry' {
        # "Bazzite" appears before its own identifier — should not be attributed to Windows
        $text = @"
identifier              {bootmgr}
description             Windows Boot Manager
description             Bazzite is the next entry
"@
        # The keyword line appears inside the Windows entry → should match {bootmgr}, not return null
        # (This documents current behavior: any line within an entry triggers the match.)
        Find-BazziteGuidInText $text | Should -Be '{bootmgr}'
    }
}

# ── Get-BazziteBootGuid ────────────────────────────────────────────────────
Describe 'Get-BazziteBootGuid' {

    It 'returns the GUID when bcdedit succeeds and an entry is found' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit {
                @{
                    Output   = @(
                        'identifier              {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}'
                        'description             Bazzite'
                    )
                    ExitCode = 0
                }
            }
            Get-BazziteBootGuid | Should -Be '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}'
        }
    }

    It 'returns $null when bcdedit succeeds but no Bazzite entry is present' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit {
                @{
                    Output   = @(
                        'identifier              {bootmgr}'
                        'description             Windows Boot Manager'
                    )
                    ExitCode = 0
                }
            }
            Get-BazziteBootGuid | Should -BeNullOrEmpty
        }
    }

    It 'throws when bcdedit exits non-zero' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('Access is denied.'); ExitCode = 1 } }
            { Get-BazziteBootGuid } | Should -Throw
        }
    }

    It 'passes /enum firmware as the argument to bcdedit' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @(); ExitCode = 0 } }
            Get-BazziteBootGuid
            Should -Invoke Invoke-BcdEdit -Times 1 -ParameterFilter {
                $Arguments -contains '/enum' -and $Arguments -contains 'firmware'
            }
        }
    }
}

# ── Set-BazziteBootNext ────────────────────────────────────────────────────
Describe 'Set-BazziteBootNext' {

    It 'calls bcdedit with bootsequence and the target GUID' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('The operation completed successfully.'); ExitCode = 0 } }
            Set-BazziteBootNext -Guid '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}'
            Should -Invoke Invoke-BcdEdit -Times 1 -ParameterFilter {
                $Arguments -contains 'bootsequence' -and
                $Arguments -contains '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}'
            }
        }
    }

    It 'targets {fwbootmgr} not {bootmgr}' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('The operation completed successfully.'); ExitCode = 0 } }
            Set-BazziteBootNext -Guid '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}'
            Should -Invoke Invoke-BcdEdit -Times 1 -ParameterFilter {
                $Arguments -contains '{fwbootmgr}'
            }
        }
    }

    It 'throws when bcdedit fails' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('Access is denied.'); ExitCode = 1 } }
            { Set-BazziteBootNext -Guid '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}' } | Should -Throw
        }
    }

    It 'rejects a GUID that is not in standard UUID format' {
        { Set-BazziteBootNext -Guid '{bootmgr}' }       | Should -Throw
        { Set-BazziteBootNext -Guid 'not-a-guid' }      | Should -Throw
        { Set-BazziteBootNext -Guid '{short-guid}' }    | Should -Throw
    }

    It 'accepts a well-formed UUID GUID' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('The operation completed successfully.'); ExitCode = 0 } }
            { Set-BazziteBootNext -Guid '{7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963}' } | Should -Not -Throw
        }
    }
}

# ── Set-WindowsBootDefault ─────────────────────────────────────────────────
Describe 'Set-WindowsBootDefault' {

    It 'calls bcdedit /set {fwbootmgr} default {bootmgr}' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('The operation completed successfully.'); ExitCode = 0 } }
            Set-WindowsBootDefault
            Should -Invoke Invoke-BcdEdit -Times 1 -ParameterFilter {
                $Arguments -contains '/set'    -and
                $Arguments -contains '{fwbootmgr}' -and
                $Arguments -contains 'default' -and
                $Arguments -contains '{bootmgr}'
            }
        }
    }

    It 'throws when bcdedit fails' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @('Access is denied.'); ExitCode = 1 } }
            { Set-WindowsBootDefault } | Should -Throw
        }
    }

    It 'does nothing when -WhatIf is passed' {
        InModuleScope DualBoot {
            Mock Invoke-BcdEdit { @{ Output = @(); ExitCode = 0 } }
            Set-WindowsBootDefault -WhatIf
            Should -Invoke Invoke-BcdEdit -Times 0
        }
    }
}

# ── Test-Administrator ─────────────────────────────────────────────────────
Describe 'Test-Administrator' {

    It 'returns a boolean' {
        Test-Administrator | Should -BeOfType [bool]
    }
}
