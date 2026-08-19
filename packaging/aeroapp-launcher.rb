# Formula for axklim/homebrew-tap — copy to Formula/aeroapp-launcher.rb there.
#
# Cutting a release: tag vX.Y.Z here, then fill in the two lines below with
#   curl -L https://github.com/axklim/aeroapp-launcher/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
class AeroappLauncher < Formula
  desc "Spotlight-style launcher that opens apps on the current AeroSpace workspace"
  homepage "https://github.com/axklim/aeroapp-launcher"
  url "https://github.com/axklim/aeroapp-launcher/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # TODO: fill in when v0.1.0 is tagged
  license "MIT"
  head "https://github.com/axklim/aeroapp-launcher.git", branch: "main"

  depends_on :macos

  def install
    # Stamp the bundle with the formula's version rather than build.sh's default.
    ENV["AEROAPP_LAUNCHER_VERSION"] = version.to_s
    system "./build.sh", buildpath/"dist"
    prefix.install buildpath/"dist/AeroAppLauncher.app"
    # The same binary is the CLI (`aeroapp-launcher summon <app>`, `toggle`, `list`).
    bin.install_symlink prefix/"AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher" => "aeroapp-launcher"
  end

  service do
    run opt_prefix/"AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher"
    keep_alive true
    run_type :immediate
    log_path var/"log/aeroapp-launcher.log"
    error_log_path var/"log/aeroapp-launcher.log"
  end

  def caveats
    <<~EOS
      AeroAppLauncher drives AeroSpace through its CLI:
        brew install --cask nikitabobko/tap/aerospace

      Start it with:
        brew services start aeroapp-launcher

      Alt-Space opens the launcher. If Raycast is running, unbind Alt-Space
      inside Raycast first, or the two race for the chord.

      No Accessibility permission is needed. Apps configured with an
      `applescript` new-window trigger prompt once for Automation permission
      the first time they are summoned; the prompt returns after an upgrade,
      because the bundle is signed ad-hoc and its code hash changes.

      Configuration lives in ~/.config/aeroapp-launcher/config.toml and is
      re-read whenever it changes. `aeroapp-launcher list` prints the bundle
      ids to key it by. See
        https://github.com/axklim/aeroapp-launcher#configuration
    EOS
  end

  test do
    # Catches the release mistake nothing else can see: a tag cut without the
    # formula's version reaching the binary.
    assert_equal version.to_s, shell_output("#{bin}/aeroapp-launcher --version").strip
    assert_match "summon", shell_output("#{bin}/aeroapp-launcher help")
    assert_path_exists prefix/"AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher"
  end
end
