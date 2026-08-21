# AeroAppLauncher

A Spotlight-style app launcher for [AeroSpace](https://github.com/nikitabobko/AeroSpace).
⌥Space opens a search overlay; launching an app puts it on the workspace you are
on, instead of teleporting you to wherever it already lives. Sibling of
[aerotab](https://github.com/axklim/aerotab).

## Why

AeroSpace parks the windows of inactive workspaces off-screen. Launch Slack from
Raycast, the Dock or Spotlight while its window sits on another workspace and macOS
activates that window — and AeroSpace's only way to show it is to switch workspace.
AeroAppLauncher asks AeroSpace where the app's windows are *first*, then does the
thing that keeps you where you are.

## Behaviour

Summoning app X, where *here* is the focused workspace:

| X's windows   | default         | `follow`            |
|---------------|-----------------|---------------------|
| none          | launch here     | launch here         |
| one here      | focus it        | focus it            |
| one elsewhere | new window here | move it here, focus |

`follow` is for apps you want exactly one of — messengers, mostly. "New window here"
has no universal trigger, so it is configured per app: `open -n -g` by default, a
command such as `zed -n`, or AppleScript. How each case runs, and what happens when
something fails: [docs/behaviour.md](docs/behaviour.md).

| Key      | Action                        |
|----------|-------------------------------|
| `⌥Space` | Open or close the launcher    |
| `↑` `↓`  | Move the selection (⌃P ⌃N)    |
| `↩`      | Summon the selected app       |
| `⎋`      | Close                         |

## Install

```sh
brew install axklim/tap/aeroapp-launcher
brew services start aeroapp-launcher
```

No Accessibility permission is needed. If Raycast is running, unbind ⌥Space inside
it, or the two race for the chord. Developed against AeroSpace 0.21. From source:
`./build.sh ~/Applications`.

## Configuration

`~/.config/aeroapp-launcher/config.toml`, re-read whenever it changes. Every
installed app is searchable without it — the file is a policy overlay, keyed by
bundle id:

```toml
[apps."com.tinyspeck.slackmacgap"]
follow = true
hotkey = "ctrl-alt-s"

[apps."dev.zed.Zed"]
new_window = ["zed", "-n"]
```

Reference: [docs/configuration.md](docs/configuration.md). Annotated example:
[examples/config.toml](examples/config.toml).

## Command line

`aeroapp-launcher summon <app>`, `toggle` and `list` — for `exec-and-forget`
bindings in `aerospace.toml`: [docs/cli.md](docs/cli.md).

## Logs

`/opt/homebrew/var/log/aeroapp-launcher.log` under `brew services`.
