import Darwin
import Foundation

/// Turns raw listeners into the ordered rows the panel shows.
public struct SnapshotBuilder: Sendable {
    public var classifier: Classifier
    public var home: String
    public var inspect: @Sendable (Int32) -> ProcessDetails?
    public var userName: @Sendable (UInt32) -> String

    public init(classifier: Classifier, home: String, inspect: @escaping @Sendable (Int32) -> ProcessDetails?, userName: @escaping @Sendable (UInt32) -> String) {
        self.classifier = classifier
        self.home = home
        self.inspect = inspect
        self.userName = userName
    }

    public static func live(overrides: [String: Placement]) -> SnapshotBuilder {
        SnapshotBuilder(
            classifier: Classifier(currentUID: getuid(), overrides: overrides),
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            inspect: { ProcessInspector.details(pid: $0) },
            userName: { ProcessInspector.userName(for: $0) }
        )
    }

    /// `own` comes from libproc; `all` (from netstat) is nil unless "Show all" is on,
    /// and contributes only processes `own` did not already cover.
    public func rows(own: [Listener], all: [Listener]?) -> [Row] {
        var ports: [Int32: Set<UInt16>] = [:]
        var names: [Int32: String] = [:]
        for listener in own { ports[listener.pid, default: []].insert(listener.port) }
        let ownPIDs = Set(ports.keys)
        for listener in all ?? [] where !ownPIDs.contains(listener.pid) {
            ports[listener.pid, default: []].insert(listener.port)
            if let name = listener.reportedName { names[listener.pid] = name }
        }
        return ports.compactMap { pid, portSet in
            guard let details = inspect(pid) else { return nil }
            let section = classifier.section(for: details)
            if section == .otherUsers, all == nil { return nil }
            let fallback = names[pid] ?? details.executablePath.map { ($0 as NSString).lastPathComponent } ?? "PID \(pid)"
            return Row(
                pid: pid,
                ports: portSet.sorted(),
                command: section == .otherUsers ? fallback : CommandLabel.label(arguments: details.arguments, fallbackName: fallback),
                folder: folder(for: details, in: section),
                owner: section == .otherUsers ? details.uid.map(userName) : nil,
                section: section,
                executablePath: details.executablePath
            )
        }
        .sorted { ($0.section.order, $0.ports[0]) < ($1.section.order, $1.ports[0]) }
    }

    func folder(for details: ProcessDetails, in section: Section) -> String? {
        switch section {
        case .otherUsers:
            return nil
        case .appsAndSystem:
            if let path = details.executablePath, let bundle = Classifier.appBundle(containing: path) { return bundle }
            return details.workingDirectory.flatMap(displayPath)
        case .dev:
            return details.workingDirectory.flatMap(displayPath)
        }
    }

    /// `~` for the home folder; nothing for `/`, which only means "not started from a project".
    func displayPath(_ path: String) -> String? {
        if path == "/" { return nil }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

public struct ScanResult: Sendable, Equatable {
    public let rows: [Row]
    /// Set when the process list itself could not be read.
    public let problem: String?
    /// Set when "Show all" is on but other users' ports could not be read.
    public let otherUsersProblem: String?
}

/// One full scan with the live sources.
public enum PortScan {
    public static func run(showAll: Bool, overrides: [String: Placement]) -> ScanResult {
        let own: [Listener]
        do {
            own = try OwnProcessSource().listeners()
        } catch {
            return ScanResult(rows: [], problem: "Couldn't read the list of processes.", otherUsersProblem: nil)
        }
        var all: [Listener]?
        var otherUsersProblem: String?
        if showAll {
            let found = try? NetstatSource().listeners()
            // netstat always lists our own listeners too, so an empty result next to a non-empty `own` means parsing broke.
            if let found, !(found.isEmpty && !own.isEmpty) {
                all = found
            } else {
                otherUsersProblem = "Can't read other users' ports on this macOS version."
            }
        }
        let rows = SnapshotBuilder.live(overrides: overrides).rows(own: own, all: all)
        return ScanResult(rows: rows, problem: nil, otherUsersProblem: otherUsersProblem)
    }
}
