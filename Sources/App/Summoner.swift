import AppKit

/// Carries out a `SummonPlan`: launches, focuses, moves, or triggers a new window,
/// then makes sure the result ends up focused on the workspace the user is on.
final class Summoner {
    var aerospace: AeroSpaceCLI

    /// How long to wait for a freshly requested window to show up in AeroSpace
    /// before giving up on focusing it. Cold launches of heavy apps take a while.
    private let newWindowTimeout: TimeInterval = 8

    init(aerospace: AeroSpaceCLI) {
        self.aerospace = aerospace
    }

    enum Outcome {
        /// The plan ran. Triggers that failed and fell back to focusing the
        /// existing window count as done — something visible happened.
        case done(SummonPlan)
        /// AeroSpace did not answer; the app was activated plainly instead.
        case aerospaceUnreachable
        /// LaunchServices refused to open the app.
        case launchFailed(String)
    }

    /// Runs off the main thread; several summons may be in flight at once, so one
    /// slow launch never delays the next hotkey.
    func summon(_ app: InstalledApp, policy: EffectivePolicy) {
        let aerospace = self.aerospace
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.perform(app, policy: policy, aerospace: aerospace)
        }
    }

    /// The whole summon, synchronously: blocks for the CLI calls, the launch
    /// hand-off and, after a new-window trigger, the wait for the window to show.
    func perform(_ app: InstalledApp, policy: EffectivePolicy, aerospace: AeroSpaceCLI? = nil) -> Outcome {
        let aerospace = aerospace ?? self.aerospace
        guard let windows = aerospace.windows(ofBundleId: app.bundleId, scope: .everywhere) else {
            // AeroSpace is not answering. Activating the app is what the Dock or
            // Raycast would do; better than a dead key.
            log("aerospace unreachable; activating \(app.name) plainly")
            if let failure = launch(app, activate: true) { return .launchFailed(failure) }
            return .aerospaceUnreachable
        }

        let plan = SummonPlan.decide(windows: windows, follow: policy.follow)
        log("\(app.name): \(describe(plan, policy)) [\(windows.count) window(s), follow=\(policy.follow)]")

        switch plan {
        case .launch:
            if let failure = launch(app, activate: true) { return .launchFailed(failure) }

        case .focus(let windowId):
            aerospace.focus(windowId: windowId)

        case .newWindow(let existing):
            openNewWindow(of: app, trigger: policy.newWindow, existing: existing, aerospace: aerospace)

        case .moveHere(let windowIds):
            guard let workspace = aerospace.focusedWorkspace() else {
                log("\(app.name): cannot determine focused workspace; focusing in place")
                aerospace.focus(windowId: windowIds[0])
                return .done(plan)
            }
            for id in windowIds {
                aerospace.move(windowId: id, toWorkspace: workspace)
            }
            aerospace.focus(windowId: windowIds[0])
        }
        return .done(plan)
    }

    private func describe(_ plan: SummonPlan, _ policy: EffectivePolicy) -> String {
        switch plan {
        case .launch: return "launch"
        case .focus(let id): return "focus window \(id) here"
        case .moveHere(let ids): return "move window(s) \(ids) here"
        case .newWindow:
            switch policy.newWindow {
            case .open: return "new window here via open -n -g"
            case .appleScript: return "new window here via AppleScript"
            case .command(let argv): return "new window here via \(argv.joined(separator: " "))"
            case .focus: return "focus existing window elsewhere (new_window = focus)"
            }
        }
    }

    // MARK: Launching

    /// Asks LaunchServices to open the app and waits for its verdict (not for the
    /// app to finish launching). Returns the error text, if any.
    @discardableResult
    private func launch(_ app: InstalledApp, activate: Bool, newInstance: Bool = false) -> String? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.createsNewApplicationInstance = newInstance

        let done = DispatchSemaphore(value: 0)
        var failure: String?
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            failure = error?.localizedDescription
            done.signal()
        }
        if done.wait(timeout: .now() + 15) == .timedOut {
            log("LaunchServices is taking long to open \(app.name); not waiting")
            return nil
        }
        if let failure {
            log("cannot open \(app.name): \(failure)")
        }
        return failure
    }

    private func openNewWindow(
        of app: InstalledApp, trigger: NewWindowTrigger, existing: [AeroWindow], aerospace: AeroSpaceCLI
    ) {
        // The status-quo fallback when a trigger cannot run: focus what exists,
        // workspace jump and all. Visible and predictable beats a silent no-op.
        func giveUp(_ reason: String) {
            log("\(app.name): \(reason); focusing existing window instead")
            aerospace.focus(windowId: existing[0].windowId)
        }

        switch trigger {
        case .focus:
            aerospace.focus(windowId: existing[0].windowId)
            return

        case .open:
            // The equivalent of `open -n -g`: a new instance, not brought to the
            // front. Single-instance apps hand the request to their running copy.
            launch(app, activate: false, newInstance: true)

        case .appleScript(let custom):
            let script = custom ?? "tell application id \"\(app.bundleId)\" to make new window"
            if let failure = runAppleScript(script) {
                giveUp("AppleScript failed: \(failure)")
                return
            }

        case .command(let argv):
            if let failure = runCommand(argv) {
                giveUp("command \(argv) failed: \(failure)")
                return
            }
        }

        focusNewWindow(of: app, existing: existing, aerospace: aerospace)
    }

    /// Waits for a window of `app` that was not there before, and focuses it —
    /// none of the triggers reliably focus what they create: `open -g` by design,
    /// the others by app whim. All workspaces are watched, not just the focused
    /// one: some apps open the window on the workspace they already live on, and
    /// it still has to end up here. When nothing appears — a single-instance app
    /// silently ignoring `open -n`, say — the existing window is focused instead,
    /// the way the Dock would have.
    private func focusNewWindow(of app: InstalledApp, existing: [AeroWindow], aerospace: AeroSpaceCLI) {
        let before = Set(existing.map(\.windowId))
        let deadline = Date().addingTimeInterval(newWindowTimeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            guard let windows = aerospace.windows(ofBundleId: app.bundleId, scope: .everywhere) else { return }
            guard let fresh = windows.first(where: { !before.contains($0.windowId) }) else { continue }
            if !fresh.workspaceIsFocused {
                log("\(app.name): new window \(fresh.windowId) appeared on workspace \(fresh.workspace); moving it here")
                if let workspace = aerospace.focusedWorkspace() {
                    aerospace.move(windowId: fresh.windowId, toWorkspace: workspace)
                }
            }
            aerospace.focus(windowId: fresh.windowId)
            return
        }
        log("\(app.name): no new window appeared within \(Int(newWindowTimeout))s; focusing the existing window instead")
        aerospace.focus(windowId: existing[0].windowId)
    }

    // MARK: Triggers

    /// Runs the script through `osascript` rather than NSAppleScript: it stays off
    /// the main thread while an Automation permission prompt is up, and the
    /// prompt is still attributed to this app as the responsible process.
    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty ? "exit status \(process.terminationStatus)" : message
        }
        return nil
    }

    /// Starts `argv` and returns immediately — a CLI like `zed -n` exits at once,
    /// but a trigger that stays running must not hold the launcher up. Failure to
    /// start is reported; a later non-zero exit is only logged.
    private func runCommand(_ argv: [String]) -> String? {
        guard let executable = resolveExecutable(argv[0]) else {
            return argv[0].contains("/") ? "'\(argv[0])' is not an executable file" : "'\(argv[0])' not found in PATH"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { p in
            if p.terminationStatus != 0 {
                log("command \(argv) exited with status \(p.terminationStatus)")
            }
        }
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    /// launchd starts services with a bare PATH, so the Homebrew prefixes are
    /// searched too — that is where `zed`, `code` and friends live.
    private func resolveExecutable(_ name: String) -> String? {
        let expanded = (name as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !directories.contains(extra) {
            directories.append(extra)
        }
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(expanded)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
