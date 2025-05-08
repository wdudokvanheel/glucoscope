import Foundation
import os

struct NightscoutDataSourceConfiguration: DataSourceConfiguration {
    static let typeIdentifier = DataSourceType.nightscout.rawValue

    let url: String
    let apiToken: String?
}

class NightscoutDataSource: DataSource {
    private let logger = Logger.new("datasource.nightscout")
    private let configuration: NightscoutDataSourceConfiguration

    init(_ configuration: NightscoutDataSourceConfiguration) {
        self.configuration = configuration
    }

    func testConnection() async throws -> Bool {
        var url = "\(configuration.url)/api/v1/status.json"

        if let token = configuration.apiToken {
            url = url + "?token=\(token)"
        }

        guard let url = URL(string: url) else {
            logger.error("Invalid URL")
            throw NetworkError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            logger.error("Invalid response from NightScout server")
            throw NetworkError.invalidResponse
        }

        do {
            let reply = try JSONDecoder().decode(NightscoutStatusReplyDTO.self, from: data)
            return reply.status.lowercased() == "ok"
        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw error
        }
    }

    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement] {
        let pastTime = Date().addingTimeInterval(-TimeInterval(hours * 60 * 60))
        let timestamp = Int(pastTime.timeIntervalSince1970 * 1000)
        let requestedCount = hours * 60

        var url = "\(configuration.url)/api/v1/entries.json"

        if let token = configuration.apiToken {
            url = url + "?token=\(token)"
        }

        guard var urlComponents = URLComponents(string: url) else {
            logger.error("Invalid URL")
            throw NetworkError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "find[date][$gte]", value: "\(timestamp)"),
            URLQueryItem(name: "count", value: "\(requestedCount)"),
        ]

        guard let url = urlComponents.url else {
            logger.error("Failed to construct valid Nightscout URL")
            throw NetworkError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            logger.error("Invalid response from Nightscout server")
            throw NetworkError.invalidResponse
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let nightscoutEntries = try decoder.decode([NightscoutEntryDTO].self, from: data)

            // Nightscout will always return entries with a 1m interval, group them manually here
            if window > 1 {
                return groupEntriesIntoIntervals(entries: nightscoutEntries, window: window)
            }
            return nightscoutEntries.map { $0.toGlucoseMeasurement() }.reversed()

        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw error
        }
    }

    private func groupEntriesIntoIntervals(entries: [NightscoutEntryDTO], window: Int) -> [GlucoseMeasurement] {
        let interval = TimeInterval(window * 60 * 1000)

        let groupedEntries = Dictionary(grouping: entries) { (entry: NightscoutEntryDTO) -> Int in
            Int(entry.date / interval)
        }

        let aggregatedMeasurements: [GlucoseMeasurement] = groupedEntries.values.map { group in
            let totalSGV = group.reduce(0.0) { $0 + $1.sgv }
            let avgSGV = totalSGV / Double(group.count)

            let totalDate = group.reduce(0.0) { $0 + $1.date }
            let avgDate = totalDate / Double(group.count)

            return GlucoseMeasurement(time: avgDate / 1000, value: avgSGV.toMmol())
        }

        return aggregatedMeasurements.sorted { $0.time < $1.time }
    }
}

struct NightscoutEntryDTO: Decodable {
    let sgv: Double // Sensor glucose value
    let date: TimeInterval // Epoch time in milliseconds

    func toGlucoseMeasurement() -> GlucoseMeasurement {
        return GlucoseMeasurement(time: date / 1000, value: sgv.toMmol())
    }
}

struct NightscoutStatusReplyDTO: Decodable {
    let status: String
}
