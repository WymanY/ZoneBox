import Foundation
import ZoneBoxCore

enum GitHubReleaseClientError: Error, Equatable {
    case invalidResponse
    case http(Int)
    case network
}

struct GitHubReleaseClient: Sendable {
    var endpoint: URL
    var session: URLSession
    var userAgent: String

    init(
        endpoint: URL = URL(string: "https://api.github.com/repos/WymanY/ZoneBox/releases/latest")!,
        session: URLSession? = nil,
        userAgent: String = GitHubReleaseClient.defaultUserAgent()
    ) {
        self.endpoint = endpoint
        self.userAgent = userAgent
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.httpAdditionalHeaders = [
                "Accept": "application/vnd.github+json",
                "User-Agent": userAgent,
                "X-GitHub-Api-Version": "2022-11-28",
            ]
            self.session = URLSession(configuration: config)
        }
    }

    func fetchLatest() async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubReleaseClientError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseClientError.http(http.statusCode)
        }
        return data
    }

    static func defaultUserAgent() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "ZoneBox/\(version) (+https://github.com/WymanY/ZoneBox)"
    }
}
