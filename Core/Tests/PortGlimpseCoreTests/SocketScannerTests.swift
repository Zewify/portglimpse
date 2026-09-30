import Foundation
import Testing
@testable import PortGlimpseCore

struct NetstatParsingTests {
    let listeners: [Listener] = {
        let url = Bundle.module.url(forResource: "netstat-listen", withExtension: "txt", subdirectory: "Fixtures")!
        return NetstatSource.parse(try! String(contentsOf: url, encoding: .utf8))
    }()

    @Test func findsEveryListenerAndSkipsEverythingElse() {
        #expect(listeners.count == 14)
        #expect(!listeners.contains { $0.port == 52011 })
    }

    @Test func readsPortPidAndName() {
        #expect(listeners.contains(Listener(port: 38123, pid: 59043, reportedName: "node")))
        #expect(listeners.contains(Listener(port: 8021, pid: 1, reportedName: "launchd")))
    }

    @Test func readsIPv6Addresses() {
        #expect(listeners.contains(Listener(port: 6379, pid: 1168, reportedName: "redis-server")))
        #expect(listeners.filter { $0.port == 6379 }.count == 2)
    }

    // Review Focus 5: names with spaces, and names netstat cut at 16 characters.
    @Test func keepsNamesWithSpacesAndTruncatedNames() {
        #expect(listeners.contains(Listener(port: 7679, pid: 1341, reportedName: "Google Drive")))
        #expect(listeners.contains(Listener(port: 58400, pid: 57295, reportedName: "ASOctaneSupportX")))
    }

    @Test func garbageYieldsNothing() {
        #expect(NetstatSource.parse("").isEmpty)
        #expect(NetstatSource.parse("tcp4 0 0 nonsense LISTEN").isEmpty)
    }
}

@Suite(.serialized)
struct LiveScannerTests {
    @Test func ownSourceFindsARealServer() async throws {
        let server = try TestServer()
        defer { server.stop() }
        try await server.waitUntilListening()
        #expect(try OwnProcessSource().listeners().contains(Listener(port: server.port, pid: server.pid)))
    }

    @Test func netstatSourceFindsARealServer() async throws {
        let server = try TestServer()
        defer { server.stop() }
        try await server.waitUntilListening()
        let found = try NetstatSource().listeners().first { $0.port == server.port }
        #expect(found?.pid == server.pid)
        #expect(found?.reportedName == "nc")
    }

    @Test func ownSourceNeverReportsOtherUsers() throws {
        let me = getuid()
        for listener in try OwnProcessSource().listeners() {
            #expect(ProcessInspector.uid(of: listener.pid) == me)
        }
    }
}
