import Foundation
import os

final class DemoDataSource: DataSource {
    private let logger = Logger.new("datasource.demo")

    private struct C {
        static let historyHours = 24
        static let baseInterval: TimeInterval = 1.5 * 60
        /// Background white‑noise amplitude (± mmol/L)
        static let noiseAmp: Double = 0.6
        /// Chance that any individual point gets a sudden spike/dip
        static let spikeChance: Double = 0.06
        /// Spike amplitude (± mmol/L)
        static let spikeAmp: Double = 3.0
        static let minG: Double = 3.0
        static let maxG: Double = 14.5
        /// 1.0 → snaps to target instantly (we apply own smoothing inside `gen`)
        static let inertia: Double = 0.8
    }

    private var measurements: [GlucoseMeasurement] = []
    private var lastValue: Double = 6.5

    // MARK: - Lifecycle ----------------------------------------------------------

    init() { generateInitial() }

    // MARK: - DataSource ---------------------------------------------------------

    func testConnection() async throws -> Bool { true }

    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement] {
        update()
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3_600)).timeIntervalSince1970
        let recent = measurements.filter { $0.time >= cutoff }
        guard window > 1 else { return recent }
        return aggregate(recent, window: window)
    }

    // MARK: - History maintenance ------------------------------------------------

    private func generateInitial() {
        let now = Date()
        let start = now.addingTimeInterval(-C.baseInterval * Double(C.historyHours * 60))
        var t = start
        while t <= now {
            let v = gen(for: t)
            measurements.append(.init(time: t.timeIntervalSince1970, value: v))
            t.addTimeInterval(C.baseInterval)
        }
    }

    private func update() {
        guard var lastT = measurements.last.map({ Date(timeIntervalSince1970: $0.time) }) else { return }
        let now = Date()
        while lastT.addingTimeInterval(C.baseInterval) <= now {
            lastT.addTimeInterval(C.baseInterval)
            let v = gen(for: lastT)
            measurements.append(.init(time: lastT.timeIntervalSince1970, value: v))
        }
        let cutoff = now.addingTimeInterval(-TimeInterval(C.historyHours * 3_600)).timeIntervalSince1970
        if let idx = measurements.firstIndex(where: { $0.time >= cutoff }) {
            measurements.removeFirst(idx)
        }
    }

    // MARK: - Glucose generator --------------------------------------------------

    /**
     Generates a profile for the last **9 h** that looks like this (time →):

       🟢 baseline  ───▼ trough (<4)───▲ rapid rise───🟥 plateau (≈12)───▽ fall── baseline
     */
    private func gen(for date: Date) -> Double {
        let now = Date()
        let age = now.timeIntervalSince(date)               // seconds ago (0…∞)
        let window: TimeInterval = 9 * 3_600                // 9 h span
        let t = max(0, min(1, (window - age) / window))     // 0 (old) → 1 (now)

        // Baseline, peak & valley levels
        let baseline: Double = 5.5
        let peak: Double = 12.0
        let valley: Double = 3.0

        // Piece‑wise target ------------------------------------------------------
        // Segment boundaries (fractions of 9 h)
        let s0 = 0.00          // 9h ago
        let s1 = 0.20          // valley centre at 7.2h ago
        let s2 = 0.35          // end of rise (≈5.9h ago)
        let s3 = 0.65          // end of plateau (≈3.1h ago)
        let s4 = 0.85          // end of fall   (≈1.3h ago)
        // 1.00 = now

        var target: Double
        switch t {
        case s0 ..< s1: // Descend into hypo then partially back up
            // Smooth valley using half‑cosine (convex dip)
            let p = (t - s0) / (s1 - s0)                  // 0…1
            target = baseline - (baseline - valley) * (1 - cos(p * .pi)) / 2

        case s1 ..< s2: // Steep rise to peak
            let p = (t - s1) / (s2 - s1)
            target = baseline + (peak - baseline) * pow(p, 0.6) // ease‑in > linear

        case s2 ..< s3: // Plateau at peak with small jitter
            let jitter = Double.random(in: -0.3 ... 0.3)
            target = peak + jitter

        case s3 ..< s4: // Fall back to baseline (slightly slower)
            let p = (t - s3) / (s4 - s3)
            target = peak - (peak - baseline) * pow(p, 1.2) // ease‑out < linear

        default: // final segment back at baseline
            target = baseline
        }

        // Inertia filter ---------------------------------------------------------
        var value = lastValue + (target - lastValue) * C.inertia

        // Background noise -------------------------------------------------------
        value += Double.random(in: -C.noiseAmp ... C.noiseAmp)

        // Occasional random spike or dip ----------------------------------------
        if Double.random(in: 0...1) < C.spikeChance {
            value += Double.random(in: -C.spikeAmp ... C.spikeAmp)
        }

        // Clamp & store ----------------------------------------------------------
        value = min(max(value, C.minG), C.maxG)
        lastValue = value
        return value
    }

    // MARK: - Down‑sampling ------------------------------------------------------

    private func aggregate(_ data: [GlucoseMeasurement], window: Int) -> [GlucoseMeasurement] {
        var out: [GlucoseMeasurement] = []
        var i = 0
        while i < data.count {
            let slice = data[i ..< min(i + window, data.count)]
            let avgV = slice.reduce(0.0) { $0 + $1.value } / Double(slice.count)
            let avgT = slice.reduce(0.0) { $0 + $1.time } / Double(slice.count)
            out.append(.init(time: avgT, value: avgV))
            i += window
        }
        return out
    }
}
