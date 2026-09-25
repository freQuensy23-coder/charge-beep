#!/bin/bash
# Universal native binaries, .app and system-wide .pkg; no external build dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:-0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected X.Y.Z version' >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo 'Build packages on macOS.' >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=13.0
version_file=Sources/ChargeBeepCore/Version.swift
original=$(cat "$version_file")
trap 'printf "%s\n" "$original" > "$version_file"' EXIT
python3 - "$version" <<'PY'
import pathlib, re, sys
p = pathlib.Path('Sources/ChargeBeepCore/Version.swift')
p.write_text(re.sub(r'let version = "[^"]+"', f'let version = "{sys.argv[1]}"', p.read_text()))
PY
rm -rf dist
app='dist/root/Applications/Charge Beep.app'
mkdir -p "$app/Contents/"{MacOS,Resources} dist/root/Library/LaunchAgents dist/pkg-scripts
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --scratch-path ".build/$arch"
done
for binary in charge-beep ChargeBeepUI; do
  arm=$(swift build -c release --arch arm64 --scratch-path .build/arm64 --show-bin-path)
  intel=$(swift build -c release --arch x86_64 --scratch-path .build/x86_64 --show-bin-path)
  /usr/bin/lipo -create "$arm/$binary" "$intel/$binary" -output "$app/Contents/MacOS/$binary"
done
cp packaging/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $version" "$app/Contents/Info.plist"
cp packaging/uninstall.sh "$app/Contents/Resources/"
cp packaging/io.github.frequensy23.charge-beep.plist dist/root/Library/LaunchAgents/
cp packaging/{preinstall,postinstall} dist/pkg-scripts/
chmod 755 dist/pkg-scripts/* "$app/Contents/Resources/uninstall.sh" "$app/Contents/MacOS/"*
python3 - "$app" <<'PY'
import math, pathlib, plistlib, struct, sys, wave
app = pathlib.Path(sys.argv[1])
# Short 880 Hz tone with an amplitude envelope, followed by a second pulse; no bundled third-party sound.
rate = 44100
samples = []
for i in range(int(rate * 0.65)):
    t = i / rate
    local = t if t < .25 else t - .4
    active = 0 <= local < .25
    envelope = min(1, max(0, local / .01), max(0, (.25-local)/.02)) if active else 0
    samples.append(int(15000 * envelope * math.sin(2*math.pi*880*t)))
with wave.open(str(app / 'Contents/Resources/beep.wav'), 'wb') as out:
    out.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    out.writeframes(struct.pack('<' + 'h'*len(samples), *samples))
with open('dist/components.plist', 'wb') as out:
    plistlib.dump([{'RootRelativeBundlePath': 'Applications/Charge Beep.app',
                   'BundleIsRelocatable': False, 'BundleIsVersionChecked': True,
                   'BundleHasStrictIdentifier': True, 'BundleOverwriteAction': 'upgrade'}], out)
PY
# Ad-hoc signing supports Apple Silicon. Developer ID/notarization is intentionally not claimed.
for binary in charge-beep ChargeBeepUI; do
  /usr/bin/codesign --force --sign - "$app/Contents/MacOS/$binary"
done
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/pkgbuild --root dist/root --scripts dist/pkg-scripts --ownership recommended \
  --component-plist dist/components.plist --identifier io.github.frequensy23.charge-beep.pkg \
  --version "$version" --install-location / dist/ChargeBeep.pkg
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" dist/ChargeBeep.app.zip
(cd dist && shasum -a 256 ChargeBeep.pkg ChargeBeep.app.zip > SHA256SUMS)
echo "Built Charge Beep $version (arm64 + x86_64)."
