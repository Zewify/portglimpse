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
