import Foundation

struct GlucoseMeasurement: Identifiable, Decodable {
    let id = UUID()
    let time: TimeInterval
    let value: Double

    var date: Date {
        Date(timeIntervalSince1970: time)
    }
}
