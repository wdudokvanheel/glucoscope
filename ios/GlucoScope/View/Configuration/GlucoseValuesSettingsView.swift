import SwiftUI

struct GlucoseValuesSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService

    var body: some View {
        RotatingConfigurationView(title: "Glucose values", header: ThemedGlucoseTargetGraphic.init) {
            HStack {
                Text("Low")
                Spacer()
                
                ThemedTextField("Value", $prefs.bgLow, formatter: NumberFormatter.decimal, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: true)
            }

            ThemedDivider()

            HStack {
                Text("High")
                Spacer()
                ThemedTextField("Value", $prefs.bgHigh, formatter: NumberFormatter.decimal, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: true)
            }

            ThemedDivider()

            HStack {
                Text("Very high")
                Spacer()
                ThemedTextField("Value", $prefs.bgUpper, formatter: NumberFormatter.decimal, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }
}
