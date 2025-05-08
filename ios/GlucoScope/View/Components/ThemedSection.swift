import SwiftUI

struct ThemedSection<Content: View>: View {
    @EnvironmentObject var prefs: PreferenceService

    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack {
            VStack {
                content()
                    .frame(maxWidth: .infinity)
            }
            .cornerRadius(12)
            .clipped()
            .background(prefs.theme.surfaceColor.cornerRadius(12))
        }
        .padding(.horizontal, 16)
    }
}
