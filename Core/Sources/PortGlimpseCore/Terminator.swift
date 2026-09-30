import Darwin
import Foundation

public enum KillOutcome: Equatable, Sendable {
    case stopped
    /// Still alive when the grace period ended; the panel offers Force kill.
    case stillRunning
    case failed(String)
}

/// Sends a signal and watches for the process to exit.
/// It refuses processes owned by other users, whatever the caller asks.
public struct Terminator: Sendable {
    public var currentUID: UInt32
    public var grace: Duration
    public var pollInterval: Duration
    public var ownerOf: @Sendable (Int32) -> UInt32?
    public var isAlive: @Sendable (Int32) -> Bool
    /// Returns 0 on success, otherwise the errno.
    public var send: @Sendable (Int32, Int32) -> Int32

    public init(
        currentUID: UInt32,
        grace: Duration,
        pollInterval: Duration,
        ownerOf: @escaping @Sendable (Int32) -> UInt32?,
        isAlive: @escaping @Sendable (Int32) -> Bool,
        send: @escaping @Sendable (Int32, Int32) -> Int32
    ) {
        self.currentUID = currentUID
        self.grace = grace
        self.pollInterval = pollInterval
        self.ownerOf = ownerOf
        self.isAlive = isAlive
        self.send = send
    }

    public static func live(grace: Duration = .seconds(3)) -> Terminator {
        Terminator(
            currentUID: getuid(),
            grace: grace,
            pollInterval: .milliseconds(100),
            ownerOf: { ProcessInspector.uid(of: $0) },
            isAlive: { ProcessInspector.isRunning($0) },
            send: { pid, signal in kill(pid, signal) == 0 ? 0 : errno }
        )
    }

    public func stop(_ pid: Int32) async -> KillOutcome {
        await deliver(SIGTERM, to: pid)
    }

    public func forceKill(_ pid: Int32) async -> KillOutcome {
        await deliver(SIGKILL, to: pid)
    }

    func deliver(_ signal: Int32, to pid: Int32) async -> KillOutcome {
        guard let owner = ownerOf(pid), isAlive(pid) else { return .failed("It has already exited.") }
        guard owner == currentUID else { return .failed("It belongs to another user.") }
        let error = send(pid, signal)
        if error == ESRCH { return .failed("It has already exited.") }
        if error != 0 { return .failed(String(cString: strerror(error))) }
        let deadline = ContinuousClock.now + grace
        while ContinuousClock.now < deadline {
            if !isAlive(pid) { return .stopped }
            try? await Task.sleep(for: pollInterval)
        }
        return isAlive(pid) ? .stillRunning : .stopped
    }
}
