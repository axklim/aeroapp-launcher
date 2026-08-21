# Command line

The daemon binary doubles as a CLI; Homebrew links it as `aeroapp-launcher`. For a
source build: `ln -s ~/Applications/AeroAppLauncher.app/Contents/MacOS/AeroAppLauncher
~/bin/aeroapp-launcher`.

| Command                         | Does                                           |
|---------------------------------|------------------------------------------------|
| `aeroapp-launcher summon <app>` | Summon by bundle id or exact name, like ⌥Space  |
| `aeroapp-launcher toggle`       | Open or close the running launcher's overlay   |
| `aeroapp-launcher list`         | Installed apps with their bundle ids           |
| `aeroapp-launcher version`      | Print the version                              |

`summon` is one-shot: it reads the config and runs the same summon logic on its
own, so it works whether or not the daemon is running, and blocks until the app is
focused (or the new-window wait gives up). The name match is exact, case- and
diacritic-insensitive, not fuzzy — a command bound to a key has to be predictable;
a miss prints suggestions and exits 1. Summons from the CLI do not count towards
the overlay's usage ranking.

`toggle` needs the daemon; it is delivered as a distributed notification.

Both exist so every key can live in `aerospace.toml` if you prefer that to the
launcher's own hotkeys:

```toml
[mode.main.binding]
alt-space  = 'exec-and-forget /opt/homebrew/bin/aeroapp-launcher toggle'
ctrl-alt-s = 'exec-and-forget /opt/homebrew/bin/aeroapp-launcher summon com.tinyspeck.slackmacgap'
```
