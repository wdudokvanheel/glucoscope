import SwiftUI
import Foundation

struct ThemedTextField<T>: View {
    @EnvironmentObject private var prefs: PreferenceService

    @Binding private var value: T
    private let label: String
    private let formatter: Formatter?
    private let alignment: TextAlignment

    init(_ label: String, _ value: Binding<T>, formatter: Formatter? = nil, alignment: TextAlignment = .leading) {
        self.label = label
        self._value = value
        self.formatter = formatter
        self.alignment = alignment
    }

    var body: some View {
        if let formatter = formatter {
            TextField(
                "",
                value: $value,
                formatter: formatter,
                prompt: Text(label)
                    .foregroundColor(prefs.theme.textColor.opacity(0.5))
            )
            .multilineTextAlignment(alignment)
            .padding(8)
            .background(prefs.theme.backgroundColor.cornerRadius(4))
            .foregroundStyle(prefs.theme.textColor)
        } else {
            TextField(
                "",
                text: Binding(get: {
                    value as? String ?? ""
                }, set: {
                    if let newValue = $0 as? T {
                        value = newValue
                    } else if T.self == String.self {
                        value = $0 as! T
                    }
                }),
                prompt: Text(label)
                    .foregroundColor(prefs.theme.textColor.opacity(0.5))
            )
            .multilineTextAlignment(alignment)
            .padding(8)
            .background(prefs.theme.backgroundColor.cornerRadius(4))
            .foregroundStyle(prefs.theme.textColor)
        }
    }
}
