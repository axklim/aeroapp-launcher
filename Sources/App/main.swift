import AppKit

// AeroAppLauncher is a Spotlight-style app launcher for AeroSpace. ⌥Space opens a
// search overlay; launching an app puts it on the workspace you are on instead of
// teleporting you to wherever it already lives. Window operations go through the
// `aerospace` CLI, hotkeys through Carbon — no Accessibility permission needed.
//
// With no arguments the binary is the daemon; with arguments it is a one-shot CLI.

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    exit(CLI.run(arguments))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let launcher = LauncherApp()
launcher.start()

app.run()
