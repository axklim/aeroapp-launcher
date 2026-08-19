import Foundation

/// Finds every launchable app on the machine. The config is a policy overlay on
/// this list, never a substitute for it.
enum AppIndex {
    /// Where apps live. `/Applications` and `~/Applications` are searched one level
    /// deep as well, which covers `Utilities`, vendor folders and Setapp.
    static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            // Safari lives in a cryptex; /Applications/Safari.app is a symlink to it.
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true),
        ]
    }

    /// Scans `roots` (directories, or `.app` bundles named directly). The first
    /// occurrence of a bundle identifier wins, so list the preferred roots first.
    static func scan(roots: [URL], excludingBundleId own: String? = nil) -> [InstalledApp] {
        var seen: Set<String> = []
        var apps: [InstalledApp] = []

        for root in roots {
            for url in bundles(under: root) {
                guard let app = inspect(url), app.bundleId != own, !seen.contains(app.bundleId) else { continue }
                seen.insert(app.bundleId)
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles directly under `root`, plus those one level down inside plain
    /// subdirectories. A root that is itself a bundle yields just that bundle.
    static func bundles(under root: URL) -> [URL] {
        if root.pathExtension == "app" { return isDirectory(root) ? [root] : [] }
        var found: [URL] = []
        for entry in children(of: root) {
            if entry.pathExtension == "app" {
                found.append(entry)
            } else if isDirectory(entry) {
                found.append(contentsOf: children(of: entry).filter { $0.pathExtension == "app" && isDirectory($0) })
            }
        }
        return found
    }

    static func inspect(_ url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier, !bundleId.isEmpty else { return nil }
        // Background-only apps have no UI to summon; menu bar apps (LSUIElement)
        // do count — launching one is a legitimate thing to want.
        if let backgroundOnly = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly"), isTruthy(backgroundOnly) {
            return nil
        }
        // Store the real bundle: an icon fetched for a symlink wears a link badge.
        return InstalledApp(bundleId: bundleId, name: displayName(of: url), url: url.resolvingSymlinksInPath())
    }

    static func displayName(of url: URL) -> String {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }

    /// Dot-entries (`.localized`, `.DS_Store`) are skipped by name. Not by the
    /// hidden flag: macOS sets it on the /Applications/Safari.app symlink, and
    /// Safari is very much launchable.
    private static func children(of directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        // Follows symlinks, so /Applications/Safari.app → the cryptex copy resolves.
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isTruthy(_ value: Any) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String { return s == "1" || s.lowercased() == "yes" || s.lowercased() == "true" }
        return false
    }
}
