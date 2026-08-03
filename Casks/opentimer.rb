cask "opentimer" do
  version "0.7.0"
  sha256 "31f80c36cdda7a40cd5aab94c915fa851985232406d99a3cecb7f5e25617455b"

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
