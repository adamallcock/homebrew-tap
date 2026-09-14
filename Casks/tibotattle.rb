cask "tibotattle" do
  arch arm: "arm64", intel: "x64"

  version "0.1.23"
  sha256 arm:   "6e0a9ad36a1dc8479ae7d145c545be4f1846d7a6713a5e8745aeecbf4e8a567f",
         intel: "14c926c49e436b50fef49ff1b70b731f87cd3ec8fb673e8f743a5870cc0ae470"

  url "https://github.com/adamallcock/tibotattle/releases/download/v#{version}/TiboTattle-#{version}-mac-#{arch}.dmg"
  name "TiboTattle"
  desc "Local-first monitor for Codex allowance usage"
  homepage "https://tibotattle.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
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
