import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService
    @EnvironmentObject var dataService: DataSourceService
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        let configuration = dataService.configuration

        RotatingConfigurationView(title: "Connection", header: ThemedServerSettingsGraphic.init) {
            if dataService.isDemoMode {
                Button("Setup GlucoScope") {
                    dataService.stopDemoMode()
                    presentationMode.wrappedValue.dismiss()
                }
            } else {
                ConnectionConfigurationEditor(configuration: configuration) { conf in
                    self.dataService.saveConfiguration(conf)
                } onReset: {
                    dataService.clearConfiguration()
                }
            }
        }
    }
}
