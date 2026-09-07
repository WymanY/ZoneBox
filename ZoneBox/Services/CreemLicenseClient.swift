import Foundation
import ZoneBoxCore

struct CreemLicenseResult: Equatable, Sendable {
    var status: LicenseValidationStatus
    var key: String?
    var instanceID: String?
    var expiresAt: Date?
}

enum CreemLicenseError: LocalizedError, Equatable {
    case notConfigured
    case invalidKey
    case activationLimit
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.text(.licenseErrorNotConfigured)
        case .invalidKey:
            return L10n.text(.licenseErrorInvalid)
        case .activationLimit:
            return L10n.text(.licenseErrorActivationLimit)
        case .network:
            return L10n.text(.licenseErrorNetwork)
        case .server(let message):
            return message
        }
    }
}

struct CreemLicenseClient: Sendable {
    var endpoint: URL
    var session: URLSession

    init(endpoint: URL = LicenseConfig.licenseAPIURL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func activate(key: String, instanceName: String) async throws -> CreemLicenseResult {
        try await post(action: "activate", body: [
            "key": key,
            "instance_name": instanceName,
        ])
    }

    func validate(key: String, instanceID: String) async throws -> CreemLicenseResult {
        try await post(action: "validate", body: [
            "key": key,
            "instance_id": instanceID,
        ])
    }

    func deactivate(key: String, instanceID: String) async throws -> CreemLicenseResult {
        try await post(action: "deactivate", body: [
            "key": key,
            "instance_id": instanceID,
        ])
    }

    private func post(action: String, body: [String: String]) async throws -> CreemLicenseResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var payload = body
        payload["action"] = action
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CreemLicenseError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 503, (json["error"] as? String) == "not_configured" {
            throw CreemLicenseError.notConfigured
        }
        if status == 400 || status == 401 || status == 404 {
            throw CreemLicenseError.invalidKey
        }
        if status == 403 {
            throw CreemLicenseError.activationLimit
        }
        if status >= 400 {
            let message = (json["error"] as? String)
                ?? (json["message"] as? String)
                ?? L10n.text(.licenseErrorServer)
            throw CreemLicenseError.server(message)
        }
        let parsed = CreemLicensePayload.parse(json)
        return CreemLicenseResult(
            status: parsed.status,
            key: parsed.key,
            instanceID: parsed.instanceID,
            expiresAt: parsed.expiresAt
        )
    }
}
