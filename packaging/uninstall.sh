#!/bin/bash
set -euo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Run this uninstaller with sudo.' >&2; exit 1; }
label='io.github.frequensy23.charge-beep'
app='/Applications/Charge Beep.app'
while read -r name uid; do
  [[ "$uid" =~ ^[0-9]+$ && "$uid" -ge 500 ]] || continue
  /bin/launchctl bootout "gui/$uid/$label" 2>/dev/null || true
done < <(/usr/bin/dscl . -list /Users UniqueID)
/bin/rm -f "/Library/LaunchAgents/$label.plist"
if [[ -L /usr/local/bin/charge-beep && "$(readlink /usr/local/bin/charge-beep)" == "$app/Contents/MacOS/charge-beep" ]]; then
  /bin/rm -f /usr/local/bin/charge-beep
fi
/usr/sbin/pkgutil --forget "$label.pkg" >/dev/null 2>&1 || true
/bin/rm -rf "$app"
# Keep each user's settings; brew uninstall --zap removes the invoking user's settings.
