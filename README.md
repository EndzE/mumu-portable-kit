# MuMu Portable Kit

> Transform official overseas MuMu Player engine installers (Android 12 & 15) into a **fully self-contained, offline-ready portable emulator**. Move it, back it up, or run it directly from an external drive with zero reinstall required.

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011%20x64-blue.svg)](#system-requirements)
[![Android](https://img.shields.io/badge/Android%20Engines-12%20%7C%2015-green.svg)](#installation-guide)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)
[![Offline](https://img.shields.io/badge/Offline-100%25%20Ready-orange.svg)](#offline-mode-firewall-isolation)

*Tested with MuMu Player 15.8.5.5750 (`mumu15`) + 12.8.5.5749 (`nemux`) + nxmain 1.8.5.5748 (overseas/global builds) on Windows 10/11 x64.*

---

> [!WARNING]
> ### Do NOT Install Alongside a Standard (Non-Portable) MuMu Installation
> **Install ONLY this portable version OR the normal version—NEVER both on the same PC.**
>
> Both versions share global Windows kernel drivers (`MuMuVMMDrv` / `MuMuNxSup`), hypervisor runtimes in `C:\Program Files`, COM class registrations, and firewall configurations. Running portable launch, driver, or cleanup scripts on a system with a standard MuMu installation will cause collisions and break the emulator.

---

## Features

- **Fully Self-Contained:** All VM definitions, settings, screenshots, and shared folders live in `<Target>\Data`. Nothing is saved to your personal Windows profile.
- **Plug & Play Portability:** Move or copy your folder to any path or drive. Paths self-repair automatically on every launch.
- **Multi-Engine Support:** Run **Android 15** (`mumu15`), **Android 12** (`nemux`), or both simultaneously in one folder.
- **Multi-Instance Manager:** Include the optional NX Launcher (`nxmain`) for full instance management and offline device cloning.
- **1-Click Offline Mode:** Built-in Windows Firewall script locks down internet access without third-party tools like simplewall.
- **Zero Residual Traces:** Includes dedicated scripts to install, uninstall, or rescue-clean drivers and system remnants anytime.

---

## System Requirements

| Requirement | Details |
|---|---|
| **Operating System** | Windows 10 / 11 (64-bit) |
| **Permissions** | Administrator rights (required once to register hypervisor kernel drivers) |
| **Storage** | ~4 GB free disk space per installed engine (~6.5 GB for both Android 12 & 15) |
| **Compatibility** | No existing standard (non-portable) MuMu installation on the PC |

---

## Installation Guide

### Step 1: Download Official Packages
Download the overseas/global installer binaries from the [LOVECHEN/mumu-release](https://github.com/LOVECHEN/mumu-release/releases) repository:

| Component | File Pattern | Description | Required? |
|---|---|---|---|
| **Android 15 Engine** | `MuMu-setup-mumu15-V15.8.5.*-overseas-*.exe` | Android 15 core engine (~1 GB) | One engine required |
| **Android 12 Engine** | `MuMu-setup-nemux-V12.8.5.*-overseas-*.exe` | Android 12 core engine (~0.9 GB) | One engine required |
| **NX Launcher UI** | `MuMu-setup-nxmain-V1.8.5.*-overseas-*.exe` | Multi-instance manager UI (~240 MB) | *Optional* |

> [!TIP]
> **Add components later:** You can install one engine now and add another engine or the launcher UI later. Place the new `.exe` next to `InstallMuMuPortable.cmd` and run it again on the same target folder—it detects what is already there and installs only the missing components.

### Step 2: Run Setup
1. Clone or download this repository.
2. Place your downloaded `.exe` installer file(s) in the **same folder** as `InstallMuMuPortable.cmd`.
3. Right-click **`InstallMuMuPortable.cmd`** and select **Run as Administrator** (or double-click and accept UAC).
4. Enter your desired destination folder (default: `C:\MuMuPortable`).
5. Choose whether to enable the kernel driver on this PC (default: **Yes**).

---

## How to Run

Inside your portable target folder, run the script for your setup:

| Script | Purpose |
|---|---|
| **`Launch Android 15.cmd`** | Directly boots the Android 15 engine (offline-ready). |
| **`Launch Android 12.cmd`** | Directly boots the Android 12 engine (offline-ready). |
| **`Launch Launcher.cmd`** | Opens the NX Launcher UI to create, clone, and manage multi-instances. |

### Shared Folder & User Data
- **File Sharing:** Place files in `<Target>\Data\MuMuSharedFolder` to access them inside Android.
- **Backups:** Simply copy or archive `<Target>\Data` to preserve all your emulators, settings, and apps.

---

## Relocating or Moving PCs

- **Moving the folder on the same PC:**
  Move or rename the target folder to any drive or path. VM definitions and configurations self-heal automatically on launch.
- **Using on a new PC:**
  Copy the target folder to the new PC, then run **`Enable-Driver.cmd`** once as Administrator to initialize the kernel driver.

---

## Offline Mode (Firewall Isolation)

To run MuMu in a completely local sandbox without network access or telemetry, use the built-in firewall toggles inside the target folder:

- **`Block-Internet.cmd`** *(Administrator)*:
  Adds Windows Firewall **BLOCK** rules (Inbound & Outbound) for every MuMu executable, engine, and hypervisor runtime.
  - Device boot, local loopback, ADB (`adb devices`), and shared folder access remain fully functional.
  - Rules are isolated per folder (`MuMu Portable Offline (<folder>)`), preventing conflicts across multiple setups.
- **`Allow-Internet.cmd`** *(Administrator)*:
  Removes the firewall block rules and restores normal network connectivity.

---

## Removal & Cleanup

### Normal Removal
1. Inside your target portable folder, run **`Disable-Driver.cmd`** as Administrator. This safely cleans up:
   - Kernel driver services (`MuMuVMMDrv`, `MuMuNxSup`, `MuMu*NetLwf`)
   - `C:\Program Files` hypervisor runtime files
   - Firewall rules and background services
2. Delete the target portable folder.

### Rescue Cleanup (`Cleanup-Residue.cmd`)
If the portable folder was already deleted without running `Disable-Driver.cmd` first, run **`Cleanup-Residue.cmd`** as Administrator from this repository. It will purge all orphan driver services, COM registrations, and runtime traces.

> [!NOTE]
> **Restoring broken runtimes:** If you ran `Cleanup-Residue.cmd` by mistake on a PC where you still have your portable folder, the emulator will fail to boot (`VERR_RPC_SERVER_UNAVAILABLE`). Run `InstallMuMuPortable.cmd` again pointing to that same folder to instantly re-create the `C:\Program Files` runtimes without reinstalling the emulators.

---

## Repository Contents

| File | Purpose |
|---|---|
| [`InstallMuMuPortable.cmd`](InstallMuMuPortable.cmd) | Main entry point (requests Administrator rights). |
| [`InstallMuMuPortable.ps1`](InstallMuMuPortable.ps1) | Setup orchestrator, silent driver installer, and wrapper generator. |
| [`Cleanup-Residue.cmd`](Cleanup-Residue.cmd) | Standalone rescue script for removing leftover system traces. |
| [`README.md`](README.md) | Documentation and user guide. |
| [`LICENSE`](LICENSE) | Project license (MIT). |

---

<details>
<summary><b>Under the Hood & Technical Architecture (Click to expand)</b></summary>

<br>

### How the Installer Works
The kit automates the official engine installers through command-line parameters (`/txn_id`, `/action=commit`, `/silent=1`, `/from_orchestrator=1`) while redirecting user directories (`APPDATA`, `LOCALAPPDATA`, `TEMP`, and `VBOX_USER_HOME`) to `<target>\Data`:

```cmd
MuMu-setup-<engine>-V<version>-<channel>-<build>.exe ^
  /txn_id=<guid> /action=install_prepare|commit ^
  /from_orchestrator=1 /silent=1 /auto_start=false ^
  /product_version=<version> /fchannel=gw-overseas12 ^
  /D=<target>\Netease\MuMuPlayer15
```

### Key Technical Aspects
1. **Unified Target Tree:** Both engines (`mumu15` and `nemux`) install into `Netease\MuMuPlayer15` and register themselves in `install_config.json`.
2. **Version Negotiation:** If an engine package reports a downgrade error (`rc 80002`), the installer detects and re-aligns against the existing installation record.
3. **Hypervisor Runtime Dependencies:** MuMu requires hypervisor runtimes located in `C:\Program Files\MuMuNxVbox` and `C:\Program Files\MuMuVMMVbox`. The scripts automatically populate and register COM classes on setup and teardown.
4. **Offline VM Initialization:** The NX Launcher expects a valid `vms` directory at the product root. Without it, the UI falls back to an online download state. The kit pre-initializes this directory to ensure offline boot.
5. **Clean Uninstallation:** Parent registry hives and folders (`HKLM:\SOFTWARE\Netease`, `ProgramData\Netease`) are checked for children before removal, ensuring no non-empty folders are removed and other software is not disturbed.

</details>

---

## Disclaimer

*This project is an independent, unofficial open-source utility. It is not affiliated with, endorsed by, or supported by NetEase. No proprietary MuMu Player binaries are distributed in this repository.*
