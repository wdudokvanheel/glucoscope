import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService
    @EnvironmentObject var dataService: DataSourceService

    var body: some View {
        let configuration = dataService.configuration

        RotatingConfigurationView(title: "Connection", header: ThemedServerSettingsGraphic.init) {
            ConnectionConfigurationEditor(configuration: configuration) { conf in
                self.dataService.saveConfiguration(conf)
            } onReset: {
                dataService.clearConfiguration()
            }
        }
    }
}
