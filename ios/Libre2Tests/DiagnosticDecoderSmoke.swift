import Foundation

/// Synthetic fixtures. Expected decimal values were independently evaluated at 60-digit
/// precision from the documented equation and selected source coefficients, not this decoder.
@main
struct DiagnosticDecoderSmoke {
    static let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
    static let patch = Data([0x9D, 0, 0, 0, 0, 0])
    static let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    static func main() throws {
        let calibration = try calibration()
        let clockAnchor = try LibreSensorClockAnchor.capture(from: calibration)
        let packet = payload(minute: 1000)
        let frame = decode(packet, calibration)
        try expect(frame.rejection == nil && frame.slots.count == 7, "seven real sparse slots")
        try expect(frame.slots.map(\.offsetMinutes) == [0, 2, 4, 6, 7, 12, 15], "fixed sparse offsets")
        try expect(frame.slots.map(\.sensorMinute) == [1000, 998, 996, 994, 993, 988, 985], "sample minutes")
        try expect(frame.slots.map { $0.timestamp.timeIntervalSince1970 } ==
                   [1700000000, 1699999880, 1699999760, 1699999640, 1699999580, 1699999280, 1699999100], "anchored UTC dates")
        try expect(frame.slots.allSatisfy { $0.rejection == nil }, "unchanged valid glucose accepted in all slots")
        try expect(decode(packet, calibration) == frame, "repeat frame never rejected for constant glucose")
        let advanced = decode(payload(minute: 1002), calibration)
        try expect(advanced.slots[1].timestamp == frame.slots[0].timestamp, "overlapping sample minute has stable date")
        let restored = try JSONDecoder().decode(LibreCalibration.self, from: JSONEncoder().encode(calibration))
        let restoredClock = try JSONDecoder().decode(LibreSensorClockAnchor.self, from: JSONEncoder().encode(clockAnchor))
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: restored, clockAnchor: restoredClock,
                    uid: uid, patchInfo: patch) == frame, "relaunch uses persisted independent anchor")
        // Reproduce recapture clock estimates shifting -6 seconds then +22 seconds.
        // The saved clock, not either new capture date, owns every overlapping timestamp.
        let recaptured = try self.calibration(minute: 1002, capturedAt: anchor.addingTimeInterval(114))
        let afterRecapture = Libre2DiagnosticDecoder.decode(payload: payload(minute: 1002), calibration: recaptured,
                                                           clockAnchor: clockAnchor, uid: uid, patchInfo: patch)
        try expect(afterRecapture == advanced, "first recapture never shifts sample dates")
        let recapturedAgain = try self.calibration(minute: 1004, capturedAt: anchor.addingTimeInterval(256))
        let afterSecondRecapture = Libre2DiagnosticDecoder.decode(payload: payload(minute: 1004), calibration: recapturedAgain,
                                                                 clockAnchor: restoredClock, uid: uid, patchInfo: patch)
        try expect(afterSecondRecapture.slots[2].sensorMinute == 1000 &&
                   afterSecondRecapture.slots[2].timestamp.timeIntervalSince1970 == 1700000000,
                   "second recapture and anchor reload preserve identical sample date")
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: nil,
                    uid: uid, patchInfo: patch).rejection == .missingAnchor, "missing clock has no implicit fallback")
        for nonfinite in [Double.infinity, -Double.infinity, Double.nan] {
            var rejected = false
            do { _ = try self.calibration(capturedAt: Date(timeIntervalSince1970: nonfinite)) }
            catch { rejected = true }
            try expect(rejected, "nonfinite capture date cannot construct calibration or clock")
        }
        var wrongClockObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clockAnchor)) as! [String: Any]
        wrongClockObject["ownerUID"] = Data(repeating: 0, count: 8).base64EncodedString()
        let foreignClock = try JSONDecoder().decode(LibreSensorClockAnchor.self,
                                                    from: JSONSerialization.data(withJSONObject: wrongClockObject))
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: foreignClock,
                    uid: uid, patchInfo: patch).rejection == .invalidAnchor, "clock identity checked independently from calibration")
        let prefixed = Data([255]) + packet
        try expect(decode(prefixed.dropFirst(), calibration) == frame, "nonzero Data start index")
        let prefixedPatch = Data([255]) + patch
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: clockAnchor, uid: uid,
                    patchInfo: prefixedPatch.dropFirst()) == frame, "nonzero patch Data start index")

        let oracles: [(Int, Int, Int, Int, Int, Double)] = [
            (1, 1000, 6000, 0, 0, 112.106692953321622526),
            (513, 1000, 6000, 4, -10, 59.893508751123186787),
            (720, 3000, 9000, -124, 100, 234.168126218974318035),
            (952, 1000, 6000, 124, 0, 32.619765752110341839),
            (1023, 3000, 9000, 0, 0, 149.637745952544577726)
        ]
        for (index, glucose, temperature, adjustment, i3, expected) in oracles {
            let sensor = try self.calibration(index: index, i3: i3)
            let actual = decode(payload(minute: 1000, glucose: glucose, temperature: temperature, adjustment: adjustment), sensor).slots[0]
            try expect(actual.rejection == nil, "oracle \(index) accepted")
            try near(actual.glucoseMgDL, expected, tolerance: 1e-8, "nonlinear oracle \(index)")
        }
        try near(frame.slots[0].temperatureCelsius, 38.5453102753473783, tolerance: 1e-10, "temperature oracle")
        // These coefficients pin both sides of every regime transition and the supported endpoints.
        let boundaries: [(Int, Double, Double)] = [
            (1, 0.75, 0.0377442), (512, 2.5, 0.0706475),
            (513, 0.75, 0.0713540), (719, 2.75, 0.0888155),
            (720, 1, 0.0897036), (951, 2.75, 0.1185246),
            (952, 1, 0.1197099), (1023, 3, 0.1283452)
        ]
        for (index, offset, sensitivity) in boundaries {
            let coefficients = Libre2DiagnosticDecoder.calibrationCoefficients(index: index)
            try near(coefficients?.offset, offset, tolerance: 1e-14, "offset \(index)")
            try near(coefficients?.sensitivity, sensitivity, tolerance: 1e-14, "sensitivity \(index)")
        }
        try expect(Libre2DiagnosticDecoder.calibrationCoefficients(index: 0) == nil, "zero coefficient index")
        try expect(Libre2DiagnosticDecoder.calibrationCoefficients(index: 1024) == nil, "no coefficient extrapolation")

        for length in [0, 1, 42, 43, 45, 46, 100] {
            try expect(decode(Data(repeating: 0, count: length), calibration).rejection == .invalidLength, "payload length \(length)")
        }
        var corrupted = packet
        corrupted[0] ^= 1
        try expect(decode(corrupted, calibration).rejection == .invalidCRC, "CRC protects raw samples")
        corrupted = packet; corrupted[43] ^= 1
        try expect(decode(corrupted, calibration).rejection == .invalidCRC, "CRC trailer corruption")
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: clockAnchor,
                    uid: Data(repeating: 0, count: 8), patchInfo: patch).rejection == .wrongSensor, "wrong UID")
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: clockAnchor,
                    uid: uid, patchInfo: Data([0xC5, 0, 0, 0, 0, 0])).rejection == .wrongSensor, "wrong exact patch")
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: clockAnchor,
                    uid: uid, patchInfo: Data([0x9D, 0, 0, 0, 7, 8])) == frame, "mutable patch word does not replace sensor ownership")
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: clockAnchor,
                    uid: uid, patchInfo: Data([0x9D, 0, 0, 1, 0, 0])).rejection == .wrongSensor, "stable patch byte changed")
        try expect(Libre2DiagnosticDecoder.decode(payload: packet, calibration: calibration, clockAnchor: clockAnchor,
                    uid: uid, patchInfo: Data([0x7F, 0, 1, 0, 0, 0])).rejection == .unsupportedCalibration, "unsupported Plus")
        try expect(decode(payload(minute: 999), calibration).rejection == .sensorMinuteBeforeAnchor, "clock rollback or stale frame")
        try expect(decode(payload(minute: 20880), calibration).rejection == nil, "reference lifetime endpoint")
        try expect(decode(payload(minute: 20881), calibration).rejection == .sensorLifetimeExceeded, "lifetime exceeded")
        try expect(decode(packet, try self.calibration(minute: 20881)).rejection == .invalidCalibrationMetadata, "expired calibration metadata")
        try expect(decode(packet, try self.calibration(state: 2)).slots.allSatisfy { $0.rejection == nil }, "starting snapshot permits post-warmup samples")
        let early = try self.calibration(minute: 0)
        try expect(decode(payload(minute: 60), early).slots.map(\.rejection) ==
                   [nil, .warmup, .warmup, .warmup, .warmup, .warmup, .warmup], "warmup applied per sample")
        try expect(decode(payload(minute: 0), early).slots.map(\.rejection) ==
                   [.warmup, .sampleBeforeStart, .sampleBeforeStart, .sampleBeforeStart, .sampleBeforeStart, .sampleBeforeStart, .sampleBeforeStart], "negative sample minute")
        for sensor in [try self.calibration(index: 0), try self.calibration(i3: 100, i4: 100), try self.calibration(i6: 0)] {
            try expect(decode(packet, sensor).rejection == .invalidCalibrationDomain, "calibration domain")
        }
        var mixed = packet
        mixed.replaceSubrange(4..<8, with: [0, 0, 0, 0])
        refreshCRC(&mixed)
        let mixedFrame = decode(mixed, calibration)
        try expect(mixedFrame.slots[1].rejection == .zeroGlucose && mixedFrame.slots[0].glucoseMgDL != nil,
                   "invalid slot does not discard good neighbor")
        try expect(decode(payload(minute: 1000, temperature: 0), calibration).slots[0].rejection == .zeroTemperature, "zero temperature")
        try expect(decode(payload(minute: 1000, temperature: 4), calibration).slots[0].rejection == .invalidTemperatureDomain, "nonpositive resistance")
        try expect(decode(payload(minute: 1000, adjustment: -124), try self.calibration(i6: 4)).slots[0].rejection == .invalidTemperatureDomain, "nonpositive adjusted denominator")
        try expect(decode(payload(minute: 1000, temperature: 200), calibration).slots[0].rejection == .temperatureOutsideDiagnosticRange, "finite extreme temperature policy")
        try expect(decode(payload(minute: 1000, glucose: 1), calibration).slots[0].rejection == .glucoseOutsideDiagnosticRange, "finite nonpositive glucose rejected")
        let extremes = decode(payload(minute: 1000, glucose: 16383, temperature: 16380, adjustment: -124), calibration).slots[0]
        try expect(extremes.rawGlucose == 16383 && extremes.rawTemperature == 16380 && extremes.temperatureAdjustment == -124, "full packed widths and negative sign")
        let extremeCalibration = try self.calibration(i3: -255, i4: 16383, i6: 16380)
        let extremeArithmetic = decode(payload(minute: 1000, glucose: 16383, temperature: 16380,
                                               adjustment: 124), extremeCalibration)
        try expect(extremeArithmetic.rejection == nil && extremeArithmetic.slots.count == 7,
                   "packed calibration and sample extremes do not overflow frame decode")
        let positive = decode(payload(minute: 1000, adjustment: 124), calibration).slots[0]
        try expect(positive.temperatureAdjustment == 124, "positive adjustment sign")
        var versionObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calibration)) as! [String: Any]
        versionObject["formatVersion"] = 2
        do {
            _ = try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: versionObject))
            throw FixtureFailure(message: "unsupported calibration version accepted")
        } catch LibreCalibrationError.unsupportedFormatVersion(_) { }
        print("Libre 2 diagnostic decoder synthetic fixtures passed (not physical accuracy validation).")
    }

    static func decode(_ payload: Data, _ calibration: LibreCalibration) -> Libre2DiagnosticFrame {
        // Synthetic convenience only. Production always supplies the independently persisted session clock.
        Libre2DiagnosticDecoder.decode(payload: payload, calibration: calibration,
                                      clockAnchor: try? LibreSensorClockAnchor.capture(from: calibration),
                                      uid: uid, patchInfo: patch)
    }

    static func calibration(index: Int = 1, i3: Int = 0, i4: Int = 10000, i6: Int = 8000,
                            minute: Int = 1000, state: UInt8 = 3, capturedAt: Date = anchor) throws -> LibreCalibration {
        var fram = Data(repeating: 0, count: 344)
        let header = UInt16(index << 3)
        fram[2] = UInt8(truncatingIfNeeded: header); fram[3] = UInt8(header >> 8)
        fram[4] = state
        fram[316] = UInt8(truncatingIfNeeded: minute); fram[317] = UInt8(minute >> 8)
        let footer = UInt64(abs(i3)) | UInt64(i4) << 8 | (i3 < 0 ? UInt64(1) << 33 : 0) | UInt64(i6 / 4) << 52
        for byte in 0..<8 { fram[336 + byte] = UInt8(truncatingIfNeeded: footer >> (byte * 8)) }
        for range in [0..<24, 24..<320, 320..<344] {
            let checksum = fixtureCRC(Array(fram[(range.lowerBound + 2)..<range.upperBound]))
            fram[range.lowerBound] = UInt8(truncatingIfNeeded: checksum)
            fram[range.lowerBound + 1] = UInt8(checksum >> 8)
        }
        return try LibreCalibration.capture(fram: fram, uid: uid, patchInfo: patch, capturedAt: capturedAt)
    }

    static func payload(minute: Int, glucose: Int = 1000, temperature: Int = 6000, adjustment: Int = 0) -> Data {
        var bytes = Data(repeating: 0, count: 44)
        let word = UInt32(glucose) | UInt32(temperature / 4) << 14 | UInt32(abs(adjustment) / 4) << 26
            | (adjustment < 0 ? UInt32(1) << 31 : 0)
        for slot in 0..<7 {
            for byte in 0..<4 { bytes[slot * 4 + byte] = UInt8(truncatingIfNeeded: word >> (byte * 8)) }
        }
        bytes[40] = UInt8(truncatingIfNeeded: minute); bytes[41] = UInt8(minute >> 8)
        refreshCRC(&bytes)
        return bytes
    }

    static func refreshCRC(_ bytes: inout Data) {
        let checksum = fixtureCRC(Array(bytes.prefix(42)))
        bytes[42] = UInt8(truncatingIfNeeded: checksum); bytes[43] = UInt8(checksum >> 8)
    }

    // Fixture CRC uses the unreflected polynomial, processing each byte least-significant bit first.
    // It shares no production helper and makes field-mutation fixtures independently CRC-valid.
    static func fixtureCRC(_ bytes: [UInt8]) -> UInt16 {
        var checksum: UInt16 = 0xFFFF
        for byte in bytes {
            for bit in 0..<8 {
                let feedback = ((checksum >> 15) ^ UInt16((byte >> bit) & 1)) != 0
                checksum = checksum << 1
                if feedback { checksum ^= 0x1021 }
            }
        }
        return checksum
    }

    struct FixtureFailure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureFailure(message: message) }
    }
    static func near(_ actual: Double?, _ expected: Double, tolerance: Double, _ message: String) throws {
        try expect(actual.map { $0.isFinite && abs($0 - expected) <= tolerance } ?? false, message)
    }
}
