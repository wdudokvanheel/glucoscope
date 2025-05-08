import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject var dataService: DataSourceService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let configuration = dataService.configuration

        Image("SettingsConnection")
            .resizable()
            .scaledToFit()
            .padding(.horizontal, 64)

        ConnectionConfigurationEditor(configuration: configuration) { conf in
            self.dataService.saveConfiguration(conf)
            dismiss()
        } onReset: {
            dataService.clearConfiguration()
        }
        
        Spacer()
    }
}
