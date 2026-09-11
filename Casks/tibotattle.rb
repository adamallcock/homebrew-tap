cask "tibotattle" do
  arch arm: "arm64", intel: "x64"

  version "0.1.21"
  sha256 arm:   "0afab510adf250775e1401307b547cee1a7955e1d7ec8dce9852cc4ca143c7e2",
         intel: "50960e1aac65eb2673a7634a18bf123b604680f2a526822a0ccccc1d3b0b52e4"

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
