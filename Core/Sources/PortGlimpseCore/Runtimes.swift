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
