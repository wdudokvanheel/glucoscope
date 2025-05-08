import SwiftUI

struct ThemedButton: View {
    @EnvironmentObject private var prefs: PreferenceService

    let action: () -> Void
    let label: String

    init(_ label: String, _ action: @escaping () -> Void) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
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
