import Foundation
import os

protocol DataSourceConfiguration: Codable {
    static var typeIdentifier: String { get }
}

// Wrapper around DataSourceConfiguration for persistence
struct DataSourceConfigurationStorage: Codable {
    let config: DataSourceConfiguration

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(config: DataSourceConfiguration) {
        self.config = config
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type(of: config).typeIdentifier, forKey: .type)
        try container.encode(config, forKey: .data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeIdentifier = try container.decode(String.self, forKey: .type)

        switch typeIdentifier {
        case GlucoScopeDataSourceConfiguration.typeIdentifier:
            config = try container.decode(GlucoScopeDataSourceConfiguration.self, forKey: .data)
        case NightscoutDataSourceConfiguration.typeIdentifier:
            config = try container.decode(NightscoutDataSourceConfiguration.self, forKey: .data)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type,
                                                   in: container,
                                                   debugDescription: "Unknown DataSourceConfiguration type: \(typeIdentifier)")
        }
    }
}
