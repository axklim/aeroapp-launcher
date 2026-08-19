import Foundation

/// How to get a *new* window of an app that already has windows on other
/// workspaces. There is no universal way, hence the choice.
enum NewWindowTrigger: Equatable {
    /// `open -n -g -b <bundle-id>`: ask LaunchServices for a new instance without
    /// activating it. Single-instance apps (browsers, editors) forward the request
    /// to the running copy, which opens a new window; others start a second process.
    case open
    /// `tell application id "<bundle-id>" to make new window`, or a custom script.
    /// Needs Automation permission for the target app.
    case appleScript(String?)
    /// Run a command, e.g. `["zed", "-n"]`. Bare names resolve against PATH plus
    /// the Homebrew prefixes, since launchd gives daemons a minimal PATH.
    case command([String])
    /// Give up on staying put: focus the existing window, jumping to its workspace
    /// the way Raycast or the Dock would.
    case focus
}

/// Per-app settings. Every field is optional so entries can be layered: an app's
/// own entry over the built-in rules over `[defaults]` over the compiled-in
/// defaults.
struct AppPolicy: Equatable {
    var follow: Bool?
    var newWindow: NewWindowTrigger?
    var hotkey: Hotkey?
    var aliases: [String]?

    /// `self` wins wherever it says something; `base` fills the rest.
    func layered(over base: AppPolicy) -> AppPolicy {
        AppPolicy(
            follow: follow ?? base.follow,
            newWindow: newWindow ?? base.newWindow,
            hotkey: hotkey ?? base.hotkey,
            aliases: aliases ?? base.aliases
        )
    }
}

/// The fully resolved policy the launcher acts on.
struct EffectivePolicy: Equatable {
    var follow: Bool
    var newWindow: NewWindowTrigger
    var hotkey: Hotkey?
    var aliases: [String]
}

struct ConfigError: Error, CustomStringConvertible, Equatable {
    let message: String
    var description: String { message }
}

struct Config: Equatable {
    static let defaultHotkey = try! Hotkey.parse("alt-space")
    static let defaultAerospacePath = "/opt/homebrew/bin/aerospace"

    /// Rules that apply before the user's `[defaults]`, for apps where the
    /// compiled-in `open` trigger is actively harmful. `open -n` on Finder starts
    /// a second Finder process; Finder is scriptable, so ask it instead.
    static let builtInApps: [String: AppPolicy] = [
        "com.apple.finder": AppPolicy(
            newWindow: .appleScript("tell application \"Finder\" to make new Finder window")
        ),
    ]
    static let builtInDefaults = AppPolicy(follow: false, newWindow: .open, hotkey: nil, aliases: [])

    var hotkey = defaultHotkey
    var aerospacePath = defaultAerospacePath
    var extraAppDirs: [String] = []
    var defaults = AppPolicy()
    var apps: [String: AppPolicy] = [:]

    func policy(for bundleId: String) -> EffectivePolicy {
        let layered = (apps[bundleId] ?? AppPolicy())
            .layered(over: Self.builtInApps[bundleId] ?? AppPolicy())
            .layered(over: defaults)
            .layered(over: Self.builtInDefaults)
        return EffectivePolicy(
            follow: layered.follow ?? false,
            newWindow: layered.newWindow ?? .open,
            hotkey: layered.hotkey,
            aliases: layered.aliases ?? []
        )
    }

    // MARK: Parsing

    static func parse(toml text: String) throws -> Config {
        let doc: [String: TOMLValue]
        do {
            doc = try TOML.parse(text)
        } catch let error as TOMLError {
            throw ConfigError(message: error.description)
        }
        return try parse(document: doc)
    }

    static func parse(document doc: [String: TOMLValue]) throws -> Config {
        var config = Config()
        try checkKeys(of: doc, allowed: ["hotkey", "aerospace", "extra_app_dirs", "defaults", "apps"], at: "")

        if let value = doc["hotkey"] {
            config.hotkey = try parseHotkey(value, at: "hotkey")
        }
        if let value = doc["aerospace"] {
            config.aerospacePath = try string(value, at: "aerospace")
        }
        if let value = doc["extra_app_dirs"] {
            config.extraAppDirs = try stringArray(value, at: "extra_app_dirs")
        }
        if let value = doc["defaults"] {
            config.defaults = try parsePolicy(value, at: "defaults", allowHotkey: false)
        }
        if let value = doc["apps"] {
            guard let table = value.table else {
                throw ConfigError(message: "apps: expected a table of [apps.\"<bundle-id>\"] entries, got \(value.typeName)")
            }
            for (bundleId, entry) in table {
                config.apps[bundleId] = try parsePolicy(entry, at: "apps.\"\(bundleId)\"", allowHotkey: true)
            }
        }
        return config
    }

    private static func parsePolicy(_ value: TOMLValue, at path: String, allowHotkey: Bool) throws -> AppPolicy {
        guard let table = value.table else {
            throw ConfigError(message: "\(path): expected a table, got \(value.typeName)")
        }
        var allowed: Set<String> = ["follow", "new_window", "aliases"]
        if allowHotkey { allowed.insert("hotkey") }
        try checkKeys(of: table, allowed: allowed, at: path)

        var policy = AppPolicy()
        if let v = table["follow"] {
            guard let b = v.bool else {
                throw ConfigError(message: "\(path).follow: expected true or false, got \(v.typeName)")
            }
            policy.follow = b
        }
        if let v = table["new_window"] {
            policy.newWindow = try parseNewWindow(v, at: "\(path).new_window")
        }
        if let v = table["hotkey"] {
            policy.hotkey = try parseHotkey(v, at: "\(path).hotkey")
        }
        if let v = table["aliases"] {
            policy.aliases = try stringArray(v, at: "\(path).aliases")
        }
        return policy
    }

    private static func parseNewWindow(_ value: TOMLValue, at path: String) throws -> NewWindowTrigger {
        switch value {
        case .string("open"): return .open
        case .string("applescript"): return .appleScript(nil)
        case .string("focus"): return .focus
        case .string(let other):
            throw ConfigError(message: "\(path): unknown trigger \"\(other)\"; expected \"open\", \"applescript\", "
                + "\"focus\", an argv array, or { applescript = \"...\" }")
        case .array:
            let argv = try stringArray(value, at: path)
            guard !argv.isEmpty else { throw ConfigError(message: "\(path): command array is empty") }
            return .command(argv)
        case .table(let table):
            try checkKeys(of: table, allowed: ["applescript"], at: path)
            guard let script = table["applescript"] else {
                throw ConfigError(message: "\(path): inline table needs an applescript key")
            }
            return .appleScript(try string(script, at: "\(path).applescript"))
        default:
            throw ConfigError(message: "\(path): expected a string, an argv array or an inline table, got \(value.typeName)")
        }
    }

    private static func parseHotkey(_ value: TOMLValue, at path: String) throws -> Hotkey {
        let spec = try string(value, at: path)
        do {
            return try Hotkey.parse(spec)
        } catch let error as Hotkey.ParseError {
            throw ConfigError(message: "\(path): \(error.message)")
        }
    }

    private static func string(_ value: TOMLValue, at path: String) throws -> String {
        guard let s = value.string else {
            throw ConfigError(message: "\(path): expected a string, got \(value.typeName)")
        }
        return s
    }

    private static func stringArray(_ value: TOMLValue, at path: String) throws -> [String] {
        guard let items = value.array else {
            throw ConfigError(message: "\(path): expected an array of strings, got \(value.typeName)")
        }
        return try items.enumerated().map { index, item in
            guard let s = item.string else {
                throw ConfigError(message: "\(path)[\(index)]: expected a string, got \(item.typeName)")
            }
            return s
        }
    }

    /// Unknown keys are errors, not warnings, the way AeroSpace treats them: a
    /// silently ignored typo (`folow = true`) is the hardest config bug to spot.
    private static func checkKeys(of table: [String: TOMLValue], allowed: Set<String>, at path: String) throws {
        for key in table.keys.sorted() where !allowed.contains(key) {
            let where_ = path.isEmpty ? "top level" : path
            let allowedList = allowed.sorted().joined(separator: ", ")
            throw ConfigError(message: "\(where_): unknown key '\(key)' (allowed: \(allowedList))")
        }
    }
}

// MARK: - Locations

/// XDG base directories, with the launcher's own subdirectory.
struct Paths {
    let configDirectory: URL
    let stateDirectory: URL

    var configFile: URL { configDirectory.appendingPathComponent("config.toml") }
    var usageFile: URL { stateDirectory.appendingPathComponent("usage.json") }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        func base(_ variable: String, fallback: String) -> URL {
            if let value = environment[variable], value.hasPrefix("/") {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return home.appendingPathComponent(fallback, isDirectory: true)
        }
        configDirectory = base("XDG_CONFIG_HOME", fallback: ".config")
            .appendingPathComponent("aeroapp-launcher", isDirectory: true)
        stateDirectory = base("XDG_STATE_HOME", fallback: ".local/state")
            .appendingPathComponent("aeroapp-launcher", isDirectory: true)
    }
}
