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
            if isEnabled {
                remember(defaults.string(forKey: Keys.latestKnown).flatMap(AppVersion.init))
                Task { await check(force: true) }
            } else {
                available = nil
            }
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
        var request = URLRequest(url: Self.feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Only a request that got an HTTP response uses up the day; offline or timeout retries on the next pass.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        defaults.set(Date(), forKey: Keys.lastCheck)
        guard http.statusCode == 200,
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
