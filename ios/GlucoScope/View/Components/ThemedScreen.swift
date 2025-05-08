import SwiftUI

struct ThemedScreen<Content: View>: View {
    @EnvironmentObject private var prefs: PreferenceService

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            prefs.theme.backgroundColor.ignoresSafeArea()
            content
        }
    }
}
