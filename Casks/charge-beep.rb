cask "charge-beep" do
  version "0.1.4"
  sha256 "a190fe00a29ca6034227eaddc5cf44d9f12a2776618e366412bc734d3774a7b9"

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
