import Foundation
import os
import SwiftUI

protocol DataSource {
    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement]
    func testConnection() async throws -> Bool
}

enum DataSourceType: String, Codable {
    case sugarscope
    case nightscout

    var formattedName: String {
        switch self {
        case .sugarscope: return "SugarScope"
        case .nightscout: return "Nightscout"
        }
    }
}

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
}
