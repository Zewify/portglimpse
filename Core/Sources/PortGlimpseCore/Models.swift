import Foundation

/// One TCP socket in the LISTEN state.
public struct Listener: Hashable, Sendable {
    public let port: UInt16
    public let pid: Int32
    /// The process name as `netstat` printed it (at most 16 characters); nil from the libproc source.
    public let reportedName: String?

    public init(port: UInt16, pid: Int32, reportedName: String? = nil) {
        self.port = port
        self.pid = pid
        self.reportedName = reportedName
    }
}

/// The panel's three sections, in display order.
public enum Section: String, Codable, Sendable, CaseIterable {
    case dev, appsAndSystem, otherUsers

    public var order: Int { Section.allCases.firstIndex(of: self)! }
}

/// Where a right-click override puts a process. Other users' processes cannot be overridden.
public enum Placement: String, Codable, Sendable {
    case dev, appsAndSystem

    public var section: Section { self == .dev ? .dev : .appsAndSystem }
}

/// What the kernel tells us about one process. Every field is optional because a process can exit mid-read.
public struct ProcessDetails: Equatable, Sendable {
    public var executablePath: String?
    public var arguments: [String]
    public var workingDirectory: String?
    public var uid: UInt32?

    public init(executablePath: String? = nil, arguments: [String] = [], workingDirectory: String? = nil, uid: UInt32? = nil) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.uid = uid
    }
}

/// One row in the panel: a process and every port it listens on.
public struct Row: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    /// Sorted ascending; never empty.
    public let ports: [UInt16]
    public let command: String
    public let folder: String?
    /// The owning user's name, set only for other users' processes.
    public let owner: String?
    public let section: Section
    public let executablePath: String?

    public init(pid: Int32, ports: [UInt16], command: String, folder: String?, owner: String?, section: Section, executablePath: String?) {
        self.pid = pid
        self.ports = ports
        self.command = command
        self.folder = folder
        self.owner = owner
        self.section = section
        self.executablePath = executablePath
    }
}
