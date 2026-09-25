#!/usr/bin/env python3
"""Generate a pinned, checksummed Homebrew cask AFTER the matching release exists."""
import hashlib
import pathlib
import re
import sys

version, package, output = sys.argv[1:]
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected X.Y.Z version')
digest = hashlib.sha256(pathlib.Path(package).read_bytes()).hexdigest()
text = '''cask "charge-beep" do
  version "VERSION"
  sha256 "DIGEST"

  url "https://github.com/freQuensy23-coder/charge-beep/releases/download/v#{version}/ChargeBeep.pkg"
  name "Charge Beep"
  desc "Native, background-only low-battery alarm"
  homepage "https://github.com/freQuensy23-coder/charge-beep"

  depends_on macos: ">= :ventura"

  pkg "ChargeBeep.pkg"

  uninstall script: {
    executable: "/Applications/Charge Beep.app/Contents/Resources/uninstall.sh",
    sudo: true,
  }

  zap trash: "~/Library/Application Support/ChargeBeep"

  caveats <<~EOS
    Installs a LaunchAgent for every user; macOS requests an administrator password.
    CLI: /usr/local/bin/charge-beep. Settings: charge-beep ui.
    Ad-hoc signed, not Apple-notarized. Respects system mute and background-item settings.
  EOS
end
'''.replace('VERSION', version).replace('DIGEST', digest)
destination = pathlib.Path(output)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(text)
