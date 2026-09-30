import Foundation

/// Turns a process's arguments into the short command a row shows: `next dev`, not `node`.
public enum CommandLabel {
    static let maxLength = 40
    static let scriptSuffixes = [".js", ".mjs", ".cjs", ".ts", ".py", ".rb", ".php", ".jar"]

    public static func label(arguments: [String], fallbackName: String) -> String {
        guard let first = arguments.first, !first.isEmpty else { return truncate(fallbackName) }
        let executable = baseName(first)
        guard Runtimes.isRuntime(executable) else {
            // A runtime that retitled itself (Next.js sets "next-server (v14.2.18)", Puma "puma 6.4.2 (tcp://…)")
            // is best named by its own title, cut to the first word.
            if Runtimes.isRuntime(fallbackName) {
                let title = first.hasPrefix("/") ? baseName(first) : first
                let word = title.split(separator: " ").first.map(String.init) ?? title
                return truncate(word)
            }
            // Servers such as redis and postgres rewrite their process title, so argv[0] can read
            // "redis-server 127.0.0.1:6379". The executable's own file name is the clean label.
            return truncate(fallbackName.isEmpty ? executable : fallbackName)
        }

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
