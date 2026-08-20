import Foundation

func runConfigTests() {
    test("Config: empty text yields defaults") {
        let config = try Config.parse(toml: "")
        expectEqual(config.hotkey, Config.defaultHotkey)
        expectEqual(config.aerospacePath, Config.defaultAerospacePath)
        expectEqual(config.apps, [:])
        let policy = config.policy(for: "com.example.anything")
        expectEqual(policy, EffectivePolicy(follow: false, newWindow: .open, hotkey: nil, aliases: []))
    }

    test("Config: full example") {
        let config = try Config.parse(toml: """
        hotkey = "ctrl-space"
        aerospace = "/usr/local/bin/aerospace"
        extra_app_dirs = ["~/Applications/Setapp"]

        [defaults]
        new_window = "focus"

        [apps."com.tinyspeck.slackmacgap"]
        follow = true
        hotkey = "alt-shift-s"
        aliases = ["chat"]

        [apps."dev.zed.Zed"]
        new_window = ["zed", "-n"]

        [apps."com.google.Chrome"]
        new_window = "applescript"

        [apps."com.apple.Terminal"]
        new_window = { applescript = 'tell application "Terminal" to do script ""' }

        [apps."com.example.plain"]
        new_window = "open"
        """)
        expectEqual(config.hotkey, try Hotkey.parse("ctrl-space"))
        expectEqual(config.aerospacePath, "/usr/local/bin/aerospace")
        expectEqual(config.extraAppDirs, ["~/Applications/Setapp"])

        let slack = config.policy(for: "com.tinyspeck.slackmacgap")
        expectEqual(slack.follow, true)
        expectEqual(slack.newWindow, .focus, "defaults fill what the entry leaves out")
        expectEqual(slack.hotkey, try Hotkey.parse("alt-shift-s"))
        expectEqual(slack.aliases, ["chat"])

        expectEqual(config.policy(for: "dev.zed.Zed").newWindow, .command(["zed", "-n"]))
        expectEqual(config.policy(for: "com.google.Chrome").newWindow, .appleScript(nil))
        expectEqual(config.policy(for: "com.apple.Terminal").newWindow, .appleScript("tell application \"Terminal\" to do script \"\""))
        expectEqual(config.policy(for: "com.example.plain").newWindow, .open)
        expectEqual(config.policy(for: "com.example.unlisted").newWindow, .focus, "[defaults] applies to unlisted apps")
        expectEqual(config.policy(for: "com.example.unlisted").follow, false)
    }

    test("Config: built-in Finder rule sits between the app entry and [defaults]") {
        let plain = try Config.parse(toml: "")
        expectEqual(plain.policy(for: "com.apple.finder").newWindow, .appleScript("tell application \"Finder\" to make new Finder window"))

        let withDefaults = try Config.parse(toml: "[defaults]\nnew_window = \"focus\"\n")
        expectEqual(withDefaults.policy(for: "com.apple.finder").newWindow, .appleScript("tell application \"Finder\" to make new Finder window"),
                    "an app-specific built-in beats a blanket default")
        expectEqual(withDefaults.policy(for: "com.apple.finder").follow, false)

        let overridden = try Config.parse(toml: "[apps.\"com.apple.finder\"]\nnew_window = \"open\"\n")
        expectEqual(overridden.policy(for: "com.apple.finder").newWindow, .open, "the user's own entry wins")

        expectEqual(plain.policy(for: "dev.zed.Zed").newWindow, .command(["zed", "-n"]),
                    "Zed is single-instance; open -n does nothing")
    }

    test("Config: errors name the offending key") {
        func message(_ text: String) -> String {
            do { _ = try Config.parse(toml: text); return "" } catch let e as ConfigError { return e.message } catch { return "\(error)" }
        }
        expect(message("folow = true\n").contains("unknown key 'folow'"), message("folow = true\n"))
        expect(message("[apps.\"com.x\"]\nfolow = true\n").contains("apps.\"com.x\": unknown key 'folow'"), message("[apps.\"com.x\"]\nfolow = true\n"))
        expect(message("[apps.\"com.x\"]\nfollow = \"yes\"\n").contains("apps.\"com.x\".follow: expected true or false"))
        expect(message("[apps.\"com.x\"]\nnew_window = \"teleport\"\n").contains("unknown trigger \"teleport\""))
        expect(message("[apps.\"com.x\"]\nnew_window = []\n").contains("command array is empty"))
        expect(message("[apps.\"com.x\"]\nnew_window = { script = \"x\" }\n").contains("unknown key 'script'"))
        expect(message("[apps.\"com.x\"]\nnew_window = 3\n").contains("expected a string, an argv array or an inline table"))
        expect(message("[apps.\"com.x\"]\nhotkey = \"alt\"\n").contains("apps.\"com.x\".hotkey: 'alt': a hotkey needs a key"))
        expect(message("hotkey = 12\n").contains("hotkey: expected a string"))
        expect(message("[defaults]\nhotkey = \"alt-x\"\n").contains("defaults: unknown key 'hotkey'"), "a default hotkey makes no sense")
        expect(message("apps = 1\n").contains("apps: expected a table"))
        expect(message("a = \n").hasPrefix("line 1:"), message("a = \n"))
    }

    test("Paths: XDG variables override the defaults") {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let plain = Paths(environment: [:], home: home)
        expectEqual(plain.configFile.path, "/Users/someone/.config/aeroapp-launcher/config.toml")
        expectEqual(plain.usageFile.path, "/Users/someone/.local/state/aeroapp-launcher/usage.json")

        let xdg = Paths(environment: ["XDG_CONFIG_HOME": "/tmp/cfg", "XDG_STATE_HOME": "/tmp/state"], home: home)
        expectEqual(xdg.configFile.path, "/tmp/cfg/aeroapp-launcher/config.toml")
        expectEqual(xdg.usageFile.path, "/tmp/state/aeroapp-launcher/usage.json")

        let relative = Paths(environment: ["XDG_CONFIG_HOME": "relative/path"], home: home)
        expectEqual(relative.configFile.path, "/Users/someone/.config/aeroapp-launcher/config.toml", "relative XDG paths are ignored per spec")
    }
}
