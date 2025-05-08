import SwiftUI

struct AppView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @EnvironmentObject private var dataService: DataSourceService

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: prefs.theme.background)
                .ignoresSafeArea()

            if dataService.datasource != nil {
                MainView()
            }
            else {
                IntroView()
            }
        }
    }
}
