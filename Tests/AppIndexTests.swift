import Foundation

func runAppIndexTests() {
    func makeApp(in dir: URL, name: String, bundleId: String?, extra: String = "") throws -> URL {
        let app = dir.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let id = bundleId.map { "<key>CFBundleIdentifier</key><string>\($0)</string>" } ?? ""
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleName</key><string>\(name)</string>
        \(id)\(extra)
        </dict></plist>
        """
        try plist.write(to: app.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        return app.deletingLastPathComponent()
    }

    test("AppIndex: scans roots one level deep, dedups by bundle id, skips background-only and id-less bundles") {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aeroapp-launcher-tests-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = tmp.appendingPathComponent("Applications", isDirectory: true)
        let other = tmp.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Utilities/Deeper"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        _ = try makeApp(in: root, name: "Zed", bundleId: "dev.zed.Zed")
        _ = try makeApp(in: root, name: "Slack", bundleId: "com.tinyspeck.slackmacgap")
        _ = try makeApp(in: root.appendingPathComponent("Utilities"), name: "Terminal", bundleId: "com.apple.Terminal")
        _ = try makeApp(in: root.appendingPathComponent("Utilities/Deeper"), name: "TooDeep", bundleId: "com.test.toodeep")
        _ = try makeApp(in: root, name: "NoId", bundleId: nil)
        _ = try makeApp(in: root, name: "Agent", bundleId: "com.test.agent", extra: "<key>LSBackgroundOnly</key><true/>")
        _ = try makeApp(in: root, name: "Me", bundleId: "com.axklim.aeroapp-launcher")
        _ = try makeApp(in: other, name: "Slack Copy", bundleId: "com.tinyspeck.slackmacgap")
        let finder = try makeApp(in: other, name: "Finder", bundleId: "com.apple.finder")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden.app/Contents"), withIntermediateDirectories: true)

        let apps = AppIndex.scan(roots: [root, finder], excludingBundleId: "com.axklim.aeroapp-launcher")
        expectEqual(apps.map(\.name), ["Finder", "Slack", "Terminal", "Zed"])
        expectEqual(apps.map(\.bundleId), ["com.apple.finder", "com.tinyspeck.slackmacgap", "com.apple.Terminal", "dev.zed.Zed"])
        expectEqual(apps.first { $0.name == "Slack" }?.url.lastPathComponent, "Slack.app", "first root wins the dedup")

        let otherFirst = AppIndex.scan(roots: [other, root])
        expectEqual(otherFirst.first { $0.bundleId == "com.tinyspeck.slackmacgap" }?.name, "Slack Copy")
    }

    test("AppIndex: the real default roots contain System Settings, Finder and Safari") {
        let apps = AppIndex.scan(roots: AppIndex.defaultRoots())
        for id in ["com.apple.systempreferences", "com.apple.finder", "com.apple.Safari"] {
            expect(apps.contains { $0.bundleId == id }, "\(id) not found")
        }
        expect(apps.allSatisfy { !$0.name.hasSuffix(".app") })
        expect(!apps.contains { $0.name.hasPrefix(".") })
    }

    test("UsageStore: counts persist across instances") {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aeroapp-launcher-usage-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("nested/usage.json")

        let store = UsageStore(file: file)
        expectEqual(store.count(for: "a"), 0)
        expectNil(store.record("a"))
        expectNil(store.record("a"))
        expectNil(store.record("b"))
        expectEqual(store.count(for: "a"), 2)

        let reloaded = UsageStore(file: file)
        expectEqual(reloaded.count(for: "a"), 2)
        expectEqual(reloaded.count(for: "b"), 1)
        expectEqual(reloaded.count(for: "c"), 0)
    }
}
