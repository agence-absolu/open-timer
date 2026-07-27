cask "opentimer" do
  version "0.2.0"
  sha256 "80a202b2fcbd5c0cb777b826231c4864b2ae82597f088d22cfcb2d320cfbbf08"

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
