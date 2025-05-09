import SwiftUI

struct GlucoScopeConfigurationView: View {
    @EnvironmentObject var prefs: PreferenceService
    @Binding var configuration: DataSourceConfiguration?

    @State private var url: String = ""
    @State private var api: String = ""

    init(configuration: Binding<DataSourceConfiguration?>) {
        _configuration = configuration

        if let glucoScopeConfig = configuration.wrappedValue as? GlucoScopeDataSourceConfiguration {
            _url = State(initialValue: glucoScopeConfig.url)
        }
    }

    var body: some View {
        TextField("", text: $url, prompt: Text("Server URL").foregroundColor(prefs.theme.textColor.opacity(0.5)))
            .padding(3)
            .background(
                prefs.theme.backgroundColor.cornerRadius(4)
            )
            .foregroundStyle(prefs.theme.textColor)
            .onChange(of: url) { newValue in
                configuration = newValue.isEmpty
                    ? nil
                    : GlucoScopeDataSourceConfiguration(url: newValue)
            }
    }
}
