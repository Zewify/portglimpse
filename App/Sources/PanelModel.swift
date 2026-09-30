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
    private var isPanelOpen = false
    private var refreshCounter = 0
    private var appliedRefresh = 0
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

    /// Idempotent: the window can report becoming key more than once without resigning.
    func panelOpened() {
        guard !isPanelOpen else { return }
        isPanelOpen = true
        viewerAppeared()
    }

    /// Clicking away from the menu bar panel withdraws any question it was asking.
    func panelClosed() {
        guard isPanelOpen else { return }
        isPanelOpen = false
        viewerDisappeared()
        cancelConfirmations()
    }

    func refresh() async {
        // Scans can overlap and finish out of order; only a result newer than the last one applied is used,
        // so a scan begun before a kill cannot bring the killed row back.
        refreshCounter += 1
        let generation = refreshCounter
        let showAll = showAll
        let overrides = overrideStore.overrides
        let result = await Task.detached(priority: .utility) { PortScan.run(showAll: showAll, overrides: overrides) }.value
        guard generation > appliedRefresh else { return }
        appliedRefresh = generation
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

    /// Escape's action: withdraws any question showing and reports whether there was one, so the key is consumed only then.
    func withdrawQuestion() -> Bool {
        let asking = rows.contains { [.confirming, .stillRunning].contains(phase(of: $0)) }
        cancelConfirmations()
        return asking
    }

    func cancelConfirmations() {
        phases = phases.filter { $0.value != .confirming && $0.value != .stillRunning }
    }

    func confirmKill(_ row: Row) {
        guard phase(of: row) == .confirming else { return }
        run(row) { terminator, pid in await terminator.stop(pid) }
    }

    func confirmForceKill(_ row: Row) {
        guard phase(of: row) == .stillRunning else { return }
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
                // With nothing showing, a question would be stale by the time the panel reopens.
                phases[pid] = viewers == 0 ? nil : .stillRunning
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
