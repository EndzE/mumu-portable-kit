# MuMu Portable Kit

Turns the official MuMu Player engine installers (Android 12 / Android 15,
overseas builds) into a **fully portable, offline installation** in a folder
you choose.

This repository contains **scripts only** - no MuMu binaries. You supply the
official engine installer(s) yourself (see below): Android 15 (`mumu15`)
and/or Android 12 (`nemux`). Optionally you can also supply the official
**NX launcher** package (`MuMu-setup-nxmain-*.exe`), which adds a launcher UI
with an Android version manager on top of the engines. The scripts drive the
installers and redirect everything they write so the result is a
self-contained folder: move it, back it up, run it from a USB drive - no
reinstall needed.

Tested with MuMu Player 15.8.5.5750 (mumu15) + 12.8.5.5749 (nemux) +
nxmain 1.8.5.5748 (overseas/global builds), Windows 10/11 x64.

## What it does

- **Install:** one-time run of the official engine installer(s), silently; the
  only downloads are the engine installers you supply yourself.
- **Engines:** installs whichever you supply - Android 15 (`mumu15`), Android 12
  (`nemux`) or both into the same folder. Drop the optional NX launcher package
  (`MuMu-setup-nxmain-*.exe`) next to the installer and it is installed too:
  you get the launcher app with the device list, and "+ New" offers exactly the
  Android versions whose engine is installed.
- **Add components later:** put the extra exe next to the installer and run it
  again on the same folder - it detects what is already installed and adds only
  the missing component(s) (another engine, or the launcher).
- **First run needs no download:** the first device is created locally and
  boots straight away; additional devices via the launcher's "+ New" work
  offline too.
- **Portability:** all user data (settings, screenshots, shared folder, VM
  profile) lives in `<target>\Data` - at runtime nothing is written to your
  real user profile - and the folder can be moved or copied to any path or
  drive: absolute paths are re-derived and self-repaired on every launch.
- **Generated scripts:** one direct-boot script per installed engine (`Launch
  Android 15.cmd` / `Launch Android 12.cmd`), `Launch Launcher.cmd` (device
  list UI, when the launcher component is included), plus `Enable-Driver.cmd` /
  `Disable-Driver.cmd` for the per-PC kernel driver.
- **Per-PC cleanup:** `Disable-Driver.cmd` removes the driver, the `C:\Program
  Files` runtimes, the firewall rules, the NX remote service, the launcher
  shortcuts / uninstall entry and runtime traces from a PC; the launch scripts
  then stop with a "run Enable-Driver.cmd" message instead of booting a doomed
  device.
- **Runtimes are required:** each engine resolves its hypervisor through
  `Netease\MuMuPlayer15\nx_device\<ver>\configs\device\hypervisor_config.json`
  (Android 15 -> `MuMuNxVbox`, Android 12 -> `MuMuVMMVbox`) and refuses to boot
  a VM when the `C:\Program Files` directory is gone
  (`VERR_RPC_SERVER_UNAVAILABLE`). The installer re-creates them automatically
  on every run (see Removal).
- **Offline mode:** `Block-Internet.cmd` (no simplewall needed) blocks all MuMu
  network access on this PC via Windows Firewall; `Allow-Internet.cmd` reverts
  it - see Going fully offline.

## Requirements

- Windows 10 / 11 (x64)
- Administrator rights (the engine installs the MuMuVMMDrv/MuMuNxSup kernel driver +
  hypervisor runtime - this is why the installer asks for UAC)
- ~4 GB free space on the target drive per engine you install (one engine is
  about 3.3 GB installed; two engines about 6.5 GB)

## Installation

1. Download the engine installer(s) you want from
   **https://github.com/LOVECHEN/mumu-release/releases**:
   - `MuMu-setup-mumu15-V15.8.5.5750-overseas-*.exe` - Android 15, about 1 GB
   - `MuMu-setup-nemux-V12.8.5.5749-overseas-*.exe` - Android 12, about 0.9 GB
2. Optional - for the launcher with Android version manager, also download
   `MuMu-setup-nxmain-V1.8.5.5748-overseas-*.exe` (about 240 MB).
3. Download / clone this repository and put the exe(s) **next to
   `InstallMuMuPortable.cmd`** in the same folder (at least one engine).
4. Double-click `InstallMuMuPortable.cmd`.
5. Accept the UAC prompt, then enter the target folder when asked
   (default `C:\MuMuPortable`).
6. Wait a few minutes; near the end it asks whether to enable the emulator
   driver on this PC (one-time, default yes). When it says done, start the
   emulator with **`Launch Android 15.cmd`** / **`Launch Android 12.cmd`**
   (or **`Launch Launcher.cmd`** for the device list) inside the target folder.

The kit auto-detects the exe(s) by filename and warns if they do not look like
the overseas/global builds.

## Repository contents

| File | Purpose |
|---|---|
| `InstallMuMuPortable.cmd` | Entry point - requests Administrator rights and launches the installer |
| `InstallMuMuPortable.ps1` | The installer logic |
| `Cleanup-Residue.cmd` | Rescue cleanup: removes driver/runtime/COM/traces left on a PC when the portable folder was deleted without uninstalling (Administrator) |
| `README.md` | This file |
| `LICENSE` | MIT license |

Everything else is generated into the target folder by the installer:
`Launch Android 15.cmd` / `Launch Android 12.cmd` (one per installed engine),
`Launch Launcher.cmd` (only when the launcher component was included),
`Enable-Driver.cmd`, `Disable-Driver.cmd`, `Block-Internet.cmd` /
`Allow-Internet.cmd` (optional offline mode), `README.txt`, `Netease\`
(program files) and `Data\` (user data + shared folder).

## Using the portable folder

- Start with the `Launch Android 1x.cmd` script of the version you want
  (boots the first engine of that version directly) or `Launch Launcher.cmd`
  (device list - included only when the launcher component is part of the
  install). All of them set up the portable environment (redirected
  `APPDATA` / `TEMP` / VirtualBox home, path self-repair).
- On a fresh install the first launch creates the first Android device
  automatically - it boots straight away, fully offline.
- Sharing Android files: `<target>\Data\MuMuSharedFolder`.
- **Moving the folder** to another path or drive: works out of the box - VM
  definitions are regenerated with the new paths on launch.
- **Copying the folder to a new PC**: run `Enable-Driver.cmd` there once
  (Administrator) - the kernel driver is per-PC - or simply re-run the
  installer on that PC.

## Going fully offline (no simplewall needed)

Run **`Block-Internet.cmd`** (Administrator) inside the target folder on any
PC where MuMu should never touch the network:

- Adds Windows Firewall **BLOCK** rules (Inbound + Outbound) for every MuMu
  executable found in the tree (all installed engines, the launcher component
  when present, and both `C:\Program Files\MuMu*Vbox` hypervisor runtimes),
  all tagged with the group `MuMu Portable Offline (<folder>)` - one group
  per portable folder, so **several setups on one PC don't overwrite each
  other's rules** (they do share the block on the common `C:\Program Files`
  runtimes).
- Windows Firewall evaluates block rules **before** allow rules, so this also
  overrides the allow rules MuMu's own installers add while offline mode is
  active.
- Fully local operation is untouched: device boot, the launcher's device list,
  adb (`adb devices`) and the shared folder all run over loopback, which
  Windows Firewall never filters. The Android guest's own internet is blocked
  too (its NAT runs inside the MuMu process) - that is the point of offline
  mode.
- It is per-PC and path-bound: re-run `Block-Internet.cmd` after **moving the
  folder** or **adding/updating a component** so new executables are covered.
- Revert anytime with **`Allow-Internet.cmd`**. `Disable-Driver.cmd` and
  `Cleanup-Residue.cmd` also remove the offline rules (full cleanup).

## Removal

- Remove the driver + runtime + firewall rules from a PC (Administrator):
  `Disable-Driver.cmd` inside the target folder.
- Deleted the target folder by accident and the driver is still installed?
  Run `Cleanup-Residue.cmd` (Administrator) from this kit on that PC - it
  removes the driver services, both hypervisor runtimes, COM registrations,
  the display device, firewall rules and traces without needing the folder.
- Kept (or restored) the target folder but ran `Cleanup-Residue.cmd` anyway?
  Devices will fail to boot (`VERR_RPC_SERVER_UNAVAILABLE`) because the
  cleanup also deleted the `C:\Program Files` runtimes that every installed
  engine needs. Just run `InstallMuMuPortable.cmd` again on the kept folder
  (with any engine exe next to it): the refresh re-creates each installed
  engine's runtime from its own `nx_device\<ver>\hypervisor` payload and
  re-registers the hypervisor COM classes from there - no reinstall and no
  driver setup needed.
- Delete the target folder to remove the emulator and all its data.

## How it works

The kit runs the official engine installers exactly as MuMu's own downloader
would - once per engine, each with its own transaction - while redirecting
`APPDATA`, `LOCALAPPDATA`, `TEMP` and `VBOX_USER_HOME` into `<target>\Data`:

```
MuMu-setup-<engine>-V<version>-<channel>-<build>.exe
  /txn_id=<guid> /action=install_prepare|commit
  /from_orchestrator=1 /silent=1 /auto_start=false
  /product_version=<version> /fchannel=gw-overseas12
  /D=<target>\Netease\MuMuPlayer15
```

`<engine>` is `mumu15` (Android 15) or `nemux` (Android 12). Both install into
the same product folder and register themselves in the product's
`install_config.json` - that is how the launcher knows which Android versions
to offer in "+ New". If a component is rejected with a version downgrade
error (rc 80002), the kit automatically retries with the already-installed
product version.

If the nxmain package is present it runs afterwards with the same protocol
against the same product folder, using the **engine's** product version
(nxmain's own version is lower and would otherwise be rejected as a
downgrade). The engine also installs the hypervisor driver and creates its
firewall rules automatically; leftover bookkeeping files in the real user
profile (engine install record, nxmain shortcuts, autostart entry, uninstall
entry, remote service, `C:\ProgramData\Netease`) are cleaned up at the end of
the install.

Implementation notes:

- The NX launcher validates a `vms` directory at the product root on every
  start. Without it the launcher runs in a degraded mode where device
  management is disabled and "+ New" tries to download an engine from the
  internet (which fails when offline). The kit creates the directory, so the
  launcher comes up in a normal, fully offline state.
- Each device is a VirtualBox VM; the base Android system image ships with the
  engine, so creating and booting devices is a purely local operation. The
  per-device VM definition files store absolute paths, and the launcher
  regenerates them with the new paths when the folder is moved - which is why
  portable relocations work without any extra steps.

## Disclaimer

Unofficial tool. Not affiliated with, endorsed by, or supported by NetEase.
No MuMu binaries are hosted in this repository; the official installer is
downloaded by the user from the link above. Intended for personal use -
portable installs, backups, and running your own legally obtained copy of
MuMu Player.
