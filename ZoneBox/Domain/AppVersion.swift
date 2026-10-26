import Foundation

public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var prerelease: [String]
    public var original: String

    public var isStable: Bool { prerelease.isEmpty }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        if prerelease.isEmpty { return core }
        return core + "-" + prerelease.joined(separator: ".")
    }

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = [], original: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.original = original ?? {
            let core = "\(major).\(minor).\(patch)"
            return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
        }()
    }

    public static func parse(_ raw: String) -> AppVersion? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var text = trimmed
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        let plusParts = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard plusParts.count <= 2, !plusParts[0].isEmpty else { return nil }
        if plusParts.count == 2, plusParts[1].isEmpty { return nil }
        text = String(plusParts[0])
        // Channel tags are stable numeric versions. Hyphenated prerelease labels are not accepted.
        guard !text.contains("-") else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        numbers.reserveCapacity(parts.count)
        for part in parts {
            guard let value = parseComponent(part) else { return nil }
            numbers.append(value)
        }
        return AppVersion(
            major: numbers[0],
            minor: numbers.count > 1 ? numbers[1] : 0,
            patch: numbers.count > 2 ? numbers[2] : 0,
            prerelease: [],
            original: trimmed
        )
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return false
    }

    private static func parseComponent(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        if raw.count > 1, raw.first == "0" { return nil }
        return Int(raw)
    }
}

extension AppVersion: Equatable {
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }
}
