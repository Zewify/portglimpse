import Darwin
import Foundation
@testable import PortGlimpseCore

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A free TCP port on 127.0.0.1, found by binding to port 0 and reading back what the kernel chose.
func freePort() throws -> UInt16 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw TestError("socket failed") }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
    }
    guard bound == 0 else { throw TestError("bind failed") }
    let named = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    guard named == 0 else { throw TestError("getsockname failed") }
    return UInt16(bigEndian: address.sin_port)
}

/// A real listening process (`nc -l`) in its own temporary folder, for end-to-end tests.
/// `exec` keeps the shell's PID, and a signal ignored before `exec` stays ignored after it.
final class TestServer {
    let port: UInt16
    let directory: URL
    private let process = Process()

    var pid: Int32 { process.processIdentifier }

    init(ignoringTerm: Bool = false) throws {
        port = try freePort()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("portglimpse-server-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let listen = "exec /usr/bin/nc -l \(port)"
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", ignoringTerm ? "trap '' TERM; \(listen)" : listen]
        process.currentDirectoryURL = directory
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    func waitUntilListening(timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try OwnProcessSource().listeners().contains(where: { $0.port == port && $0.pid == pid }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TestError("nothing listened on \(port) within \(timeout)")
    }

    func stop() {
        if process.isRunning { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { stop() }
}
