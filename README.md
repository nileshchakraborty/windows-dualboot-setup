# Windows Dual-Boot Setup — ROG Xbox Ally X

Scripts for managing a **Windows + Bazzite** dual-boot setup on the ROG Xbox Ally X.

**The problem:** the UEFI firmware defaults to whichever OS booted last, so waking from
sleep/hibernate in Windows can unexpectedly drop you into Bazzite. These scripts pin Windows
as the persistent default while giving you a one-click shortcut to boot Bazzite on demand.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Hardware | ROG Xbox Ally X (or any UEFI dual-boot PC) |
| Firmware mode | **UEFI** — CSM / Legacy boot must be **off** |
| Bazzite | Installed with its own UEFI entry (labelled `Bazzite`, `fedora`, or containing `shimx64.efi`) |
| Windows | 10 or 11 with **Administrator** account |
| PowerShell | 5.1+ (built into Windows — no install needed) |
| `bcdedit.exe` | Built into Windows — no install needed |

> No third-party software, package manager, or internet connection is required.

---

## Quick start

```
1. Boot into Windows.
2. Double-click  Install.cmd  (approve UAC prompt — one time only).
3. A "Restart to Bazzite" shortcut appears on your Desktop.
4. To boot Bazzite: double-click the shortcut → approve UAC → device reboots into Bazzite.
5. To return to Windows: reboot normally from within Bazzite.
```

---

## Project structure

```
windows-dualboot-setup/
├── lib/
│   └── DualBoot.psm1           # Shared module — all bcdedit logic lives here (DRY)
├── tests/
│   └── DualBoot.Tests.ps1      # Pester v5 unit tests
├── extras/
│   ├── RestartToBazzite.cs     # Optional standalone C# / WinForms GUI
│   └── Fix-RTSS.ps1            # Utility: fix RivaTuner Statistics Server hooks
├── Install.ps1                 # One-time setup (run via Install.cmd)
├── Install.cmd                 # UAC-elevating launcher for Install.ps1
├── Restart-To-Bazzite.ps1      # Runtime restart script
├── Restart-To-Bazzite.cmd      # UAC-elevating launcher for Restart-To-Bazzite.ps1
├── .gitignore
└── README.md
```

### `lib/DualBoot.psm1` — the shared module

All UEFI boot logic is in one place. Both `Install.ps1` and `Restart-To-Bazzite.ps1` import it.

| Function | Description |
|---|---|
| `Find-BazziteGuidInText` | Pure parser — extracts the Bazzite GUID from `bcdedit /enum firmware` text |
| `Get-BazziteBootGuid` | Calls `bcdedit` and returns the Bazzite UEFI GUID (or `$null`) |
| `Set-WindowsBootDefault` | `bcdedit /set {fwbootmgr} default {bootmgr}` — pins Windows |
| `Set-BazziteBootNext` | `bcdedit /set {fwbootmgr} bootsequence <guid>` — arms Bazzite once |
| `Test-Administrator` | Returns `$true` if running as Administrator |

### `Install.ps1` — one-time setup

1. Detects the Bazzite UEFI entry.
2. Copies `Restart-To-Bazzite.ps1` and `lib/DualBoot.psm1` to `C:\DualBoot\`.
3. Generates a minimal `Set-WindowsBootPriority.cmd` (one-liner bcdedit, no PS overhead).
4. Creates a desktop shortcut with the UAC "run as administrator" bit set.
5. Registers the `StickyWindowsBoot` scheduled task (runs at startup + logon as SYSTEM).
6. Immediately pins Windows as the UEFI default.

### `Restart-To-Bazzite.ps1` — runtime

Imports the module, calls `Get-BazziteBootGuid` + `Set-BazziteBootNext`, then `shutdown /r /t 0`.

---

## How the sticky-boot mechanism works

```
Windows logon
  └─ StickyWindowsBoot task fires (SYSTEM, highest privileges)
       └─ bcdedit /set {fwbootmgr} default {bootmgr}   ← Windows stays default

"Restart to Bazzite" shortcut pressed
  └─ bcdedit /set {fwbootmgr} bootsequence <bazzite-guid>  ← one-time override
  └─ shutdown /r /t 0

Device boots Bazzite  (bootsequence is consumed, firmware reverts to Windows default)

Next Windows logon
  └─ StickyWindowsBoot re-confirms Windows as default
```

> `bootsequence` (not `default`) is used for the Bazzite arm — so after one Bazzite session the
> firmware automatically reverts. The scheduled task then re-pins Windows on the next logon.

---

## Running the tests

Tests use [Pester v5](https://pester.dev). Install it once, then run:

```powershell
# Install Pester v5 (one time)
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser

# Run all tests
Invoke-Pester .\tests\DualBoot.Tests.ps1 -Output Detailed
```

The tests cover all exported module functions with full mocking of `bcdedit` via `InModuleScope`,
so no real bcdedit process is spawned and tests run on any platform (including macOS/Linux for CI).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "Bazzite boot entry not found" | Bazzite's EFI entry has an unusual label | Run `bcdedit /enum firmware` in elevated cmd; check that at least one entry contains `Bazzite`, `fedora`, or `shimx64.efi` |
| UAC prompt loops / nothing happens | Execution policy blocking PowerShell | Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` once in an elevated PowerShell |
| Device still boots Windows after shortcut | `bootsequence` was not written | Run `bcdedit /enum firmware` after the script and verify `bootsequence` contains the Bazzite GUID |
| Scheduled task not running | Task registered without SYSTEM privileges | Open Task Scheduler → `StickyWindowsBoot` → verify it runs as `NT AUTHORITY\SYSTEM` at highest level |
| `C:\DualBoot` scripts missing | Install.ps1 not run after a reinstall | Re-run `Install.cmd` |
