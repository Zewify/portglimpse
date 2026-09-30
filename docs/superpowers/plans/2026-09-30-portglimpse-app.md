# PortGlimpse App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build PortGlimpse 1.0 as a working, locally installable Mac menu bar app: it lists listening ports with their project folder, sorts them into Dev servers, Apps & system and Other users, kills a process only after confirmation, and can pop the list out into an always-on-top window.

**Architecture:** A `PortGlimpseCore` Swift package (Foundation and Darwin only) holds every rule: scanning sockets, inspecting processes, labelling commands, classifying, overrides, the kill flow and version comparison.
A thin SwiftUI app (`MenuBarExtra` in window style) polls the Core while its panel is open and renders the design from the canvas.
The layout mirrors TickThock: XcodeGen `project.yml`, a generated and gitignored `.xcodeproj`, and `scripts/` for test, build and local install.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ServiceManagement, swift-testing (`import Testing`), XcodeGen, libproc and sysctl.

**Spec:** `docs/superpowers/specs/2026-09-30-portglimpse-design.md` — read it before starting any task.

**Not in this plan:** the GitHub Actions release workflow, Developer ID signing and notarization, `install.sh`, and the zewify.com page.
Those form the second plan, written once the Developer ID certificate exists.

## Global Constraints

- Minimum macOS 14.0; Swift language mode 6.0; Apple silicon and Intel.
- Bundle ID `com.zewify.portglimpse`; product name `PortGlimpse`; marketing version `1.0.0`, build `1`.
- No App Sandbox; Hardened Runtime on; no entitlements file.
- No third-party dependencies anywhere.
- The Core imports only Foundation and Darwin, never AppKit or SwiftUI.
- Never run `lsof`; the only external tool is `/usr/sbin/netstat`, for "Show all".
- Kill always asks first; the Core refuses to signal a process owned by another user.
- Colours: page `#16130f`, panel `#201b17`, raised `#2a241f`, text `#f6ede3`, soft text `#d8cbbd`, muted `#a8998a`, lines `#342c25` / `#4a3f35`, amber `#f48e48`, amber face `#ffb067 → #ee8237`, text on amber `#1b1815`, amber tint `#2c211a` / `#4d3424`, keycap `#2e2721`, keycap ink `#e9ddd0`.
- Fonts: Bricolage Grotesque (title), Figtree (text), IBM Plex Mono (ports), bundled with their OFL licences.
- The panel is always dark, regardless of the system appearance.
- Zewify rule: nothing in the app, repo, commits or docs may name or identify the person who builds it — no names, handles, personal links or emails.
- Commits use the repo's configured author `Zewify <335855398+Zewify@users.noreply.github.com>`; never pass `--author` or change `user.name` / `user.email`, and add no co-author trailers.
- Markdown docs put each full sentence on its own line.

## Review Focus

1. A Python dev server's executable lives inside `Python.app` (Command Line Tools or Xcode's copy), yet it must be classified as a dev server, not an app — Task 2 pins it.
2. A process that exits between the socket scan and the process inspection must be dropped from the list without crashing — Task 6 pins it.
3. A server listening on the same port over IPv4 and IPv6 must show that port once — Task 6 pins it.
4. Killing a process that has already exited must report "It has already exited." and send no signal — Task 7 pins it.
5. `netstat` prints names that contain spaces (`Google Drive:1341`) or are cut at 16 characters (`ASOctaneSupportX`), and the parser must keep them intact — Task 5 pins it.

---

## File Structure

```
portglimpse/
  .gitignore
  CLAUDE.md                              repo rules for agents (Task 1, extended in Task 9)
  README.md                              what it is, how to build (Task 13)
  project.yml                            XcodeGen spec (Task 9)
  scripts/
    test.sh                              core tests, then app build (Task 1, extended in Task 9)
    build.sh                             generate + build, prints the .app path (Task 9)
    install-local.sh                     Release build copied to /Applications and launched (Task 9)
    make-icon.swift                      renders AppIcon.appiconset (Task 9)
  Core/
    Package.swift
    Sources/PortGlimpseCore/
      Models.swift                       Listener, Section, Placement, ProcessDetails, Row
      Runtimes.swift                     which executables are language runtimes
      CommandLabel.swift                 arguments -> short command ("next dev")
      Classifier.swift                   process -> Section
      OverrideStore.swift                right-click overrides, JSON on disk
      ProcessInspector.swift             libproc/sysctl reads for one PID
      SocketScanner.swift                ListenerSource, OwnProcessSource, NetstatSource
      Snapshot.swift                     SnapshotBuilder, ScanResult, PortScan
      Terminator.swift                   KillOutcome, the SIGTERM -> wait -> SIGKILL flow
      AppVersion.swift                   AppVersion, ReleaseFeed
    Tests/PortGlimpseCoreTests/
      CommandLabelTests.swift
      ClassifierTests.swift
      OverrideStoreTests.swift
      ProcessInspectorTests.swift
      SocketScannerTests.swift
      SnapshotTests.swift
      TerminatorTests.swift
      AppVersionTests.swift
      Support/TestServer.swift           spawns a real listening process
      Fixtures/netstat-listen.txt        a real `netstat -anv -p tcp` capture
  App/
    Signing.xcconfig
    Sources/
      PortGlimpseApp.swift                  @main, AppDelegate
      Theme.swift                        colours, fonts, button style
      MenuBarLabel.swift                 keycap glyph + count
      PanelModel.swift                   polling, row phases, actions
      PanelWindowObserver.swift          open/close detection for the panel window
      PanelView.swift                    the menu bar panel and LiveBadge
      PortList.swift                     the three sections, shared by panel and window
      RowView.swift                      one row in every phase
      LoginItem.swift                    SMAppService wrapper
      FloatingWindow.swift               the always-on-top pop-out window and its drag handle
      WindowView.swift                   the window's content, compact below 360 points
      UpdateChecker.swift                daily GitHub release check
    Resources/
      Assets.xcassets/                   AppIcon
      Fonts/                             TTFs + OFL licences
```

---

### Task 1: Core package, models and command labels

**Files:**
- Create: `.gitignore`, `CLAUDE.md`, `scripts/test.sh`
- Create: `Core/Package.swift`
- Create: `Core/Sources/PortGlimpseCore/Models.swift`, `Core/Sources/PortGlimpseCore/Runtimes.swift`, `Core/Sources/PortGlimpseCore/CommandLabel.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/CommandLabelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct Listener: Hashable, Sendable { port: UInt16; pid: Int32; reportedName: String? }` with `init(port:pid:reportedName: = nil)`.
  - `public enum Section: String, Codable, Sendable, CaseIterable { case dev, appsAndSystem, otherUsers }` with `var order: Int`.
  - `public enum Placement: String, Codable, Sendable { case dev, appsAndSystem }` with `var section: Section`.
  - `public struct ProcessDetails: Equatable, Sendable { executablePath: String?; arguments: [String]; workingDirectory: String?; uid: UInt32? }`.
  - `public struct Row: Identifiable, Equatable, Sendable { pid: Int32; ports: [UInt16]; command: String; folder: String?; owner: String?; section: Section; executablePath: String? }`, `id == pid`.
  - `public enum Runtimes { static func isRuntime(_ executableName: String) -> Bool }`.
  - `public enum CommandLabel { static func label(arguments: [String], fallbackName: String) -> String }`.

- [ ] **Step 1: Create the repo scaffolding**

`.gitignore`:

```
.DS_Store
.build/
.swiftpm/
DerivedData/
build/
*.xcodeproj/
*.xcworkspace/
xcuserdata/
# Local signing overrides, never committed
Signing.local.xcconfig
```

`CLAUDE.md`:

```markdown
# PortGlimpse

A free Mac menu bar app that lists listening ports with their project folder and kills a process after confirmation; a Zewify product.
Design: `docs/superpowers/specs/2026-09-30-portglimpse-design.md`. Plan: `docs/superpowers/plans/2026-09-30-portglimpse-app.md`.

## Layout

- `Core/` — the `PortGlimpseCore` Swift package: every rule, Foundation and Darwin only.
- `App/` — the thin SwiftUI menu bar app.

## Commands

- `./scripts/test.sh` — core tests, then an app build. Run before every commit; the exit code is the verdict.

## Rules that are not obvious

- Zewify rule: nothing in the app, repo, commits or docs may identify the person who builds it.
- Commits use the repo's configured author (`Zewify`); never override it and never add co-author trailers.
- The Core never imports AppKit or SwiftUI.
- Never run `lsof`; "Show all" reads `/usr/sbin/netstat -anv -p tcp`.
- The Core refuses to signal a process owned by another user, whatever the UI asks.
```

`scripts/test.sh` (made executable with `chmod +x scripts/test.sh`):

```bash
#!/usr/bin/env bash
# Runs the core tests. Task 9 adds the app build.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd Core && swift test --quiet)
```

`Core/Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PortGlimpseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortGlimpseCore", targets: ["PortGlimpseCore"]),
    ],
    targets: [
        // Every rule the app follows: scanning, inspecting, labelling, classifying,
        // overrides, the kill flow and version comparison. Foundation and Darwin only.
        .target(name: "PortGlimpseCore"),
        .testTarget(name: "PortGlimpseCoreTests", dependencies: ["PortGlimpseCore"]),
    ]
)
```

- [ ] **Step 2: Write the models and runtimes**

`Core/Sources/PortGlimpseCore/Models.swift`:

```swift
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
```

`Core/Sources/PortGlimpseCore/Runtimes.swift`:

```swift
import Foundation

/// Interpreters and VMs that run a developer's code, so their own name says little about what is running.
public enum Runtimes {
    static let names: Set<String> = ["node", "bun", "deno", "ruby", "php", "java", "python", "python3"]

    /// Case-insensitive, so the `Python` executable inside `Python.app` counts.
    public static func isRuntime(_ executableName: String) -> Bool {
        let name = executableName.lowercased()
        return names.contains(name) || name.hasPrefix("python3.")
    }
}
```

- [ ] **Step 3: Write the failing command label tests**

`Core/Tests/PortGlimpseCoreTests/CommandLabelTests.swift`:

```swift
import Testing
@testable import PortGlimpseCore

struct CommandLabelTests {
    func label(_ arguments: [String], fallback: String = "fallback") -> String {
        CommandLabel.label(arguments: arguments, fallbackName: fallback)
    }

    @Test func nextThroughTheBinShim() {
        #expect(label(["node", "/Users/me/financy/node_modules/.bin/next", "dev"]) == "next dev")
    }

    @Test func nextThroughItsPackage() {
        #expect(label(["node", "/Users/me/app/node_modules/next/dist/bin/next", "dev"]) == "next dev")
    }

    @Test func scopedPackageUsesThePackageName() {
        #expect(label(["node", "/x/node_modules/@vue/cli-service/bin/vue-cli-service.js", "serve"]) == "cli-service serve")
    }

    @Test func viteWithAFullRuntimePath() {
        #expect(label(["/usr/local/bin/node", "/Users/me/dota/node_modules/vite/bin/vite.js"]) == "vite")
    }

    @Test func pythonModule() {
        #expect(label(["python3", "-m", "http.server", "8000"]) == "http.server")
    }

    @Test func pythonScriptWithSubcommand() {
        #expect(label(["/usr/bin/python3", "manage.py", "runserver"]) == "manage.py runserver")
    }

    @Test func capitalisedPythonFromPythonApp() {
        #expect(label(["/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", "-m", "uvicorn"]) == "uvicorn")
    }

    @Test func runtimeFlagsAreSkipped() {
        #expect(label(["node", "--inspect", "server.js"]) == "server.js")
    }

    @Test func runtimeWithSubcommands() {
        #expect(label(["bun", "run", "dev"]) == "bun run dev")
    }

    @Test func plainBinaryIsItsName() {
        #expect(label(["/opt/homebrew/opt/redis/bin/redis-server", "127.0.0.1:6379"]) == "redis-server")
    }

    @Test func noArgumentsUsesTheFallback() {
        #expect(label([], fallback: "mysqld") == "mysqld")
    }

    @Test func longLabelsAreTruncated() {
        let long = String(repeating: "a", count: 60)
        let result = label(["/bin/\(long)"])
        #expect(result.count == 40)
        #expect(result.hasSuffix("…"))
    }
}
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `cd Core && swift test --filter CommandLabelTests`
Expected: compile failure, `cannot find 'CommandLabel' in scope`.

- [ ] **Step 5: Implement `CommandLabel`**

`Core/Sources/PortGlimpseCore/CommandLabel.swift`:

```swift
import Foundation

/// Turns a process's arguments into the short command a row shows: `next dev`, not `node`.
public enum CommandLabel {
    static let maxLength = 40
    static let scriptSuffixes = [".js", ".mjs", ".cjs", ".ts", ".py", ".rb", ".php", ".jar"]

    public static func label(arguments: [String], fallbackName: String) -> String {
        guard let first = arguments.first, !first.isEmpty else { return truncate(fallbackName) }
        let executable = baseName(first)
        guard Runtimes.isRuntime(executable) else { return truncate(executable) }

        let rest = Array(arguments.dropFirst())
        if let flag = rest.firstIndex(of: "-m"), flag + 1 < rest.count {
            return truncate(rest[flag + 1])
        }
        let words = rest.filter { !$0.hasPrefix("-") }
        guard let target = words.first else { return truncate(executable) }
        if looksLikeScript(target) {
            let subcommand = words.dropFirst().first.map { " " + $0 } ?? ""
            return truncate(toolName(fromScript: target) + subcommand)
        }
        return truncate(([executable] + words.prefix(2)).joined(separator: " "))
    }

    static func looksLikeScript(_ word: String) -> Bool {
        word.contains("/") || scriptSuffixes.contains { word.hasSuffix($0) }
    }

    /// `…/node_modules/.bin/next` and `…/node_modules/next/dist/bin/next` both name the tool `next`.
    static func toolName(fromScript path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let index = parts.lastIndex(of: "node_modules"), index + 1 < parts.count {
            let package = parts[index + 1]
            if (package == ".bin" || package.hasPrefix("@")), index + 2 < parts.count {
                return parts[index + 2]
            }
            return package
        }
        return baseName(path)
    }

    static func baseName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func truncate(_ text: String) -> String {
        text.count <= maxLength ? text : String(text.prefix(maxLength - 1)) + "…"
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `cd Core && swift test --filter CommandLabelTests`
Expected: all 12 tests pass.

- [ ] **Step 7: Commit**

```bash
chmod +x scripts/test.sh
./scripts/test.sh
git add .gitignore CLAUDE.md scripts/test.sh Core
git commit -m "Add the Core package with models and command labels"
```

---

### Task 2: Classifier

**Files:**
- Create: `Core/Sources/PortGlimpseCore/Classifier.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/ClassifierTests.swift`

**Interfaces:**
- Consumes: `ProcessDetails`, `Section`, `Placement`, `Runtimes.isRuntime` from Task 1.
- Produces:
  - `public struct Classifier: Sendable { init(currentUID: UInt32, overrides: [String: Placement]); func section(for: ProcessDetails) -> Section }`.
  - `public static func appBundle(containing executablePath: String) -> String?` on `Classifier`: the outermost `.app` bundle path, or nil.

- [ ] **Step 1: Write the failing tests**

`Core/Tests/PortGlimpseCoreTests/ClassifierTests.swift`:

```swift
import Testing
@testable import PortGlimpseCore

struct ClassifierTests {
    let me: UInt32 = 501

    func section(_ path: String?, uid: UInt32? = 501, overrides: [String: Placement] = [:]) -> Section {
        Classifier(currentUID: me, overrides: overrides).section(for: ProcessDetails(executablePath: path, uid: uid))
    }

    @Test func anotherUsersProcessIsOtherUsers() {
        #expect(section("/usr/local/bin/node", uid: 0) == .otherUsers)
    }

    @Test func unknownOwnerIsOtherUsers() {
        #expect(section("/usr/local/bin/node", uid: nil) == .otherUsers)
    }

    @Test func nodeIsDev() {
        #expect(section("/usr/local/bin/node") == .dev)
    }

    @Test func homebrewServerIsDev() {
        #expect(section("/opt/homebrew/Cellar/redis/7.2.4/bin/redis-server") == .dev)
    }

    @Test func applicationIsAppsAndSystem() {
        #expect(section("/Applications/DBeaver.app/Contents/MacOS/dbeaver") == .appsAndSystem)
    }

    @Test func helperNestedInAnAppIsAppsAndSystem() {
        #expect(section("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/130.0/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper") == .appsAndSystem)
    }

    @Test func systemServicesAreAppsAndSystem() {
        #expect(section("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter") == .appsAndSystem)
        #expect(section("/usr/libexec/rapportd") == .appsAndSystem)
        #expect(section("/usr/sbin/cupsd") == .appsAndSystem)
    }

    // Review Focus 1: Python's executable lives inside Python.app, but a Python server is a dev server.
    @Test func commandLineToolsPythonIsDev() {
        #expect(section("/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python") == .dev)
    }

    @Test func xcodePythonIsDev() {
        #expect(section("/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python") == .dev)
    }

    @Test func missingPathIsAppsAndSystem() {
        #expect(section(nil) == .appsAndSystem)
    }

    @Test func overridesWinOverTheRule() {
        let dbeaver = "/Applications/DBeaver.app/Contents/MacOS/dbeaver"
        #expect(section(dbeaver, overrides: [dbeaver: .dev]) == .dev)
        #expect(section("/usr/local/bin/node", overrides: ["/usr/local/bin/node": .appsAndSystem]) == .appsAndSystem)
    }

    @Test func overridesNeverApplyToOtherUsers() {
        #expect(section("/usr/local/bin/node", uid: 0, overrides: ["/usr/local/bin/node": .dev]) == .otherUsers)
    }

    @Test func appBundleIsTheOutermostApp() {
        #expect(Classifier.appBundle(containing: "/Applications/DBeaver.app/Contents/MacOS/dbeaver") == "/Applications/DBeaver.app")
        #expect(Classifier.appBundle(containing: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Helper.app/Contents/MacOS/Helper") == "/Applications/Google Chrome.app")
        #expect(Classifier.appBundle(containing: "/usr/local/bin/node") == nil)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Core && swift test --filter ClassifierTests`
Expected: compile failure, `cannot find 'Classifier' in scope`.

- [ ] **Step 3: Implement `Classifier`**

`Core/Sources/PortGlimpseCore/Classifier.swift`:

```swift
import Foundation

/// Decides which section a process belongs in.
public struct Classifier: Sendable {
    public let currentUID: UInt32
    /// Right-click overrides, keyed by executable path.
    public let overrides: [String: Placement]

    static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]

    public init(currentUID: UInt32, overrides: [String: Placement]) {
        self.currentUID = currentUID
        self.overrides = overrides
    }

    /// Order matters: ownership, then overrides, then runtimes (Python runs from inside `Python.app`),
    /// then macOS's own folders, then app bundles; anything left is a dev server.
    public func section(for details: ProcessDetails) -> Section {
        guard let uid = details.uid, uid == currentUID else { return .otherUsers }
        guard let path = details.executablePath else { return .appsAndSystem }
        if let placement = overrides[path] { return placement.section }
        if Runtimes.isRuntime((path as NSString).lastPathComponent) { return .dev }
        if Self.systemPrefixes.contains(where: { path.hasPrefix($0) }) { return .appsAndSystem }
        if Self.appBundle(containing: path) != nil { return .appsAndSystem }
        return .dev
    }

    /// The outermost `.app` bundle an executable lives in, or nil when it is not inside one.
    public static func appBundle(containing executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Core && swift test --filter ClassifierTests`
Expected: all 13 tests pass.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Classify processes into dev, apps and other users"
```

---

### Task 3: Override store

**Files:**
- Create: `Core/Sources/PortGlimpseCore/OverrideStore.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/OverrideStoreTests.swift`

**Interfaces:**
- Consumes: `Placement` from Task 1.
- Produces: `public final class OverrideStore { static var defaultURL: URL; init(fileURL: URL); private(set) var overrides: [String: Placement]; func set(_ placement: Placement?, for executablePath: String) throws }`.

- [ ] **Step 1: Write the failing tests**

`Core/Tests/PortGlimpseCoreTests/OverrideStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import PortGlimpseCore

struct OverrideStoreTests {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("portglimpse-overrides-\(UUID().uuidString)")
        .appendingPathComponent("nested/overrides.json")

    @Test func startsEmptyWhenNoFileExists() {
        #expect(OverrideStore(fileURL: file).overrides.isEmpty)
    }

    @Test func savedOverridesSurviveAReload() throws {
        let store = OverrideStore(fileURL: file)
        try store.set(.dev, for: "/Applications/Postgres.app/Contents/MacOS/postgres")
        try store.set(.appsAndSystem, for: "/usr/local/bin/node")
        let reloaded = OverrideStore(fileURL: file)
        #expect(reloaded.overrides == [
            "/Applications/Postgres.app/Contents/MacOS/postgres": .dev,
            "/usr/local/bin/node": .appsAndSystem,
        ])
    }

    @Test func settingNilRemovesTheOverride() throws {
        let store = OverrideStore(fileURL: file)
        try store.set(.dev, for: "/a")
        try store.set(nil, for: "/a")
        #expect(store.overrides.isEmpty)
        #expect(OverrideStore(fileURL: file).overrides.isEmpty)
    }

    @Test func aCorruptFileIsTreatedAsEmpty() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(OverrideStore(fileURL: file).overrides.isEmpty)
    }

    @Test func defaultLocationIsApplicationSupport() {
        #expect(OverrideStore.defaultURL.path.hasSuffix("Library/Application Support/PortGlimpse/overrides.json"))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Core && swift test --filter OverrideStoreTests`
Expected: compile failure, `cannot find 'OverrideStore' in scope`.

- [ ] **Step 3: Implement `OverrideStore`**

`Core/Sources/PortGlimpseCore/OverrideStore.swift`:

```swift
import Foundation

/// Right-click overrides ("Always show as dev"), stored as JSON keyed by executable path.
public final class OverrideStore {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortGlimpse/overrides.json")
    }

    public let fileURL: URL
    public private(set) var overrides: [String: Placement]

    /// A missing or unreadable file means no overrides; it is rewritten on the next change.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        overrides = data.flatMap { try? JSONDecoder().decode([String: Placement].self, from: $0) } ?? [:]
    }

    /// Nil removes the override, returning the process to automatic placement.
    public func set(_ placement: Placement?, for executablePath: String) throws {
        overrides[executablePath] = placement
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(overrides).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Core && swift test --filter OverrideStoreTests`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Persist right-click overrides"
```

---

### Task 4: Process inspector

**Files:**
- Create: `Core/Sources/PortGlimpseCore/ProcessInspector.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/ProcessInspectorTests.swift`

**Interfaces:**
- Consumes: `ProcessDetails` from Task 1.
- Produces: `public enum ProcessInspector` with
  - `static func details(pid: Int32) -> ProcessDetails?` — nil when the process does not exist.
  - `static func uid(of pid: Int32) -> UInt32?`
  - `static func isRunning(_ pid: Int32) -> Bool` — false for exited and zombie processes.
  - `static func userName(for uid: UInt32) -> String` — the account name, or the number as text.
  - `static func parseProcArgs(_ bytes: [UInt8]) -> [String]` (internal, tested directly).

- [ ] **Step 1: Write the failing tests**

`Core/Tests/PortGlimpseCoreTests/ProcessInspectorTests.swift`:

```swift
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

    @Test func launchdBelongsToRoot() {
        #expect(ProcessInspector.uid(of: 1) == 0)
        #expect(ProcessInspector.userName(for: 0) == "root")
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Core && swift test --filter ProcessInspectorTests`
Expected: compile failure, `cannot find 'ProcessInspector' in scope`.

- [ ] **Step 3: Implement `ProcessInspector`**

`Core/Sources/PortGlimpseCore/ProcessInspector.swift`:

```swift
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
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return String(uid) }
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
        return length > 0 ? String(cString: buffer) : nil
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Core && swift test --filter ProcessInspectorTests`
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Inspect a process's path, arguments, folder and owner"
```

---

### Task 5: Socket scanner

**Files:**
- Modify: `Core/Package.swift` (test target gains resources)
- Create: `Core/Sources/PortGlimpseCore/SocketScanner.swift`
- Create: `Core/Tests/PortGlimpseCoreTests/Fixtures/netstat-listen.txt`, `Core/Tests/PortGlimpseCoreTests/Support/TestServer.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/SocketScannerTests.swift`

**Interfaces:**
- Consumes: `Listener` from Task 1, `ProcessInspector.uid(of:)` from Task 4.
- Produces:
  - `public protocol ListenerSource: Sendable { func listeners() throws -> [Listener] }`.
  - `public struct OwnProcessSource: ListenerSource` — the current user's listeners via libproc; throws `ScanError.processListUnavailable`.
  - `public struct NetstatSource: ListenerSource` — every user's listeners via `netstat`; `static func parse(_ output: String) -> [Listener]`; throws `ScanError.netstatFailed(Int32)`.
  - `public enum ScanError: Error, Equatable { case processListUnavailable, netstatFailed(Int32) }`.
  - Test support (tests only): `final class TestServer { init(ignoringTerm: Bool = false) throws; port: UInt16; pid: Int32; directory: URL; func waitUntilListening() async throws; func stop() }`.

- [ ] **Step 1: Add the fixture and the test resources**

In `Core/Package.swift`, change the test target to:

```swift
        .testTarget(name: "PortGlimpseCoreTests", dependencies: ["PortGlimpseCore"], resources: [.copy("Fixtures")]),
```

`Core/Tests/PortGlimpseCoreTests/Fixtures/netstat-listen.txt` — a real capture from macOS 26 (keep the spacing exactly):

```
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address                                 Foreign Address                               (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
tcp4       0      0  127.0.0.1.3306         127.0.0.1.52011        ESTABLISHED         1024         2048  408300  146988           mysqld:1441   00102 00000106 0000000000003d01 00000000 00000800      1      0 000000
tcp46      0      0  *.38123                *.*                    LISTEN                 0            0  131072  131072             node:59043  00100 00000106 000000000081eda0 00000001 00000800      1      0 000000
tcp4       0      0  127.0.0.1.58400        *.*                    LISTEN                 0            0  131072  131072 ASOctaneSupportX:57295  00100 00000006 00000000007f0897 00000001 00000800      1      0 000000
tcp4       0      0  127.0.0.1.17030        *.*                    LISTEN                 0            0  131072  131072          dbeaver:99011  00000 00000006 0000000000797df5 00000000 00002800      2      0 000000
tcp4       0      0  127.0.0.1.3306         *.*                    LISTEN                 0            0  131072  131072           mysqld:1441   00100 00000006 0000000000003cff 00000000 00000800      1      0 000000
tcp4       0      0  127.0.0.1.33060        *.*                    LISTEN                 0            0  131072  131072           mysqld:1441   00000 00000006 0000000000003cf1 00000000 00000800      1      0 000000
tcp6       0      0  ::1.7679               *.*                    LISTEN                 0            0  131072  131072     Google Drive:1341   00100 00000006 0000000000002bff 00000001 00000800      1      0 000000
tcp6       0      0  *.43257                *.*                    LISTEN                 0            0  131072  131072 io.tailscale.ipn:1233   00180 00000006 0000000000002b2d 00000000 00000800      1      0 000000
tcp4       0      0  *.55614                *.*                    LISTEN                 0            0  131072  131072 io.tailscale.ipn:1233   00180 00000006 0000000000002b28 00000000 00000800      1      0 000000
tcp6       0      0  ::1.6379               *.*                    LISTEN                 0            0  131072  131072     redis-server:1168   00100 00000006 0000000000002302 00000000 00000800      1      0 000000
tcp4       0      0  127.0.0.1.6379         *.*                    LISTEN                 0            0  131072  131072     redis-server:1168   00100 00000006 00000000000022fe 00000000 00000800      1      0 000000
tcp6       0      0  *.5000                 *.*                    LISTEN                 0            0  131072  131072    ControlCenter:724    00100 00000006 0000000000001616 00000001 00000800      1      0 000000
tcp4       0      0  *.5000                 *.*                    LISTEN                 0            0  131072  131072    ControlCenter:724    00100 00000006 0000000000001615 00000001 00000800      1      0 000000
tcp4       0      0  127.0.0.1.8021         *.*                    LISTEN                 0            0  131072  131072          launchd:1      00180 00000006 0000000000000dc6 00000000 00000800      1      0 000000
tcp6       0      0  ::1.8021               *.*                    LISTEN                 0            0  131072  131072          launchd:1      00180 00000006 0000000000000dc5 00000000 00000800      1      0 000000
```

- [ ] **Step 2: Write the test server helper**

`Core/Tests/PortGlimpseCoreTests/Support/TestServer.swift`:

```swift
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
```

- [ ] **Step 3: Write the failing scanner tests**

`Core/Tests/PortGlimpseCoreTests/SocketScannerTests.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `cd Core && swift test --filter "NetstatParsingTests|LiveScannerTests"`
Expected: compile failure, `cannot find 'NetstatSource' in scope`.

- [ ] **Step 5: Implement the scanner**

`Core/Sources/PortGlimpseCore/SocketScanner.swift`:

```swift
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
        let me = getuid()
        return try Self.allPIDs()
            .filter { ProcessInspector.uid(of: $0) == me }
            .flatMap { pid in Set(Self.listeningPorts(of: pid)).map { Listener(port: $0, pid: pid) } }
    }

    static func allPIDs() throws -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { throw ScanError.processListUnavailable }
        var pids = [Int32](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard filled > 0 else { throw ScanError.processListUnavailable }
        return Array(pids.prefix(Int(filled))).filter { $0 > 0 }
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
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `cd Core && swift test --filter "NetstatParsingTests|LiveScannerTests"`
Expected: all 8 tests pass.
If `netstatSourceFindsARealServer` reports a name other than `nc`, print `found` and check the real `netstat -anv -p tcp` output before changing the parser.

- [ ] **Step 7: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Scan listening sockets through libproc and netstat"
```

---

### Task 6: Snapshot builder and the live scan

**Files:**
- Create: `Core/Sources/PortGlimpseCore/Snapshot.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `Listener`, `Row`, `Section`, `ProcessDetails`, `Placement` (Task 1); `CommandLabel` (Task 1); `Classifier` (Task 2); `ProcessInspector` (Task 4); `OwnProcessSource`, `NetstatSource` (Task 5).
- Produces:
  - `public struct SnapshotBuilder: Sendable { init(classifier:home:inspect:userName:); func rows(own: [Listener], all: [Listener]?) -> [Row]; static func live(overrides: [String: Placement]) -> SnapshotBuilder }`.
  - `public struct ScanResult: Sendable, Equatable { rows: [Row]; problem: String?; otherUsersProblem: String? }`.
  - `public enum PortScan { static func run(showAll: Bool, overrides: [String: Placement]) -> ScanResult }`.

- [ ] **Step 1: Write the failing tests**

`Core/Tests/PortGlimpseCoreTests/SnapshotTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Core && swift test --filter "SnapshotTests|LiveScanTests"`
Expected: compile failure, `cannot find 'SnapshotBuilder' in scope`.

- [ ] **Step 3: Implement the snapshot**

`Core/Sources/PortGlimpseCore/Snapshot.swift`:

```swift
import Darwin
import Foundation

/// Turns raw listeners into the ordered rows the panel shows.
public struct SnapshotBuilder: Sendable {
    public var classifier: Classifier
    public var home: String
    public var inspect: @Sendable (Int32) -> ProcessDetails?
    public var userName: @Sendable (UInt32) -> String

    public init(classifier: Classifier, home: String, inspect: @escaping @Sendable (Int32) -> ProcessDetails?, userName: @escaping @Sendable (UInt32) -> String) {
        self.classifier = classifier
        self.home = home
        self.inspect = inspect
        self.userName = userName
    }

    public static func live(overrides: [String: Placement]) -> SnapshotBuilder {
        SnapshotBuilder(
            classifier: Classifier(currentUID: getuid(), overrides: overrides),
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            inspect: { ProcessInspector.details(pid: $0) },
            userName: { ProcessInspector.userName(for: $0) }
        )
    }

    /// `own` comes from libproc; `all` (from netstat) is nil unless "Show all" is on,
    /// and contributes only processes `own` did not already cover.
    public func rows(own: [Listener], all: [Listener]?) -> [Row] {
        var ports: [Int32: Set<UInt16>] = [:]
        var names: [Int32: String] = [:]
        for listener in own { ports[listener.pid, default: []].insert(listener.port) }
        let ownPIDs = Set(ports.keys)
        for listener in all ?? [] where !ownPIDs.contains(listener.pid) {
            ports[listener.pid, default: []].insert(listener.port)
            if let name = listener.reportedName { names[listener.pid] = name }
        }
        return ports.compactMap { pid, portSet in
            guard let details = inspect(pid) else { return nil }
            let section = classifier.section(for: details)
            if section == .otherUsers, all == nil { return nil }
            let fallback = names[pid] ?? details.executablePath.map { ($0 as NSString).lastPathComponent } ?? "PID \(pid)"
            return Row(
                pid: pid,
                ports: portSet.sorted(),
                command: section == .otherUsers ? fallback : CommandLabel.label(arguments: details.arguments, fallbackName: fallback),
                folder: folder(for: details, in: section),
                owner: section == .otherUsers ? details.uid.map(userName) : nil,
                section: section,
                executablePath: details.executablePath
            )
        }
        .sorted { ($0.section.order, $0.ports[0]) < ($1.section.order, $1.ports[0]) }
    }

    func folder(for details: ProcessDetails, in section: Section) -> String? {
        switch section {
        case .otherUsers:
            return nil
        case .appsAndSystem:
            if let path = details.executablePath, let bundle = Classifier.appBundle(containing: path) { return bundle }
            return details.workingDirectory.flatMap(displayPath)
        case .dev:
            return details.workingDirectory.flatMap(displayPath)
        }
    }

    /// `~` for the home folder; nothing for `/`, which only means "not started from a project".
    func displayPath(_ path: String) -> String? {
        if path == "/" { return nil }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

public struct ScanResult: Sendable, Equatable {
    public let rows: [Row]
    /// Set when the process list itself could not be read.
    public let problem: String?
    /// Set when "Show all" is on but other users' ports could not be read.
    public let otherUsersProblem: String?
}

/// One full scan with the live sources.
public enum PortScan {
    public static func run(showAll: Bool, overrides: [String: Placement]) -> ScanResult {
        let own: [Listener]
        do {
            own = try OwnProcessSource().listeners()
        } catch {
            return ScanResult(rows: [], problem: "Couldn't read the list of processes.", otherUsersProblem: nil)
        }
        var all: [Listener]?
        var otherUsersProblem: String?
        if showAll {
            let found = try? NetstatSource().listeners()
            // netstat always lists our own listeners too, so an empty result next to a non-empty `own` means parsing broke.
            if let found, !(found.isEmpty && !own.isEmpty) {
                all = found
            } else {
                otherUsersProblem = "Can't read other users' ports on this macOS version."
            }
        }
        let rows = SnapshotBuilder.live(overrides: overrides).rows(own: own, all: all)
        return ScanResult(rows: rows, problem: nil, otherUsersProblem: otherUsersProblem)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Core && swift test --filter "SnapshotTests|LiveScanTests"`
Expected: all 10 tests pass.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Build panel rows from listeners and run a live scan"
```

---

### Task 7: Terminator

**Files:**
- Create: `Core/Sources/PortGlimpseCore/Terminator.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/TerminatorTests.swift`

**Interfaces:**
- Consumes: `ProcessInspector.uid(of:)`, `ProcessInspector.isRunning(_:)` (Task 4); `TestServer`, `OwnProcessSource` (Task 5).
- Produces:
  - `public enum KillOutcome: Equatable, Sendable { case stopped, stillRunning, failed(String) }`.
  - `public struct Terminator: Sendable { init(currentUID:grace:pollInterval:ownerOf:isAlive:send:); static func live(grace: Duration = .seconds(3)) -> Terminator; func stop(_ pid: Int32) async -> KillOutcome; func forceKill(_ pid: Int32) async -> KillOutcome }`.
  - The failure reasons, verbatim: `"It has already exited."`, `"It belongs to another user."`.

- [ ] **Step 1: Write the failing tests**

`Core/Tests/PortGlimpseCoreTests/TerminatorTests.swift`:

```swift
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

    @Test func refusesLaunchd() async {
        #expect(await Terminator.live().stop(1) == .failed("It belongs to another user."))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Core && swift test --filter "TerminatorTests|LiveTerminatorTests"`
Expected: compile failure, `cannot find 'Terminator' in scope`.

- [ ] **Step 3: Implement `Terminator`**

`Core/Sources/PortGlimpseCore/Terminator.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Core && swift test --filter "TerminatorTests|LiveTerminatorTests"`
Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Stop processes with a graceful signal and a force kill"
```

---

### Task 8: Version comparison and the release feed

**Files:**
- Create: `Core/Sources/PortGlimpseCore/AppVersion.swift`
- Test: `Core/Tests/PortGlimpseCoreTests/AppVersionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct AppVersion: Comparable, Sendable, CustomStringConvertible { init?(_ text: String); parts: [Int] }`.
  - `public enum ReleaseFeed { static func latestVersion(fromJSON data: Data) throws -> AppVersion? }`.

- [ ] **Step 1: Write the failing tests**

`Core/Tests/PortGlimpseCoreTests/AppVersionTests.swift`:

```swift
import Foundation
import Testing
@testable import PortGlimpseCore

struct AppVersionTests {
    @Test func parsesWithOrWithoutAV() {
        #expect(AppVersion("v1.2.3")?.parts == [1, 2, 3])
        #expect(AppVersion("1.2.3")?.parts == [1, 2, 3])
    }

    @Test func rejectsNonsense() {
        #expect(AppVersion("beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumerically() {
        #expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
        #expect(AppVersion("v1.0.1")! > AppVersion("1.0.0")!)
    }

    @Test func missingPartsCountAsZero() {
        #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
        #expect(!(AppVersion("1.0")! < AppVersion("1.0.0")!))
    }

    @Test func printsWithoutTheV() {
        #expect(AppVersion("v1.2.0")!.description == "1.2.0")
    }

    @Test func readsTheLatestReleaseTag() throws {
        let json = Data(#"{"tag_name":"v1.0.1","name":"PortGlimpse 1.0.1","draft":false}"#.utf8)
        #expect(try ReleaseFeed.latestVersion(fromJSON: json) == AppVersion("1.0.1"))
    }

    @Test func aResponseWithoutATagThrows() {
        #expect(throws: DecodingError.self) { try ReleaseFeed.latestVersion(fromJSON: Data(#"{"message":"Not Found"}"#.utf8)) }
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Core && swift test --filter AppVersionTests`
Expected: compile failure, `cannot find 'AppVersion' in scope`.

- [ ] **Step 3: Implement it**

`Core/Sources/PortGlimpseCore/AppVersion.swift`:

```swift
import Foundation

/// A dotted version such as `1.0.2`; a leading `v` (as in release tags) is accepted and dropped.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        parts = numbers.map { $0! }
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    static func padded(_ a: AppVersion, _ b: AppVersion) -> ([Int], [Int]) {
        let count = max(a.parts.count, b.parts.count)
        return (a.parts + Array(repeating: 0, count: count - a.parts.count),
                b.parts + Array(repeating: 0, count: count - b.parts.count))
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let (x, y) = padded(a, b)
        return x == y
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let (x, y) = padded(a, b)
        return x.lexicographicallyPrecedes(y)
    }
}

/// Reads GitHub's "latest release" response.
public enum ReleaseFeed {
    struct Release: Decodable {
        let tag_name: String
    }

    public static func latestVersion(fromJSON data: Data) throws -> AppVersion? {
        AppVersion(try JSONDecoder().decode(Release.self, from: data).tag_name)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Core && swift test --filter AppVersionTests`
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add Core
git commit -m "Compare versions and read the latest release tag"
```

---

### Task 9: App shell — project, fonts, icon, theme and menu bar label

**Files:**
- Create: `project.yml`, `App/Signing.xcconfig`
- Create: `scripts/build.sh`, `scripts/install-local.sh`, `scripts/make-icon.swift`
- Modify: `scripts/test.sh`, `CLAUDE.md`
- Create: `App/Resources/Fonts/*` (downloaded), `App/Resources/Assets.xcassets/Contents.json`, `App/Resources/Assets.xcassets/AppIcon.appiconset/*` (rendered)
- Create: `App/Sources/PortGlimpseApp.swift`, `App/Sources/Theme.swift`, `App/Sources/MenuBarLabel.swift`

**Interfaces:**
- Consumes: the `PortGlimpseCore` library.
- Produces:
  - `enum Theme` with colours `page, panel, raised, text, softText, muted, line, lineStrong, amber, amberFace (LinearGradient), onAmber, amberTint, amberTintLine, cap, capInk`, and fonts `title(_:)`, `body(_:_:)`, `mono(_:)`.
  - `struct PanelButtonStyle: ButtonStyle { enum Kind { case ghost, primary }; init(_ kind: Kind) }`.
  - `@MainActor enum KeycapGlyph { static func image(dimmed: Bool) -> NSImage }`.
  - `struct MenuBarLabel: View { init(devCount: Int, showCount: Bool) }`.
  - `@MainActor final class AppDelegate` (extended in Tasks 10 and 11).

- [ ] **Step 1: Download the fonts and licences**

```bash
mkdir -p App/Resources/Fonts
base=https://github.com/google/fonts/raw/main/ofl
curl -fsSL -o "App/Resources/Fonts/Figtree[wght].ttf" "$base/figtree/Figtree%5Bwght%5D.ttf"
curl -fsSL -o "App/Resources/Fonts/BricolageGrotesque[opsz,wdth,wght].ttf" "$base/bricolagegrotesque/BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf"
curl -fsSL -o App/Resources/Fonts/IBMPlexMono-Medium.ttf "$base/ibmplexmono/IBMPlexMono-Medium.ttf"
curl -fsSL -o App/Resources/Fonts/IBMPlexMono-SemiBold.ttf "$base/ibmplexmono/IBMPlexMono-SemiBold.ttf"
curl -fsSL -o App/Resources/Fonts/OFL-Figtree.txt "$base/figtree/OFL.txt"
curl -fsSL -o App/Resources/Fonts/OFL-BricolageGrotesque.txt "$base/bricolagegrotesque/OFL.txt"
curl -fsSL -o App/Resources/Fonts/OFL-IBMPlexMono.txt "$base/ibmplexmono/OFL.txt"
grep -l "SIL OPEN FONT LICENSE" App/Resources/Fonts/OFL-*.txt | wc -l
```

Expected: the last command prints `3`, confirming all three are under the SIL Open Font License, which allows bundling.

- [ ] **Step 2: Write the project and signing config**

`project.yml`:

```yaml
name: PortGlimpse
options:
  bundleIdPrefix: com.zewify
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
  developmentLanguage: en
packages:
  PortGlimpseCore:
    path: Core
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES
targets:
  PortGlimpse:
    type: application
    platform: macOS
    configFiles:
      Debug: App/Signing.xcconfig
      Release: App/Signing.xcconfig
    sources:
      - path: App/Sources
      - path: App/Resources/Assets.xcassets
      - path: App/Resources/Fonts
        type: folder
        buildPhase: resources
    dependencies:
      - package: PortGlimpseCore
    info:
      path: App/Info.plist
      properties:
        CFBundleName: PortGlimpse
        CFBundleDisplayName: PortGlimpse
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.developer-tools
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        NSHumanReadableCopyright: © 2026 Zewify
        ATSApplicationFontsPath: Fonts
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.zewify.portglimpse
        PRODUCT_NAME: PortGlimpse
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ENABLE_HARDENED_RUNTIME: YES
        GENERATE_INFOPLIST_FILE: NO
schemes:
  PortGlimpse:
    build:
      targets:
        PortGlimpse: all
    run:
      config: Debug
    archive:
      config: Release
```

`App/Signing.xcconfig`:

```
// Committed signing defaults: ad hoc, which is enough to build and run locally.
// Developer ID signing for releases comes with the distribution plan; a local identity
// can go in Signing.local.xcconfig next to this file (gitignored).
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
#include? "Signing.local.xcconfig"
```

XcodeGen writes `App/Info.plist` from the `info` block above on every `xcodegen generate`; commit it, as TickThock does, and never edit it by hand.

- [ ] **Step 3: Write the scripts**

`scripts/build.sh`:

```bash
#!/usr/bin/env bash
# Generates the Xcode project and builds PortGlimpse.app; prints the app's path.
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
xcodegen generate --quiet
xcodebuild -project PortGlimpse.xcodeproj -scheme PortGlimpse -configuration "$configuration" \
  -derivedDataPath build/DerivedData -quiet build
echo "build/DerivedData/Build/Products/$configuration/PortGlimpse.app"
```

`scripts/test.sh` (replace the whole file):

```bash
#!/usr/bin/env bash
# Runs the core tests, then builds the app so a compile error anywhere fails the run.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd Core && swift test --quiet)
./scripts/build.sh Debug >/dev/null
```

`scripts/install-local.sh`:

```bash
#!/usr/bin/env bash
# Builds Release, replaces /Applications/PortGlimpse.app with it, and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$(./scripts/build.sh Release | tail -1)"
osascript -e 'quit app "PortGlimpse"' >/dev/null 2>&1 || true
rm -rf "/Applications/PortGlimpse.app"
ditto "$app" "/Applications/PortGlimpse.app"
open "/Applications/PortGlimpse.app"
echo "Installed /Applications/PortGlimpse.app"
```

Run: `chmod +x scripts/*.sh`

- [ ] **Step 4: Render the app icon**

`scripts/make-icon.swift`:

```swift
// Renders AppIcon.appiconset: an amber keycap with a colon on TickThock's dark tile.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    // macOS icon grid: an 824-point tile inset 100 points in the 1024 canvas.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(color(0x221E1B))
    ctx.fillPath()
    // The key's darker skirt, then its face on top; the skirt shows as a band along the bottom.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 262, y: 238, width: 500, height: 520), cornerWidth: 110, cornerHeight: 110, transform: nil))
    ctx.setFillColor(color(0xB9531A))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 262, y: 290, width: 500, height: 468), cornerWidth: 110, cornerHeight: 110, transform: nil))
    ctx.clip()
    let face = CGGradient(colorsSpace: space, colors: [color(0xFFB067), color(0xEE8237)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: 512, y: 758), end: CGPoint(x: 512, y: 290), options: [])
    ctx.restoreGState()
    // The colon.
    ctx.setFillColor(color(0x1B1815))
    for centre in [CGFloat(434), 614] {
        ctx.fillEllipse(in: CGRect(x: 512 - 44, y: centre - 44, width: 88, height: 88))
    }
    let bitmap = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(sizes.count) icons to \(output.path)")
```

`App/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Run: `swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset`
Expected: `Wrote 10 icons to …/AppIcon.appiconset`.
Open `icon_512x512@2x.png` and check: a dark rounded tile, an amber key with a darker band along its bottom, and a dark colon centred on the key face.

- [ ] **Step 5: Write the theme**

`App/Sources/Theme.swift`:

```swift
import SwiftUI

/// TickThock's dark palette and type, shared by every view.
enum Theme {
    static let page = Color(hex: 0x16130F)
    static let panel = Color(hex: 0x201B17)
    static let raised = Color(hex: 0x2A241F)
    static let footer = Color(hex: 0x1B1714)
    static let text = Color(hex: 0xF6EDE3)
    static let softText = Color(hex: 0xD8CBBD)
    static let muted = Color(hex: 0xA8998A)
    static let line = Color(hex: 0x342C25)
    static let lineStrong = Color(hex: 0x4A3F35)
    static let amber = Color(hex: 0xF48E48)
    static let amberFace = LinearGradient(colors: [Color(hex: 0xFFB067), Color(hex: 0xEE8237)], startPoint: .top, endPoint: .bottom)
    static let onAmber = Color(hex: 0x1B1815)
    static let amberTint = Color(hex: 0x2C211A)
    static let amberTintLine = Color(hex: 0x4D3424)
    static let cap = Color(hex: 0x2E2721)
    static let capInk = Color(hex: 0xE9DDD0)

    static func title(_ size: CGFloat) -> Font { .custom("Bricolage Grotesque", size: size).weight(.heavy) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Figtree", size: size).weight(weight) }
    static func mono(_ size: CGFloat) -> Font { .custom("IBM Plex Mono", size: size).weight(.semibold) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Flat 30-point buttons: a keycap-coloured ghost, or the amber primary used only for Kill and Force kill.
struct PanelButtonStyle: ButtonStyle {
    enum Kind { case ghost, primary }
    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(kind == .primary ? Theme.onAmber : Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(kind == .primary ? AnyShapeStyle(Theme.amberFace) : AnyShapeStyle(Theme.cap), in: shape)
            .overlay(shape.strokeBorder(kind == .primary ? Color.clear : Theme.lineStrong))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(shape)
    }
}
```

- [ ] **Step 6: Write the menu bar label**

`App/Sources/MenuBarLabel.swift`:

```swift
import AppKit
import SwiftUI

/// The colon keycap, drawn as a template image so macOS tints it for the menu bar.
@MainActor
enum KeycapGlyph {
    private static let normal = draw(alpha: 1)
    private static let dim = draw(alpha: 0.5)

    static func image(dimmed: Bool) -> NSImage { dimmed ? dim : normal }

    private static func draw(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let ink = NSColor.black.withAlphaComponent(alpha)
            let key = NSBezierPath(roundedRect: NSRect(x: 2.25, y: 2.25, width: 11.5, height: 11.5), xRadius: 3, yRadius: 3)
            key.lineWidth = 1.5
            ink.setStroke()
            key.stroke()
            ink.setFill()
            for centreY in [6.0, 10.0] {
                NSBezierPath(ovalIn: NSRect(x: 8 - 1.2, y: centreY - 1.2, width: 2.4, height: 2.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PortGlimpse"
        return image
    }
}

/// The icon plus the number of dev servers; dimmed with no number when there are none.
struct MenuBarLabel: View {
    let devCount: Int
    let showCount: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: KeycapGlyph.image(dimmed: devCount == 0))
            if showCount, devCount > 0 {
                Text(verbatim: "\(devCount)").monospacedDigit()
            }
        }
    }
}
```

- [ ] **Step 7: Write the app entry point with a placeholder panel**

`App/Sources/PortGlimpseApp.swift` (Task 10 replaces the placeholder panel):

```swift
import SwiftUI
import PortGlimpseCore

@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Text("PortGlimpse")
                .font(Theme.title(18))
                .foregroundStyle(Theme.text)
                .padding(24)
                .background(Theme.panel)
        } label: {
            MenuBarLabel(devCount: 0, showCount: true)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {}
```

- [ ] **Step 8: Build and look at it**

Run: `./scripts/test.sh`
Expected: exit code 0.
Run: `open "$(./scripts/build.sh | tail -1)"`
Check by hand:
- A dimmed keycap-with-colon icon appears in the menu bar, with no Dock icon.
- Clicking it opens a dark panel whose "PortGlimpse" title is set in Bricolage Grotesque, not the system font.
  To be sure the bundled font loaded, temporarily change `"Bricolage Grotesque"` in `Theme.title` to `"Nope"`, rebuild, and confirm the title visibly changes to the system font; then revert.
- Quit it from Activity Monitor or `osascript -e 'quit app "PortGlimpse"'`.

- [ ] **Step 9: Update CLAUDE.md and commit**

In `CLAUDE.md`, replace the `## Commands` section with:

```markdown
## Commands

- `./scripts/test.sh` — core tests, then an app build. Run before every commit; the exit code is the verdict.
- `./scripts/build.sh [Debug|Release]` — generates the project and builds; prints the app path.
- `./scripts/install-local.sh` — a Release build copied to `/Applications` and launched.
- `swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset` — re-renders the app icon.
- `project.yml` is the XcodeGen spec; the `.xcodeproj` is generated and gitignored, so never edit or commit it.
```

```bash
./scripts/test.sh
git add .gitignore CLAUDE.md project.yml App scripts
git commit -m "Add the app shell with fonts, icon, theme and menu bar label"
```

---

### Task 10: The panel — model, rows and kill flow

**Files:**
- Create: `App/Sources/PanelModel.swift`, `App/Sources/PanelWindowObserver.swift`, `App/Sources/PanelView.swift`, `App/Sources/PortList.swift`, `App/Sources/RowView.swift`
- Modify: `App/Sources/PortGlimpseApp.swift`

**Interfaces:**
- Consumes: `PortScan.run(showAll:overrides:)`, `ScanResult`, `Row`, `Section`, `Placement`, `OverrideStore`, `Terminator`, `KillOutcome` (Core); `Theme`, `PanelButtonStyle`, `MenuBarLabel` (Task 9).
- Produces:
  - `enum RowPhase: Equatable { case idle, confirming, stopping, stillRunning, failed(String) }`.
  - `@MainActor @Observable final class PanelModel` with `rows`, `problem`, `otherUsersProblem`, `appsExpanded`, `showAll`, `showCount`, `devCount`, `rows(in:)`, `phase(of:)`, `start()`, `viewerAppeared()`, `viewerDisappeared()`, `panelOpened()`, `panelClosed()`, `refresh()`, `askKill(_:)`, `cancel(_:)`, `cancelConfirmations()`, `confirmKill(_:)`, `confirmForceKill(_:)`, `placement(of:)`, `setPlacement(_:for:)`, `openInBrowser(_:)`, `copyPID(_:)`, `revealFolder(_:)`.
  - `struct RowView: View { init(row: Row, model: PanelModel, compact: Bool = false) }`.
  - `struct PortList: View { init(model: PanelModel, compact: Bool = false) }` — the three sections, shared by the panel and the pop-out window.
  - `struct PanelView: View { init(model: PanelModel, onPopOut: (() -> Void)? = nil, footer: () -> some View) }` — Task 11 supplies the footer's settings and update row; Task 12 supplies `onPopOut`.

- [ ] **Step 1: Write the panel model**

`App/Sources/PanelModel.swift`:

```swift
import AppKit
import Observation
import PortGlimpseCore

enum RowPhase: Equatable {
    case idle
    case confirming
    case stopping
    /// Still alive after the grace period: the row asks to force kill.
    case stillRunning
    case failed(String)
}

/// Everything the panel shows and does. Scans run off the main actor; state changes happen on it.
@MainActor
@Observable
final class PanelModel {
    private(set) var rows: [Row] = []
    private(set) var problem: String?
    private(set) var otherUsersProblem: String?
    private var phases: [Int32: RowPhase] = [:]
    var appsExpanded = false
    var showAll: Bool {
        didSet { defaults.set(showAll, forKey: Keys.showAll); Task { await refresh() } }
    }
    var showCount: Bool {
        didSet { defaults.set(showCount, forKey: Keys.showCount) }
    }

    var devCount: Int { rows(in: .dev).count }

    private enum Keys {
        static let showAll = "showAllUsers"
        static let showCount = "showCountInMenuBar"
    }

    private let defaults: UserDefaults
    private let overrideStore: OverrideStore
    private let terminator = Terminator.live()
    private var viewers = 0
    private var liveLoop: Task<Void, Never>?
    private var backgroundLoop: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, overrideStore: OverrideStore = OverrideStore(fileURL: OverrideStore.defaultURL)) {
        self.defaults = defaults
        self.overrideStore = overrideStore
        showAll = defaults.bool(forKey: Keys.showAll)
        showCount = defaults.object(forKey: Keys.showCount) as? Bool ?? true
    }

    func rows(in section: Section) -> [Row] { rows.filter { $0.section == section } }

    func phase(of row: Row) -> RowPhase { phases[row.pid] ?? .idle }

    // MARK: Polling

    /// Keeps the menu bar count current with one cheap scan every 10 seconds.
    func start() {
        backgroundLoop?.cancel()
        backgroundLoop = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// While the panel or the pop-out window is showing, the list refreshes every second.
    /// Both report here, so the loop runs once however many are showing.
    func viewerAppeared() {
        viewers += 1
        guard viewers == 1 else { return }
        liveLoop = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func viewerDisappeared() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        liveLoop?.cancel()
        liveLoop = nil
    }

    func panelOpened() { viewerAppeared() }

    /// Clicking away from the menu bar panel withdraws any question it was asking.
    func panelClosed() {
        viewerDisappeared()
        cancelConfirmations()
    }

    func refresh() async {
        let showAll = showAll
        let overrides = overrideStore.overrides
        let result = await Task.detached(priority: .utility) { PortScan.run(showAll: showAll, overrides: overrides) }.value
        rows = result.rows
        problem = result.problem
        otherUsersProblem = result.otherUsersProblem
        let live = Set(rows.map(\.pid))
        phases = phases.filter { live.contains($0.key) }
    }

    // MARK: Kill flow

    /// Only one row asks at a time; asking on another row withdraws the first question.
    func askKill(_ row: Row) {
        cancelConfirmations()
        phases[row.pid] = .confirming
    }

    func cancel(_ row: Row) { phases[row.pid] = nil }

    func cancelConfirmations() {
        phases = phases.filter { $0.value != .confirming && $0.value != .stillRunning }
    }

    func confirmKill(_ row: Row) {
        run(row) { terminator, pid in await terminator.stop(pid) }
    }

    func confirmForceKill(_ row: Row) {
        run(row) { terminator, pid in await terminator.forceKill(pid) }
    }

    private func run(_ row: Row, _ action: @escaping @Sendable (Terminator, Int32) async -> KillOutcome) {
        let pid = row.pid
        let terminator = terminator
        phases[pid] = .stopping
        Task {
            switch await action(terminator, pid) {
            case .stopped:
                phases[pid] = nil
                await refresh()
            case .stillRunning:
                phases[pid] = .stillRunning
            case .failed(let reason):
                phases[pid] = .failed(reason)
                try? await Task.sleep(for: .seconds(4))
                if phases[pid] == .failed(reason) { phases[pid] = nil }
                await refresh()
            }
        }
    }

    // MARK: Overrides

    func placement(of row: Row) -> Placement? {
        row.executablePath.flatMap { overrideStore.overrides[$0] }
    }

    func setPlacement(_ placement: Placement?, for row: Row) {
        guard let path = row.executablePath else { return }
        try? overrideStore.set(placement, for: path)
        Task { await refresh() }
    }

    // MARK: Row actions

    func openInBrowser(_ row: Row) {
        guard let url = URL(string: "http://localhost:\(row.ports[0])") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyPID(_ row: Row) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(row.pid), forType: .string)
    }

    func revealFolder(_ row: Row) {
        guard let folder = row.folder else { return }
        let path = (folder as NSString).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
```

- [ ] **Step 2: Write the window observer**

`App/Sources/PanelWindowObserver.swift`:

```swift
import AppKit
import SwiftUI

/// Tells the model when the menu bar panel opens and closes.
/// A window-style MenuBarExtra keeps its view alive between openings, so onAppear is not enough;
/// the panel's window becomes key when shown and resigns key when dismissed.
struct PanelWindowObserver: NSViewRepresentable {
    let onOpen: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onOpen = onOpen
        view.onClose = onClose
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        var onOpen: (@MainActor () -> Void)?
        var onClose: (@MainActor () -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpen?() }
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose?() }
            })
            if window.isKeyWindow { onOpen?() }
        }
    }
}
```

- [ ] **Step 3: Write the row view**

`App/Sources/RowView.swift`:

```swift
import PortGlimpseCore
import SwiftUI

/// One process: its ports, command and folder, and the kill flow in place.
/// `compact` is the pop-out window's layout below 360 points wide.
struct RowView: View {
    let row: Row
    let model: PanelModel
    var compact = false
    @State private var hovering = false

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering && row.section != .otherUsers ? Theme.raised : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { rowMenu }
    }

    private var fullBody: some View {
        HStack(alignment: .center, spacing: 14) {
            ports
            content
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
        .frame(minHeight: 52)
    }

    /// Port and command only; the folder moves to a tooltip, only Kill shows on hover,
    /// and a question wraps onto its own line above its buttons.
    @ViewBuilder private var compactBody: some View {
        switch model.phase(of: row) {
        case .confirming:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PortTag(port: row.ports[0], section: row.section)
                    Text(verbatim: "Kill \(row.command) on :\(row.ports[0])?")
                        .font(Theme.body(13, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Spacer()
                    Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
                    Button("Kill") { model.confirmKill(row) }.buttonStyle(PanelButtonStyle(.primary))
                }
            }
            .padding(8)
        case .stillRunning:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PortTag(port: row.ports[0], section: row.section)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(row.command) didn’t stop").font(Theme.body(13, .bold)).foregroundStyle(Theme.text)
                        Text("Force kill it? Unsaved work in it is lost.").font(Theme.body(12)).foregroundStyle(Theme.softText)
                    }
                }
                HStack(spacing: 6) {
                    Spacer()
                    Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
                    Button("Force kill") { model.confirmForceKill(row) }.buttonStyle(PanelButtonStyle(.primary))
                }
            }
            .padding(8)
        case .idle, .stopping, .failed:
            HStack(spacing: 10) {
                PortTag(port: row.ports[0], section: row.section)
                compactText
                Spacer(minLength: 0)
                if model.phase(of: row) == .idle {
                    if row.section == .otherUsers {
                        ownerBadge
                    } else if hovering {
                        IconButton(symbol: "xmark.circle", label: "Kill", destructive: true) { model.askKill(row) }
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 40)
            .help(row.folder ?? "")
        }
    }

    @ViewBuilder private var compactText: some View {
        switch model.phase(of: row) {
        case .stopping:
            Text(verbatim: "Stopping…").font(Theme.body(13)).foregroundStyle(Theme.muted)
        case .failed(let reason):
            Text(verbatim: "Couldn’t kill. \(reason)").font(Theme.body(12)).foregroundStyle(Theme.softText).lineLimit(2)
        default:
            Text(verbatim: row.command)
                .font(Theme.body(14, .bold))
                .foregroundStyle(row.section == .dev ? Theme.text : Theme.softText)
                .lineLimit(1)
        }
    }

    private var ports: some View {
        VStack(alignment: .leading, spacing: 6) {
            PortTag(port: row.ports[0], section: row.section)
            if row.ports.count > 1 {
                Text(verbatim: "+ " + row.ports.dropFirst().map { ":\($0)" }.joined(separator: " "))
                    .font(.custom("IBM Plex Mono", size: 11).weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: 72, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch model.phase(of: row) {
        case .idle:
            details
            Spacer(minLength: 0)
            if row.section == .otherUsers {
                ownerBadge
            } else if hovering {
                actions
            }
        case .confirming:
            Text(verbatim: "Kill \(row.command) on :\(row.ports[0])?")
                .font(Theme.body(13, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
            Button("Kill") { model.confirmKill(row) }.buttonStyle(PanelButtonStyle(.primary))
        case .stopping:
            Text(verbatim: "Stopping \(row.command)…").font(Theme.body(13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        case .stillRunning:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(row.command) didn’t stop").font(Theme.body(14, .bold)).foregroundStyle(Theme.text)
                Text("Force kill it? Unsaved work in it is lost.").font(Theme.body(12)).foregroundStyle(Theme.softText)
            }
            Spacer(minLength: 8)
            Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
            Button("Force kill") { model.confirmForceKill(row) }.buttonStyle(PanelButtonStyle(.primary))
        case .failed(let reason):
            Text(verbatim: "Couldn’t kill \(row.command). \(reason)")
                .font(Theme.body(13))
                .foregroundStyle(Theme.softText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.command)
                .font(Theme.body(14, .bold))
                .foregroundStyle(row.section == .dev ? Theme.text : Theme.softText)
                .lineLimit(1)
            Text(verbatim: row.section == .otherUsers ? "PID \(row.pid)" : (row.folder ?? "PID \(row.pid)"))
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if row.section == .dev {
                IconButton(symbol: "arrow.up.right.square", label: "Open localhost:\(row.ports[0])") { model.openInBrowser(row) }
            }
            IconButton(symbol: "doc.on.doc", label: "Copy PID \(row.pid)") { model.copyPID(row) }
            if row.section == .dev, row.folder != nil {
                IconButton(symbol: "folder", label: "Reveal in Finder") { model.revealFolder(row) }
            }
            IconButton(symbol: "xmark.circle", label: "Kill", destructive: true) { model.askKill(row) }
        }
    }

    private var ownerBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock").font(.system(size: 11, weight: .semibold))
            Text(verbatim: row.owner ?? "another user").font(Theme.body(12, .semibold))
        }
        .foregroundStyle(Theme.muted)
        .padding(.trailing, 6)
        .help("Owned by \(row.owner ?? "another user")")
    }

    /// The row's actions (the only way to reach them in a compact row), then placement.
    /// Other users' rows get no menu at all.
    @ViewBuilder private var rowMenu: some View {
        if row.section != .otherUsers {
            if row.section == .dev {
                Button("Open localhost:\(String(row.ports[0]))") { model.openInBrowser(row) }
            }
            Button("Copy PID \(String(row.pid))") { model.copyPID(row) }
            if row.section == .dev, row.folder != nil {
                Button("Reveal in Finder") { model.revealFolder(row) }
            }
            Button("Kill…") { model.askKill(row) }
            if row.executablePath != nil {
                Divider()
                Button("Always show as dev") { model.setPlacement(.dev, for: row) }
                    .disabled(model.placement(of: row) == .dev)
                Button("Always hide in Apps & system") { model.setPlacement(.appsAndSystem, for: row) }
                    .disabled(model.placement(of: row) == .appsAndSystem)
                if model.placement(of: row) != nil {
                    Button("Use automatic placement") { model.setPlacement(nil, for: row) }
                }
            }
        }
    }
}

/// A flat port label; deliberately unlike a button.
struct PortTag: View {
    let port: UInt16
    let section: Section

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(verbatim: ":\(port)")
            .font(Theme.mono(14))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(minWidth: 52, minHeight: 24)
            .background(section == .dev ? Theme.amberTint : .clear, in: shape)
            .overlay(shape.strokeBorder(border))
    }

    private var foreground: Color {
        switch section {
        case .dev: Theme.amber
        case .appsAndSystem: Theme.capInk
        case .otherUsers: Theme.muted
        }
    }

    private var border: Color {
        switch section {
        case .dev: Theme.amberTintLine
        case .appsAndSystem: Theme.lineStrong
        case .otherUsers: Theme.line
        }
    }
}

/// A 30-point icon button that lights up on hover; Kill turns amber.
struct IconButton: View {
    let symbol: String
    let label: String
    var destructive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(hovering ? (destructive ? Theme.amber : Theme.text) : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? (destructive ? Theme.amberTint : Theme.cap) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 4: Write the panel view and the shared list**

`App/Sources/PanelView.swift`:

```swift
import PortGlimpseCore
import SwiftUI

/// The menu bar panel: header, the shared list, and a footer supplied by the caller.
struct PanelView<Footer: View>: View {
    @Bindable var model: PanelModel
    /// Set by Task 12; when nil the header has no pop-out button.
    let onPopOut: (() -> Void)?
    let footer: Footer

    /// Past this many rows the list scrolls instead of growing off the screen.
    static var scrollThreshold: Int { 12 }

    init(model: PanelModel, onPopOut: (() -> Void)? = nil, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.onPopOut = onPopOut
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if model.rows.count > Self.scrollThreshold {
                ScrollView { PortList(model: model) }.frame(height: 600)
            } else {
                PortList(model: model)
            }
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 408)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .background(PanelWindowObserver(onOpen: model.panelOpened, onClose: model.panelClosed))
        .onKeyPress(.escape) {
            model.cancelConfirmations()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("PortGlimpse").font(Theme.title(18)).tracking(-0.5).foregroundStyle(Theme.text)
            Spacer()
            LiveBadge()
            if let onPopOut {
                IconButton(symbol: "macwindow.on.rectangle", label: "Open in a window", action: onPopOut)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 46)
    }
}

/// The amber "Live" dot shown in both headers.
struct LiveBadge: View {
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.amber).frame(width: 7, height: 7)
                .background(Circle().fill(Theme.amber.opacity(0.18)).frame(width: 13, height: 13))
            if showsLabel {
                Text("Live").font(Theme.body(12, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Updating live")
    }
}
```

`App/Sources/PortList.swift`:

```swift
import PortGlimpseCore
import SwiftUI

/// The three sections, shared by the menu bar panel and the pop-out window.
struct PortList: View {
    @Bindable var model: PanelModel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Dev servers")
                if let problem = model.problem {
                    message(problem)
                } else if model.rows(in: .dev).isEmpty {
                    message("Nothing listening. Your ports are free.")
                }
                ForEach(model.rows(in: .dev)) { RowView(row: $0, model: model, compact: compact) }
            }
            .padding(8)

            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    model.appsExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.appsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 14)
                        Text("Apps & system").font(Theme.body(13, .bold))
                        Spacer()
                        Text(verbatim: "\(model.rows(in: .appsAndSystem).count)").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.softText)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.appsExpanded ? "Expanded" : "Collapsed")
                if model.appsExpanded {
                    ForEach(model.rows(in: .appsAndSystem)) { RowView(row: $0, model: model, compact: compact) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if model.showAll {
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Other users · view only")
                    if let problem = model.otherUsersProblem { message(problem) }
                    ForEach(model.rows(in: .otherUsers)) { RowView(row: $0, model: model, compact: compact) }
                }
                .padding(8)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.body(11, .bold))
            .tracking(0.9)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
    }
}
```

- [ ] **Step 5: Wire the panel into the app**

Replace `App/Sources/PortGlimpseApp.swift` with (Task 11 fills in the footer's settings and update row):

```swift
import PortGlimpseCore
import SwiftUI

@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model) {
                PanelFooter(model: delegate.model)
            }
        } label: {
            MenuBarLabel(devCount: delegate.model.devCount, showCount: delegate.model.showCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// "Show all" and Quit; Task 11 adds the Settings menu and the update row.
struct PanelFooter: View {
    @Bindable var model: PanelModel

    var body: some View {
        HStack {
            Toggle("Show all users’ ports", isOn: $model.showAll)
                .toggleStyle(.checkbox)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.softText)
                .tint(Theme.amber)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(Theme.footer)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PanelModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}
```

- [ ] **Step 6: Build and walk through it end to end**

Run: `./scripts/test.sh`
Expected: exit code 0.
Start two real servers in separate terminals: `cd ~/Developer && python3 -m http.server 8765` and `cd /tmp && sh -c "trap '' TERM; exec nc -l 8766"`.
Run: `open "$(./scripts/build.sh | tail -1)"`, open the panel, and check each item against the canvas boards "Menu panel" and "Row states":
- The menu bar shows the keycap and a count that includes both servers, within 10 seconds of starting them.
- Under Dev servers: `:8765 http.server ~/Developer` and `:8766 nc /private/tmp` (or `/tmp`), with amber-tinted port labels.
- Hovering a dev row shows the raised background and four icons; Open in browser opens `http://localhost:8765`; Copy PID puts the PID on the clipboard; Reveal opens Finder at the folder.
- Kill on `:8765` shows `Kill http.server on :8765?` with Cancel and Kill the same height (measure with the Accessibility Inspector or a screenshot at 100 %); Escape cancels; clicking Kill shows "Stopping http.server…" and the row disappears.
- Kill on `:8766` ends at `nc didn’t stop` with Cancel / Force kill; Force kill removes the row.
- Apps & system expands and collapses, its count matches its rows, and those rows offer only Copy PID and Kill.
- Right-click a row in Apps & system → "Always show as dev" moves it to Dev servers within a second; "Use automatic placement" moves it back.
- Tick "Show all users’ ports": an "Other users · view only" section lists `launchd` with `root` and a lock, and no hover actions; untick it and relaunch — the choice was remembered.
- Close and reopen the panel while a confirmation is showing: the confirmation is gone.
- Every text uses Figtree, the title Bricolage Grotesque, and the ports IBM Plex Mono; check at 2560×1440 and on a laptop-width display, and measure sizes with the Accessibility Inspector rather than from screenshots.
Fix any mismatch with the canvas before committing.

- [ ] **Step 7: Commit**

```bash
./scripts/test.sh
git add App
git commit -m "Build the panel with rows, overrides and the kill flow"
```

---

### Task 11: Settings, launch at login and the update check

**Files:**
- Create: `App/Sources/LoginItem.swift`, `App/Sources/UpdateChecker.swift`
- Modify: `App/Sources/PortGlimpseApp.swift`

**Interfaces:**
- Consumes: `AppVersion`, `ReleaseFeed` (Task 8); `PanelModel`, `PanelFooter` (Task 10); `Theme` (Task 9).
- Produces:
  - `@MainActor @Observable final class LoginItem { isEnabled: Bool; func set(_ on: Bool); func enableOnFirstLaunch() }`.
  - `@MainActor @Observable final class UpdateChecker { static let installCommand: String; available: AppVersion?; isEnabled: Bool; func start(); func copyInstallCommand() }`.

- [ ] **Step 1: Write the login item wrapper**

`App/Sources/LoginItem.swift`:

```swift
import Observation
import ServiceManagement

/// Launch at login through SMAppService; on by default, set once on the first launch.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // The toggle shows the real status below, so a refusal is visible without an alert.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func enableOnFirstLaunch() {
        let key = "didSetUpLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}
```

- [ ] **Step 2: Write the update checker**

`App/Sources/UpdateChecker.swift`:

```swift
import AppKit
import Observation
import PortGlimpseCore

/// Once a day, asks GitHub for the latest release and remembers a newer one. Network failures are silent.
@MainActor
@Observable
final class UpdateChecker {
    static let installCommand = "curl -fsSL https://zewify.com/portglimpse/install.sh | sh"
    static let feed = URL(string: "https://api.github.com/repos/zewify/portglimpse/releases/latest")!

    private enum Keys {
        static let enabled = "checkForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let latestKnown = "latestKnownVersion"
    }

    private(set) var available: AppVersion?
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { Task { await check(force: true) } } else { available = nil }
        }
    }

    private let defaults = UserDefaults.standard
    private let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")

    init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        remember(defaults.string(forKey: Keys.latestKnown).flatMap(AppVersion.init))
    }

    func start() {
        Task {
            while !Task.isCancelled {
                await check(force: false)
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func check(force: Bool) async {
        guard isEnabled else { return }
        let last = defaults.object(forKey: Keys.lastCheck) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) >= 86_400 else { return }
        defaults.set(Date(), forKey: Keys.lastCheck)
        var request = URLRequest(url: Self.feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? ReleaseFeed.latestVersion(fromJSON: data) else { return }
        defaults.set(latest.description, forKey: Keys.latestKnown)
        remember(latest)
    }

    private func remember(_ latest: AppVersion?) {
        guard isEnabled, let latest, let current, latest > current else { available = nil; return }
        available = latest
    }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
    }
}
```

- [ ] **Step 3: Add the Settings menu and the update row to the footer**

In `App/Sources/PortGlimpseApp.swift`, replace `PanelFooter` and `AppDelegate`, and pass the new objects in from the scene:

```swift
@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model) {
                PanelFooter(model: delegate.model, loginItem: delegate.loginItem, updates: delegate.updates)
            }
        } label: {
            MenuBarLabel(devCount: delegate.model.devCount, showCount: delegate.model.showCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// "Show all", the Settings menu and Quit, with an update row above them when a newer release exists.
struct PanelFooter: View {
    @Bindable var model: PanelModel
    let loginItem: LoginItem
    @Bindable var updates: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            if let version = updates.available {
                HStack {
                    Text(verbatim: "Update available: \(version)").font(Theme.body(13, .semibold)).foregroundStyle(Theme.amber)
                    Spacer()
                    Button("Copy install command") { updates.copyInstallCommand() }.buttonStyle(PanelButtonStyle(.ghost))
                }
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                Divider().overlay(Theme.line)
            }
            HStack(spacing: 4) {
                // The narrow pop-out window gets the short label rather than a truncated long one.
                ViewThatFits(in: .horizontal) {
                    showAllToggle("Show all users’ ports")
                    showAllToggle("Show all")
                }
                Spacer(minLength: 4)
                Menu("Settings") {
                    Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                    Toggle("Show count in menu bar", isOn: $model.showCount)
                    Toggle("Check for updates", isOn: $updates.isEnabled)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .background(Theme.footer)
    }

    private func showAllToggle(_ title: String) -> some View {
        Toggle(title, isOn: $model.showAll)
            .toggleStyle(.checkbox)
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.softText)
            .tint(Theme.amber)
            .lineLimit(1)
            .fixedSize()
            .help("Show all users’ ports")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PanelModel()
    let loginItem = LoginItem()
    let updates = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        updates.start()
        loginItem.enableOnFirstLaunch()
    }
}
```

- [ ] **Step 4: Build and check the settings by hand**

Run: `./scripts/test.sh`
Expected: exit code 0.
Run: `./scripts/install-local.sh`, then check:
- Settings shows three toggles; Launch at login is on after the first launch, and System Settings → General → Login Items lists PortGlimpse; turning it off removes it there.
- Turning off "Show count in menu bar" leaves just the icon.
- With the repo not yet published, no update row appears and nothing is logged as an error (the 404 is silent).
- Simulate an update: `defaults write com.zewify.portglimpse latestKnownVersion 9.9.9`, relaunch, and see "Update available: 9.9.9"; "Copy install command" puts `curl -fsSL https://zewify.com/portglimpse/install.sh | sh` on the clipboard; then `defaults delete com.zewify.portglimpse latestKnownVersion` and relaunch to clear it.
- Turning off "Check for updates" hides the row immediately.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add App
git commit -m "Add settings, launch at login and the daily update check"
```

---

### Task 12: The pop-out window

**Files:**
- Create: `App/Sources/FloatingWindow.swift`, `App/Sources/WindowView.swift`
- Modify: `App/Sources/PortGlimpseApp.swift`

**Interfaces:**
- Consumes: `PanelModel.viewerAppeared()`, `viewerDisappeared()`, `cancelConfirmations()`, `PortList`, `LiveBadge`, `PanelView(model:onPopOut:footer:)` (Task 10); `PanelFooter(model:loginItem:updates:)`, `LoginItem`, `UpdateChecker` (Task 11); `Theme` (Task 9).
- Produces:
  - `@MainActor final class FloatingWindowController: NSObject, NSWindowDelegate { init(model: PanelModel, content: @escaping @MainActor () -> AnyView); func show() }`.
  - `struct WindowView<Footer: View>: View { init(model: PanelModel, @ViewBuilder footer: () -> Footer) }`.
  - Constants: default size 420 × 480, minimum 300 × 240, compact below 360 points wide, frame autosave name `PortGlimpseWindow`.

- [ ] **Step 1: Write the window controller**

`App/Sources/FloatingWindow.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the one pop-out window: always on top, on every Space and over full-screen apps,
/// with the traffic lights drawn inside PortGlimpse's own dark header.
@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 420, height: 480)
    static let minimumSize = NSSize(width: 300, height: 240)
    static let autosaveName = "PortGlimpseWindow"

    private let model: PanelModel
    private let content: @MainActor () -> AnyView
    private var window: NSWindow?

    init(model: PanelModel, content: @escaping @MainActor () -> AnyView) {
        self.model = model
        self.content = content
    }

    /// Opens the window, or brings the open one forward; there is never more than one.
    func show() {
        if let window {
            window.orderFrontRegardless()
            window.makeKey()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = Self.minimumSize
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.panel)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.delegate = self
        // Reopens where it was left; the very first time, it is centred at the default size.
        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)
        self.window = window
        model.viewerAppeared()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelConfirmations()
        model.viewerDisappeared()
        window = nil
    }
}

/// Lets the window be dragged by the header: a mouse-down here starts a window drag.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
```

- [ ] **Step 2: Write the window's view**

`App/Sources/WindowView.swift`:

```swift
import PortGlimpseCore
import SwiftUI

/// The pop-out window's content. Below 360 points wide the rows switch to their compact layout,
/// and the list always scrolls within whatever height the window has.
struct WindowView<Footer: View>: View {
    static var compactWidth: CGFloat { 360 }

    @Bindable var model: PanelModel
    let footer: Footer

    init(model: PanelModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header(compact: geometry.size.width < Self.compactWidth)
                Divider().overlay(Theme.line)
                ScrollView {
                    PortList(model: model, compact: geometry.size.width < Self.compactWidth)
                }
                Divider().overlay(Theme.line)
                footer
            }
        }
        .frame(minWidth: 300, minHeight: 240)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .onKeyPress(.escape) {
            model.cancelConfirmations()
            return .handled
        }
    }

    /// The traffic lights sit over the leading 78 points; the text ignores clicks so the drag handle gets them.
    private func header(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text("PortGlimpse")
                .font(Theme.title(compact ? 15 : 16))
                .tracking(-0.5)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            LiveBadge(showsLabel: !compact)
        }
        .allowsHitTesting(false)
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(WindowDragHandle())
    }
}
```

- [ ] **Step 3: Give the panel its pop-out button**

In `App/Sources/PortGlimpseApp.swift`, replace `PortGlimpseApp` and `AppDelegate` with:

```swift
@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model, onPopOut: { delegate.popOut() }) {
                PanelFooter(model: delegate.model, loginItem: delegate.loginItem, updates: delegate.updates)
            }
        } label: {
            MenuBarLabel(devCount: delegate.model.devCount, showCount: delegate.model.showCount)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PanelModel()
    let loginItem = LoginItem()
    let updates = UpdateChecker()
    lazy var window = FloatingWindowController(model: model) { [unowned self] in
        AnyView(WindowView(model: model) {
            PanelFooter(model: model, loginItem: loginItem, updates: updates)
        })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        updates.start()
        loginItem.enableOnFirstLaunch()
    }

    /// Opening the window makes it key, which dismisses the menu bar panel.
    func popOut() {
        window.show()
    }
}
```

- [ ] **Step 4: Build and check the window by hand**

Run: `./scripts/test.sh`
Expected: exit code 0.
Start a server (`cd ~/Developer && python3 -m http.server 8765`), run `./scripts/install-local.sh`, and check against the canvas board "Pop-out window":
- The panel header shows the window icon after "Live"; clicking it opens a 420 × 480 window, centred, and the panel closes.
- Clicking the icon again, from the panel, brings the same window forward rather than opening a second.
- The window has no grey title bar: the red, yellow and green buttons sit in the dark header, left of "PortGlimpse".
- Dragging by the header moves the window; dragging on a row does not.
- Clicking into another app leaves the window on top of it.
- Switching desktops with Ctrl-→ keeps it on screen, and it floats over a full-screen app.
- PortGlimpse does not appear in the Dock or in ⌘-Tab.
- Resizing narrower than 360 points switches rows to compact: port and command, a tooltip with the folder, only Kill on hover; Kill's question wraps above Cancel and Kill; the footer label shortens to "Show all".
- It cannot be made smaller than 300 × 240; at that size the list scrolls and the header and footer stay whole.
- Right-clicking a row, at any width, offers Open localhost, Copy PID, Reveal in Finder and Kill…, then the placement choices.
- Kill a server from the window and see the row go; the menu bar count drops too.
- Close with ⌘W, reopen: same size and position. Quit and relaunch: the window starts closed, and opening it restores the last size and position.
- With the window open and the panel closed, the list still refreshes every second: start a new server and see it appear within about a second.
Fix any mismatch with the canvas before committing.

- [ ] **Step 5: Commit**

```bash
./scripts/test.sh
git add App
git commit -m "Add the always-on-top pop-out window"
```

---

### Task 13: README and the final walkthrough

**Files:**
- Create: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the repo's front page and a verified 1.0 build.

- [ ] **Step 1: Write the README**

`README.md`:

```markdown
# PortGlimpse

PortGlimpse is a free Mac menu bar app that shows what is listening on your ports, which project each server belongs to, and lets you stop one after confirming.

## What it shows

- **Dev servers** — your own servers, with their command (`next dev`, `vite`) and project folder.
- **Apps & system** — ports opened by apps and macOS services, collapsed by default.
- **Other users** — ports owned by root or other accounts, view only, when "Show all users' ports" is on.

Right-click a row to always show a program as a dev server, or always hide it.

## Install

PortGlimpse needs macOS 14 or later.
Installation instructions live at https://zewify.com/portglimpse/.

## Build from source

You need Xcode and XcodeGen (`brew install xcodegen`).

- `./scripts/test.sh` runs the tests and builds the app.
- `./scripts/install-local.sh` builds a Release copy into `/Applications` and opens it.

## Privacy

PortGlimpse reads the list of listening ports and process details from macOS on your Mac.
It sends nothing anywhere; the only network request is an optional daily check for a newer release on GitHub.

## Licence

The bundled fonts — Bricolage Grotesque, Figtree and IBM Plex Mono — are under the SIL Open Font License; their licences are in `App/Resources/Fonts`.
```

- [ ] **Step 2: Check the repo for anything identifying**

The patterns that identify the builder live outside every repo, in `~/.config/zewify/identity-denylist` (one extended regex per line, `#` for comments), so this public repo never contains them.
Never copy them into the repo, a commit message or a test.
Run: `grep -v '^#' ~/.config/zewify/identity-denylist | git grep -niEf /dev/stdin -- . ':!*.ttf' || echo "clean"`
Expected: `clean`.
If the denylist file is missing, stop and ask the owner for it rather than skipping the check.
Run: `git log --format='%an <%ae>' | sort -u`
Expected: exactly `Zewify <335855398+Zewify@users.noreply.github.com>`.

- [ ] **Step 3: Final walkthrough on a clean install**

Run: `./scripts/test.sh` and confirm exit code 0.
Run: `./scripts/install-local.sh`.
Repeat every check from Task 10 Step 6, Task 11 Step 4 and Task 12 Step 4 against the installed copy, not the Debug build.
Also check:
- Quit and relaunch: the icon returns, Show all and Show count keep their settings, and overrides are still applied.
- Start 15 servers (`for p in $(seq 9001 9015); do (cd /tmp && nc -l $p &) ; done`): the panel scrolls at 600 points instead of growing off screen; stop them with `pkill -f "nc -l 90"`.
- Memory: `footprint $(pgrep -x "PortGlimpse")` with the panel closed stays under 60 MB.

- [ ] **Step 4: Commit**

In `CLAUDE.md`, add under "Rules that are not obvious":

```markdown
- The menu bar panel's open and close come from its window's key status (`PanelWindowObserver`), because a window-style `MenuBarExtra` keeps its view alive between openings.
- Distribution (Developer ID signing, notarization, `install.sh`, the zewify.com page) is the second plan and is not built yet.
```

```bash
./scripts/test.sh
git add README.md CLAUDE.md
git commit -m "Add the README and record the panel's open detection"
```
