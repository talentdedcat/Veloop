# frozen_string_literal: true

cask "veloop" do
  version "0.1.0"
  sha256 "056c226734157d03f19bbac929aed92f908cbbf1b49b48b1ade88427a5f635db"

  url "https://github.com/talentdedcat/Veloop/releases/download/v#{version}/Veloop-#{version}-universal.dmg"
  name "Veloop"
  desc "Local clipboard history beside the active text caret"
  homepage "https://github.com/talentdedcat/Veloop"

  depends_on macos: :ventura

  app "Veloop.app"
  binary "#{appdir}/Veloop.app/Contents/Resources/veloopctl"

  uninstall launchctl: "com.veloop.service",
            quit:      "com.veloop.app",
            signal:    [
              ["TERM", "com.veloop.service"],
              ["TERM", "com.talentdedcat.veloop.palette"],
            ]

  zap trash: [
    "~/Library/Application Support/Veloop",
    "~/Library/Caches/com.veloop.app",
    "~/Library/Caches/com.veloop.diagnostics.carethost",
    "~/Library/Caches/com.veloop.service",
    "~/Library/Input Methods/VeloopPalette.app",
    "~/Library/LaunchAgents/com.veloop.service.plist",
    "~/Library/Preferences/com.veloop.app.plist",
    "~/Library/Preferences/com.veloop.service.plist",
    "~/Library/Preferences/com.veloop.shared.plist",
    "~/Library/Saved Application State/com.veloop.app.savedState",
    "~/Library/WebKit/com.veloop.diagnostics.carethost",
  ]

  caveats <<~EOS
    Veloop #{version} is ad-hoc signed and not notarized.
    Before the first launch, run:
      xattr -dr com.apple.quarantine /Applications/Veloop.app
      open /Applications/Veloop.app
  EOS
end
