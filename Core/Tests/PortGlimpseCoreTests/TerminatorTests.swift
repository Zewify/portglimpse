import Darwin
import Foundation
import Testing
@testable import PortGlimpseCore

/// A pretend process whose reactions to signals are scripted.
final class FakeProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var alive: Bool
    private var received: [Int32] = []
    let owner: UInt32
    let ignoresTerm: Bool
    let sendError: Int32

    init(owner: UInt32 = 501, alive: Bool = true, ignoresTerm: Bool = false, sendError: Int32 = 0) {
        self.owner = owner
        self.alive = alive
        self.ignoresTerm = ignoresTerm
        self.sendError = sendError
    }

    var signals: [Int32] { lock.withLock { received } }
    var isAlive: Bool { lock.withLock { alive } }

    func receive(_ signal: Int32) -> Int32 {
        lock.withLock {
            received.append(signal)
            if sendError != 0 { return sendError }
            if signal == SIGKILL || (signal == SIGTERM && !ignoresTerm) { alive = false }
            return 0
        }
    }

    func terminator(grace: Duration = .milliseconds(300)) -> Terminator {
        Terminator(
            currentUID: 501,
            grace: grace,
            pollInterval: .milliseconds(20),
            ownerOf: { _ in self.isAlive ? self.owner : nil },
            isAlive: { _ in self.isAlive },
            send: { _, signal in self.receive(signal) }
        )
    }
}

struct TerminatorTests {
    @Test func aProcessThatStopsReportsStopped() async {
        let process = FakeProcess()
        #expect(await process.terminator().stop(42) == .stopped)
        #expect(process.signals == [SIGTERM])
    }

    @Test func aProcessIgnoringTermReportsStillRunning() async {
        let process = FakeProcess(ignoresTerm: true)
        #expect(await process.terminator().stop(42) == .stillRunning)
        #expect(await process.terminator().forceKill(42) == .stopped)
        #expect(process.signals == [SIGTERM, SIGKILL])
    }

    @Test func anotherUsersProcessIsNeverSignalled() async {
        let process = FakeProcess(owner: 0)
        #expect(await process.terminator().stop(1) == .failed("It belongs to another user."))
        #expect(await process.terminator().forceKill(1) == .failed("It belongs to another user."))
        #expect(process.signals.isEmpty)
    }

    // Review Focus 4: a process that already exited gets no signal.
    @Test func anExitedProcessIsNeverSignalled() async {
        let process = FakeProcess(alive: false)
        #expect(await process.terminator().stop(42) == .failed("It has already exited."))
        #expect(process.signals.isEmpty)
    }

    @Test func nonPositivePidsAreNeverSignalled() async {
        let process = FakeProcess()
        #expect(await process.terminator().stop(0) == .failed("It has already exited."))
        #expect(await process.terminator().stop(-1) == .failed("It has already exited."))
        #expect(await process.terminator().forceKill(-1) == .failed("It has already exited."))
        #expect(process.signals.isEmpty)
    }

    @Test func aProcessThatVanishesMidSignalReportsExited() async {
        let process = FakeProcess(sendError: ESRCH)
        #expect(await process.terminator().stop(42) == .failed("It has already exited."))
    }

    @Test func otherSignalErrorsAreReported() async {
        let process = FakeProcess(sendError: EPERM)
        #expect(await process.terminator().stop(42) == .failed(String(cString: strerror(EPERM))))
    }
}

@Suite(.serialized)
struct LiveTerminatorTests {
    @Test func stopsARealServerAndFreesItsPort() async throws {
        let server = try TestServer()
        defer { server.stop() }
        try await server.waitUntilListening()
        #expect(await Terminator.live().stop(server.pid) == .stopped)
        #expect(try !OwnProcessSource().listeners().contains { $0.port == server.port })
    }

    @Test func forceKillsAServerThatIgnoresTerm() async throws {
        let server = try TestServer(ignoringTerm: true)
        defer { server.stop() }
        try await server.waitUntilListening()
        let terminator = Terminator.live(grace: .milliseconds(500))
        #expect(await terminator.stop(server.pid) == .stillRunning)
        #expect(await terminator.forceKill(server.pid) == .stopped)
    }

    @Test(.disabled(if: getuid() == 0, "Signalling PID 1 as root would stop launchd"))
    func refusesLaunchd() async {
        #expect(await Terminator.live().stop(1) == .failed("It belongs to another user."))
    }
}
