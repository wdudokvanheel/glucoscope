import SwiftUI

struct NightscoutConfigurationView: View {
    @EnvironmentObject var prefs: PreferenceService

    @Binding var configuration: DataSourceConfiguration?

    @State private var url: String = ""
    @State private var apiToken: String = ""

    init(configuration: Binding<DataSourceConfiguration?>) {
        _configuration = configuration

        if let nightscoutConfig = configuration.wrappedValue as? NightscoutDataSourceConfiguration {
            _url = State(initialValue: nightscoutConfig.url)
            _apiToken = State(initialValue: nightscoutConfig.apiToken ?? "")
        }
    }

    var body: some View {
        TextField("", text: $url, prompt: Text("Server URL").foregroundColor(prefs.theme.textColor.opacity(0.5)))
            .padding(3)
            .background(
                prefs.theme.backgroundColor.cornerRadius(4)
            )
            .foregroundStyle(prefs.theme.textColor)
            .onChange(of: url) { _ in
                updateConfiguration()
            }

        SecureField("", text: $apiToken, prompt: Text("API Token (optional)").foregroundColor(prefs.theme.textColor.opacity(0.5)))
            .padding(3)
            .background(
                prefs.theme.backgroundColor.cornerRadius(4)
            )
            .foregroundStyle(prefs.theme.textColor)
            .onChange(of: apiToken) { _ in
                updateConfiguration()
            }
    }

    private func updateConfiguration() {
        configuration = url.isEmpty
            ? nil
            : NightscoutDataSourceConfiguration(
                url: url,
                apiToken: apiToken.isEmpty ? nil : apiToken
            )
    }
}
