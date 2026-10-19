cask "cleanr" do
  version "0.1.0"
  # Set to the published DMG's hash at release time. build-dmg.sh prints
  # "SHA256:" at the end; the release workflow fills this in automatically.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  # Homebrew dropped the optional URL hostname check (Homebrew/brew#23280);
  # keeping it only produced a brew-update warning (issue #147). url and
  # homepage already share github.com/coldrazer/CleanR.
  url "https://github.com/coldrazer/CleanR/releases/download/v#{version}/CleanR-#{version}.dmg"
  name "CleanR"
  desc "Open-source Mac cleaner, optimizer, and malware scanner"
  homepage "https://github.com/coldrazer/CleanR"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Symbol form means "this release or newer"; the old comparison-string
  # form (">= :sonoma") is deprecated by Homebrew and warns on every install.
  depends_on macos: :sonoma

  app "CleanR.app"

  # Quit a running CleanR before upgrading/uninstalling so the old copy is
  # cleanly replaced instead of lingering (macOS can't swap a running app).
  uninstall quit: "com.cleanr.app"

  zap trash: [
    "~/Library/Application Support/CleanR",
    "~/Library/Caches/com.cleanr.app",
    "~/Library/HTTPStorages/com.cleanr.app",
    "~/Library/Logs/CleanR",
    "~/Library/Preferences/com.cleanr.app.plist",
    "~/Library/Preferences/com.cleanr.shared.plist",
    "~/Library/Saved Application State/com.cleanr.app.savedState",
  ]

  caveats <<~EOS
    Some features (Mail, Safari, Privacy scans) require Full Disk Access:
      System Settings → Privacy & Security → Full Disk Access
  EOS
end
