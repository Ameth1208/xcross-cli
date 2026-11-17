# XCross CLI (xcm) v1.3.0

![XCross CLI logo](assets/logo.svg)

![XCross CLI demo](docs/cli-demo.gif)

[![GitHub stars](https://img.shields.io/github/stars/Ameth1208/xcross-cli?style=social)](https://github.com/Ameth1208/xcross-cli)

⭐ **If you find this useful, please star the repo!** It helps others discover it.
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub Pages](https://img.shields.io/badge/demo-live-brightgreen)](https://ameth1208.github.io/xcross-cli/)


A terminal interface inspired by modern CLIs used with programming assistants. **It does not include an AI model**, but provides a fast keyboard-driven experience with a command palette and reusable commands.

> Windows-focused (PowerShell 5.1+). For a cross-platform Flutter setup helper, see `linux/setup-flutter.sh` (and `linux/linux-cli.sh` for Linux).

## Features

- Menu-driven TUI navigated with arrow keys (no Enter needed for most actions)
- Command palette (`/`) with fuzzy filtering
- Direct commands: `xcm help`, `xcm doctor`, `xcm device`, `xcm run`, `xcm sign`, etc.
- Guided installers for Swift, xcross and dependencies
- Project/bundle management for Flutter iOS builds
- USB/Wi-Fi tunnel helpers for device debugging
- Direct USB installation of existing signed IPAs on Windows: `xcm install "app.ipa"`
- Optional IPA signing, Flutter IPA builds, and Git updates from the current directory
- No admin rights required for the global `xcm` command

## Live preview

See how the CLI menu looks: https://ameth1208.github.io/xcross-cli/

## Install from GitHub (no clone needed)

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Ameth1208/xcross-cli/main/windows/xcm-install.ps1 | iex
```

## Language / Idioma

The CLI is bilingual (English by default, Spanish available):

```powershell
xcm language en
xcm language es
```

Or press `I` in the menu and confirm. Scripts are copied to `%LOCALAPPDATA%\Programs\XCrossCLI` and added to your user `PATH`. Open a **new terminal** to use `xcm` anywhere.

To remove it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\uninstall.ps1
```

Without the global command, replace `xcm` with `./windows/xcm.cmd` when inside the extracted folder.

## Flutter setup helper (`setup-flutter.sh`)

For a quick cross-platform Flutter environment setup:

```bash
chmod +x linux/setup-flutter.sh
./linux/setup-flutter.sh
```

## Linux CLI (`linux-cli.sh`)

A Linux counterpart of the Windows CLI. Run directly:

```bash
chmod +x linux/linux-cli.sh
./linux/linux-cli.sh            # interactive menu
./linux/linux-cli.sh doctor     # verify tools
./linux/linux-cli.sh help       # list commands
```

## Build, sign and install IPA files (Windows)

Already have an IPA signed for your iPhone? Install it directly:

```powershell
xcm install "C:\Apps\my-app.ipa"
```

Installation only needs `pymobiledevice3`, Apple USB drivers and an unlocked, trusted iPhone connected over USB. It does not ask for a P12 certificate, provisioning profile, Apple ID, Xcode or Flutter project. iOS validates the signature already in the package; unsigned or incompatible IPAs can still be rejected. Press **7** in the main menu for direct installation. `xcm install` without arguments keeps the guided setup.

Open `xcm ipa` or run:

```powershell
xcm ipa build --mode release
xcm ipa build --project "C:\projects\my-app" --target lib/main.dart --flavor staging
xcm ipa sign ".\my-app.ipa" --certificate ".\certificate.p12" --profile ".\app.mobileprovision" --output ".\my-app-signed.ipa"
xcm ipa install ".\my-app-signed.ipa" --udid "IPHONE-UDID"
```

Build uses `xcross flutter build --ipa` with `debug`, `profile` or `release` (default). Project resolution prefers `--project`, then the current Flutter folder, then the saved project. Building requires the XCross iOS toolchain; the resulting IPA still needs a valid development or distribution signature for device installation.

Signing existing IPAs requires [zsign for Windows](https://github.com/zhlynn/zsign#build) on PATH, a `.p12` containing the private key, and a compatible `.mobileprovision` profile. XCross 2.0.5 has no standalone IPA signing command. The P12 password is prompted securely and never saved or printed; zsign receives it as a process argument. Optional `--bundle-id` changes the identifier if the profile permits it. Output defaults to `name-signed.ipa` beside the original; existing output files are rejected. Apps with extensions needing separate profiles require more specific signing configuration through zsign.

Install uses `pymobiledevice3 apps install --streaming` for an existing signed IPA. Connect and unlock your iPhone over USB and accept Trust. Omit `--udid` for a single connected device; multiple devices require a selection. iOS validates the signature and profile during installation. This does not make encrypted App Store packages installable.

IPA, certificate and profile paths are relative to the caller's current directory. `xcm sign` keeps its signing diagnostics behavior; use `xcm ipa sign` or `xcm sign-ipa` for signing. `xcm build` and `xcm install-ipa` are also available.

## Update from the current directory

```powershell
xcm project update
xcm project update "C:\projects\my-app"
xcm update-cli --local
```

`project update` (alias `update-project`) updates the Git repository in the current directory, including non-Flutter projects. It requires a clean working tree and an upstream branch, then runs `git pull --ff-only`. Divergent history fails without merging or discarding local work. The saved Flutter project does not affect this command.

Run `update-cli --local` from this package's root or its `windows` folder to install the local scripts into `%LOCALAPPDATA%\Programs\XCrossCLI` and register the user PATH. This activates local changes without publishing. `xcm update-cli` still downloads from GitHub; `xcm update` updates XCross itself. Without a global installation, use `.\windows\xcm.cmd` instead of `xcm` from this folder.
