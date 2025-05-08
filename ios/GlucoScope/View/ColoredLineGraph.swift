import Charts
import SwiftUI

struct ColoredLineGraph: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var prefs: PreferenceService

    var data: [GlucoseMeasurement]

    init(data: [GlucoseMeasurement]) {
        self.data = data
    }

    var minValue: Double {
        max(prefs.graph.boundsLower, data.map { $0.value }.min() ?? prefs.graph.boundsLower)
    }

    var maxValue: Double {
        min(prefs.graph.boundsHigher, data.map { $0.value }.max() ?? prefs.graph.boundsHigher)
    }

    // Using a logarithmic scale for normalization to calculate the stops for the line gradient.
    var gradient_range_low: Double {
        (log(prefs.bgLow) - log(minValue)) / (log(maxValue) - log(minValue))
    }

    var gradient_range_high: Double {
        (log(prefs.bgHigh) - log(minValue)) / (log(maxValue) - log(minValue))
    }

    var gradient_range_upper: Double {
        (log(prefs.bgUpper) - log(minValue)) / (log(maxValue) - log(minValue))
    }

    var timeRange: [Date] {
        guard let firstDate = data.map({ $0.date }).min(),
              let lastDate = data.map({ $0.date }).max()
        else {
            return []
        }
        let calendar = Calendar.current
        var times: [Date] = []
        var current = calendar.startOfHour(for: firstDate)
        while current <= lastDate {
            times.append(current)
            current = calendar.date(byAdding: .hour, value: 1, to: current)!
        }
        return times.dropFirst().map { $0 }
    }

    var body: some View {
//        GeometryReader { geometry in
            Chart(data) { point in
//                AreaMark(
//                    x: .value("Time", point.date),
//                    yStart: .value("Value", prefs.graph.boundsLower),
//                    yEnd: .value("Value", point.value)
//                )
//                .foregroundStyle(Color("GraphFill").opacity(0.1))

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: prefs.theme.lowColor, location: 0.0),
                            .init(color: prefs.theme.lowColor, location: gradient_range_low - 0.035),

                            .init(color: prefs.theme.inRangeColor, location: gradient_range_low + 0.025),
                            .init(color: prefs.theme.inRangeColor, location: gradient_range_high - 0.025),

                            .init(color: prefs.theme.highColor, location: gradient_range_high + 0.025),
                            .init(color: prefs.theme.upperColor, location: gradient_range_upper),

                            .init(color: prefs.theme.upperColor, location: gradient_range_upper),
                            .init(color: prefs.theme.upperColor, location: 1.0)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3))
            }
            .chartXScale(domain: Date(timeIntervalSince1970: data.first?.time ?? 0) ...
                Date(timeIntervalSince1970: data.last?.time ?? 0))
            .chartXAxis {
                AxisMarks(values: timeRange) { value in
                    if value.index % 2 == 0 || verticalSizeClass == .compact {
                        AxisGridLine()
                            .foregroundStyle(prefs.theme.gridLinesXColor)
                        AxisTick()
                            .foregroundStyle(prefs.theme.gridLinesXColor)
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                            .foregroundStyle(prefs.theme.labelAxisXColor)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [3, 4, 5, 6, 7, 10, 15, 20]) { _ in
                    AxisGridLine()
                        .foregroundStyle(prefs.theme.gridLinesYColor)
                    AxisValueLabel()
                        .foregroundStyle(prefs.theme.labelAxisYColor)
                }
            }
            .chartYScale(domain: prefs.graph.boundsLower ... prefs.graph.boundsHigher, type: .log)
            .padding(.top, 8)
//            .frame(height: verticalSizeClass == .compact ? geometry.size.height : geometry.size.height)
            .frame(maxWidth: .infinity)
        }
//    }
}
