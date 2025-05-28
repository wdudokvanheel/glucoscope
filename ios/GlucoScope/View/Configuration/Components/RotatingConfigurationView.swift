import SwiftUI

struct RotatingConfigurationView<Header: View, Content: View>: View {
    @EnvironmentObject private var prefs: PreferenceService

    private let title: String
    private let header: Header
    private let content: Content

    init(
        title: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.header = header()
        self.content = content()
    }

    var body: some View {
        OrientationAdaptiveView {
            VStack {
                header
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                Spacer()

                ThemedSection {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(prefs.theme.textColor)
                    .padding(16)
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(prefs.theme.textColor)
        }
        landscape: {
            HStack {
                header
                    .padding(.vertical, 16)
                    .padding(.leading, 16)
                Spacer()
                VStack {
                    Spacer()

                    ThemedSection {
                        VStack(alignment: .leading, spacing: 16) {
                            content
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(prefs.theme.textColor)
                    }
                }
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(prefs.theme.textColor)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .minimumScaleFactor(0.5)
                    .font(.title)
                    .foregroundStyle(prefs.theme.textColor)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
