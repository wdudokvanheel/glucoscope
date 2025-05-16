import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService
    @EnvironmentObject var dataService: DataSourceService

    var body: some View {
        VStack {
            let configuration = dataService.configuration

            ThemedServerSettingsGraphic()

            Spacer()

            ConnectionConfigurationEditor(configuration: configuration) { conf in
                self.dataService.saveConfiguration(conf)
            } onReset: {
                dataService.clearConfiguration()
            }
            .padding(.bottom, 16)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Connection")
                    .minimumScaleFactor(0.5)
                    .font(.title)
                    .foregroundStyle(prefs.theme.textColor)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
