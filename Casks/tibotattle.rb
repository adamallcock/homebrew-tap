cask "tibotattle" do
  arch arm: "arm64", intel: "x64"

  version "0.1.29"
  sha256 arm:   "4a4696bd297e31ad8a7ecce5e08b0fb6c639518c7199d6d69c05de8048e5af52",
         intel: "462561a50ce102cf8d808fe540c7a0950261acf5b91e47c3b18f40696ceb1991"

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
