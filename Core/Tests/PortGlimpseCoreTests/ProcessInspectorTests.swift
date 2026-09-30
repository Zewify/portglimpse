import Darwin
import Foundation
import Testing
@testable import PortGlimpseCore

struct ProcessInspectorTests {
    /// The `KERN_PROCARGS2` layout: argc as Int32, the exec path, NUL padding, then argc strings, then the environment.
    func procArgs(argc: Int32, execPath: String, arguments: [String], environment: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(execPath.utf8) + [0, 0, 0, 0]
        for argument in arguments + environment { bytes += Array(argument.utf8) + [0] }
        return bytes
    }

    @Test func parsesArgumentsAndStopsBeforeTheEnvironment() {
        let bytes = procArgs(argc: 3, execPath: "/usr/local/bin/node", arguments: ["node", "server.js", "--port=3000"], environment: ["HOME=/Users/me"])
        #expect(ProcessInspector.parseProcArgs(bytes) == ["node", "server.js", "--port=3000"])
    }

    @Test func aTruncatedBufferYieldsWhatIsThere() {
        let bytes = procArgs(argc: 5, execPath: "/bin/x", arguments: ["x", "a"], environment: [])
        #expect(ProcessInspector.parseProcArgs(bytes) == ["x", "a"])
    }

    @Test func aTooShortBufferYieldsNothing() {
        #expect(ProcessInspector.parseProcArgs([1, 0]) == [])
    }

    @Test func inspectsThisTestProcess() throws {
        let details = try #require(ProcessInspector.details(pid: getpid()))
        #expect(details.uid == getuid())
        #expect(details.executablePath?.isEmpty == false)
        #expect(details.arguments.isEmpty == false)
        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path
        let actual = details.workingDirectory.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        #expect(actual == expected)
    }

    @Test func aMissingProcessHasNoDetails() {
        #expect(ProcessInspector.details(pid: Int32.max) == nil)
        #expect(ProcessInspector.isRunning(Int32.max) == false)
    }

    @Test func thisProcessIsRunning() {
        #expect(ProcessInspector.isRunning(getpid()))
    }

    @Test func readsTheParentProcess() {
        #expect(ProcessInspector.details(pid: getpid())?.parentPID == getppid())
    }

    @Test func launchdBelongsToRoot() {
        #expect(ProcessInspector.uid(of: 1) == 0)
        #expect(ProcessInspector.userName(for: 0) == "root")
    }
}
