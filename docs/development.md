# Development

## Shape

Same as aerotab: no dependencies, no SwiftPM. `build.sh` compiles every file under
`Sources/` with one `swiftc` call into `AeroAppLauncher.app` and signs it ad-hoc;
the Homebrew formula (`packaging/aeroapp-launcher.rb`, destined for
`axklim/homebrew-tap`) runs that script and installs the bundle as a
`brew services` daemon. The Command Line Tools are enough to build and test.

- `Sources/Core/` — Foundation-only and unit-tested: the TOML subset parser, the
  config model, hotkey names, the matcher, the app index, the summon decision
  table, usage counts. Nothing here imports AppKit or Carbon.
- `Sources/App/` — AppKit and Carbon: the overlay panel, hotkey registration, the
  `aerospace` CLI wrapper, the summoner that executes plans, the config watcher,
  the CLI, and the daemon wiring.
- `Tests/` — a self-contained runner (`Harness.swift`); XCTest and swift-testing
  ship only with Xcode.

```sh
./test.sh                            # compiles Sources/Core + Tests, runs them
./build.sh dist                      # dist/AeroAppLauncher.app
BIN=dist/AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher
$BIN                                 # the daemon, logging to the terminal
$BIN summon Zed                      # the CLI
```

`build.sh` generates `Version.swift` (`let appVersion = "..."`) into a temp dir
from `AEROAPP_LAUNCHER_VERSION`, so compiling `Sources/App` by hand needs that
one-liner supplied too.

## Trying it without AeroSpace

Point `aerospace = "..."` in a scratch config at a script that logs its arguments
and prints canned JSON for `list-windows`, and run the daemon or `summon` with
`XDG_CONFIG_HOME` set to that scratch directory. Every branch of the decision
table can be driven that way; only the real `move-node-to-workspace`/`focus` round
trip and a real ⌥Space keypress need a live session.

## Releasing

1. Tag `vX.Y.Z` and push the tag.
2. `curl -L https://github.com/axklim/aeroapp-launcher/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`
3. Put the version and sha256 into `packaging/aeroapp-launcher.rb`, copy it to
   `Formula/aeroapp-launcher.rb` in `axklim/homebrew-tap` (and the tap's README
   table). `brew test aeroapp-launcher` checks the binary reports that version.
