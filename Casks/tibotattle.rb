cask "tibotattle" do
  version "0.1.12"
  sha256 "0537b683cbb27a5ce93fffce86bb9e658900f750fd42a01eb0bf450a9623b0a6"

  url "https://github.com/adamallcock/tibotattle/releases/download/v#{version}/TiboTattle-#{version}-macOS-arm64.dmg",
      verified: "github.com/adamallcock/tibotattle/"
  name "TiboTattle"
  desc "Local-first monitor for Codex allowance usage"
  homepage "https://tibotattle.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "TiboTattle.app"

  uninstall quit: "com.usagemonitor.local"

  zap trash: [
    "~/Library/Application Support/Usage Monitor",
    "~/Library/Caches/com.usagemonitor.local",
    "~/Library/HTTPStorages/com.usagemonitor.local",
    "~/Library/HTTPStorages/com.usagemonitor.local.binarycookies",
    "~/Library/Preferences/com.usagemonitor.local.plist",
    "~/Library/Saved Application State/com.usagemonitor.local.savedState",
    "~/Library/WebKit/com.usagemonitor.local",
  ]
end
