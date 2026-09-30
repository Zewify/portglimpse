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
