import Foundation
import os

struct GlucoScopeDataSourceConfiguration: DataSourceConfiguration {
    static let typeIdentifier = DataSourceType.glucoscope.rawValue

    let url: String
    let apiToken: String?
}

class GlucoScopeDataSource: DataSource {
    private let logger = Logger.new("datasource.glucoscope")
    private let configuration: GlucoScopeDataSourceConfiguration

    private var baseUrl: String {
        if !configuration.url.lowercased().starts(with: "http") {
            return "https://\(configuration.url)/api/s1"
        } else {
            return "\(configuration.url)/api/s1"
        }
    }

    init(_ configuration: GlucoScopeDataSourceConfiguration) {
        self.configuration = configuration
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(baseUrl)/status") else {
            logger.error("Invalid status URL: \(self.baseUrl)/status")
            throw NetworkError.invalidURL
        }

        let reply: GlucoScopeStatusReplyDto = try await fetch(GlucoScopeStatusReplyDto.self, from: url)
        return reply.status.lowercased() == "ok"
    }

    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement] {
        var components = URLComponents(string: "\(baseUrl)/entries/last")
        components?.queryItems = [
            URLQueryItem(name: "hours", value: "\(hours)"),
            URLQueryItem(name: "window", value: "\(window)")
        ]

        guard let url = components?.url else {
            logger.error("Invalid entries URL")
            throw NetworkError.invalidURL
        }

        return try await fetch([GlucoseMeasurement].self, from: url)
    }

    /// Builds a `URLRequest` for the given URL, injecting the Authorization header when an API token is provided.
    private func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        if let token = configuration.apiToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let request = makeRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Non‑HTTP response from GlucoScope server")
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            logger.error("Unauthorized (status: \(httpResponse.statusCode)) – check API token")
            throw NetworkError.unauthorized
        default:
            logger.error("Unexpected status code \(httpResponse.statusCode) from GlucoScope server")
            throw NetworkError.invalidResponse
        }

        if let responseString = String(data: data, encoding: .utf8) {
            logger.trace("Response from \(url)\n\(responseString)")
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw error
        }
    }
}

struct GlucoScopeStatusReplyDto: Decodable {
    let status: String
}
