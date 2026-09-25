#!/bin/bash
# Installs and removes system files. Use a disposable CI Mac.
set -Eeuo pipefail
trap 'echo "E2E failed at line $LINENO: $BASH_COMMAND" >&2' ERR
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || exit 1
[[ "${CI:-}" == true ]] || { echo 'Run only on a disposable CI Mac (CI=true).' >&2; exit 1; }
label='io.github.frequensy23.charge-beep'
app='/Applications/Charge Beep.app'
cli="$app/Contents/MacOS/charge-beep"
domain="gui/$(id -u)/$label"
scratch=$(mktemp -d)
cleanup() {
  if [[ -f "$app/Contents/Resources/uninstall.sh" ]]; then sudo /bin/bash "$app/Contents/Resources/uninstall.sh"; fi
  rm -rf "$scratch"
}
trap cleanup EXIT
pid() { /bin/launchctl print "$domain" 2>/dev/null | awk '/^[[:space:]]*pid = / {print $3; exit}'; }
wait_running() {
  for _ in {1..60}; do
    current=$(pid || true)
    if [[ -n "$current" && "$current" != "${1:-}" ]]; then kill -0 "$current" && return 0; fi
    sleep 1
  done
  /bin/launchctl print "$domain" || true
  echo 'LaunchAgent did not start/restart.' >&2; return 1
}
sudo /usr/sbin/installer -pkg dist/ChargeBeep.pkg -target /
wait_running
[[ "$(stat -f '%Su:%Sg:%Lp' "/Library/LaunchAgents/$label.plist")" == 'root:wheel:644' ]]
/usr/bin/lipo "$cli" -verify_arch arm64 x86_64
/usr/bin/lipo "$app/Contents/MacOS/ChargeBeepUI" -verify_arch arm64 x86_64
/usr/bin/codesign --verify --deep --strict "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print LSUIElement' "$app/Contents/Info.plist")" == true ]]
"$cli" status --json | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["agent_running"] and s["autostart_installed"]'
if "$cli" _test-agent; then echo 'Release exposes battery injection!' >&2; exit 1; fi
"$cli" test
before=$(pid)
kill -KILL "$before"
wait_running "$before"
after=$(pid)
debug=$(swift build --show-bin-path)
CHARGE_BEEP_HOME="$scratch/settings" "$debug/ChargeBeepUITestDriver" "$cli" "$scratch/ui-result" &
uipid=$!
for _ in {1..30}; do
  kill -0 "$uipid" 2>/dev/null || break
  sleep 1
done
if kill -0 "$uipid" 2>/dev/null; then kill "$uipid"; echo 'UI did not exit after closing.' >&2; exit 1; fi
wait "$uipid"
grep -qx 'PASS' "$scratch/ui-result"
cp "$scratch/ui-result.png" dist/UI.png
[[ "$(pid)" == "$after" ]]
"$cli" set threshold 4
sudo /usr/sbin/installer -pkg dist/ChargeBeep.pkg -target /
wait_running "$after"
"$cli" status --json | python3 -c 'import json,sys; assert json.load(sys.stdin)["threshold"] == 4'
stable=$(pid); sleep 3; [[ "$(pid)" == "$stable" ]]
ps -o pid=,rss=,%cpu=,comm= -p "$stable" | tee dist/idle-process.txt
sudo /bin/bash "$app/Contents/Resources/uninstall.sh"
[[ ! -e "/Library/LaunchAgents/$label.plist" && ! -e "$app" && ! -L /usr/local/bin/charge-beep ]]
if /bin/launchctl print "$domain" >/dev/null 2>&1; then echo 'Service survived uninstall.' >&2; exit 1; fi
echo 'PASS: install, crash recovery, UI editing/close, upgrade, uninstall.'
