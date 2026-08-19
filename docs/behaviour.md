# Behaviour

## Summoning

Every summon starts from one query:

```sh
aerospace list-windows --monitor all --app-bundle-id <id> \
    --format '%{window-id}%{workspace}%{workspace-is-focused}' --json
```

and then follows the table in the README. Every window operation goes through the
`aerospace` CLI the way aerotab already does; nothing touches the Accessibility API.

- **No windows** — the app is opened and activated. Its first window lands on the
  focused workspace because that is where AeroSpace puts new windows. An app that
  is running with no windows (Slack closed to the menu bar) gets the reopen event
  and behaves the same.
- **A window here** — `aerospace focus --window-id`. Other windows elsewhere are
  left alone.
- **Windows only elsewhere, `follow`** — `aerospace move-node-to-workspace
  --window-id <id> <focused-workspace>` for *every* window of the app, then focus
  the first. All of them, because `follow` means the app lives on exactly one
  workspace at a time. It is deliberately not "show on all workspaces": AeroSpace
  has no sticky windows, so while you sit on B with Slack on A, Slack is not
  visible until you ask for it.
- **Windows only elsewhere, default** — run the app's new-window trigger, then wait
  for a window of the app to appear on the focused workspace (up to eight seconds)
  and focus it, since `open -g` by design and the other triggers by app whim leave
  the new window unfocused.

## New-window triggers

There is no universal way to ask an app for a new window, so the trigger is
per-app (`new_window` in the config). From most to least generic:

- `"open"` — the equivalent of `open -n -g`: a new instance, not brought to the
  front. Single-instance apps such as browsers and editors hand the request to
  their running copy, which opens a new window; apps that are not single-instance
  start a second process. This is the default for apps without an entry.
- `["zed", "-n"]` — run a command. Bare names are looked up in `PATH` plus the
  Homebrew prefixes, because launchd starts services with a bare `PATH`. The
  command is not waited for beyond starting it.
- `"applescript"` — `tell application id "<bundle-id>" to make new window`, or
  `{ applescript = '...' }` for apps that spell it differently (Safari: `make new
  document`). Needs Automation permission per target app; macOS prompts once.
- `"focus"` — give up and focus the existing window, jumping to its workspace the
  way Raycast would.

Finder has a built-in rule (`make new Finder window`), because `open -n` on Finder
starts a second Finder. An entry of your own for Finder overrides it.

## Search and ranking

Every `.app` under `/Applications`, `~/Applications` (one level deep as well, so
`Utilities`, vendor folders and Setapp count), the system application folders and
`extra_app_dirs` is offered, except background-only ones. Typing matches the app's
name by prefix, then word prefix, then initials (`vsc`), then substring, then
subsequence — and `aliases` from the config the same way. Ties go to the app you
have launched from here more often, then the shorter name. With nothing typed the
list is most-used first, then alphabetical.

## Failure modes

The launcher degrades toward what the Dock would have done:

- **AeroSpace not responding** — the app is activated plainly, which may switch
  workspace. Better than a dead key.
- **New-window trigger fails** (AppleScript error, command not found) — the
  existing window is focused instead, jump and all; the reason is logged.
- **No window appears after a trigger** — logged after eight seconds; nothing else.
- **Config file broken** — previous settings stay in effect; the error is logged
  with a line number.
- **Hotkey taken** — logged and skipped; the rest are still registered. Two apps
  registering the same chord do not error, they race, hence the Raycast note.
- **App in the config not installed** — its entry is ignored, hotkey included, so
  one file can serve every machine in a dotfiles repo.

Known limitation: AeroSpace [#2234](https://github.com/nikitabobko/AeroSpace/issues/2234)
(a reopened window reusing a closed window's id) can misfile windows and is not
workaroundable here.

## Permissions and rebuilds

None are needed for the launcher itself: ⌥Space and the per-app chords go through
`RegisterEventHotKey`, and windows are driven through the `aerospace` CLI. A
bare-modifier hotkey would need an event tap, and with it Accessibility — which is
why only chords are supported.

`applescript` triggers ask for Automation permission for their target app on first
use. `build.sh` signs the bundle ad-hoc, so an upgrade changes the code hash and
the prompt comes back once per app; there is no silent failure of the kind
aerotab's Accessibility grant suffers.
