cask "tibotattle" do
  arch arm: "arm64", intel: "x64"

  version "0.1.26"
  sha256 arm:   "7b5f66d91c9f1b8c1537505da860c67177d2b489ee6fb90d445d97c7e46cc9ec",
         intel: "3806a1ce2650350b69faff759287c08a5f146acfb9c26e3b3b04abb5cf8896c3"

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
