import AppKit

/// The command-line face of the same binary. Everything here is one-shot: read
/// the config, do the thing, exit — no daemon required, except for `toggle`,
/// which by its nature talks to the running one.
enum CLI {
    static let usage = """
    usage: aeroapp-launcher                run the launcher (what brew services does)
           aeroapp-launcher summon <app>   summon an app by bundle id or name, as the overlay would
           aeroapp-launcher toggle         open or close the overlay of the running launcher
           aeroapp-launcher list           print installed apps with their bundle ids
           aeroapp-launcher version
    """

    /// The distributed notification `toggle` sends to the daemon.
    static let toggleNotification = Notification.Name("com.axklim.aeroapp-launcher.toggle")

    static func run(_ arguments: [String]) -> Int32 {
        Log.plain = true
        switch arguments.first {
        case "summon":
            guard arguments.count == 2 else {
                return fail("summon takes exactly one argument: a bundle id or an app name")
            }
            return summon(arguments[1])
        case "toggle":
            return toggle()
        case "list":
            return list()
        case "version", "--version", "-v":
            print(appVersion)
            return 0
        case "help", "--help", "-h":
            print(usage)
            return 0
        case let other?:
            return fail("unknown command '\(other)'\n\(usage)")
        case nil:
            return fail(usage)
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }

    // MARK: Commands

    private static func summon(_ query: String) -> Int32 {
        let config = loadConfig()
        guard let app = resolve(query, config: config) else { return 1 }

        let summoner = Summoner(aerospace: AeroSpaceCLI(path: config.aerospacePath))
        // LaunchServices wants a run loop to call back on; keep the main one spinning
        // while the work happens elsewhere.
        DispatchQueue.global(qos: .userInitiated).async {
            switch summoner.perform(app, policy: config.policy(for: app.bundleId)) {
            case .done, .aerospaceUnreachable:
                exit(0)
            case .launchFailed:
                exit(1)
            }
        }
        RunLoop.main.run()
        return 0
    }

    private static func toggle() -> Int32 {
        DistributedNotificationCenter.default().postNotificationName(
            toggleNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
        return 0
    }

    private static func list() -> Int32 {
        let apps = installedApps(config: loadConfig())
        let width = apps.map(\.bundleId.count).max() ?? 0
        for app in apps {
            print(app.bundleId.padding(toLength: width + 2, withPad: " ", startingAt: 0) + app.name)
        }
        return 0
    }

    // MARK: Helpers

    /// The same file the daemon reads; errors are fatal here rather than logged
    /// and skipped, because a one-shot command has no previous settings to keep.
    private static func loadConfig() -> Config {
        let file = Paths().configFile
        guard FileManager.default.fileExists(atPath: file.path) else { return Config() }
        do {
            return try Config.parse(toml: try String(contentsOf: file, encoding: .utf8))
        } catch {
            _ = fail("\(file.path): \(error)")
            exit(1)
        }
    }

    private static func installedApps(config: Config) -> [InstalledApp] {
        let roots = AppIndex.defaultRoots() + config.extraAppDirs.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
        return AppIndex.scan(roots: roots, excludingBundleId: "com.axklim.aeroapp-launcher")
    }

    /// A bundle id, or an app name compared case- and diacritic-insensitively.
    /// Deliberately not fuzzy: a command bound to a key has to be predictable.
    private static func resolve(_ query: String, config: Config) -> InstalledApp? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query), let app = AppIndex.inspect(url) {
            return app
        }
        let apps = installedApps(config: config)
        let wanted = Matcher.normalize(query).lowercased()
        if let app = apps.first(where: { Matcher.normalize($0.name).lowercased() == wanted }) {
            return app
        }
        var message = "no installed app with bundle id or name '\(query)'"
        let suggestions = Matcher.rank(apps, query: query).prefix(3).map { "\($0.app.name) (\($0.app.bundleId))" }
        if !suggestions.isEmpty {
            message += "; did you mean: " + suggestions.joined(separator: ", ")
        }
        _ = fail(message)
        return nil
    }
}
