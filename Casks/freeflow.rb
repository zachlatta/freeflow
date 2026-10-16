cask "freeflow" do
  version "1.3.1"
  sha256 "17392f0dbc64921d67208e81e8e4b81963284ac673be7a812f7323255b8f5fe6"

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
