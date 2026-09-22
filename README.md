# Windows Dual-Boot Setup

> **One-click restart into Bazzite from handheld launchers + persistent sticky Windows UEFI boot priority.**
> 
> **Problem:** On dual-boot systems, the UEFI firmware defaults to whichever OS booted last, so waking from sleep/hibernate or rebooting in Windows can land you in Bazzite unexpectedly. Additionally, handheld frontends (Armoury Crate, Xbox, Winhance) require a clean `.exe` with elevated privileges rather than raw scripts.
> 
> **Solution:** This project provides:
> 1. **`RestartToBazzite.exe`** — A standalone C# GUI application (built via `RestartToBazzite.sln`) with embedded icon and automatic UAC elevation, ready to attach to ASUS Armoury Crate SE, Xbox App, Winhance, or your desktop.
> 2. **`StickyWindowsBoot`** — A lightweight background task that keeps Windows Boot Manager as the persistent UEFI default.
> 
> **Companion Project:** Works together with [`restart-to-windows`](https://github.com/nileshchakraborty/restart-to-windows) (Decky Loader plugin) for seamless two-way switching between Windows and Bazzite / SteamOS.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Hardware | ROG Ally, ROG Ally X, Lenovo Legion Go, Steam Deck, or any UEFI dual-boot PC |
| Firmware mode | **UEFI only** — CSM / Legacy boot must be **off** |
| Bazzite | Already installed with its own UEFI firmware entry |
| Windows | 10 or 11, **Administrator** account |
| PowerShell | 5.1+ (built into Windows — no extra install) |
| `bcdedit.exe` | Built into Windows — no extra install |

> **No third-party runtime or package manager is required.** (Compiled `net48` binary runs natively on all Windows 10/11 installations).

The tool auto-detects Bazzite by matching any UEFI entry whose `path` or
`description` contains **`Bazzite`**, **`fedora`**, **`shimx64.efi`**, **`grubx64.efi`**, or **`steamos`**.

---

## Quick start

```
1. Boot into Windows.
2. Double-click  Install.cmd  and approve the UAC prompt (one time only).
3. A "Restart to Bazzite" shortcut appears on your Desktop.
4. To boot Bazzite: double-click the shortcut → approve UAC → reboots into Bazzite.
5. To return to Windows: reboot normally from within Bazzite.
   The StickyWindowsBoot task re-pins Windows as UEFI default on next logon.
```

---

## Project structure

```
windows-dualboot-setup/
│
├── RestartToBazzite.sln        # Visual Studio solution (builds both Bazzite & SteamOS apps)
├── build.cmd                  # Quick build script (dotnet CLI, MSBuild, or csc.exe)
│
├── src/
│   ├── RestartToBazzite/      # Bazzite launcher project
│   │   ├── RestartToBazzite.csproj
│   │   ├── Program.cs         # Core application logic & dynamic UEFI discovery
│   │   ├── app.manifest       # UAC administrator elevation & PerMonitorV2 DPI
│   │   └── RestartToBazzite.ico
│   │
│   └── RestartToSteamOS/      # SteamOS launcher project (Steam-themed)
│       ├── RestartToSteamOS.csproj
│       ├── app.manifest
│       └── RestartToSteamOS.ico
│
├── lib/
│   └── DualBoot.psm1          # Shared PowerShell module — all bcdedit/boot logic
│
├── tests/
│   ├── DualBoot.Tests.ps1     # Pester v5 unit tests (bcdedit mock cases)
│   └── RestartToBazzite.Tests/# C# MSTest unit tests (12 automated CI cases)
│
├── extras/
│   ├── RestartToBazzite.cs    # Standalone single-file C# source
│   └── Fix-RTSS.ps1           # Utility: repair RivaTuner Statistics Server hooks
│
├── Install.ps1                # One-time setup (auto-detects Bazzite or SteamOS)
├── Install.cmd                # Double-click launcher → UAC-elevates → Install.ps1
├── Restart-To-Bazzite.ps1     # Runtime script for Bazzite
├── Restart-To-Bazzite.cmd     # Double-click launcher for Bazzite
├── Restart-To-SteamOS.ps1     # Runtime script for SteamOS
├── Restart-To-SteamOS.cmd     # Double-click launcher for SteamOS
├── .github/workflows/build.yml # CI workflow: builds both launchers & runs tests
├── .gitignore
└── README.md
```

---

## Module — `lib/DualBoot.psm1`

All UEFI boot logic lives here. Both `Install.ps1` and `Restart-To-Bazzite.ps1`
import this module, so the implementation is never duplicated.

| Function | Signature | Description |
|---|---|---|
| `Find-BazziteGuidInText` | `([string]$Text)` | **Pure parser.** Scans `bcdedit /enum firmware` output and returns the first matching GUID, or `$null`. No process spawned — directly testable. |
| `Get-BazziteBootGuid` | `()` | Calls `bcdedit /enum firmware` and returns the Bazzite UEFI GUID, or `$null` if absent. Throws on bcdedit failure (not admin, EFI unsupported, etc.). |
| `Set-WindowsBootDefault` | `([-WhatIf])` | Runs `bcdedit /set {fwbootmgr} default {bootmgr}`. Supports `-WhatIf`. |
| `Set-BazziteBootNext` | `(-Guid <uuid> [-WhatIf])` | Runs `bcdedit /set {fwbootmgr} bootsequence <guid>`. Validates GUID format (`{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`). Supports `-WhatIf`. |
| `Test-Administrator` | `()` | Returns `[bool]` — `$true` when the current session is elevated. |

The private `Invoke-BcdEdit` function wraps every real `bcdedit` call and is
the **single mock point** used by all unit tests.

---

## Scripts

### `Install.ps1` — one-time setup

```powershell
# Default install to C:\DualBoot
.\Install.ps1

# Custom install directory
.\Install.ps1 -InstallDir D:\DualBoot
```

Steps performed:

| Step | Action |
|---|---|
| 1 | Detect Bazzite UEFI entry via `Get-BazziteBootGuid` (warns if absent, continues) |
| 2 | Copy `Restart-To-Bazzite.ps1` and `lib/DualBoot.psm1` to `InstallDir\` |
| 3 | Generate `InstallDir\Set-WindowsBootPriority.cmd` — a minimal one-liner bcdedit called by the scheduled task at logon (no PowerShell startup overhead) |
| 4 | Create `Restart to Bazzite.lnk` on the Desktop with the UAC "run as administrator" flag set in the `.lnk` binary header |
| 5 | Register `StickyWindowsBoot` scheduled task (triggers: startup + logon, principal: `NT AUTHORITY\SYSTEM`, highest privileges) |
| 6 | Immediately call `Set-WindowsBootDefault` to pin Windows for the current session |

### `Restart-To-Bazzite.ps1` — runtime restart

Imports the module, calls `Get-BazziteBootGuid` then `Set-BazziteBootNext`, then
`shutdown /r /t 0`. Exits with code 1 and a clear error message if no Bazzite
entry is found.

### `.cmd` launchers

Both `Install.cmd` and `Restart-To-Bazzite.cmd` follow the same pattern:

```cmd
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~dpnx0\"' -Verb RunAs"
    exit /b
)
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0<Script>.ps1"
```

They self-elevate via UAC if not already running as Administrator, then hand
off to the corresponding `.ps1`. No logic lives in the `.cmd` files themselves.

---

## How the sticky-boot mechanism works

```
Windows logon
  └─ StickyWindowsBoot task fires (SYSTEM, highest privileges)
       └─ Set-WindowsBootPriority.cmd
            └─ bcdedit /set {fwbootmgr} default {bootmgr}   ← Windows stays default

"Restart to Bazzite" shortcut pressed
  └─ Restart-To-Bazzite.ps1
       ├─ bcdedit /set {fwbootmgr} bootsequence <bazzite-guid>  ← one-time override
       └─ shutdown /r /t 0

Device boots Bazzite
  └─ bootsequence is consumed by firmware → reverts to {fwbootmgr} default = Windows

Next Windows logon
  └─ StickyWindowsBoot re-pins Windows as default
```

> **Why `bootsequence` and not `default`?** `bootsequence` is consumed after a
> single boot, so the firmware automatically reverts to the persistent `default`
> (Windows). No cleanup step is needed after returning from Bazzite.

---

## Running the tests

Tests use [Pester v5](https://pester.dev) and mock all `bcdedit` calls — no
real process is spawned and tests run on any platform (Windows, macOS, Linux).

```powershell
# Install Pester v5 once
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser

# Run all tests with detailed output
Invoke-Pester .\tests\DualBoot.Tests.ps1 -Output Detailed
```

### Test coverage

| `Describe` block | Cases | What is covered |
|---|---|---|
| `Find-BazziteGuidInText` | 7 | `Bazzite` / `fedora` / `shimx64.efi` labels, case-insensitivity, multi-entry ordering, empty string |
| `Get-BazziteBootGuid` | 4 | Found, not-found, bcdedit non-zero exit, correct `/enum firmware` argument |
| `Set-BazziteBootNext` | 5 | Correct args, targets `{fwbootmgr}`, bcdedit failure, invalid GUID rejected, valid UUID accepted |
| `Set-WindowsBootDefault` | 3 | Correct args, bcdedit failure, `-WhatIf` produces zero bcdedit calls |
| `Test-Administrator` | 1 | Returns `[bool]` |

---

## Building the Launchers (`RestartToBazzite.exe` & `RestartToSteamOS.exe`)

`RestartToBazzite.sln` generates two standalone Windows GUI executables designed specifically for handheld launchers where launching PowerShell or batch scripts is clunky or unsupported:
- **`RestartToBazzite.exe`** — Themed with Bazzite cyan/violet branding and icon.
- **`RestartToSteamOS.exe`** — Themed with SteamOS electric blue branding and icon.

Both binaries dynamically detect whether Bazzite or SteamOS is present on the device, adapt their dialogs/titles accordingly, arm the EFI boot target via `bcdedit /set {fwbootmgr} bootsequence <guid>`, and trigger an immediate reboot (`shutdown /r /t 0`).

### Target Frameworks & Compatibility
- **`net48` (.NET Framework 4.8):** Zero-dependency build. .NET Framework 4.8 is built into every Windows 10 (1903+) and Windows 11 installation. The resulting binary (~30-60 KB) runs out-of-the-box on any gaming handheld without installing additional runtimes.
- **`net8.0-windows` (.NET 8):** Modern .NET Desktop SDK build for environments with .NET 8 Desktop Runtime installed.

### How to Build

#### Option A: Visual Studio 2019 / 2022
1. Open `RestartToBazzite.sln` in Visual Studio.
2. Select **Release** and **Any CPU** (or **x64**).
3. Press **Ctrl+Shift+B** (Build Solution).
4. Both binaries are created under `src/RestartToBazzite/bin/Release/net48/` and `src/RestartToSteamOS/bin/Release/net48/`.

#### Option B: .NET CLI
```cmd
dotnet build RestartToBazzite.sln -c Release
```

#### Option C: Built-in `build.cmd` (Zero Pre-requisites)
Simply double-click `build.cmd` or run:
```cmd
build.cmd
```
`build.cmd` checks for `dotnet`, then Visual Studio `MSBuild`, and automatically falls back to Windows's built-in `csc.exe` compiler (`%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`), guaranteeing a successful build for both executables on any Windows machine.

---

## Handheld Launcher Integration

Attach the desired executable (`RestartToBazzite.exe` or `RestartToSteamOS.exe`) to your handheld's front-end for seamless 1-click reboot using your controller:

### 1. ASUS Armoury Crate SE (ROG Ally & Ally X)
1. Open Armoury Crate SE → **Game Library**.
2. Press **Add** (or gamepad `X`).
3. Browse to `C:\DualBoot\RestartToBazzite.exe` (or `RestartToSteamOS.exe`).
4. Armoury Crate automatically attaches the embedded icon.
5. Highlight the tile → press `Menu` → rename to **"Restart to Bazzite"** (or **"Restart to SteamOS"**).
6. Select the tile anytime to reboot instantly!

### 2. Xbox App
1. Open the Xbox App on Windows.
2. Under "Installed", click **Add a game from your PC**.
3. Browse and select `RestartToBazzite.exe` or `RestartToSteamOS.exe`.
4. The tile appears in your Xbox App library.

### 3. Winhance / Handheld Companion
1. Open Winhance or Handheld Companion Quick Access Menu / App launcher.
2. Add `RestartToBazzite.exe` or `RestartToSteamOS.exe` as a quick-action button or app shortcut.
3. Trigger from the overlay with a single button press.

---

## Two-Way Dual-Boot Ecosystem

This project works in tandem with [`restart-to-windows`](https://github.com/nileshchakraborty/restart-to-windows) (Decky Loader plugin for Bazzite / SteamOS):

| From | To | Mechanism | Tool |
|---|---|---|---|
| **Windows** | **Bazzite** | Windows pins `bootsequence` via `bcdedit` and restarts | `RestartToBazzite.exe` / `Restart-To-Bazzite.cmd` |
| **Bazzite** | **Windows** | Bazzite sets `BootNext` via `efibootmgr` and restarts | [`restart-to-windows`](https://github.com/nileshchakraborty/restart-to-windows) Decky Plugin |

The `StickyWindowsBoot` task ensures Windows remains the persistent default, so sleep, wake, or normal restarts in Windows never unintentionally throw you into Bazzite.

---

## Extras

| File | Purpose |
|---|---|
| [`src/RestartToBazzite/`](./src/RestartToBazzite/) | Full C# project source with `RestartToBazzite.sln`, multi-targeting `net48`/`net8.0-windows`, UAC `app.manifest`, and embedded icon. |
| [`extras/RestartToBazzite.cs`](./extras/RestartToBazzite.cs) | Standalone single-file C# / WinForms GUI. |
| [`extras/Fix-RTSS.ps1`](./extras/Fix-RTSS.ps1) | Repairs RivaTuner Statistics Server (RTSS) hooks — enables Microsoft Detours, disables D3D8 hooking, clears stale `FnOffsetCache`. Unrelated to dual-boot; included as a convenience utility for gaming setups. |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Bazzite boot entry not found" | EFI entry has an unusual label | Run `bcdedit /enum firmware` in an elevated cmd; verify at least one entry contains `Bazzite`, `fedora`, or `shimx64.efi` |
| UAC prompt loops / nothing runs | PowerShell execution policy | Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` in an elevated PowerShell |
| Shortcut clicks but nothing happens | Script path changed after moving `InstallDir` | Re-run `Install.cmd` with the new `-InstallDir` path |
| Device still boots Windows after shortcut | `bootsequence` not written (bcdedit failed silently) | Open an elevated PowerShell and run `Restart-To-Bazzite.ps1` directly to see the error |
| Device reboots to Windows instead of Bazzite | Bazzite GUID changed after a firmware update | Re-run `Install.cmd` to re-detect the GUID |
| Scheduled task not running | Task deregistered or missing SYSTEM privilege | Open Task Scheduler → `StickyWindowsBoot` → verify principal is `NT AUTHORITY\SYSTEM` at highest level; re-run `Install.cmd` if missing |
| `C:\DualBoot` scripts missing | `Install.ps1` not re-run after reinstall | Re-run `Install.cmd` |
