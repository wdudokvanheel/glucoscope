import SwiftUI

struct GlucoseValuesSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService

    var body: some View {
        RotatingConfigurationView(title: "Glucose values", header: ThemedGlucoseTargetGraphic.init) {
            HStack {
                Text("Low")
                Spacer()
                TextField(
                    "",
                    value: $prefs.bgLow,
                    format: .number,
                    prompt: Text("Value").foregroundColor(prefs.theme.textColor.opacity(0.5))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: true)
                .padding(4)
                .padding(.leading, 16)
                .background(
                    prefs.theme.backgroundColor.cornerRadius(4)
                )
            }

            ThemedDivider()

            HStack {
                Text("High")
                Spacer()
                TextField(
                    "",
                    value: $prefs.bgHigh,
                    format: .number,
                    prompt: Text("Value").foregroundColor(prefs.theme.textColor.opacity(0.5))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: true)
                .padding(4)
                .padding(.leading, 16)
                .background(
                    prefs.theme.backgroundColor.cornerRadius(4)
                )
            }

            ThemedDivider()

            HStack {
                Text("Very high")
                Spacer()
                TextField(
                    "",
                    value: $prefs.bgUpper,
                    format: .number,
                    prompt: Text("Value").foregroundColor(prefs.theme.textColor.opacity(0.5))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: true)
                .padding(4)
                .padding(.leading, 16)
                .background(
                    prefs.theme.backgroundColor.cornerRadius(4)
                )
            }
        }
    }
}
