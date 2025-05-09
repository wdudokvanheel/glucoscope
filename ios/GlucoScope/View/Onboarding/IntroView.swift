import SwiftUI

struct IntroView: View {
    @EnvironmentObject private var prefs: PreferenceService

    var body: some View {
        ThemedScreen {
            VStack {
                Image("OnboardLogo")
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, 32)
                    .padding(.horizontal, 32)

                Spacer()

                ThemedSection {
                    VStack(alignment: .leading) {
                        Text("Welcome to \(GlucoScopeApp.APP_NAME)")
                            .font(.title)
                            .fontWeight(.semibold)

                        Text("Beautiful blood glucose visualization for diabetics")
                            .font(.subheadline)
                            .fontWeight(.light)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 16) {
                            OnboardFeatureList()
//                            OnboardFeatureItem("eye", "Instant insight", "Quickly see your current and past levels without thinking")
//                            OnboardFeatureItem("chart.xyaxis.line", "Beautiful graphs", "Select one of the many themes to customize your experience")
//                            OnboardFeatureItem("timer", "Real time updates", "Values are updated often so you never miss a high or low")
                        }
                        .padding(.vertical, 32)

                        ThemedNavigationButton("Get started", ConnectionTypeView())
                    }
                    .padding(16)
                }
                .padding(.top, 32)
            }
        }
        .foregroundStyle(prefs.theme.textColor)
    }
}

// MARK: – Model of one feature line

struct Feature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// Your three lines
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
                        .font(.system(size: 34))
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
