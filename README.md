# Charge Beep

Low-battery alarm for macOS 13+, Intel and Apple Silicon.

## Install

```sh
brew tap freQuensy23-coder/charge-beep https://github.com/freQuensy23-coder/charge-beep.git
brew install --cask freQuensy23-coder/charge-beep/charge-beep
```

Installation requests an administrator password. It installs a LaunchAgent in
`/Library/LaunchAgents`, starts it in existing GUI sessions, and enables startup
at login for every user. No menu-bar or Dock icon. Closing the settings window
exits the UI without stopping the agent.

## Use

```sh
charge-beep status [--json]
charge-beep set threshold 3
charge-beep set enabled false
charge-beep set enabled true
charge-beep test
charge-beep ui
charge-beep update
```

The window contains a threshold field, an enable switch, and a sound-test button.
The default threshold is 1%; valid values are 1 through 100. Settings are per user
at `~/Library/Application Support/ChargeBeep/settings.json`. CLI and UI changes
apply immediately. `update` uses Homebrew and requires the Homebrew-owning user.

While on battery at or below the threshold, the active console user's agent plays
a two-pulse tone every 10 seconds. Connecting power, exceeding the threshold,
switching away from the user, or disabling the alarm stops it. Missing or invalid
battery readings do not trigger an alarm.

The alarm respects system volume, mute and the selected audio output. It cannot
sound during sleep, before login, or after shutdown. At 1%, the battery may shut
down before a warning; use a higher threshold for more margin.

The package is ad-hoc signed, not Apple-notarized. macOS may require approval or
block installation. The installer does not bypass Gatekeeper or re-enable a
background item that the user disabled. Check `charge-beep status` after install.

## Implementation

Swift with Apple frameworks; no third-party dependencies. The agent uses IOKit
battery events, console-session notifications, and file-system notifications.
There is no periodic polling or timer while idle. Audio is allocated only during
an alarm. AppKit runs in the separate UI process. `launchd` restarts a crashed
agent. Settings writes are atomic and serialized across processes.

## Build and test

On macOS with Xcode command-line tools and Python 3:

```sh
swift test
python3 scripts/e2e.py "$(swift build --show-bin-path)/charge-beep"
bash scripts/build.sh 0.1.0
sudo installer -pkg dist/ChargeBeep.pkg -target /
```

`dist/` contains the universal app ZIP, installer and checksums. The ZIP alone
does not install the LaunchAgent.

Unit tests cover threshold boundaries, timer behavior, cancellation, invalid
battery readings, and settings persistence/rollback. CLI tests run separate
processes and verify exit codes and serialized writes. The UI test driver lives
under `Tests/`, uses the production window and application delegate, and checks
external settings updates, active editing, controls and saving on close. No test
commands or self-test code are shipped in the application.

Every push and pull request runs tests on Intel and Apple Silicon. CI also
installs the package, verifies crash recovery and UI/service independence,
reinstalls it, and tests Homebrew installation and removal. A main-branch push
publishes a release and checksummed cask only after both jobs pass. UI screenshots
and process measurements are attached to the CI run.

The installer tests modify the system; run them only on a disposable Mac:

```sh
CI=true bash scripts/e2e-macos.sh
CI=true bash scripts/e2e-brew.sh 0.1.0
```

CI does not physically discharge a battery, verify audible output, or perform a
real multi-user desktop switch. The UI driver uses AppKit controls in-process,
not an external Accessibility robot. RAM and CPU depend on the device; CI
measurements are not performance guarantees.

## Uninstall

```sh
brew uninstall --cask freQuensy23-coder/charge-beep/charge-beep
```

For a direct package installation:

```sh
sudo /bin/bash '/Applications/Charge Beep.app/Contents/Resources/uninstall.sh'
```

Uninstallation stops logged-in users' agents and removes the application,
LaunchAgent, CLI link and package receipt. User settings are retained. Homebrew's
`--zap` option also removes the invoking user's settings.

MIT license.
