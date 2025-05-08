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
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.subheadline)
                            .fontWeight(.light)

                        VStack(spacing: 16) {
                            OnboardFeatureItem("hourglass", "Instant insight", "Quickly see your current and past levels without thinking")
                            OnboardFeatureItem("hourglass", "Instant insight", "Quickly see your current and past levels without thinking")
                            OnboardFeatureItem("hourglass", "Instant insight", "Quickly see your current and past levels without thinking")
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
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.footnote)
                    .fontWeight(.light)
            }
        }
    }
}
