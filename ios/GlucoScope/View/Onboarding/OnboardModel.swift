import SwiftUI

enum ConenctionTestState: Equatable {
    case pending
    case failed(String)
    case success
}

@MainActor
class OnboardModel: ObservableObject {
    @Published var connectionType: DataSourceType = .glucoscope
    @Published var url: String = ""
    @Published var apiToken: String = ""
    @Published var connectionTestState: ConenctionTestState?
    @Published var testedConfiguration: DataSourceConfiguration?

    private let dataSourceService: DataSourceService

    init(_ dataSourceService: DataSourceService) {
        self.dataSourceService = dataSourceService
    }

    var testSuccessful: Bool {
        return connectionTestState != nil && connectionTestState == .success
    }

    var canTest: Bool {
        return connectionTestState == nil || connectionTestState != .pending
    }

    func testConnection() {
        connectionTestState = .pending

        Task.detached { [url = url, apiToken = apiToken, connectionType = connectionType] in
            let datasourceConfiguration = createDataSourceConfiguration(
                url: url, apiToken: apiToken, type: connectionType
            )

            guard let datasource = await self.dataSourceService.createDataSource(from: datasourceConfiguration) else {
                await self.updateTestState(.failed("Failed to apply configuration"))
                return
            }

            do {
                if try await datasource.testConnection() {
                    await MainActor.run {
                        self.testedConfiguration = datasourceConfiguration
                    }
                    await self.updateTestState(.success)
                }
                else {
                    await self.updateTestState(.failed("Failed to reach server"))
                }
            }
            catch let urlError as URLError where urlError.code == .unsupportedURL {
                await self.updateTestState(.failed("Invalid URL"))
            }
            catch NetworkError.invalidResponse {
                await self.updateTestState(.failed("Invalid response from server"))
            }
            catch {
                await self.updateTestState(.failed("Failed \(error)"))
            }
        }
    }

    func completeWizard() {
        if let config = self.testedConfiguration {
            dataSourceService.saveConfiguration(config)
        }
    }

    private func updateTestState(_ state: ConenctionTestState) async {
        await MainActor.run {
            connectionTestState = state
        }
    }
}

private func createDataSourceConfiguration(url: String, apiToken: String, type: DataSourceType) -> DataSourceConfiguration {
    let cleanedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

    switch type {
    case .glucoscope:
        return GlucoScopeDataSourceConfiguration(url: cleanedURL)

    case .nightscout:
        return NightscoutDataSourceConfiguration(
            url: cleanedURL,
            apiToken: cleanedToken.isEmpty ? nil : cleanedToken
        )
    }
}

private func createDataSourceFromConfiguration(url: String, apiToken: String, type: DataSourceType) -> DataSource {
    let cleanedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

    switch type {
    case .glucoscope:
        let config = GlucoScopeDataSourceConfiguration(url: cleanedURL)
        return GlucoScopeDataSource(config)

    case .nightscout:
        let config = NightscoutDataSourceConfiguration(
            url: cleanedURL,
            apiToken: cleanedToken.isEmpty ? nil : cleanedToken
        )
        return NightscoutDataSource(config)
    }
}
