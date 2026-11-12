import Foundation

/// A small, dependency-free semantic version. Release tags are `v1.2.3`, but a
/// bare `1.2` or `1.2.3-beta.1` is accepted too, because a hand-made tag should
/// never break the updater.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        let split = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = split[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(numbers.count) else { return nil }

        var parts: [Int] = []
        for piece in numbers {
            guard let value = Int(piece), value >= 0 else { return nil }
            parts.append(value)
        }
        while parts.count < 3 { parts.append(0) }

        major = parts[0]
        minor = parts[1]
        patch = parts[2]
        prerelease = split.count == 2 ? String(split[1]) : nil
    }

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        if let prerelease { return base + "-" + prerelease }
        return base
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false          // 1.0.0 is newer than 1.0.0-beta
        case (_, nil): return true
        case let (left?, right?):
            let leftParts = left.split(separator: ".")
            let rightParts = right.split(separator: ".")
            for (a, b) in zip(leftParts, rightParts) where a != b {
                if let ai = Int(a), let bi = Int(b) { return ai < bi }
                return a.localizedStandardCompare(String(b)) == .orderedAscending
            }
            return leftParts.count < rightParts.count
        }
    }
}

public enum UpdateSchedule {
    /// The automatic check is deliberately infrequent: once every 30 days. A
    /// manual check from the menu always runs, regardless of this gate.
    public static let automaticInterval: TimeInterval = 30 * 24 * 60 * 60

    public static func shouldCheck(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= automaticInterval
    }

    /// Compares a release tag with the running bundle version.
    public static func isNewer(_ releaseTag: String, than currentVersion: String) -> Bool {
        guard let release = SemanticVersion(releaseTag),
              let current = SemanticVersion(currentVersion) else { return false }
        return release > current
    }
}
