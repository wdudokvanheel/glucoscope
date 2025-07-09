import Foundation
import os

final class DemoDataSource: DataSource {
    private let logger = Logger.new("datasource.demo")

    private struct C {
        static let historyHours = 24
        static let baseInterval: TimeInterval = 1.5 * 60
        static let noiseAmp = 0.3
        static let minG = 3.0
        static let maxG = 14.5
    }

    private var measurements: [GlucoseMeasurement] = []
    private var lastValue: Double = 5.5

    init() { generateInitial() }

    func testConnection() async throws -> Bool { true }

    func getLatestEntries(hours: Int, window: Int) async throws -> [GlucoseMeasurement] {
        update()
        let start = Date().addingTimeInterval(-TimeInterval(hours * 3600)).timeIntervalSince1970
        let recent = measurements.filter { $0.time >= start }
        guard window > 1 else { return recent }
        return aggregate(recent, window: window)
    }

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
        let cut = now.addingTimeInterval(-TimeInterval(C.historyHours * 3600)).timeIntervalSince1970
        if let idx = measurements.firstIndex(where: { $0.time >= cut }) {
            measurements.removeFirst(idx)
        }
    }

    private func gen(for date: Date) -> Double {
        let now = Date()
        let dt = now.timeIntervalSince(date)
        let win: TimeInterval = 9 * 3600
        let baseline = 5.5
        let amp = 2.0
        var target = baseline
        if dt <= win {
            let frac = (win - dt) / win
            let angle = -Double.pi / 2 + frac * 2 * Double.pi
            target += amp * sin(angle)
        }
        var value = lastValue + (target - lastValue) * 0.8
        value += Double.random(in: -C.noiseAmp ... C.noiseAmp)
        value = min(max(value, C.minG), C.maxG)
        lastValue = value
        return value
    }

    private func aggregate(_ data: [GlucoseMeasurement], window: Int) -> [GlucoseMeasurement] {
        var agg: [GlucoseMeasurement] = []
        var i = 0
        while i < data.count {
            let slice = data[i ..< min(i + window, data.count)]
            let avgV = slice.reduce(0.0) { $0 + $1.value } / Double(slice.count)
            let avgT = slice.reduce(0.0) { $0 + $1.time } / Double(slice.count)
            agg.append(.init(time: avgT, value: avgV))
            i += window
        }
        return agg
    }
}
