# Charge Beep

A native macOS battery alarm. No menu-bar item, Dock icon, web view, account, telemetry, or third-party runtime. The settings window and background monitor are separate processes.

## Install

macOS 13 or later, Apple Silicon or Intel. After the first successful main-branch build publishes the release and cask:

```sh
brew tap freQuensy23-coder/charge-beep https://github.com/freQuensy23-coder/charge-beep.git
brew install --cask freQuensy23-coder/charge-beep/charge-beep
```

The package requests an administrator password once per installation/upgrade. It installs `/Applications/Charge Beep.app`, `/usr/local/bin/charge-beep`, and a root-owned `/Library/LaunchAgents/io.github.frequensy23.charge-beep.plist`. No `brew services start` or manual login-item setup is needed. Existing GUI sessions are started immediately; future users start the agent at login. The CLI path works independently of which user owns Homebrew.

The package is ad-hoc signed, **not Apple Developer ID signed/notarized**. It does not disable Gatekeeper or remove quarantine. macOS security policy can require approval or block unsigned distribution; do not interpret a failed installation as a running service. A source build on your Mac is available below. If macOS disables a background item, enable it in System Settings, General, Login Items. The installer does not override an explicit disable decision.

## Use

```sh
charge-beep status                 # version, battery, settings, launchd PID/status
charge-beep status --json
charge-beep set threshold 3        # integer 1...100; default 1
charge-beep set enabled false
charge-beep set enabled true
charge-beep test                   # hear the actual alarm
charge-beep ui                     # minimal native settings window
charge-beep update                 # brew update, then brew upgrade --cask
```

The UI can also be opened from Applications or Spotlight. Closing it exits only the UI; the launchd-managed monitor continues. Settings are **per user**, stored atomically in `~/Library/Application Support/ChargeBeep/settings.json`. UI and CLI changes apply immediately to that user's running agent. `status` reports missing/stopped launchd jobs rather than assuming installation means the agent is running. Updating requires the Homebrew-owning user and administrator approval for the package.

## Alarm behavior

At or below the threshold, while running on battery and in the active console user's session, a two-pulse tone sounds immediately and repeats every 10 seconds. Connecting power stops it even when macOS reports “not charging.” It stops above the threshold or when disabled. Unknown/missing/invalid batteries are not treated as 0%; UPS and peripheral batteries are ignored. With multiple logged-in users, only the active console user's agent can sound, using that user's settings.

It respects the system output device, volume and mute; it does not force volume or bypass headphones. It cannot play while the Mac is asleep, powered off, or before anyone logs in. A 1% threshold leaves little margin before hardware shutdown: choose a higher threshold for more warning. It is a convenience alarm, not a guarantee against battery shutdown.

## Architecture

Swift and Apple system frameworks only; zero package dependencies. The resident CLI/agent uses Foundation, IOKit, SystemConfiguration and AudioToolbox, **not AppKit**. AppKit loads only for the separate settings window. IOKit events update battery state; console-session events handle fast user switching; a directory file-system event source detects atomic settings changes. There is no periodic battery polling or idle alarm timer. A timer exists only while an alarm is active. `launchd` restarts a crashed agent. An advisory lock prevents duplicates; another lock serializes concurrent UI/CLI settings updates. Invalid settings preserve the running monitor's last valid settings and are reported rather than overwritten. No numerical CPU/RAM claims are made without device measurements.

“All users” means a user-context LaunchAgent installed globally, **not** a root daemon attempting to use somebody else's audio session. No administrator privileges are used during monitoring or settings changes.

## Build and test

Requires Xcode command-line tools and Python 3 on a development Mac. Nothing besides macOS is required by the installed application.

```sh
swift test
python3 scripts/e2e.py "$(swift build --show-bin-path)/charge-beep"
bash scripts/build.sh 0.1.0
sudo installer -pkg dist/ChargeBeep.pkg -target /
```

`dist/` contains universal `.app.zip`, `.pkg`, and SHA-256 checksums. The app ZIP alone does not install the LaunchAgent; use the package for system-wide startup. The pure policy, settings and CLI tests also run on Linux with Swift installed.

GitHub Actions runs on **every push and pull request**, testing on both Apple Silicon and Intel. It runs unit tests and real CLI/debug-agent subprocess tests, builds universal release binaries, installs the package on a disposable Mac, verifies root-owned autostart and service status, kills the daemon to check recovery, operates actual AppKit controls with a debug-only in-process driver and closes its window, verifies the agent survives, reinstalls the package to check restart/settings retention, and tests uninstallation. It also rejects battery-injection commands in production binaries. Battery transitions are simulated through the same production policy: CI cannot physically discharge a laptop, verify audible output, or reproduce a real multi-user desktop switch. The AppKit driver is not an external Accessibility/XCUITest robot.

Only after **both** macOS jobs pass does a main push publish `v0.1.<workflow-run-number>` and update `Casks/charge-beep.rb` with its exact package checksum. Branch/PR builds are artifacts only. The generated cask commit uses `GITHUB_TOKEN`, which does not recursively trigger another workflow. Releasing needs the repository's Actions policy to permit the declared `contents: write` permission. No personal token or external publishing service is needed. Release binaries are never overwritten on reruns.

To run the installer/lifecycle test manually, use **only a disposable Mac**; it installs and removes the application:

```sh
CI=true bash scripts/e2e-macos.sh
```

## Uninstall

```sh
brew uninstall --cask freQuensy23-coder/charge-beep/charge-beep
# For a direct .pkg installation:
sudo /bin/bash '/Applications/Charge Beep.app/Contents/Resources/uninstall.sh'
```

Uninstall unloads every currently logged-in user's agent and removes global startup, the app, CLI link and package receipt. User settings are retained; `brew uninstall --zap --cask freQuensy23-coder/charge-beep/charge-beep` additionally removes the invoking user's settings.

## References

[Apple: launchd and global LaunchAgents](https://support.apple.com/guide/terminal/script-management-with-launchd-apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac), [Homebrew cask packages](https://docs.brew.sh/Cask-Cookbook), [custom tap URLs](https://docs.brew.sh/Taps).

MIT license.
