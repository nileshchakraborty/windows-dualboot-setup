# Windows Dual-Boot Setup — ROG Xbox Ally X

Scripts for managing a **Windows + Bazzite** dual-boot setup on the ROG Xbox Ally X.
The core problem they solve: the UEFI firmware defaults to whichever OS booted last, so waking
from sleep/hibernate in Windows can unexpectedly land you in Bazzite. These scripts pin Windows as
the persistent default while giving you a one-click desktop shortcut to boot into Bazzite on demand.

---

## Prerequisites

### Hardware / firmware

| Requirement | Details |
|---|---|
| Device | ROG Xbox Ally X (or any UEFI dual-boot PC) |
| Firmware mode | **UEFI** — Secure Boot state does not matter, but CSM / Legacy boot must be **off** |
| Bazzite installed | Bazzite must already be installed and have its own UEFI firmware entry (labelled `Bazzite`, `fedora`, or containing `shimx64.efi`) |
| Windows installed | Windows must be installed alongside Bazzite on the same drive |

### Windows requirements

| Requirement | Version / Notes |
|---|---|
| Windows | 10 or 11 |
| PowerShell | 5.1+ (built into Windows — no install needed) |
| `bcdedit.exe` | Built into Windows — lives at `%SystemRoot%\System32\bcdedit.exe` |
| Administrator account | All scripts require elevated (Administrator) privileges — they self-elevate via UAC if needed |

> **No third-party software, package manager, or internet connection is required.**

---

## What the scripts do

### One-time setup — `Install-StickyBoot.cmd`

Run this **once** on Windows (double-click or right-click → Run as administrator).

It calls [`Setup-StickyBoot.ps1`](./Setup-StickyBoot.ps1) which does four things:

1. **Detects the Bazzite UEFI entry** from `bcdedit /enum firmware` (matches `Bazzite`, `fedora`, or `shimx64.efi`).
2. **Creates `C:\DualBoot\`** and drops two runtime scripts into it:
   - `Set-WindowsBootPriority.cmd` — sets `{fwbootmgr} default {bootmgr}` (pins Windows as default)
   - `Restart-To-Bazzite.ps1` / `Restart-To-Bazzite.cmd` — arms Bazzite as a one-time boot target and reboots
3. **Creates a Desktop shortcut** — "Restart to Bazzite.lnk" → `C:\DualBoot\Restart-To-Bazzite.cmd`
4. **Registers a Scheduled Task** (`StickyWindowsBoot`) that runs `Set-WindowsBootPriority.cmd` at startup and logon as `SYSTEM`, ensuring Windows remains the UEFI default even after a Bazzite session changes it.

### Restarting to Bazzite — `Restart-To-Bazzite.cmd` / `.ps1` / `.vbs`

Three equivalent launchers for the same action — use whichever suits your workflow:

| File | Best for |
|---|---|
| `Restart-To-Bazzite.cmd` | Desktop shortcut, Task Scheduler, or plain double-click |
| `Restart-To-Bazzite.ps1` | Running directly from a PowerShell prompt |
| `Restart-To-Bazzite.vbs` | Silent background launch (no console window) |

All three:
1. Auto-elevate to Administrator if not already elevated (UAC prompt).
2. Run `bcdedit /enum firmware` to dynamically locate the Bazzite UEFI GUID.
3. Call `bcdedit /set {fwbootmgr} bootsequence <bazzite-guid>` to arm Bazzite as the **one-time** next boot.
4. Call `shutdown /r /t 0` to reboot immediately.

> **One-time only:** `bootsequence` (not `default`) is used, so after a single Bazzite session the firmware reverts to the Windows default set by the Scheduled Task on next logon.

### GUI launcher — `RestartToBazzite.cs`

A minimal C# / WinForms executable source. Compile with:

```cmd
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe ^
  /target:winexe /r:System.Windows.Forms.dll ^
  RestartToBazzite.cs /out:RestartToBazzite.exe
```

Behaviour: auto-elevates via UAC, searches `bcdedit /enum firmware` for the Bazzite entry, arms `bootsequence`, and calls `shutdown /r /t 0`. Shows a message box on error.

### Helper scripts

| File | Purpose |
|---|---|
| `Set-WindowsBootPriority.cmd` | Called by the Scheduled Task — sets `{fwbootmgr} default {bootmgr}` |
| `Create-Shortcut.ps1` | Standalone shortcut creator if the setup script's shortcut needs to be recreated |
| `Fix-Shortcut.ps1` | Repairs the desktop shortcut path if `C:\DualBoot` was moved |
| `Fix-RTSS.ps1` | RivaTuner Statistics Server compatibility fix (unrelated to dual-boot) |
| `Generate-Icon.ps1` | Generates a custom `.ico` for the desktop shortcut |

---

## Quick start

```
1. Boot into Windows.
2. Double-click  Install-StickyBoot.cmd  (approve UAC prompt).
3. Setup completes — "Restart to Bazzite" shortcut appears on your Desktop.
4. To boot Bazzite: double-click the shortcut → approve UAC → device reboots into Bazzite.
5. To return to Windows: reboot normally from Bazzite (or press the power button).
   The Scheduled Task re-pins Windows as default on next Windows logon.
```

---

## How the sticky-boot mechanism works

The UEFI firmware's `{fwbootmgr} default` entry controls which OS loads on power-on/reboot.
Bazzite (like most Linux bootloaders) resets this to itself each boot.
`StickyWindowsBoot` counters that by running `bcdedit /set {fwbootmgr} default {bootmgr}` as
SYSTEM at every Windows startup and logon — so Windows always wins the default race without
modifying Bazzite's side of the setup.

```
Windows logon
  └─ StickyWindowsBoot task fires
       └─ bcdedit /set {fwbootmgr} default {bootmgr}   ← Windows stays default

"Restart to Bazzite" shortcut pressed
  └─ bcdedit /set {fwbootmgr} bootsequence <bazzite-guid>  ← one-time override
  └─ shutdown /r /t 0

Device boots Bazzite  (bootsequence consumed, firmware reverts to default = Windows)

Next Windows boot
  └─ StickyWindowsBoot re-confirms Windows as default
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Script says "Bazzite boot entry not found" | Bazzite's EFI entry has an unusual label | Run `bcdedit /enum firmware` in an elevated cmd and look for the Bazzite entry; update the regex in `Restart-To-Bazzite.ps1` if needed |
| UAC prompt loops / never elevates | Execution policy blocking PowerShell | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once in an elevated PowerShell |
| Device still boots Windows after shortcut | `bootsequence` was not written | Run `bcdedit /enum firmware` after the script and verify `bootsequence` contains the Bazzite GUID |
| Scheduled Task not running | Task requires SYSTEM-level run | Open Task Scheduler → `StickyWindowsBoot` → verify it runs as `NT AUTHORITY\SYSTEM` with highest privileges |
| `C:\DualBoot` scripts missing after reinstall | Setup script wasn't re-run | Re-run `Install-StickyBoot.cmd` |
