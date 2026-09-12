import Foundation

@main
struct LiveActivityPayloadSmoke {
    static func main() throws {
        let points = (0..<36).map { GlucoseActivityAttributes.Point(offset: $0 * 1200, value: 400) }
        let state = GlucoseActivityAttributes.ContentState(
            glucoseMGDL: 400, sampleDate: Date(), trend: "↓↓", points: points,
            graphStart: Date().addingTimeInterval(-12 * 3600), graphHours: 12, hideWhenLocked: true,
            background: "#123456FF", foreground: "#FFFFFFFF", accent: "#123456FF", lowColor: "#123456FF", highColor: "#123456FF",
            lowMGDL: 70, highMGDL: 180
        )
        let data = try JSONEncoder().encode(state)
        let attributes = try JSONEncoder().encode(GlucoseActivityAttributes())
        precondition(data.count + attributes.count < 4096, "Live Activity exceeds Apple's 4 KB content budget")
        let restored = try JSONDecoder().decode(GlucoseActivityAttributes.ContentState.self, from: data)
        precondition(restored == state, "Activity state does not round-trip across app and extension")
        print("Live Activity payload: \(data.count + attributes.count) bytes including attributes; 4 KB limit and round-trip passed")
    }
}
