# AeroAppLauncher

Spotlight-style launcher for AeroSpace: ⌥Space overlay plus per-app hotkeys; summoning
an app keeps you on the focused workspace (see the table in README.md). Sibling of
axklim/aerotab and built the same way. User docs live in `docs/`, not here.

## Layout

- `Sources/Core/` — Foundation-only, unit-tested. Must not import AppKit or Carbon.
  Logic that can be pure goes here, with a test in `Tests/`.
- `Sources/App/` — AppKit/Carbon wiring and UI. `Summoner` executes `SummonPlan`s
  through the `aerospace` CLI; `CLI.swift` is the one-shot command-line mode.
- `Tests/` — own runner (`Harness.swift`: `test`, `expect`, `expectEqual`,
  `expectThrows`); no XCTest — the Command Line Tools alone must suffice.
- `build.sh` → `.app` via one `swiftc` call; `packaging/aeroapp-launcher.rb` is the
  Homebrew formula for `axklim/homebrew-tap`; `examples/config.toml` is annotated.

## Commands

```sh
make test                                   # = ./test.sh, all unit tests
make build                                  # = ./build.sh dist (gitignored)
XDG_CONFIG_HOME=/tmp/x dist/AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher   # daemon
dist/AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher summon Safari            # CLI
```

`build.sh` generates `Version.swift` (`let appVersion`) into a temp dir; compiling
`Sources/App/*.swift` by hand needs that file too. To exercise summon logic without
AeroSpace, point `aerospace = "..."` in a scratch config at a script that prints
canned `list-windows` JSON (see `docs/development.md`).

## Rules

- Zero dependencies, no SwiftPM, no Package.swift — everything builds with bare
  `swiftc`.
- No Accessibility API and no event tap: chords via `RegisterEventHotKey`, every window
  operation via the `aerospace` CLI. Keep it that way; it is the point of the design.
- Config is strict (unknown keys are errors) and a broken file keeps the previous
  settings. The file is a policy overlay, never the list of launchable apps.
- Behaviour must degrade toward what the Dock would do, never to a silent no-op; log why.
- Comments explain why, not what. Keep README short; put detail in `docs/*.md`.
