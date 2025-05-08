import Foundation
import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var prefs: PreferenceService
    @State var themes: [Theme] = []
    @State var previewData: [GlucoseMeasurement] = []

    var body: some View {
        OrientationView { orientation in
            switch orientation {
                case .portrait:
                    GeometryReader { geom in
                        VStack(spacing: 16) {
                            ThemeSettingsGraphPreview(previewData: previewData)
                                .padding(.horizontal, 16)
                                .frame(height: geom.size.height * 0.33)

                            ThemeSettingsList(themes: themes)
                        }
                        .padding(.bottom, 16)
                    }
                case .landscape:
                    HStack(spacing: 0) {
                        ThemeSettingsGraphPreview(previewData: previewData)
                            .padding(.leading, 16)

                        ThemeSettingsList(themes: themes)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            self.previewData = generatePreviewGlucoseData(minRange: prefs.graph.boundsLower, maxRange: prefs.graph.boundsHigher, low: prefs.bgLow, high: prefs.bgHigh)
            self.themes = loadThemes()
        }
    }

    // TODO: Move to a service
    private func loadThemes() -> [Theme] {
        guard let url = Bundle.main.url(forResource: "themes", withExtension: "json") else {
            print("Could not locate themes.json file in the bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let themes = try JSONDecoder().decode([Theme].self, from: data)
            return themes.sorted { $0.name < $1.name }
        } catch {
            print("Error reading or decoding the file: \(error)")
            return []
        }
    }

    // TODO: Move to a service or static function
    private func generatePreviewGlucoseData(
        minRange: Double,
        maxRange: Double,
        low: Double,
        high: Double,
        noiseFraction: Double = 0.05,
        includeMealSpikes: Bool = true
    ) -> [GlucoseMeasurement] {
        var data: [GlucoseMeasurement] = []
        let cal = Calendar.current
        let today = Date()
        let startOfDay = cal.startOfDay(for: today)
        guard
            let t0 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: startOfDay),
            let t1 = cal.date(bySettingHour: 15, minute: 0, second: 0, of: startOfDay)
        else { return data }

        let interval = TimeInterval(5 * 60) // 5‑minute sampling
        let totalSeconds = t1.timeIntervalSince(t0) // 6h = 21 600s
        let firstSegSecs = totalSeconds / 3.0 // 2h = 7 200s
        let secondSegSecs = totalSeconds - firstSegSecs // 4h = 14 400s

        // --- climb/fall params (first 2h) ---
        let climbMin = minRange * 1.1
        let climbMax = maxRange * 0.7
        let centerCL = (climbMin + climbMax) / 2
        let ampCL = (climbMax - climbMin) / 2

        // --- sine params (last 4h) ---
        let centerLH = (low + high) / 2
        let ampLH = (high - low) / 2

        // --- noise & spike settings ---
        let fullRange = maxRange - minRange
        let noiseAmp = fullRange * noiseFraction
        let mealSpikeAmp = fullRange * 0.3 // up to ±30% bump
        let mealSpikeWidth = TimeInterval(30 * 60) // 30 min σ
        // offsets from t0: 09:30, 12:00, 13:00
        let mealOffsets: [TimeInterval] = [30 * 60, 180 * 60, 240 * 60]

        var current = t0
        while current <= t1 {
            let dt = current.timeIntervalSince(t0)
            let raw: Double

            if dt < firstSegSecs {
                // smooth climb‑and‑fall: map [0…7 200] → [–π/2…3π/2]
                let angle = -Double.pi / 2 + (dt / firstSegSecs) * 2 * Double.pi
                raw = centerCL + ampCL * sin(angle)

            } else {
                // one sine cycle in [low…high]
                let subDt = dt - firstSegSecs
                let frac = subDt / secondSegSecs
                let angle = frac * 2 * Double.pi
                raw = centerLH + ampLH * sin(angle)
            }

            var value = raw

            // add meal‑spike bumps
            if includeMealSpikes {
                for meal in mealOffsets {
                    let delta = dt - meal
                    // gaussian bump
                    let bump = mealSpikeAmp * exp(-0.5 * (delta / mealSpikeWidth) * (delta / mealSpikeWidth))
                    value += bump
                }
            }

            // add a bit of random noise
            let noise = Double.random(in: -noiseAmp ... noiseAmp)
            value += noise

            // clamp into [minRange…maxRange]
            let clamped = min(max(value, minRange), maxRange)
            data.append(.init(time: current.timeIntervalSince1970, value: clamped))

            current.addTimeInterval(interval)
        }

        return data
    }
}

struct ThemeSettingsGraphPreview: View {
    @EnvironmentObject var prefs: PreferenceService
    let previewData: [GlucoseMeasurement]

    var body: some View {
        ZStack(alignment: .top) {
            prefs.theme.backgroundColor
            ColoredLineGraph(data: previewData)
                .padding(8)

            Text("Theme Preview")
                .font(.footnote)
                .foregroundStyle(prefs.theme.textColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    prefs.theme.surfaceColor
                        .cornerRadius(4, corners: [.bottomLeft, .bottomRight])
                )
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(prefs.theme.surfaceColor, lineWidth: 2)
        )
    }
}

struct ThemeSettingsList: View {
    @EnvironmentObject var prefs: PreferenceService

    let themes: [Theme]

    var body: some View {
        ThemedSection {
            ScrollView {
                VStack {
                    ForEach(Array(themes.enumerated()), id: \.1.id) { index, theme in
                        VStack(spacing: 4) {
                            HStack {
                                Text("\(theme.name)")
                                    .font(.body)
                                    .foregroundStyle(theme == prefs.theme ? prefs.theme.accentColor : prefs.theme.textColor)
                                    .fontWeight(theme == prefs.theme ? .semibold : .regular)
                                    .animation(nil, value: theme == prefs.theme)

                                if !theme.variant.isEmpty {
                                    Text("- \(theme.variant)")
                                        .font(.callout)
                                        .foregroundStyle((theme == prefs.theme ? prefs.theme.accentColor : prefs.theme.textColor).opacity(0.75))
                                        .fontWeight(theme == prefs.theme ? .regular : .light)
                                        .animation(nil, value: theme == prefs.theme)
                                }

                                Spacer()
                                ThemeSwatch(theme)
                            }
                            .contentShape(Rectangle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    prefs.theme = theme
                                }
                            }

                            if index < themes.count - 1 {
                                ThemedDivider()
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding(8)
                .padding(.trailing, 4)
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.vertical])
            .padding(0)
        }
    }
}
