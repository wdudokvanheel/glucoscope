import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GlucoScopeActivityBundle: WidgetBundle {
    var body: some Widget { GlucoseLiveActivityWidget() }
}

struct GlucoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            GlucoseActivityLockScreen(context: context)
                .activityBackgroundTint(Color(activityHex: context.state.background))
                .activitySystemActionForegroundColor(Color(activityHex: context.state.foreground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlucoseActivityValue(state: context.state, stale: context.isStale)
                        .privacySensitive(context.state.hideWhenLocked)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GlucoseActivityAge(state: context.state, stale: context.isStale)
                        .privacySensitive(context.state.hideWhenLocked)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GlucoseActivityGraph(state: context.state).frame(height: 45)
                        .privacySensitive(context.state.hideWhenLocked)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "clock.badge.exclamationmark" : "drop.fill")
                    .foregroundStyle(context.isStale ? .orange : Color(activityHex: context.state.accent))
            } compactTrailing: {
                Text(context.state.glucoseMGDL.map { String(format: "%.1f", Double($0) / 18.0182) } ?? "—")
                    .fontWeight(.semibold)
                    .strikethrough(context.isStale)
                    .privacySensitive(context.state.hideWhenLocked)
            } minimal: {
                Image(systemName: context.isStale ? "clock.badge.exclamationmark" : "drop.fill")
            }
        }
    }
}

private struct GlucoseActivityLockScreen: View {
    let context: ActivityViewContext<GlucoseActivityAttributes>
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var redaction
    private var privacyHidden: Bool { context.state.hideWhenLocked && redaction.contains(.privacy) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("GlucoScope", systemImage: "drop.fill").font(.caption.weight(.medium))
                Spacer()
                Text("\(context.state.graphHours)h").font(.caption)
            }.opacity(0.7)
            if privacyHidden {
                Label("Unlock to see glucose", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity, minHeight: 76)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        GlucoseActivityValue(state: context.state, stale: context.isStale)
                        GlucoseActivityAge(state: context.state, stale: context.isStale)
                    }
                    GlucoseActivityGraph(state: context.state).frame(height: 72)
                }.privacySensitive(context.state.hideWhenLocked)
            }
        }
        .padding(16)
        .foregroundStyle(Color(activityHex: context.state.foreground))
        .opacity(dimmed ? 0.75 : 1)
        .widgetURL(URL(string: "glucoscope://graph"))
    }
}

private struct GlucoseActivityValue: View {
    let state: GlucoseActivityAttributes.ContentState
    let stale: Bool
    var body: some View {
        if let mgdl = state.glucoseMGDL {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.1f", Double(mgdl) / 18.0182)).font(.system(size: 30, weight: .semibold, design: .rounded))
                    .strikethrough(stale)
                Text(state.trend).font(.title3)
            }
            .accessibilityLabel("\(String(format: "%.1f", Double(mgdl) / 18.0182)) millimoles per liter, trend \(state.trend)\(stale ? ", outdated" : "")")
            Text("mmol/L").font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Waiting for a reading").font(.subheadline.weight(.medium))
        }
    }
}

private struct GlucoseActivityAge: View {
    let state: GlucoseActivityAttributes.ContentState
    let stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if stale { Label("Outdated", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) }
            if let date = state.sampleDate {
                HStack(spacing: 3) { Text("Age"); Text(date, style: .timer).monospacedDigit() }
            } else { Text("Connect your sensor") }
        }.font(.caption2)
    }
}

private struct GlucoseActivityGraph: View {
    let state: GlucoseActivityAttributes.ContentState
    @Environment(\.redactionReasons) private var redaction
    var body: some View {
        Canvas { context, size in
            guard !(state.hideWhenLocked && redaction.contains(.privacy)), !state.points.isEmpty else { return }
            let minimum = Double(min(state.lowMGDL - 18, state.points.map(\.value).min() ?? state.lowMGDL))
            let maximum = Double(max(state.highMGDL + 18, state.points.map(\.value).max() ?? state.highMGDL))
            let span = max(36, maximum - minimum)
            func position(_ point: GlucoseActivityAttributes.Point) -> CGPoint {
                CGPoint(x: Double(point.offset) / Double(state.graphHours * 3600) * size.width,
                        y: size.height - (Double(point.value) - minimum) / span * size.height)
            }
            for threshold in [state.lowMGDL, state.highMGDL] {
                let y = size.height - (Double(threshold) - minimum) / span * size.height
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Color(activityHex: state.foreground).opacity(0.2)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
            for index in state.points.indices {
                let point = state.points[index]
                let color = Color(activityHex: point.value < state.lowMGDL ? state.lowColor : point.value > state.highMGDL ? state.highColor : state.accent)
                let current = position(point)
                // Do not draw a continuous line across unobserved gaps longer than 20 min.
                if index > 0, point.offset - state.points[index - 1].offset <= 1200 {
                    var line = Path(); line.move(to: position(state.points[index - 1])); line.addLine(to: current)
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                } else { context.fill(Path(ellipseIn: CGRect(x: current.x - 1.5, y: current.y - 1.5, width: 3, height: 3)), with: .color(color)) }
            }
        }
        .accessibilityLabel("Glucose graph, last \(state.graphHours) hours of the latest available readings")
    }
}

private extension Color {
    init(activityHex: String) {
        let cleaned = activityHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(cleaned, radix: 16) ?? 0xffffff
        if cleaned.count == 8 {
            self.init(.sRGB, red: Double((number >> 24) & 255) / 255, green: Double((number >> 16) & 255) / 255,
                      blue: Double((number >> 8) & 255) / 255, opacity: Double(number & 255) / 255)
        } else {
            self.init(.sRGB, red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255,
                      blue: Double(number & 255) / 255, opacity: 1)
        }
    }
}
