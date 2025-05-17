import Foundation

struct MeasurementComponents {
    let low: Double
    let inRange: Double
    let upper: Double
    let high: Double
}


extension Array where Element == GlucoseMeasurement {
    /// Returns the fraction of time spent in each glycaemic range.
    ///
    /// - Parameters:
    ///   - low:   Anything *below* this is counted as `low`.
    ///   - upper: Anything **from** `low` **up to, but not including,** `upper` is `inRange`.
    ///   - high:  Anything **from** `upper` **up to, but not including,** `high` is `upper`.
    ///            Values `>= high` are `high`.
    ///
    /// - Note: The last data point has no “forward” interval; here we
    ///         treat its interval as equal to the previous one.
    func toComponents(low: Double,
                      upper: Double,
                      high: Double) -> MeasurementComponents {

        // Need at least two points to derive an interval
        guard count > 1 else {
            return MeasurementComponents(low: 0, inRange: 0, upper: 0, high: 0)
        }

        let samples = self.sorted { $0.time < $1.time }

        var lowSec:   TimeInterval = 0
        var inSec:    TimeInterval = 0
        var upperSec: TimeInterval = 0
        var highSec:  TimeInterval = 0

        for i in 0 ..< samples.count - 1 {
            let interval = samples[i + 1].time - samples[i].time
            switch samples[i].value {
            case ..<low:      lowSec   += interval
            case low..<upper: inSec    += interval
            case upper..<high: upperSec += interval
            default:          highSec  += interval
            }
        }

        // Give the last measurement the same length
        //        as the previous interval
        if samples.count >= 2 {
            let lastInterval = samples[samples.count - 1].time
                             - samples[samples.count - 2].time
            switch samples.last!.value {
            case ..<low:      lowSec   += lastInterval
            case low..<upper: inSec    += lastInterval
            case upper..<high: upperSec += lastInterval
            default:          highSec  += lastInterval
            }
        }

        let total = lowSec + inSec + upperSec + highSec
        guard total > 0 else {
            return MeasurementComponents(low: 0, inRange: 0, upper: 0, high: 0)
        }

        return MeasurementComponents(low:      lowSec   / total,
                                     inRange:  inSec    / total,
                                     upper:    upperSec / total,
                                     high:     highSec  / total)
    }
}
