# XCross CLI (xcm) v1.2.0

A terminal interface inspired by modern CLIs used with programming assistants. **It does not include an AI model**, but provides a fast keyboard-driven experience with a command palette and reusable commands.

> Windows-focused (PowerShell 5.1+). For a cross-platform Flutter setup helper, see `setup-flutter.sh` (and `linux-cli.sh` for Linux).

## Features

- Menu-driven TUI navigated with arrow keys (no Enter needed for most actions)
- Command palette (`/`) with fuzzy filtering
- Direct commands: `xcm help`, `xcm doctor`, `xcm device`, `xcm run`, `xcm sign`, etc.
- Guided installers for Swift, xcross and dependencies
- Project/bundle management for Flutter iOS builds
- USB/Wi-Fi tunnel helpers for device debugging
- No admin rights required for the global `xcm` command

## Quick Start (Windows)

1. Extract this ZIP into a permanent folder.
2. Run `start.cmd` to open the menu, or `xcm.cmd` from that folder.
3. Use **arrows** to navigate and **Right arrow / Space** to execute. Press `/` for the command palette.
4. Numbers `1`-`9`, `D`, `F`, `P`, `I`, `?` are shortcuts where shown. `Esc` / `0` goes back.

## Install `xcm` as a global command

Run the installer (no administrator required):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Or press `I` in the menu and confirm. Scripts are copied to `%LOCALAPPDATA%\Programs\XCrossCLI` and added to your user `PATH`. Open a **new terminal** to use `xcm` anywhere.

To remove it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Saved settings in `%APPDATA%\XCrossMenu` are preserved.

## Direct commands (without opening the menu)

```powershell
xcm help
xcm doctor
xcm device
xcm devmode status
xcm devmode reveal
xcm devmode enable
xcm tunnel usb
xcm tunnel wifi
xcm xcode
xcm sdk install "C:\Users\USER\Downloads\Xcode.xip"
xcm precache debug
xcm precache all
xcm project show
xcm project set "C:\path\to\flutter_project"
xcm bundle default
xcm bundle original
xcm sign
xcm sign com.example.app
xcm run --usb -t lib/main.dart
xcm run --wifi
xcm update
```

Without the global command, replace `xcm` with `./xcm.cmd` when inside the extracted folder.

## Flutter setup helper (`setup-flutter.sh`)

For a quick cross-platform Flutter environment setup:

```bash
chmod +x setup-flutter.sh
./setup-flutter.sh
```

It verifies basic dependencies, installs the Flutter SDK, attempts to install `xcross`, and configures your shell `PATH`. Override defaults with environment variables:

```bash
FLUTTER_VERSION=stable INSTALL_DIR=$HOME/dev ./setup-flutter.sh
```

## Linux CLI (`linux-cli.sh`)

A Linux counterpart of the Windows CLI. Run directly:

```bash
chmod +x linux-cli.sh
./linux-cli.sh            # interactive menu
./linux-cli.sh doctor     # verify tools
./linux-cli.sh help       # list commands
```

## Notes on downloads and signing

- Guided install (`xcm install`) prepares Swift, xcross and dependencies. `xcross setup` may install LLVM, Python, Visual Studio Build Tools, etc.
- `xcm xcode` opens official Apple downloads. `xcross sdk install` does **not** download `Xcode.xip`; it imports the SDK from an already downloaded file, matched to the active Swift version.
- `xcm precache debug` / `all` download Flutter engine artifacts for iOS, run from the selected Flutter project.
- On iOS 27, an **"Untrusted Developer"** warning must be resolved **on the iPhone** with developer authorization. Changing the Bundle ID or re-downloading Flutter does not authorize certificates. Use `xcm sign` for diagnostics and `xcm trust` for guidance.
- `xcm tunnel usb` may require an elevated PowerShell. The menu opens an elevated window when needed. Keep the tunnel open during debugging.
- For xcross Apple ID authentication, consider a separate test account; unofficial methods may trigger verification or blocks.

## How it works

Everything is written in PowerShell with no extra dependencies for the UI. The CLI calls tools installed on your machine: `winget`, `swift`, `xcross`, `pymobiledevice3`, `flutter`. **It does not include or redistribute Apple SDK, credentials, Swift, xcross or Flutter engines.** It stores no passwords. It keeps the current project, the `Xcode.xip` path and the App ID mode in `%APPDATA%\XCrossMenu\settings.json`.

Third-party installers require confirmation. The official xcross script comes from `https://raw.githubusercontent.com/arxdeus/xcross/main/install.ps1`; its locally computed SHA-256 is shown for inspection (this is not code-signing verification).

## Compatibility and validation

Designed for Windows PowerShell 5.1 or later. Preserves v1.1.0 functionality and the same settings file. **Not executed or tested on real Windows with an iPhone in this environment**; before relying on it for an important project, run `xcm help`, `xcm doctor`, `xcm device` and `xcm run` locally.

On failure, run the official project commands at https://github.com/arxdeus/xcross for full logs.

## License

MIT (or your preferred license). Update this section as needed.
