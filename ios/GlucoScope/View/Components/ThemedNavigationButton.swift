import SwiftUI

struct ThemedNavigationButton<Destination: View>: View {
    @EnvironmentObject private var prefs: PreferenceService

    let destination: Destination
    let label: String

    init(_ label: String, _ destination: Destination) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink(destination: destination) {
            Text(label)
                .font(.headline)
                .fontWeight(.regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(prefs.theme.accentColor)
    }
}
