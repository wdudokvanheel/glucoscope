import SwiftUI

struct ConnectionUrlView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @EnvironmentObject private var model: OnboardModel

    var body: some View {
        ThemedScreen {
            VStack {
                Image("OnboardUrl")
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, 32)
                    .padding(.horizontal, 32)

                Spacer()

                ThemedSection {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connection settings")
                            .font(.title)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading) {
                            Text("Enter the address of your \(model.connectionType.formattedName) server")
                                .fontWeight(.light)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.subheadline)

                            ThemedTextField("Server address", $model.url)
                        }

                        VStack(alignment: .leading) {
                            Text("Optionally enter the API token required for authentication")
                                .font(.subheadline)
                                .fontWeight(.light)
                                .fixedSize(horizontal: false, vertical: true)

                            ThemedSecureField("API Token", $model.apiToken)
                        }
                        
                        ThemedNavigationButton("Test connection", ConnectionTestView())
                            .padding(.top, 16)
                    }
                    .padding(16)
                }
                .padding(.top, 32)
            }
        }
        .foregroundStyle(prefs.theme.textColor)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(GlucoScopeApp.APP_NAME)
                    .minimumScaleFactor(0.5)
                    .font(.title)
                    .foregroundStyle(prefs.theme.textColor)
            }
        }
    }
}
