import Foundation
import Testing
@testable import PortGlimpseCore

struct SnapshotTests {
    static let me: UInt32 = 501

    static let processes: [Int32: ProcessDetails] = [
        10: ProcessDetails(executablePath: "/usr/local/bin/node", arguments: ["node", "/Users/me/financy/node_modules/.bin/next", "dev"], workingDirectory: "/Users/me/financy", uid: me),
        11: ProcessDetails(executablePath: "/opt/homebrew/bin/mysqld", arguments: ["/opt/homebrew/bin/mysqld"], workingDirectory: "/opt/homebrew/var/mysql", uid: me),
        12: ProcessDetails(executablePath: "/Applications/DBeaver.app/Contents/MacOS/dbeaver", arguments: ["dbeaver"], workingDirectory: "/Applications/DBeaver.app/Contents/MacOS", uid: me),
        13: ProcessDetails(executablePath: "/usr/local/bin/node", arguments: ["node", "server.js"], workingDirectory: "/", uid: me),
        1: ProcessDetails(executablePath: nil, arguments: [], workingDirectory: nil, uid: 0),
    ]

    func builder(overrides: [String: Placement] = [:]) -> SnapshotBuilder {
        SnapshotBuilder(
            classifier: Classifier(currentUID: Self.me, overrides: overrides),
            home: "/Users/me",
            inspect: { Self.processes[$0] },
            userName: { $0 == 0 ? "root" : "me" }
        )
    }

    @Test func oneRowPerProcessWithSortedPorts() {
        let rows = builder().rows(own: [Listener(port: 33060, pid: 11), Listener(port: 3306, pid: 11)], all: nil)
        #expect(rows.count == 1)
        #expect(rows[0].ports == [3306, 33060])
        #expect(rows[0].command == "mysqld")
    }

    // Review Focus 3: the same port over IPv4 and IPv6 shows once.
    @Test func duplicatePortsCollapse() {
        let rows = builder().rows(own: [Listener(port: 3000, pid: 10), Listener(port: 3000, pid: 10)], all: nil)
        #expect(rows[0].ports == [3000])
    }

    // Review Focus 2: a process that exited after the scan is dropped.
    @Test func exitedProcessesAreDropped() {
        let rows = builder().rows(own: [Listener(port: 4000, pid: 999), Listener(port: 3000, pid: 10)], all: nil)
        #expect(rows.map(\.pid) == [10])
    }

    @Test func devRowShowsCommandAndHomeRelativeFolder() {
        let row = builder().rows(own: [Listener(port: 3000, pid: 10)], all: nil)[0]
        #expect(row.section == .dev)
        #expect(row.command == "next dev")
        #expect(row.folder == "~/financy")
        #expect(row.owner == nil)
    }

    @Test func rootFolderIsNotShown() {
        #expect(builder().rows(own: [Listener(port: 8080, pid: 13)], all: nil)[0].folder == nil)
    }

    @Test func appRowShowsItsBundle() {
        let row = builder().rows(own: [Listener(port: 17030, pid: 12)], all: nil)[0]
        #expect(row.section == .appsAndSystem)
        #expect(row.folder == "/Applications/DBeaver.app")
    }

    @Test func otherUsersAppearOnlyWithShowAll() {
        let own = [Listener(port: 3000, pid: 10)]
        let all = [Listener(port: 3000, pid: 10, reportedName: "node"), Listener(port: 8021, pid: 1, reportedName: "launchd")]
        #expect(builder().rows(own: own, all: nil).count == 1)
        let rows = builder().rows(own: own, all: all)
        #expect(rows.count == 2)
        let launchd = rows[1]
        #expect(launchd.section == .otherUsers)
        #expect(launchd.command == "launchd")
        #expect(launchd.owner == "root")
        #expect(launchd.folder == nil)
    }

    @Test func rowsAreOrderedBySectionThenPort() {
        let own = [Listener(port: 17030, pid: 12), Listener(port: 3306, pid: 11), Listener(port: 3000, pid: 10)]
        let all = own + [Listener(port: 8021, pid: 1, reportedName: "launchd")]
        let rows = builder().rows(own: own, all: all)
        #expect(rows.map(\.pid) == [10, 11, 12, 1])
    }

    @Test func processesSharingALowestPortKeepAStableOrder() {
        for _ in 0..<20 {
            let rows = builder().rows(own: [Listener(port: 3000, pid: 13), Listener(port: 3000, pid: 10)], all: nil)
            #expect(rows.map(\.pid) == [10, 13])
        }
    }

    @Test func appBundleInsideHomeIsShownHomeRelative() {
        let home = ProcessDetails(executablePath: "/Users/me/Applications/Foo.app/Contents/MacOS/foo", arguments: ["foo"], workingDirectory: "/", uid: Self.me)
        let builder = SnapshotBuilder(
            classifier: Classifier(currentUID: Self.me, overrides: [:]),
            home: "/Users/me",
            inspect: { $0 == 30 ? home : nil },
            userName: { _ in "me" }
        )
        let row = builder.rows(own: [Listener(port: 9000, pid: 30)], all: nil)[0]
        #expect(row.section == .appsAndSystem)
        #expect(row.folder == "~/Applications/Foo.app")
    }

    @Test func overridesMoveRows() {
        let rows = builder(overrides: ["/Applications/DBeaver.app/Contents/MacOS/dbeaver": .dev]).rows(own: [Listener(port: 17030, pid: 12)], all: nil)
        #expect(rows[0].section == .dev)
    }
}

@Suite(.serialized)
struct LiveScanTests {
    @Test func aRealServerIsADevServerInItsFolder() async throws {
        let server = try TestServer()
        defer { server.stop() }
        try await server.waitUntilListening()
        let result = PortScan.run(showAll: true, overrides: [:])
        #expect(result.problem == nil)
        #expect(result.otherUsersProblem == nil)
        let row = try #require(result.rows.first { $0.pid == server.pid })
        #expect(row.ports == [server.port])
        #expect(row.section == .dev)
        #expect(row.command == "nc")
        let expected = server.directory.resolvingSymlinksInPath().path
        #expect(row.folder.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == expected)
        #expect(result.rows.filter { $0.section == .otherUsers }.allSatisfy { $0.folder == nil && $0.owner != nil })
    }
}
