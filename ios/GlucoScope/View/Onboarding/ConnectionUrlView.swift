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
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.subheadline)
                                .fontWeight(.light)

                            ThemedTextField("Server address", $model.url)
                        }

                        VStack(alignment: .leading) {
                            Text("Optionally enter the API token required for authentication")
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.subheadline)
                                .fontWeight(.light)

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
                Text(SugarScopeApp.APP_NAME)
                    .minimumScaleFactor(0.5)
                    .font(.title)
                    .foregroundStyle(prefs.theme.textColor)
            }
        }

//        VStack {
//            Text("Enter url & API Key")
//            Spacer()
//
//            ThemedNavigationButton("Test connection", ConnectionTestView())
//
//            NavigationLink(destination: ConnectionTestView()) {
//                Text("Next")
//                    .frame(maxWidth: .infinity)
//            }
//            .buttonStyle(.borderedProminent)
//            .tint(prefs.theme.accentColor)
//        }
//        .padding(32)
    }
}
