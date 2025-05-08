import Combine
import Foundation
import SwiftUI

class RealtimeDataService: ObservableObject {
    @Published var measurements: [GlucoseMeasurement] = []
    @Published var currentValue: Double?
    @Published var lastUpdate: Date? = nil
    @Published var window = 5
    @Published var hours = 12
    
    private var dataSourceService: DataSourceService

    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    
    init(dataSourceService: DataSourceService) {
        self.dataSourceService = dataSourceService
        observeDataSource()
        observeAppLifecycle()
    }
    
    private func onDataSourceAvailable(_ datasource: DataSource) {
        fetchLatestEntries(datasource)
        startBackgroundFetch(datasource)
    }
    
    private func startBackgroundFetch(_ datasource: DataSource) {
        stopBackgroundFetch()
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchLatestEntries(datasource)
            }
    }
    
    private func stopBackgroundFetch(){
        timer?.cancel()
    }
    
    func refresh(){
        stopBackgroundFetch()
        self.measurements = []
        
        guard let datasource = self.dataSourceService.datasource else { return }
        self.fetchLatestEntries(datasource)
        self.startBackgroundFetch(datasource)
    }
    
    private func fetchLatestEntries(_ datasource: DataSource) {
        Task {
            let values = try await datasource.getLatestEntries(hours: self.hours, window: self.window)
            DispatchQueue.main.async {
                self.measurements = values
                self.currentValue = values.last?.value
                self.lastUpdate = Date()
            }
        }
    }
    
    private func observeDataSource() {
        dataSourceService.$datasource
            .compactMap { $0 } // Ignore nil values
            .sink { [weak self] datasource in
                self?.onDataSourceAvailable(datasource)
            }
            .store(in: &cancellables)
    }
    
    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self = self, let datasource = self.dataSourceService.datasource else { return }
                self.startBackgroundFetch(datasource)
            }
            .store(in: &cancellables)
    }
}
