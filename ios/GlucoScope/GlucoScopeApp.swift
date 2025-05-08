import SwiftUI

@main
struct SugarScopeApp: App {
    public static let APP_NAME = "GlucoScope"

    private let preferences: PreferenceService
    private let dataService: DataSourceService
    private let realTimeDataSource: RealtimeDataService

    init() {
        self.preferences = PreferenceService()
        self.dataService = DataSourceService(prefences: preferences)
        self.realTimeDataSource = RealtimeDataService(dataSourceService: dataService)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.red

                NavigationView {
                    AppView()
                }
            }
            .accentColor(preferences.theme.accentColor)
            .environmentObject(preferences)
            .environmentObject(OnboardModel(dataService))
            .environmentObject(dataService)
            .environmentObject(realTimeDataSource)
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}
