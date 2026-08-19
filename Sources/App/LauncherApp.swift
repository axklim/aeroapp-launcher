import AppKit

final class LauncherApp: OverlayDataSource {
    private let paths = Paths()
    private let ownBundleId = Bundle.main.bundleIdentifier ?? "com.axklim.aeroapp-launcher"

    private var config = Config()
    private var apps: [InstalledApp] = []
    private var lastScan = Date.distantPast

    private let usage: UsageStore
    private let hotkeys = HotkeyCenter()
    private let overlay = Overlay()
    private let summoner: Summoner
    private var watcher: ConfigWatcher?

    init() {
        usage = UsageStore(file: paths.usageFile)
        summoner = Summoner(aerospace: AeroSpaceCLI(path: Config.defaultAerospacePath))
        overlay.dataSource = self
    }

    func start() {
        log("version \(appVersion), config \(paths.configFile.path)")

        loadConfig()
        applyConfig()
        rescanApps()
        watchConfig()

        // `aeroapp-launcher toggle` — so the overlay can be bound from aerospace.toml
        // or a script instead of, or as well as, the built-in hotkey.
        DistributedNotificationCenter.default().addObserver(
            forName: CLI.toggleNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.overlay.toggle()
        }
    }

    // MARK: Config

    /// Reads the config file. A missing file means defaults; a broken one keeps
    /// whatever was loaded before, so a typo cannot take the hotkeys down.
    private func loadConfig() {
        let file = paths.configFile
        guard FileManager.default.fileExists(atPath: file.path) else {
            log("no config file, using defaults")
            config = Config()
            return
        }
        do {
            let text = try String(contentsOf: file, encoding: .utf8)
            config = try Config.parse(toml: text)
            log("config loaded: \(config.apps.count) app entr\(config.apps.count == 1 ? "y" : "ies")")
        } catch {
            log("config error, keeping previous settings: \(error)")
        }
    }

    private func applyConfig() {
        summoner.aerospace = AeroSpaceCLI(path: config.aerospacePath)
        registerHotkeys()
        overlay.refresh()
    }

    private func registerHotkeys() {
        hotkeys.unregisterAll()
        var taken: Set<Hotkey> = []

        if hotkeys.register(config.hotkey, action: { [weak self] in self?.overlay.toggle() }) {
            taken.insert(config.hotkey)
            log("hotkey \(config.hotkey) opens the launcher")
        }

        for (bundleId, policy) in config.apps.sorted(by: { $0.key < $1.key }) {
            guard let hotkey = policy.hotkey else { continue }
            // One config file serves several machines; a chord for an app that is
            // not installed here must not be taken away from whatever else wants it.
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
                log("hotkey \(hotkey) for \(bundleId) not registered: app not installed")
                continue
            }
            guard !taken.contains(hotkey) else {
                log("hotkey \(hotkey) for \(bundleId) is already taken; skipping")
                continue
            }
            if hotkeys.register(hotkey, action: { [weak self] in self?.summon(bundleId: bundleId) }) {
                taken.insert(hotkey)
                log("hotkey \(hotkey) summons \(bundleId)")
            }
        }
    }

    private func watchConfig() {
        // The directory has to exist to be watched; creating it is what any app
        // owning an XDG config directory does.
        try? FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let watcher = ConfigWatcher(file: paths.configFile) { [weak self] in
            guard let self else { return }
            log("config changed, reloading")
            self.loadConfig()
            self.applyConfig()
            self.rescanApps()
        }
        if !watcher.start() {
            log("cannot watch \(paths.configDirectory.path); config changes need a restart")
        }
        self.watcher = watcher
    }

    // MARK: App index

    private func rescanApps() {
        lastScan = Date()
        let roots = AppIndex.defaultRoots() + config.extraAppDirs.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
        let own = ownBundleId
        DispatchQueue.global(qos: .utility).async {
            let found = AppIndex.scan(roots: roots, excludingBundleId: own)
            DispatchQueue.main.async {
                if found != self.apps {
                    log("indexed \(found.count) apps")
                    self.apps = found
                    self.overlay.refresh()
                }
            }
        }
    }

    // MARK: Summoning

    private func summon(bundleId: String) {
        overlay.hide()
        if let app = apps.first(where: { $0.bundleId == bundleId }) {
            summon(app)
            return
        }
        // Not in the index — perhaps installed since the last scan.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let app = AppIndex.inspect(url) {
            summon(app)
            rescanApps()
            return
        }
        log("hotkey for \(bundleId) pressed, but no such app is installed")
    }

    private func summon(_ app: InstalledApp) {
        if let error = usage.record(app.bundleId) {
            log("cannot save usage counts: \(error.localizedDescription)")
        }
        summoner.summon(app, policy: config.policy(for: app.bundleId))
    }

    // MARK: OverlayDataSource

    func overlayResults(for query: String) -> [OverlayRow] {
        // Apps come and go while the launcher runs; a scan is cheap, so refresh in
        // the background whenever the panel opens after a quiet minute.
        if Date().timeIntervalSince(lastScan) > 60 { rescanApps() }

        return Matcher.rank(
            apps,
            query: query,
            aliases: { [config] in config.policy(for: $0.bundleId).aliases },
            usage: { [usage] in usage.count(for: $0.bundleId) }
        ).map { ranked in
            OverlayRow(app: ranked.app, detail: config.policy(for: ranked.app.bundleId).hotkey?.glyphs ?? "")
        }
    }

    func overlayDidSelect(_ row: OverlayRow) {
        summon(row.app)
    }
}
