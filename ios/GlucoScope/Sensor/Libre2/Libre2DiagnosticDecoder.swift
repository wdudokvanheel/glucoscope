import Foundation

enum Libre2DiagnosticRejection: String, Sendable, Equatable, CustomStringConvertible {
    case invalidLength, invalidCRC, wrongSensor, unsupportedCalibration
    case lifecycleNotReady, missingAnchor, invalidAnchor, sensorMinuteBeforeAnchor, sensorLifetimeExceeded
    case invalidCalibrationDomain, invalidCalibrationMetadata, warmup, sampleBeforeStart, zeroGlucose, zeroTemperature
    case invalidTemperatureDomain, temperatureOutsideDiagnosticRange, glucoseOutsideDiagnosticRange

    var description: String {
        switch self {
        case .invalidLength: return "Payload must contain exactly 44 bytes."
        case .invalidCRC: return "Payload CRC failed."
        case .wrongSensor: return "Calibration does not belong to this sensor."
        case .unsupportedCalibration: return "Unsupported calibration version or sensor revision."
        case .lifecycleNotReady: return "NFC lifecycle snapshot is neither starting nor ready."
        case .missingAnchor: return "Needs sensor clock reference; read calibration with NFC."
        case .invalidAnchor: return "Needs a valid sensor clock reference; read calibration with NFC."
        case .sensorMinuteBeforeAnchor: return "Frame sensor minute precedes the saved clock reference."
        case .sensorLifetimeExceeded: return "Sensor minute exceeds the 14.5-day diagnostic limit."
        case .invalidCalibrationDomain: return "Calibration coefficients are outside the conversion domain."
        case .invalidCalibrationMetadata: return "Calibration capture date or sensor minute is invalid."
        case .warmup: return "Sample is within the first 60 sensor minutes."
        case .sampleBeforeStart: return "Sample offset precedes sensor start."
        case .zeroGlucose: return "Raw glucose slot is zero."
        case .zeroTemperature: return "Raw temperature slot is zero."
        case .invalidTemperatureDomain: return "Temperature adjustment or logarithm domain is invalid."
        case .temperatureOutsideDiagnosticRange: return "Converted temperature is outside -10...60 °C diagnostic bounds."
        case .glucoseOutsideDiagnosticRange: return "Converted glucose is outside 1...1000 mg/dL diagnostic bounds."
        }
    }
}

struct Libre2DiagnosticFrame: Sendable, Equatable {
    let sensorMinute: Int?
    let rejection: Libre2DiagnosticRejection?
    let slots: [Libre2DiagnosticSlot]
}

struct Libre2DiagnosticSlot: Sendable, Equatable {
    let offsetMinutes: Int
    let sensorMinute: Int
    let timestamp: Date
    let rawGlucose: Int
    let rawTemperature: Int
    let temperatureAdjustment: Int
    let temperatureCelsius: Double?
    let glucoseMgDL: Double?
    let rejection: Libre2DiagnosticRejection?
}

/// Experimental, stateless calculations for diagnostics only. See docs/libre2-eu-protocol.md.
/// Identity is supplied by the authenticated transport; the plaintext has no sensor UID.
enum Libre2DiagnosticDecoder {
    static let version = "libre2-nonlinear-diagnostic-v2"
    static let sampleOffsets = [0, 2, 4, 6, 7, 12, 15]
    static let maximumSensorMinute = LibreSensorClockAnchor.maximumSensorMinute

    static func decode(payload: Data, calibration: LibreCalibration, clockAnchor: LibreSensorClockAnchor?,
                       uid: Data, patchInfo: Data) -> Libre2DiagnosticFrame {
        func rejected(_ reason: Libre2DiagnosticRejection, minute: Int? = nil) -> Libre2DiagnosticFrame {
            Libre2DiagnosticFrame(sensorMinute: minute, rejection: reason, slots: [])
        }
        guard payload.count == 44 else { return rejected(.invalidLength) }
        // Normalize Data indices: a sliced Data value need not begin at zero.
        let bytes = Array(payload)
        guard payloadCRC(bytes.prefix(42)) == UInt16(bytes[42]) | UInt16(bytes[43]) << 8 else {
            return rejected(.invalidCRC)
        }
        guard calibration.formatVersion == LibreCalibration.currentFormatVersion,
              (try? Libre2Protocol.classify(patchInfo: Data(Array(patchInfo)))) != nil else {
            return rejected(.unsupportedCalibration)
        }
        guard uid.count == 8, (try? calibration.validateOwnership(uid: uid, patchInfo: patchInfo)) != nil else {
            return rejected(.wrongSensor)
        }
        let minute = Int(bytes[40]) | Int(bytes[41]) << 8
        // NFC is a historical snapshot, not a live BLE status. A starting capture can
        // support post-warmup samples without inventing a transition to live ready.
        guard calibration.lifecycle == 0x02 || calibration.lifecycle == 0x03 else {
            return rejected(.lifecycleNotReady, minute: minute)
        }
        guard calibration.capturedAt.timeIntervalSince1970.isFinite,
              (0...maximumSensorMinute).contains(calibration.sensorMinute) else {
            return rejected(.invalidCalibrationMetadata, minute: minute)
        }
        guard let clockAnchor else { return rejected(.missingAnchor, minute: minute) }
        guard (try? clockAnchor.validateOwnership(uid: uid, patchInfo: patchInfo)) != nil,
              clockAnchor.referenceDate.timeIntervalSince1970.isFinite,
              (0...maximumSensorMinute).contains(clockAnchor.referenceSensorMinute) else {
            return rejected(.invalidAnchor, minute: minute)
        }
        guard minute >= clockAnchor.referenceSensorMinute else { return rejected(.sensorMinuteBeforeAnchor, minute: minute) }
        guard minute <= maximumSensorMinute else { return rejected(.sensorLifetimeExceeded, minute: minute) }
        // Validate every date before constructing a frame; formatting never sees nonfinite dates.
        let timestamps: [Date]
        do {
            timestamps = try sampleOffsets.map { try clockAnchor.timestamp(for: minute - $0) }
        } catch {
            return rejected(.invalidAnchor, minute: minute)
        }
        guard let coefficients = calibrationCoefficients(index: calibration.i2),
              calibration.i4 > calibration.i3, calibration.i6 > 0 else {
            return rejected(.invalidCalibrationDomain, minute: minute)
        }
        let slots = sampleOffsets.enumerated().map { slotIndex, offset -> Libre2DiagnosticSlot in
            let start = slotIndex * 4
            let word = UInt32(bytes[start]) | UInt32(bytes[start + 1]) << 8
                | UInt32(bytes[start + 2]) << 16 | UInt32(bytes[start + 3]) << 24
            let glucose = Int(word & 0x3FFF)
            let temperature = Int((word >> 14) & 0xFFF) * 4
            let magnitude = Int((word >> 26) & 0x1F) * 4
            let adjustment = word & 0x8000_0000 == 0 ? magnitude : -magnitude
            let sampleMinute = minute - offset
            let timestamp = timestamps[slotIndex]
            func result(_ reason: Libre2DiagnosticRejection? = nil, celsius: Double? = nil,
                        value: Double? = nil) -> Libre2DiagnosticSlot {
                Libre2DiagnosticSlot(offsetMinutes: offset, sensorMinute: sampleMinute, timestamp: timestamp,
                                     rawGlucose: glucose, rawTemperature: temperature, temperatureAdjustment: adjustment,
                                     temperatureCelsius: celsius, glucoseMgDL: value, rejection: reason)
            }
            guard sampleMinute >= 0 else { return result(.sampleBeforeStart) }
            guard sampleMinute >= 60 else { return result(.warmup) }
            guard glucose > 0 else { return result(.zeroGlucose) }
            guard temperature > 0 else { return result(.zeroTemperature) }
            // Field packing bounds adjustment to ±124 in multiples of four.
            let denominator = Double(calibration.i6 + adjustment)
            guard denominator > 0 else { return result(.invalidTemperatureDomain) }
            let resistance = Double(temperature) * 72_500 / denominator - 1_000
            guard resistance.isFinite, resistance > 0 else { return result(.invalidTemperatureDomain) }
            let logarithm = log(resistance)
            let inverseKelvin = 0.0009180023 + logarithm * (0.0001964561
                + logarithm * (0.0000007061775 + logarithm * 0.00000005283566))
            guard inverseKelvin.isFinite, inverseKelvin > 0 else { return result(.invalidTemperatureDomain) }
            let celsius = 1 / inverseKelvin - 273.15
            guard celsius.isFinite, (-10.0...60.0).contains(celsius) else {
                return result(.temperatureOutsideDiagnosticRange)
            }
            let normalized = 65 * Double(glucose - calibration.i3) / Double(calibration.i4 - calibration.i3)
            let corrected = normalized * pow(1.045, 32.5 - celsius)
            let value = (corrected - coefficients.offset) / coefficients.sensitivity
            guard value.isFinite, (1.0...1000.0).contains(value) else {
                return result(.glucoseOutsideDiagnosticRange, celsius: celsius)
            }
            return result(celsius: celsius, value: value)
        }
        return Libre2DiagnosticFrame(sensorMinute: minute, rejection: nil, slots: slots)
    }

    /// Finite-domain arithmetic reconstruction, not the unavailable original table generator.
    /// The seed's rounding interval and the four index regimes are documented in the specification.
    static func calibrationCoefficients(index: Int) -> (offset: Double, sensitivity: Double)? {
        guard (1...1023).contains(index) else { return nil }
        let position = index - 1
        let row: Int
        let column: Int
        let base: Double
        switch position {
        case 0..<512:
            row = position / 8; column = position % 8; base = 0.75
        case 512..<719:
            row = 64 + (position - 512) / 9; column = (position - 512) % 9; base = 0.75
        case 719..<951:
            row = 87 + (position - 719) / 8; column = (position - 719) % 8; base = 1
        default:
            row = 116 + (position - 951) / 9; column = (position - 951) % 9; base = 1
        }
        let sensitivity = (0.037744227 * pow(1.01, Double(row)) * 10_000_000).rounded() / 10_000_000
        return (base + Double(column) / 4, sensitivity)
    }

    private static func payloadCRC(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var remainder: UInt16 = 0xFFFF
        for byte in bytes {
            remainder ^= UInt16(byte)
            for _ in 0..<8 {
                remainder = remainder & 1 == 0 ? remainder >> 1 : (remainder >> 1) ^ 0x8408
            }
        }
        var reversed: UInt16 = 0
        for bit in 0..<16 { reversed |= ((remainder >> bit) & 1) << (15 - bit) }
        return reversed
    }
}
