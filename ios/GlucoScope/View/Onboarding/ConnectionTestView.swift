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
                ThemedConnectionTestGraphic(state: model.connectionTestState)

                Spacer()

                ThemedSection {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connection test")
                            .font(.title)
                            .fontWeight(.semibold)

                        ZStack(alignment: .topLeading) {
                            switch model.connectionTestState {
                            case .pending:
                                Text("Testing connectiong, please stand by...")
                                    .font(.subheadline)
                            case .failed(let error):
                                VStack (alignment: .leading){
                                    Text("\(GlucoScopeApp.APP_NAME) failed to connect to your server:")
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(error)
                                        .foregroundStyle(prefs.theme.lowColor)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Text("\nGo back to change your settings and try again")
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            case .success:
                                Text("The connection has been verified, you can now use this server to retrieve your blood glucose values.")
                                    .font(.subheadline)
                            case .none:
                                Text("GlucoScope will now verify your connection settings to see if everything works correctly.")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .font(.subheadline)
                            }

                            Text("\n\n\n")
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.subheadline)
                        }

                        if model.connectionTestState == nil {
                            ThemedButton("Test now", model.testConnection)
                                .disabled(!model.canTest)
                        }
                        else if model.testSuccessful {
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.connectionTestState = nil
        }
    }
}
