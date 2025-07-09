import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService
    @EnvironmentObject var dataService: DataSourceService

    var body: some View {
        let configuration = dataService.configuration

        RotatingConfigurationView(title: "Connection", header: ThemedServerSettingsGraphic.init) {
            if dataService.isDemoMode {
                Text("Demo mode")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(prefs.theme.textColor)
                    .font(.body)
                
                Text("Currently in demonstration mode. Please run the setup to connect to a server.")
                    .font(.body)
                VStack{
                    ThemedButton("Setup GlucoScope") {
                        dataService.stopDemoMode()
                    }
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
