import Foundation
import os
import SwiftUI

protocol DataSource {
    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement]
    func testConnection() async throws -> Bool
}

enum DataSourceType: String, Codable {
    case glucoscope
    case nightscout

    var formattedName: String {
        switch self {
        case .glucoscope: return "GlucoScope"
        case .nightscout: return "Nightscout"
        }
    }
}

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
}
