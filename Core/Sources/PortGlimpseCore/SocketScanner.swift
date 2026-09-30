import Darwin
import Foundation

public enum ScanError: Error, Equatable {
    case processListUnavailable
    case netstatFailed(Int32)
}

/// Somewhere to find TCP listeners.
public protocol ListenerSource: Sendable {
    func listeners() throws -> [Listener]
}

/// The current user's listeners, read through libproc: public API, and the only source that can also read folders.
public struct OwnProcessSource: ListenerSource {
    public init() {}

    public func listeners() throws -> [Listener] {
        try Self.pids(of: getuid())
            .flatMap { pid in Set(Self.listeningPorts(of: pid)).map { Listener(port: $0, pid: pid) } }
    }

    /// The kernel filters by owner in one call, instead of one `sysctl` per process on the Mac;
    /// that per-process check was nearly all of a scan's CPU time.
    static func pids(of uid: uid_t) throws -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard bytes > 0 else { throw ScanError.processListUnavailable }
        // Room for processes started between the two calls.
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size * 2)
        let filled = proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard filled > 0 else { throw ScanError.processListUnavailable }
        return Array(pids.prefix(Int(filled) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    static func listeningPorts(of pid: Int32) -> [UInt16] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / MemoryLayout<proc_fdinfo>.size)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard filled > 0 else { return [] }
        var ports: [UInt16] = []
        for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            // insi_lport holds the port in network byte order.
            let raw = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.append(UInt16(bigEndian: raw))
        }
        return ports
    }
}

/// Every user's listeners, parsed from `netstat -anv -p tcp`, which names other users' processes without root.
public struct NetstatSource: ListenerSource {
    public init() {}

    public func listeners() throws -> [Listener] {
        try Self.parse(Self.run())
    }

    static func run() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-anv", "-p", "tcp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ScanError.netstatFailed(process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Columns: proto, recv-q, send-q, local, foreign, state, then four numbers, then `name:pid`,
    /// where the name may contain spaces. The port is whatever follows the local address's last dot.
    public static func parse(_ output: String) -> [Listener] {
        var listeners: [Listener] = []
        for line in output.split(separator: "\n") {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count > 10, tokens[0].hasPrefix("tcp"), tokens[5] == "LISTEN",
                  let dot = tokens[3].lastIndex(of: "."),
                  let port = UInt16(tokens[3][tokens[3].index(after: dot)...]) else { continue }
            var nameParts: [String] = []
            for token in tokens[10...] {
                if let colon = token.lastIndex(of: ":"), let pid = Int32(token[token.index(after: colon)...]) {
                    nameParts.append(String(token[..<colon]))
                    listeners.append(Listener(port: port, pid: pid, reportedName: nameParts.joined(separator: " ")))
                    break
                }
                nameParts.append(token)
            }
        }
        return listeners
    }
}
