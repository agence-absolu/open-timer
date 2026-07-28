cask "opentimer" do
  version "0.6.1"
  sha256 "a75407eaa455b407fdbbc485460f2600821f0eb22f46fd724f7362f52fa70e4a"

  url "https://github.com/agence-absolu/open-timer/releases/download/v#{version}/OpenTimer-#{version}.zip"
  name "OpenTimer"
  desc "Time tracker pour OpenProject dans la barre de menu"
  homepage "https://github.com/agence-absolu/open-timer"

  app "OpenTimer.app"

  # App non signée / non notarisée : le flag --no-quarantine a été retiré de
  # Homebrew (v4.7). On retire donc l'attribut de quarantaine après l'install,
  # sinon macOS bloquerait l'app (« endommagée »).
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/OpenTimer.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.lmwr.opentimer.plist",
  ]
end
