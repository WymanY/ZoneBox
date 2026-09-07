import Foundation

public enum LicenseValidationStatus: String, Codable, Sendable, Equatable {
    case active
    case inactive
    case expired
    case disabled
    case unknown
}

public struct LicenseRecord: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var trialStartedAt: Date
    public var licenseKey: String?
    public var instanceID: String?
    public var lastValidatedAt: Date?
    public var lastValidationStatus: LicenseValidationStatus
    public var cachedExpiresAt: Date?

    public init(
        schemaVersion: Int = 1,
        trialStartedAt: Date,
        licenseKey: String? = nil,
        instanceID: String? = nil,
        lastValidatedAt: Date? = nil,
        lastValidationStatus: LicenseValidationStatus = .unknown,
        cachedExpiresAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.trialStartedAt = trialStartedAt
        self.licenseKey = licenseKey
        self.instanceID = instanceID
        self.lastValidatedAt = lastValidatedAt
        self.lastValidationStatus = lastValidationStatus
        self.cachedExpiresAt = cachedExpiresAt
    }

    public static func freshTrial(now: Date = Date()) -> LicenseRecord {
        LicenseRecord(trialStartedAt: now)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        trialStartedAt = try c.decodeIfPresent(Date.self, forKey: .trialStartedAt) ?? Date()
        licenseKey = try c.decodeIfPresent(String.self, forKey: .licenseKey)
        instanceID = try c.decodeIfPresent(String.self, forKey: .instanceID)
        lastValidatedAt = try c.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        lastValidationStatus = try c.decodeIfPresent(
            LicenseValidationStatus.self,
            forKey: .lastValidationStatus
        ) ?? .unknown
        cachedExpiresAt = try c.decodeIfPresent(Date.self, forKey: .cachedExpiresAt)
    }
}

public enum LicenseKind: Equatable, Sendable {
    case licensed
    case trial
    case offlineGrace
    case expired
}

public struct LicenseSnapshot: Equatable, Sendable {
    public var kind: LicenseKind
    public var allowsPro: Bool
    public var trialDaysRemaining: Int
    public var maskedKey: String?
    public var expiresAt: Date?

    public static let trialLengthDays = 14
    public static let offlineGraceDays = 30

    public init(
        kind: LicenseKind,
        allowsPro: Bool,
        trialDaysRemaining: Int,
        maskedKey: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.kind = kind
        self.allowsPro = allowsPro
        self.trialDaysRemaining = trialDaysRemaining
        self.maskedKey = maskedKey
        self.expiresAt = expiresAt
    }
}

public enum LicenseAccess {
    public static let trialLength: TimeInterval = TimeInterval(LicenseSnapshot.trialLengthDays * 24 * 60 * 60)
    public static let offlineGrace: TimeInterval = TimeInterval(LicenseSnapshot.offlineGraceDays * 24 * 60 * 60)

    public static func snapshot(_ record: LicenseRecord, now: Date = Date()) -> LicenseSnapshot {
        let trialEnd = record.trialStartedAt.addingTimeInterval(trialLength)
        let trialRemaining = daysRemaining(from: now, to: trialEnd)
        let masked = record.licenseKey.map(mask)

        if let key = record.licenseKey, record.instanceID != nil {
            if let expires = record.cachedExpiresAt, expires <= now {
                return LicenseSnapshot(
                    kind: .expired,
                    allowsPro: false,
                    trialDaysRemaining: 0,
                    maskedKey: mask(key),
                    expiresAt: expires
                )
            }
            switch record.lastValidationStatus {
            case .active:
                if let validated = record.lastValidatedAt,
                   now.timeIntervalSince(validated) <= offlineGrace
                {
                    let kind: LicenseKind = now.timeIntervalSince(validated) <= 7 * 24 * 60 * 60
                        ? .licensed
                        : .offlineGrace
                    return LicenseSnapshot(
                        kind: kind,
                        allowsPro: true,
                        trialDaysRemaining: trialRemaining,
                        maskedKey: mask(key),
                        expiresAt: record.cachedExpiresAt
                    )
                }
            case .expired, .disabled, .inactive:
                return LicenseSnapshot(
                    kind: .expired,
                    allowsPro: false,
                    trialDaysRemaining: 0,
                    maskedKey: mask(key),
                    expiresAt: record.cachedExpiresAt
                )
            case .unknown:
                break
            }
        }

        if now < trialEnd {
            return LicenseSnapshot(
                kind: .trial,
                allowsPro: true,
                trialDaysRemaining: max(1, trialRemaining),
                maskedKey: masked,
                expiresAt: trialEnd
            )
        }
        return LicenseSnapshot(
            kind: .expired,
            allowsPro: false,
            trialDaysRemaining: 0,
            maskedKey: masked,
            expiresAt: nil
        )
    }

    public static func mask(_ key: String) -> String {
        let compact = key.filter { !$0.isWhitespace }
        guard compact.count > 5 else { return "•••••" }
        return "•••••" + compact.suffix(5)
    }

    public static func daysRemaining(from now: Date, to end: Date) -> Int {
        let seconds = end.timeIntervalSince(now)
        if seconds <= 0 { return 0 }
        return Int(ceil(seconds / 86_400))
    }
}

public struct CreemLicensePayload: Equatable, Sendable {
    public var status: LicenseValidationStatus
    public var key: String?
    public var instanceID: String?
    public var expiresAt: Date?

    public static func parse(_ json: [String: Any]) -> CreemLicensePayload {
        let rawStatus = (json["status"] as? String)?.lowercased() ?? "unknown"
        let status = LicenseValidationStatus(rawValue: rawStatus) ?? .unknown
        let key = json["key"] as? String
        return CreemLicensePayload(
            status: status,
            key: key,
            instanceID: instanceID(from: json),
            expiresAt: date(json["expires_at"])
        )
    }

    public static func instanceID(from json: [String: Any]) -> String? {
        if let instance = json["instance"] as? [String: Any] {
            return instance["id"] as? String
        }
        if let instances = json["instance"] as? [[String: Any]] {
            return instances.first { ($0["status"] as? String)?.lowercased() == "active" }?["id"] as? String
                ?? instances.first?["id"] as? String
        }
        return json["instance_id"] as? String
    }

    public static func date(_ raw: Any?) -> Date? {
        if raw == nil || raw is NSNull { return nil }
        if let value = raw as? Date { return value }
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "<null>", trimmed.lowercased() != "null" else { return nil }
        if let parsed = ISO8601DateFormatter.internet.date(from: trimmed) {
            return parsed
        }
        return ISO8601DateFormatter.plain.date(from: trimmed)
    }
}

private extension ISO8601DateFormatter {
    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
