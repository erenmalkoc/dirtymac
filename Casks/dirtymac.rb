# This file belongs in your Homebrew tap repository, NOT in the
# dirtymac source repository. Move it to:
#
#     <OWNER>/homebrew-tap/Casks/dirtymac.rb
#
# After each release, update `version` and `sha256` (the workflow
# prints both). Or set up `livecheck` (already wired up below) and
# let `brew bump-cask-pr` automate it.

cask "dirtymac" do
  version "1.0.0"
  sha256 "REPLACE_ME_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/<OWNER>/dirtymac/releases/download/v#{version}/dirtymac-#{version}.dmg"
  name "dirtymac"
  desc "Menu bar utility that locks the keyboard for cleaning"
  homepage "https://github.com/<OWNER>/dirtymac"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "dirtymac.app"

  zap trash: [
    "~/Library/Preferences/tech.erenium.dirtymac.plist",
  ]
end
