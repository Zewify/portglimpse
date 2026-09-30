import Darwin
import Foundation

/// Reads one process's details straight from the kernel: libproc and sysctl, never `ps` or `lsof`.
public enum ProcessInspector {
    /// `SZOMB` in `<sys/proc.h>`: a process that has exited but not been reaped.
    static let zombieState: Int32 = 5

    /// Nil when the process does not exist. Other fields stay nil or empty when the kernel refuses them,
    /// which it does for other users' paths and arguments.
    public static func details(pid: Int32) -> ProcessDetails? {
        guard let uid = uid(of: pid) else { return nil }
        return ProcessDetails(
            executablePath: executablePath(of: pid),
            arguments: arguments(of: pid),
            workingDirectory: workingDirectory(of: pid),
            uid: uid
        )
    }

    public static func uid(of pid: Int32) -> UInt32? {
        kinfo(of: pid).map { $0.kp_eproc.e_ucred.cr_uid }
    }

    public static func isRunning(_ pid: Int32) -> Bool {
        guard let info = kinfo(of: pid) else { return false }
        return Int32(info.kp_proc.p_stat) != zombieState
    }

    public static func userName(for uid: UInt32) -> String {
        // `getpwuid` returns process-global storage, and scans run concurrently, so use the reentrant form.
        let suggested = sysconf(_SC_GETPW_R_SIZE_MAX)
        var buffer = [CChar](repeating: 0, count: suggested > 0 ? suggested : 4096)
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwuid_r(uid, &entry, &buffer, buffer.count, &result) == 0, result != nil, let name = entry.pw_name else {
            return String(uid)
        }
        return String(cString: name)
    }

    static func kinfo(of pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info
    }

    static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    static func arguments(of pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    /// `KERN_PROCARGS2`: argc (Int32), the exec path, NUL padding, then argc NUL-terminated arguments.
    static func parseProcArgs(_ bytes: [UInt8]) -> [String] {
        guard bytes.count >= 4 else { return [] }
        let argc = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = 4
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
