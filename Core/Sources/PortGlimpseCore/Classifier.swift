import Foundation

/// Decides which section a process belongs in.
public struct Classifier: Sendable {
    public let currentUID: UInt32
    /// Right-click overrides, keyed by executable path.
    public let overrides: [String: Placement]

    static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]

    public init(currentUID: UInt32, overrides: [String: Placement]) {
        self.currentUID = currentUID
        self.overrides = overrides
    }

    /// Order matters: ownership, then overrides, then runtimes outside app bundles (Python runs from inside `Python.app`),
    /// then macOS's own folders, then app bundles; anything left is a dev server.
    public func section(for details: ProcessDetails) -> Section {
        guard let uid = details.uid, uid == currentUID else { return .otherUsers }
        guard let path = details.executablePath else { return .appsAndSystem }
        if let placement = overrides[path] { return placement.section }
        if Runtimes.isRuntime((path as NSString).lastPathComponent), Self.runtimeKeepsDevPlacement(path) { return .dev }
        if Self.systemPrefixes.contains(where: { path.hasPrefix($0) }) { return .appsAndSystem }
        if Self.appBundle(containing: path) != nil { return .appsAndSystem }
        return .dev
    }

    /// A runtime is a dev server unless it is bundled inside an app (a `node` shipped in `Some.app`);
    /// Python is the exception, as it runs from `Python.app` inside `Python.framework`.
    static func runtimeKeepsDevPlacement(_ path: String) -> Bool {
        appBundle(containing: path) == nil || path.contains(".framework/")
    }

    /// The outermost `.app` bundle an executable lives in, or nil when it is not inside one.
    public static func appBundle(containing executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
}
