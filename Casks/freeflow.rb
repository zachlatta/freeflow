cask "freeflow" do
  version "1.2.0"
  sha256 "f55e384d6da375e5c85d6cff40de5655dff8c1e8e14dd903a6c09703c7556da6"

  url "https://github.com/zachlatta/freeflow/releases/download/v#{version}/FreeFlow.dmg"
  name "FreeFlow"
  desc "Dictation app with AI transcription and context-aware cleanup"
  homepage "https://github.com/zachlatta/freeflow"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "FreeFlow.app"

  uninstall quit:       "com.zachlatta.freeflow",
            login_item: "FreeFlow"

  zap trash: [
    "~/Library/Application Support/FreeFlow",
    "~/Library/Caches/com.zachlatta.freeflow",
    "~/Library/HTTPStorages/com.zachlatta.freeflow",
    "~/Library/Preferences/com.zachlatta.freeflow.plist",
  ]
end
