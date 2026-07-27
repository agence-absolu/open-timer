cask "opentimer" do
  version "0.1.0"
  sha256 "e53956c7ba485c9c293f96895f3daedbda8b678aa6f91199741abbc52a56387d"

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
