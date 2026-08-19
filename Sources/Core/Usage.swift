import Foundation

/// Launch counts per bundle identifier, so often-used apps rank first among equal
/// matches. Stored as a flat JSON object under the XDG state directory.
final class UsageStore {
    private(set) var counts: [String: Int]
    private let file: URL

    init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            counts = decoded
        } else {
            counts = [:]
        }
    }

    func count(for bundleId: String) -> Int {
        counts[bundleId] ?? 0
    }

    /// Bumps the count and writes the file. Errors are returned, not thrown, so
    /// the caller can log and carry on — losing a count is not worth failing a launch.
    @discardableResult
    func record(_ bundleId: String) -> Error? {
        counts[bundleId, default: 0] += 1
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(counts).write(to: file, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
