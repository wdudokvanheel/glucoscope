import SwiftUI

struct IntroView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @EnvironmentObject private var dataService: DataSourceService
    @State private var showDemoAlert = false

    var body: some View {
        ThemedScreen {
            VStack {
                VStack {
                    ThemedLogoGraphic()
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                ThemedSection {
                    VStack(alignment: .leading) {
                        Text("Welcome to \(GlucoScopeApp.APP_NAME)")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Beautiful blood glucose visualization for diabetics")
                            .font(.subheadline)
                            .fontWeight(.light)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 16) {
                            OnboardFeatureList()
                        }
                        .padding(.vertical, 8)

                        ThemedNavigationButton("Get started", ConnectionTypeView())
                    }
                    .padding(16)
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                
                VStack(alignment: .center) {
                    Button("Demo mode") {
                        showDemoAlert = true
                    }
                    .font(.footnote)
                    .opacity(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(prefs.theme.textColor)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Start demo mode?", isPresented: $showDemoAlert) {
            Button("Start") { dataService.startDemoMode() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Demo mode allows you to use the full app, but using fake data. You can setup a connection later in the settings menu. Start GlucoScope in demo mode?")
        }
    }
}

struct Feature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

private let onboardFeatures: [Feature] = [
    .init(icon: "eye",
          title: "Instant insight",
          description: "Quickly see your current and past levels without thinking"),
    .init(icon: "chart.xyaxis.line",
          title: "Beautiful graphs",
          description: "Select one of the many themes to customize your experience"),
    .init(icon: "timer",
          title: "Real time updates",
          description: "Values are updated often so you never miss a high or low")
]

struct OnboardFeatureList: View {
    var body: some View {
        Grid(alignment: .leading,
             horizontalSpacing: 16,
             verticalSpacing: 16)
        {

            ForEach(onboardFeatures) { feature in
                GridRow {
                    Image(systemName: feature.icon)
                        .font(.system(size: 32))
                        .gridColumnAlignment(.center)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(feature.title)
                            .font(.callout).fontWeight(.semibold)
                        Text(feature.description)
                            .font(.footnote).fontWeight(.light)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(0.9)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct OnboardFeatureItem: View {
    let icon: String
    let title: String
    let description: String

    init(_ icon: String, _ title: String, _ description: String) {
        self.icon = icon
        self.title = title
        self.description = description
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .padding(.leading, 0)
                .padding(.trailing, 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)

                Text(description)
                    .fontWeight(.light)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
