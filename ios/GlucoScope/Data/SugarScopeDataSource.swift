import Foundation
import os

struct SugarScopeDataSourceConfiguration: DataSourceConfiguration {
    static let typeIdentifier = DataSourceType.sugarscope.rawValue

    let url: String
}

class SugarScopeDataSource: DataSource {
    private let logger = Logger.new("datasource.sugarscope")
    private let configuration: SugarScopeDataSourceConfiguration
    
    private var baseUrl: String {
        if !configuration.url.starts(with: "http") {
            return "http://\(configuration.url)/api/s1"
        } else {
            return "\(configuration.url)/api/s1"
        }
    }
    
    init(_ configuration: SugarScopeDataSourceConfiguration) {
        self.configuration = configuration
    }
    
    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(baseUrl)/status") else {
            logger.warning("\(self.baseUrl)/status")
            logger.error("Invalid status URL!")
            throw NetworkError.invalidURL
        }
           
        let (data, response) = try await URLSession.shared.data(from: url)
           
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            logger.error("Invalid response from SugarScope server")
            throw NetworkError.invalidResponse
        }
           
        do {
            let reply = try JSONDecoder().decode(SugarScopeStatusReplyDto.self, from: data)
            return reply.status.lowercased() == "ok"
        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement] {
        var urlComponents = URLComponents(string: "\(self.baseUrl)/entries/last")
        urlComponents?.queryItems = [
            URLQueryItem(name: "hours", value: "\(hours)"),
            URLQueryItem(name: "window", value: "\(window)")
        ]
        
        guard let url = urlComponents?.url else {
            logger.error("Invalid URL!")
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            logger.error("Invalid response from SugarScope server")
            throw NetworkError.invalidResponse
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            logger.trace("Response from \(url)\n\(responseString)")
        } else {
            logger.warning("Unable to decode response data as UTF-8 string")
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let measurements = try decoder.decode([GlucoseMeasurement].self, from: data)
            return measurements
        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw error
        }
    }
}

struct SugarScopeStatusReplyDto: Decodable {
    let status: String
}
