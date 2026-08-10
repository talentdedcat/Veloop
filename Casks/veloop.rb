# frozen_string_literal: true

cask "veloop" do
  version "0.2.0"
  sha256 "d372266c8d03c808ae489d27db7b6d716a154b26573fb5c9c81982b546c14927"

  url "https://github.com/talentdedcat/Veloop/releases/download/v#{version}/Veloop-#{version}-universal.dmg"
  name "Veloop"
  desc "Local clipboard history beside the active text caret"
  homepage "https://github.com/talentdedcat/Veloop"

  depends_on macos: :ventura

  app "Veloop.app"
  binary "#{appdir}/Veloop.app/Contents/Resources/veloopctl"

  uninstall launchctl: [
              "com.veloop.service",
              "com.veloop.uninstall-watcher",
            ],
            quit:      "com.veloop.app",
            signal:    [
              ["TERM", "com.veloop.service"],
              ["TERM", "com.veloop.uninstall-watcher"],
              ["TERM", "com.talentdedcat.veloop.palette"],
            ],
            script:    {
              executable: "#{appdir}/Veloop.app/Contents/Resources/veloopctl",
              args:       ["uninstall", "--purge"],
              must_succeed: true,
            },
            delete:    [
              "/Applications/Veloop Agent.app",
              "~/Applications/Veloop Agent.app",
              "~/Library/Application Support/Veloop",
              "~/Library/Caches/com.veloop.app",
              "~/Library/Caches/com.veloop.diagnostics.carethost",
              "~/Library/Caches/com.veloop.service",
              "~/Library/Input Methods/VeloopPalette.app",
              "~/Library/LaunchAgents/com.veloop.service.plist",
              "~/Library/LaunchAgents/com.veloop.uninstall-watcher.plist",
              "~/Library/Preferences/com.veloop.app.plist",
              "~/Library/Preferences/com.veloop.service.plist",
              "~/Library/Preferences/com.veloop.shared.plist",
              "~/Library/Saved Application State/com.veloop.app.savedState",
              "~/Library/WebKit/com.veloop.diagnostics.carethost",
            ]

  zap trash: [
    "/Applications/Veloop Agent.app",
    "~/Applications/Veloop Agent.app",
    "~/Library/Application Support/Veloop",
    "~/Library/Caches/com.veloop.app",
    "~/Library/Caches/com.veloop.diagnostics.carethost",
    "~/Library/Caches/com.veloop.service",
    "~/Library/Input Methods/VeloopPalette.app",
    "~/Library/LaunchAgents/com.veloop.service.plist",
    "~/Library/LaunchAgents/com.veloop.uninstall-watcher.plist",
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
