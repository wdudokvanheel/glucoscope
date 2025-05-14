import SwiftUI

@main
struct GlucoScopeApp: App {
    public static let APP_NAME = "GlucoScope"
    public static let URL_LICENSE = "https://wdudokvanheel.github.io/glucoscope/license.html"
    public static let URL_PRIVACY = "https://wdudokvanheel.github.io/glucoscope/privacy.html"
    public static let URL_SOURCE = "https://github.com/wdudokvanheel/glucoscope/"
    

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
