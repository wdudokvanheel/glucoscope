import SwiftUI

struct ConnectionTestView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @EnvironmentObject private var model: OnboardModel

    var imageName: String {
        guard let state = model.connectionTestState else {
            return "Pending"
        }

        return switch state {
            case .success: "Success"
            case .failed: "Fail"
            case .pending: "Pending"
        }
    }

    var body: some View {

        ThemedScreen {
            VStack {
                Image("OnboardTest\(imageName)")
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, 32)
                    .padding(.horizontal, 32)

                Spacer()

                ThemedSection {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connection test")
                            .font(.title)
                            .fontWeight(.semibold)

                        Text("GlucoScope will now verify your connection settings to see if everything works correctly.")
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.subheadline)

                        switch model.connectionTestState {
                            case .pending:
                                Text("Testing connectiong, please stand by...")
                                    .font(.subheadline)
                            case .failed(let error):
                                Text("Failed to connect: \(error)")
                                    .foregroundStyle(prefs.theme.upperColor)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .success:
                                Text("The connection has been verified, you can now use this server to retrieve your blood glucose values.")
                                    .font(.subheadline)
                            case .none:
                                Text("Testing connectiong, please stand by...")
                                    .font(.subheadline)
                        }

                        if model.testSuccessful {
                            ThemedButton("Start using \(GlucoScopeApp.APP_NAME)", model.completeWizard)
                        }
                        else {
                            ThemedButton("Test again", model.testConnection)
                                .disabled(!model.canTest)
                        }
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
        .onAppear {
            model.testConnection()
        }
    }
}
