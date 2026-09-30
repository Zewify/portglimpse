import Darwin
import Foundation
import Testing
@testable import PortGlimpseCore

/// A worker is a process listening only on ports its parent (or an ancestor) also listens on:
/// granian, gunicorn, uvicorn --workers, Node's cluster and nginx all hand their socket to children.
struct WorkerFoldingTests {
    static let me: UInt32 = 501

    func builder(_ processes: [Int32: ProcessDetails]) -> SnapshotBuilder {
        SnapshotBuilder(
            classifier: Classifier(currentUID: Self.me, overrides: [:]),
            home: "/Users/me",
            inspect: { processes[$0] },
            userName: { $0 == 0 ? "root" : "me" }
        )
    }

    func server(parent: Int32? = nil, uid: UInt32 = me) -> ProcessDetails {
        ProcessDetails(executablePath: "/opt/homebrew/bin/granian", arguments: ["granian", "wsgi"], workingDirectory: "/Users/me/api", uid: uid, parentPID: parent)
    }

    @Test func aWorkerSharingItsParentsPortFoldsIntoTheParentsRow() {
        let rows = builder([20: server(parent: 1), 21: server(parent: 20)])
            .rows(own: [Listener(port: 5080, pid: 20), Listener(port: 5080, pid: 21)], all: nil)
        #expect(rows.map(\.pid) == [20])
        #expect(rows[0].workerPIDs == [21])
        #expect(rows[0].ports == [5080])
    }

    @Test func workersOfWorkersFoldIntoTheTopListeningAncestor() {
        let rows = builder([20: server(parent: 1), 21: server(parent: 20), 22: server(parent: 21)])
            .rows(own: [Listener(port: 5080, pid: 20), Listener(port: 5080, pid: 21), Listener(port: 5080, pid: 22)], all: nil)
        #expect(rows.map(\.pid) == [20])
        #expect(rows[0].workerPIDs == [21, 22])
    }

    @Test func aChildWithAPortOfItsOwnKeepsItsOwnRow() {
        let rows = builder([20: server(parent: 1), 21: server(parent: 20)])
            .rows(own: [Listener(port: 5080, pid: 20), Listener(port: 5080, pid: 21), Listener(port: 9000, pid: 21)], all: nil)
        #expect(rows.map(\.pid) == [20, 21])
        #expect(rows.allSatisfy { $0.workerPIDs.isEmpty })
    }

    @Test func unrelatedProcessesSharingAPortStaySeparate() {
        let rows = builder([20: server(parent: 1), 30: server(parent: 1)])
            .rows(own: [Listener(port: 5080, pid: 20), Listener(port: 5080, pid: 30)], all: nil)
        #expect(rows.map(\.pid) == [20, 30])
    }

    @Test func aChildOfANonListeningParentKeepsItsOwnRow() {
        let rows = builder([21: server(parent: 20)])
            .rows(own: [Listener(port: 5080, pid: 21)], all: nil)
        #expect(rows.map(\.pid) == [21])
        #expect(rows[0].workerPIDs.isEmpty)
    }

    @Test func aChildOwnedByAnotherUserIsNeverFolded() {
        let rows = builder([20: server(parent: 1), 21: server(parent: 20, uid: 0)])
            .rows(own: [Listener(port: 5080, pid: 20)], all: [Listener(port: 5080, pid: 20), Listener(port: 5080, pid: 21, reportedName: "granian")])
        #expect(rows.map(\.pid) == [20, 21])
        #expect(rows[0].workerPIDs.isEmpty)
    }

    @Test func workerPIDsAreSorted() {
        let rows = builder([20: server(parent: 1), 23: server(parent: 20), 21: server(parent: 20)])
            .rows(own: [Listener(port: 5080, pid: 20), Listener(port: 5080, pid: 23), Listener(port: 5080, pid: 21)], all: nil)
        #expect(rows[0].workerPIDs == [21, 23])
    }
}

@Suite(.serialized)
struct LiveWorkerFoldingTests {
    /// A real parent that forks after listening, so both processes hold the same listening socket.
    @Test func aForkedWorkerFoldsIntoItsParentsRow() async throws {
        let port = try freePort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
            import os, socket, time
            s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", \(port))); s.listen()
            os.fork()
            time.sleep(60)
            """]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let parent = process.processIdentifier
        var row: Row?
        defer {
            for pid in (row?.workerPIDs ?? []) + [parent] { kill(pid, SIGKILL) }
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            row = PortScan.run(showAll: false, overrides: [:]).rows.first { $0.ports.contains(port) }
            if let row, !row.workerPIDs.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let found = try #require(row)
        #expect(found.pid == parent)
        #expect(found.workerPIDs.count == 1)
        #expect(PortScan.run(showAll: false, overrides: [:]).rows.filter { $0.ports.contains(port) }.count == 1)
    }
}
