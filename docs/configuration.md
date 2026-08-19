# Configuration

`~/.config/aeroapp-launcher/config.toml`, or `$XDG_CONFIG_HOME/aeroapp-launcher/`.
Re-read whenever it changes, in place or replaced. Unknown keys are errors, the way
AeroSpace treats them; a file that fails to parse leaves the previous settings in
effect, and both are logged.

The file is a policy overlay: every installed app is searchable and launchable
without it. `aeroapp-launcher list` prints the bundle ids to key entries by.
Entries for apps that are not installed are ignored, hotkeys included.

```toml
hotkey = "alt-space"

[defaults]
new_window = "open"

[apps."com.tinyspeck.slackmacgap"]
follow = true
hotkey = "ctrl-alt-s"
aliases = ["chat"]

[apps."dev.zed.Zed"]
new_window = ["zed", "-n"]

[apps."com.google.Chrome"]
new_window = "applescript"

[apps."com.apple.Safari"]
new_window = { applescript = 'tell application "Safari" to make new document' }
```

[`examples/config.toml`](../examples/config.toml) is a longer, annotated version.

## Top-level keys

- `hotkey` — the chord that opens the launcher. Default `alt-space`.
- `aerospace` — path to the CLI. Default `/opt/homebrew/bin/aerospace`.
- `extra_app_dirs` — directories to search besides `/Applications`,
  `~/Applications` and the system folders. Each is searched one level deep too.

## Per-app keys

Under `[apps."<bundle-id>"]`, and — except `hotkey` — under `[defaults]`, which
applies to every app without an entry of its own. Resolution order: the app's
entry, then the built-in rules (Finder), then `[defaults]`, then compiled-in
defaults (`follow = false`, `new_window = "open"`).

- `follow` — `true` to move the existing window here instead of opening a new one.
- `new_window` — what to do when the app has windows only on other workspaces:
  - `"open"` — `open -n -g` (default);
  - `["zed", "-n"]` — run a command, bare names resolved in `PATH` and Homebrew;
  - `"applescript"` — `make new window` via AppleScript;
  - `{ applescript = '...' }` — a script of your own;
  - `"focus"` — focus the existing window, jumping to its workspace.
  See [behaviour.md](behaviour.md#new-window-triggers) for what each does.
- `hotkey` — a chord that summons this app directly, without the overlay.
- `aliases` — extra names the app can be found by.

## Hotkey syntax

AeroSpace's key names, joined by `-`, modifiers first in any order: `alt`, `ctrl`,
`cmd`, `shift`, then one key — `a`-`z`, `0`-`9`, `space`, `enter`, `esc`, `tab`,
`backspace`, `f1`-`f20`, `minus`, `equal`, `comma`, `period`, `slash`,
`backslash`, `semicolon`, `quote`, `backtick`, `leftSquareBracket`,
`rightSquareBracket`, arrows, `home`, `end`, `pageUp`, `pageDown`, `keypad0`-`9`.
`opt`/`option`, `control` and `command` are accepted as synonyms. A bare modifier
is rejected: it would need an event tap and Accessibility permission.
