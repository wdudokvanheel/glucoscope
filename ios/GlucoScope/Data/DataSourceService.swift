import Foundation
import os
import SwiftUI

class DataSourceService: ObservableObject {
    private let logger = Logger.new("datasource.service")

    private let prefences: PreferenceService

    @Published
    public var configuration: DataSourceConfiguration?
    @Published
    public var datasource: DataSource?

    init(prefences: PreferenceService) {
        self.prefences = prefences
        self.configuration = loadConfiguration()
        initDataSource()
    }

    private func initDataSource() {
        if let config = configuration {
            datasource = createDataSource(from: config)
        }
    }

    private func loadConfiguration() -> DataSourceConfiguration? {
        // TODO: Convert to new preference system
        guard let jsonString: String = prefences.connection,
              let jsonData = jsonString.data(using: .utf8)
        else {
            logger.debug("No configuration found")
            return nil
        }

        logger.trace("Configuration data: \(jsonString)")

        do {
            let storedConfig = try JSONDecoder().decode(DataSourceConfigurationStorage.self, from: jsonData)
            return storedConfig.config
        } catch {
            logger.warning("Failed to decode stored configuration: \(error.localizedDescription)")
            return nil
        }
    }

    func saveConfiguration(_ config: DataSourceConfiguration) {
        do {
            let storage = DataSourceConfigurationStorage(config: config)
            let jsonData = try JSONEncoder().encode(storage)
            let jsonString = String(data: jsonData, encoding: .utf8)

            logger.trace("Saving configuration: \(jsonString!)")

            prefences.connection = jsonString

            configuration = config
            initDataSource()
        } catch {
            logger.error("Failed to save configuration: \(error.localizedDescription)")
        }
    }

    func createDataSource(from config: DataSourceConfiguration) -> DataSource? {
        switch config {
        case let config as GlucoScopeDataSourceConfiguration:
            return GlucoScopeDataSource(config)
        case let config as NightscoutDataSourceConfiguration:
            return NightscoutDataSource(config)
        default:
            logger.error("Unregistered DataSourceConfiguration type")
            return nil
        }
    }
    
    func clearConfiguration() {
        logger.debug("Removing current configuration")
        configuration = nil
        datasource = nil
        prefences.connection = nil
    }
}
