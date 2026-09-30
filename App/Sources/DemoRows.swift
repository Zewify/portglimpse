#if DEBUG
import Foundation
import PortGlimpseCore

/// Made-up rows for the website's screenshots (`-PortGlimpseDemo YES` on a Debug build).
/// The PIDs are far above any real one, so the Terminator refuses them as already exited.
enum DemoRows {
    static let enabled = UserDefaults.standard.bool(forKey: "PortGlimpseDemo")

    static let rows: [Row] = [
        Row(pid: 990_001, ports: [3000], command: "next dev", folder: "~/Developer/shop/web", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/node"),
        Row(pid: 990_002, ports: [5173], command: "vite", folder: "~/Developer/shop/admin", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/node"),
        Row(pid: 990_003, ports: [8000], command: "granian asgi", folder: "~/Developer/shop/api", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/python3", workerPIDs: [990_004, 990_005]),
        Row(pid: 990_006, ports: [5432], command: "postgres", folder: "/opt/homebrew/var/postgresql@17", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/postgres"),
        Row(pid: 990_007, ports: [6379], command: "redis-server", folder: "/opt/homebrew/var/db/redis", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/redis-server"),
        Row(pid: 990_008, ports: [5000, 7000], command: "ControlCenter", folder: nil, owner: nil, section: .appsAndSystem, executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"),
        Row(pid: 990_009, ports: [49152], command: "rapportd", folder: nil, owner: nil, section: .appsAndSystem, executablePath: "/usr/libexec/rapportd"),
    ]
}
#endif
