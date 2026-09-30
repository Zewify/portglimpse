import Foundation

/// Right-click overrides ("Always show as dev"), stored as JSON keyed by executable path.
public final class OverrideStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortGlimpse/overrides.json")
    }

    public let fileURL: URL
    public private(set) var overrides: [String: Placement]

    /// A missing or unreadable file means no overrides; it is rewritten on the next change.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        overrides = data.flatMap { try? JSONDecoder().decode([String: Placement].self, from: $0) } ?? [:]
    }

    /// Nil removes the override, returning the process to automatic placement.
    public func set(_ placement: Placement?, for executablePath: String) throws {
        overrides[executablePath] = placement
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(overrides).write(to: fileURL, options: .atomic)
    }
}
