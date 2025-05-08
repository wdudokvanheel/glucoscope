import SwiftUI

struct ThemedTextField: View {
    @EnvironmentObject private var prefs: PreferenceService

    @Binding private var text: String
    private let label: String

    init(_ label: String, _ text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(label)
            .foregroundColor(prefs.theme.textColor.opacity(0.5)))
            .padding(8)
            .background(
                prefs.theme.backgroundColor
                    .cornerRadius(4)
            )
            .foregroundStyle(prefs.theme.textColor)
    }
}
