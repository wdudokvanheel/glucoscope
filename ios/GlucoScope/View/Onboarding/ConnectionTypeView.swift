import SwiftUI

struct ConnectionTypeView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @EnvironmentObject private var model: OnboardModel

    var body: some View {
        ThemedScreen {
            VStack {
                Image("OnboardConnection")
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, 32)
                    .padding(.horizontal, 32)

                Spacer()

                ThemedSection {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection type")
                            .font(.title)
                            .fontWeight(.semibold)

                        Text("In order to retrieve your blood glucose values, we need to connect to a cloud service.")
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.subheadline)
                            .fontWeight(.light)

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Are you using Nightscout or SugarScope to store your blood glucose values?")
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.subheadline)
                                .fontWeight(.light)

                            Picker("Server type", selection: $model.connectionType) {
                                Text("SugarScope").tag(DataSourceType.sugarscope)
                                Text("Nightscout").tag(DataSourceType.nightscout)
                            }
                            .onAppear {
                                UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(prefs.theme.accentColor)
                                UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(prefs.theme.indicatorLabelColor)], for: .selected)
                                UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(prefs.theme.textColor)], for: .normal)
                                UISegmentedControl.appearance().backgroundColor = UIColor(prefs.theme.surfaceColor)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 0)
                        }
                        .padding(.horizontal, 0)
                        .padding(.vertical, 32)

                        ThemedNavigationButton("Continue", ConnectionUrlView())
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
