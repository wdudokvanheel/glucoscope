import Foundation
#if os(iOS)
import ActivityKit
#endif

/// Shared by the app and Widget extension. Keep the encoded state below ActivityKit's 4 KB limit.
struct GlucoseActivityAttributes: Codable {
    struct Point: Codable, Hashable {
        let offset: Int
        let value: Int
    }
    struct ContentState: Codable, Hashable {
        var glucoseMGDL: Int?
        var sampleDate: Date?
        var trend: String
        var points: [Point]
        var graphStart: Date
        var graphHours: Int
        var hideWhenLocked: Bool
        var background: String
        var foreground: String
        var accent: String
        var lowColor: String
        var highColor: String
        var lowMGDL: Int
        var highMGDL: Int
    }
    var name = "GlucoScope"
}

#if os(iOS)
extension GlucoseActivityAttributes: ActivityAttributes {}
#endif
