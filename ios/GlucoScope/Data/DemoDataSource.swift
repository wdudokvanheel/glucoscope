import Foundation
import os

/// Simple datasource used for demo mode. It generates random but slowly varying
/// glucose values and always reports a successful connection.
class DemoDataSource: DataSource {
    private let logger = Logger.new("datasource.demo")
    private var lastValue: Double = 5.5

    func testConnection() async throws -> Bool {
        // Demo mode is always "connected"
        true
    }

    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement] {
        let count = max(1, hours * 60 / max(1, window))
        let interval = Double(window * 60)
        let now = Date().timeIntervalSince1970

        var measurements: [GlucoseMeasurement] = []
        for i in 0..<count {
            // Keep the value within realistic boundaries and slowly vary
            lastValue += Double.random(in: -0.3...0.3)
            lastValue = min(max(lastValue, 3.5), 10.0)
            let time = now - Double(count - i) * interval
            measurements.append(GlucoseMeasurement(time: time, value: lastValue))
        }
        logger.trace("Generated \(measurements.count) demo values")
        return measurements
    }
}
