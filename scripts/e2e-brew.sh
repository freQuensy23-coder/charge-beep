#!/bin/bash
# Exercise Homebrew's actual pkg/uninstall machinery against a local, checksummed test tap.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${CI:-}" == true && "$(uname -s)" == Darwin ]] || exit 1
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
name=charge-beep/e2e/charge-beep
tap="$(brew --repository)/Library/Taps/charge-beep/homebrew-e2e"
[[ ! -e "$tap" ]] || { echo 'Refusing to overwrite existing test tap.' >&2; exit 1; }
cleanup() {
  brew uninstall --cask "$name" >/dev/null 2>&1 || true
  brew untap charge-beep/e2e >/dev/null 2>&1 || true
}
trap cleanup EXIT
mkdir -p "$tap/Casks"
python3 scripts/cask.py "${1:?version required}" dist/ChargeBeep.pkg "$tap/Casks/charge-beep.rb"
python3 - "$tap/Casks/charge-beep.rb" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
url = pathlib.Path('dist/ChargeBeep.pkg').resolve().as_uri()
p.write_text(re.sub(r'^  url .*$', '  url "' + url + '"', p.read_text(), flags=re.M))
PY
git -C "$tap" init -q
git -C "$tap" add .
git -C "$tap" -c user.name=CI -c user.email=ci@example.invalid commit -qm 'Test cask'
brew install --cask "$name"
/usr/local/bin/charge-beep status --json | python3 -c 'import json,sys; assert json.load(sys.stdin)["agent_running"]'
/usr/local/bin/charge-beep set threshold 7
brew reinstall --cask "$name"
/usr/local/bin/charge-beep status --json | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["agent_running"] and s["threshold"] == 7'
brew uninstall --cask "$name"
[[ ! -e '/Applications/Charge Beep.app' && ! -e /Library/LaunchAgents/io.github.frequensy23.charge-beep.plist ]]
echo 'PASS: Homebrew install, reinstall, settings persistence, uninstall.'
