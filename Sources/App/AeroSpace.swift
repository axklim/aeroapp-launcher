import Foundation

/// The `aerospace` CLI. Every window operation goes through it — the launcher
/// never touches the Accessibility API itself.
struct AeroSpaceCLI {
    var path: String

    /// Returns nil when the CLI could not be reached or exited non-zero, which
    /// callers treat differently from "reached it, found nothing".
    @discardableResult
    func run(_ arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            log("cannot run \(path): \(error.localizedDescription)")
            return nil
        }

        // Drain before waiting so a large payload cannot deadlock the pipe.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            log("aerospace \(arguments.joined(separator: " ")) failed (\(process.terminationStatus)): \(message)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    enum Scope {
        /// Every monitor, every workspace.
        case everywhere
        /// The focused workspace only.
        case focusedWorkspace

        var arguments: [String] {
            switch self {
            case .everywhere: return ["--monitor", "all"]
            case .focusedWorkspace: return ["--workspace", "focused"]
            }
        }
    }

    /// Windows of one app. Nil when AeroSpace is not answering.
    func windows(ofBundleId bundleId: String, scope: Scope) -> [AeroWindow]? {
        guard let output = run(
            ["list-windows"] + scope.arguments + ["--app-bundle-id", bundleId, "--format", AeroWindow.format, "--json"]
        ) else { return nil }
        do {
            return try AeroWindow.decode(json: Data(output.utf8))
        } catch {
            log("cannot decode list-windows output: \(error)")
            return nil
        }
    }

    func focusedWorkspace() -> String? {
        guard let output = run(["list-workspaces", "--focused"]) else { return nil }
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    @discardableResult
    func focus(windowId: Int) -> Bool {
        run(["focus", "--window-id", String(windowId)]) != nil
    }

    @discardableResult
    func move(windowId: Int, toWorkspace workspace: String) -> Bool {
        run(["move-node-to-workspace", "--window-id", String(windowId), "--", workspace]) != nil
    }
}
