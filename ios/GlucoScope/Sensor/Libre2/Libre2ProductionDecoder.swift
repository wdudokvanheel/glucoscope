import Foundation

/// An engineering policy is not evidence of sensor accuracy or live sensor health.
/// The development app stores checked results with engineering provenance.
enum Libre2ProductionPolicy: String, Sendable, CaseIterable {
    case engineeringV1 = "libre2-production-engineering-policy-v1"

    var canIngestCanonical: Bool { true }
    var qualificationBlockers: Set<Libre2QualificationBlocker> {
        Set(Libre2QualificationBlocker.allCases)
    }
}

enum Libre2QualificationBlocker: String, Sendable, CaseIterable {
    case numericalEvidence, liveStatus, clockFreshness, writerOwnership
}

/// A caller-supplied snapshot of enabled ownership for a synchronous evaluation.
/// This value cannot prove continued ownership after an await or authorize a commit.
struct Libre2DecodeOwnership: Sendable, Equatable {
    let generation: UInt64
    let session: LibreSensorSession
    let persistenceSessionID: UUID?
}

/// Redacted provenance; no raw payload, UID, pairing secret or calibration escapes.
struct Libre2DecodeContext: Sendable, Equatable {
    let persistenceSessionID: UUID?
    let generation: UInt64
    let sequence: UInt64
    /// Invalid input dates remain absent even on a rejected frame, so consumers
    /// cannot accidentally pass nonfinite or unsupported provenance to a formatter.
    let receivedAt: Date?
    let policyVersion: String
    let decoderVersion: String
}

enum Libre2FrameRejection: String, Error, Sendable {
    case collectionDisabled, staleOwnership, missingWearIdentity, sessionMismatch
    case invalidLength, invalidCRC, unsupportedRevision, invalidRingIndex
    case missingCalibration, invalidCalibrationMetadata, wrongCalibrationOwner, lifecycleNotSupported
    case missingAnchor, invalidAnchor, clockDisagreement, invalidSessionMetadata, inactiveSession
    case sensorMinuteBeforeAnchor, sensorLifetimeExceeded, invalidCalibrationDomain, unqualifiedPolicy
}

enum Libre2SlotRejectionReason: String, Sendable {
    case sampleBeforeStart, sampleAfterCurrentMinute, warmup, invalidSampleDate, zeroGlucose, zeroTemperature
    case invalidTemperatureDomain, temperatureOutsideEngineeringRange, nonfiniteConversion
    case glucoseOutsideCanonicalRange
}

struct Libre2SlotRejection: Sendable, Equatable {
    let index: Int
    let offsetMinutes: Int
    let sensorMinute: Int?
    let reason: Libre2SlotRejectionReason
}

/// Only the decoder can construct a checked slot. This is not a ReadingCandidate.
struct Libre2AcceptedSlot: Sendable, Equatable {
    let index: Int
    let offsetMinutes: Int
    let sensorMinute: Int
    let timestamp: Date
    let glucoseMGDL: Int
    let decoderVersion: String
    let quality: String

    fileprivate init(index: Int, offsetMinutes: Int, sensorMinute: Int, timestamp: Date, glucoseMGDL: Int,
                     decoderVersion: String = Libre2ProductionDecoder.version) {
        self.index = index
        self.offsetMinutes = offsetMinutes
        self.sensorMinute = sensorMinute
        self.timestamp = timestamp
        self.glucoseMGDL = glucoseMGDL
        self.decoderVersion = decoderVersion
        self.quality = "engineeringChecksPassed-v1"
    }
}

enum Libre2SlotOutcome: Sendable, Equatable {
    case accepted(Libre2AcceptedSlot)
    case rejected(Libre2SlotRejection)
}

struct Libre2ProductionDecodeResult: Sendable, Equatable {
    let context: Libre2DecodeContext
    let rejection: Libre2FrameRejection?
    let slots: [Libre2SlotOutcome]

    fileprivate init(context: Libre2DecodeContext, rejection: Libre2FrameRejection?, slots: [Libre2SlotOutcome]) {
        self.context = context
        self.rejection = rejection
        self.slots = slots
    }
}

#if LIBRE2_ENGINEERING_DECODER_FIXTURES
/// Available only in the portable fixture executable, never enabled by DEBUG.
/// Seven engineering outcomes do not constitute a qualified production result.
struct Libre2EngineeringEvaluation: Sendable, Equatable {
    let context: Libre2DecodeContext
    let rejection: Libre2FrameRejection?
    let slots: [Libre2SlotOutcome]
}
#endif

/// Pure decoder boundary. Nothing here reads storage, repairs a
/// clock, ingests readings, publishes glucose or interprets payload bytes 28..<40.
enum Libre2ProductionDecoder {
    static let version = "libre2-nonlinear-production-v1"
    static let sampleOffsets = [0, 2, 4, 6, 7, 12, 15]
    private static let maximumSensorMinute = LibreSensorClockAnchor.maximumSensorMinute
    private static let storeDateRange = 946_684_800.0...4_102_444_800.0

    static func decode(
        frame: LibreVerifiedFrame,
        session: ReadingSessionSnapshot,
        ownership: Libre2DecodeOwnership?,
        policy: Libre2ProductionPolicy = .engineeringV1
    ) -> Libre2ProductionDecodeResult {
        let context = makeContext(frame: frame, policy: policy)
        switch validate(frame: frame, session: session, ownership: ownership) {
        case .failure(let reason):
            return Libre2ProductionDecodeResult(context: context, rejection: reason, slots: [])
        case .success(let common):
            let slots = sampleOffsets.enumerated().map { index, offset in
                evaluateSlot(index: index, offset: offset, common: common)
            }
            return Libre2ProductionDecodeResult(context: context, rejection: nil, slots: slots)
        }
    }

#if LIBRE2_ENGINEERING_DECODER_FIXTURES
    static func evaluateEngineering(
        frame: LibreVerifiedFrame,
        session: ReadingSessionSnapshot,
        ownership: Libre2DecodeOwnership?,
        policy: Libre2ProductionPolicy = .engineeringV1
    ) -> Libre2EngineeringEvaluation {
        let result = decode(frame: frame, session: session, ownership: ownership, policy: policy)
        return Libre2EngineeringEvaluation(context: result.context, rejection: result.rejection, slots: result.slots)
    }

    static func quantizeForEngineeringFixture(_ value: Double) -> Int? {
        quantize(value)
    }
#endif

    private struct ValidatedFrame {
        let bytes: [UInt8]
        let minute: Int
        let calibration: LibreCalibration
        let clock: ReadingClockSnapshot
        let offset: Double
        let sensitivity: Double
    }

    private static func makeContext(frame: LibreVerifiedFrame, policy: Libre2ProductionPolicy) -> Libre2DecodeContext {
        Libre2DecodeContext(persistenceSessionID: frame.persistenceSessionID,
                            generation: frame.generation, sequence: frame.sequence,
                            receivedAt: usableDate(frame.receivedAt) ? frame.receivedAt : nil,
                            policyVersion: policy.rawValue, decoderVersion: version)
    }

    private static func validate(
        frame: LibreVerifiedFrame, session: ReadingSessionSnapshot, ownership: Libre2DecodeOwnership?
    ) -> Result<ValidatedFrame, Libre2FrameRejection> {
        guard let ownership else { return .failure(.collectionDisabled) }
        guard ownership.generation == frame.generation,
              ownership.session == frame.sessionSnapshot,
              ownership.persistenceSessionID == frame.persistenceSessionID else { return .failure(.staleOwnership) }
        let captured = frame.sessionSnapshot
        guard captured.setupComplete else { return .failure(.collectionDisabled) }
        guard let wearID = frame.persistenceSessionID,
              (try? captured.validatedPersistenceSessionID()) == wearID else { return .failure(.missingWearIdentity) }
        guard session.id == wearID else { return .failure(.sessionMismatch) }
        guard frame.payload.count == 44 else { return .failure(.invalidLength) }
        let bytes = Array(frame.payload)
        guard payloadCRC(bytes.prefix(42)) == UInt16(bytes[42]) | UInt16(bytes[43]) << 8 else {
            return .failure(.invalidCRC)
        }
        // The existing fingerprint helper classifies by fixed Data offsets. Use
        // a local normalized copy without relabeling the captured ownership value.
        var normalized = captured
        normalized.uid = Data(Array(captured.uid))
        normalized.patchInfo = Data(Array(captured.patchInfo))
        guard let revision = try? Libre2Protocol.classify(patchInfo: normalized.patchInfo),
              revision == captured.sensorKind else { return .failure(.unsupportedRevision) }
        guard let fingerprint = try? normalized.stableIdentityFingerprint(),
              fingerprint == session.stableIdentityFingerprint,
              session.sensorRevision == revision.rawValue else { return .failure(.sessionMismatch) }
        guard let calibration = captured.calibration else { return .failure(.missingCalibration) }
        // LibreCalibration's private initializer and strict Codable decoder enforce
        // the exact ten-byte compact source and bounded bit fields before access.
        guard calibration.formatVersion == LibreCalibration.currentFormatVersion,
              calibration.ownerUID.count == 8,
              usableDate(calibration.capturedAt),
              (0...maximumSensorMinute).contains(calibration.sensorMinute) else {
            return .failure(.invalidCalibrationMetadata)
        }
        guard (try? calibration.validateOwnership(uid: normalized.uid, patchInfo: normalized.patchInfo)) != nil else {
            return .failure(.wrongCalibrationOwner)
        }
        guard calibration.lifecycle == 0x02 || calibration.lifecycle == 0x03 else {
            return .failure(.lifecycleNotSupported)
        }
        guard let anchor = captured.clockAnchor else { return .failure(.missingAnchor) }
        guard anchor.formatVersion == LibreSensorClockAnchor.currentFormatVersion,
              anchor.ownerUID.count == 8,
              (try? anchor.validateOwnership(uid: normalized.uid, patchInfo: normalized.patchInfo)) != nil,
              anchor.uncertaintySeconds == 60,
              usableDate(anchor.referenceDate),
              (0...maximumSensorMinute).contains(anchor.referenceSensorMinute),
              usableDate(session.clock.referenceDate),
              (0...Int64(maximumSensorMinute)).contains(session.clock.referenceSensorMinute),
              session.clock.provenance == LibreSensorClockAnchor.canonicalPersistenceProvenance else {
            return .failure(.invalidAnchor)
        }
        guard session.clock.referenceSensorMinute == Int64(anchor.referenceSensorMinute),
              abs(session.clock.referenceDate.timeIntervalSince(anchor.referenceDate)) <= 0.001 else {
            return .failure(.clockDisagreement)
        }
        guard usableDate(session.firstObservedAt), usableDate(session.observedAt),
              usableDate(frame.receivedAt), usableDate(captured.createdAt),
              session.firstObservedAt <= session.observedAt else { return .failure(.invalidSessionMetadata) }
        guard session.lifecycleState == .active else { return .failure(.inactiveSession) }
        let minute = Int(bytes[40]) | Int(bytes[41]) << 8
        guard minute >= anchor.referenceSensorMinute else { return .failure(.sensorMinuteBeforeAnchor) }
        guard minute <= maximumSensorMinute else { return .failure(.sensorLifetimeExceeded) }
        // Share only the finite-domain coefficient reconstruction with diagnostics;
        // never consume a diagnostic frame, slot, value, acceptance rule or fallback.
        guard let coefficients = Libre2DiagnosticDecoder.calibrationCoefficients(index: calibration.i2),
              coefficients.offset.isFinite, coefficients.sensitivity.isFinite, coefficients.sensitivity > 0,
              calibration.i4 > calibration.i3, calibration.i6 > 0 else { return .failure(.invalidCalibrationDomain) }
        return .success(ValidatedFrame(bytes: bytes, minute: minute, calibration: calibration,
                                       clock: session.clock, offset: coefficients.offset, sensitivity: coefficients.sensitivity))
    }

    private static func evaluateSlot(index: Int, offset: Int, common: ValidatedFrame) -> Libre2SlotOutcome {
        let start = index * 4
        let bytes = common.bytes
        let word = UInt32(bytes[start]) | UInt32(bytes[start + 1]) << 8
            | UInt32(bytes[start + 2]) << 16 | UInt32(bytes[start + 3]) << 24
        let glucose = Double(word & 0x3FFF)
        let temperature = Double((word >> 14) & 0xFFF) * 4
        let magnitude = Double((word >> 26) & 0x1F) * 4
        let adjustment = word & 0x8000_0000 == 0 ? magnitude : -magnitude
        return evaluateRawSlot(index: index, offset: offset, frameMinute: common.minute,
                               glucose: glucose, temperature: temperature, adjustment: adjustment,
                               calibration: common.calibration, clock: common.clock,
                               calibrationOffset: common.offset, sensitivity: common.sensitivity)
    }

    /// The BLE and NFC layouts feed the same checked conversion and clock mapping.
    static func evaluateRawSlot(
        index: Int, offset: Int, frameMinute: Int,
        glucose: Double, temperature: Double, adjustment: Double,
        calibration: LibreCalibration, clock: ReadingClockSnapshot,
        calibrationOffset: Double, sensitivity: Double,
        decoderVersion: String = version
    ) -> Libre2SlotOutcome {
        let subtraction = frameMinute.subtractingReportingOverflow(offset)
        let minute = subtraction.partialValue
        func rejected(_ reason: Libre2SlotRejectionReason) -> Libre2SlotOutcome {
            .rejected(Libre2SlotRejection(index: index, offsetMinutes: offset,
                                         sensorMinute: subtraction.overflow ? nil : minute, reason: reason))
        }
        guard !subtraction.overflow, minute >= 0 else { return rejected(.sampleBeforeStart) }
        guard minute >= 60 else { return rejected(.warmup) }
        let delta = Int64(minute).subtractingReportingOverflow(clock.referenceSensorMinute)
        guard !delta.overflow else { return rejected(.invalidSampleDate) }
        let interval = Double(delta.partialValue) * 60
        let seconds = clock.referenceDate.timeIntervalSince1970 + interval
        guard interval.isFinite, seconds.isFinite, storeDateRange.contains(seconds) else {
            return rejected(.invalidSampleDate)
        }
        // Match the canonical clock and writer without an epoch conversion that
        // can round away subsecond precision from an NFC capture's Date().
        let timestamp = clock.referenceDate.addingTimeInterval(interval)
        guard usableDate(timestamp) else { return rejected(.invalidSampleDate) }
        guard glucose > 0 else { return rejected(.zeroGlucose) }
        guard temperature > 0 else { return rejected(.zeroTemperature) }
        let denominator = Double(calibration.i6) + adjustment
        guard denominator.isFinite, denominator > 0 else { return rejected(.invalidTemperatureDomain) }
        let scaledTemperature = temperature * 72_500
        guard scaledTemperature.isFinite else { return rejected(.invalidTemperatureDomain) }
        let resistance = scaledTemperature / denominator - 1_000
        guard resistance.isFinite, resistance > 0 else { return rejected(.invalidTemperatureDomain) }
        let logarithm = log(resistance)
        guard logarithm.isFinite else { return rejected(.invalidTemperatureDomain) }
        let cubicTerm = 0.00000005283566 * logarithm
        let quadraticTerm = logarithm * (0.0000007061775 + cubicTerm)
        let linearTerm = logarithm * (0.0001964561 + quadraticTerm)
        guard cubicTerm.isFinite, quadraticTerm.isFinite, linearTerm.isFinite else {
            return rejected(.invalidTemperatureDomain)
        }
        let inverseKelvin = 0.0009180023 + linearTerm
        guard inverseKelvin.isFinite, inverseKelvin > 0 else { return rejected(.invalidTemperatureDomain) }
        let celsius = 1 / inverseKelvin - 273.15
        guard celsius.isFinite else { return rejected(.nonfiniteConversion) }
        guard (-10.0...60.0).contains(celsius) else { return rejected(.temperatureOutsideEngineeringRange) }
        // All fields were structurally decoded into bounded integers. Convert them
        // before subtraction/multiplication to avoid fixed-width integer traps.
        let glucoseDifference = glucose - Double(calibration.i3)
        let calibrationDifference = Double(calibration.i4) - Double(calibration.i3)
        let scaledGlucose = 65 * glucoseDifference
        guard scaledGlucose.isFinite, calibrationDifference.isFinite, calibrationDifference > 0 else {
            return rejected(.nonfiniteConversion)
        }
        let normalized = scaledGlucose / calibrationDifference
        let exponent = 32.5 - celsius
        guard normalized.isFinite, exponent.isFinite else { return rejected(.nonfiniteConversion) }
        let factor = pow(1.045, exponent)
        guard factor.isFinite, factor > 0 else { return rejected(.nonfiniteConversion) }
        let corrected = normalized * factor
        guard corrected.isFinite else { return rejected(.nonfiniteConversion) }
        let numerator = corrected - calibrationOffset
        guard numerator.isFinite else { return rejected(.nonfiniteConversion) }
        let value = numerator / sensitivity
        guard value.isFinite else { return rejected(.nonfiniteConversion) }
        guard let integer = quantize(value) else { return rejected(.glucoseOutsideCanonicalRange) }
        return .accepted(Libre2AcceptedSlot(index: index, offsetMinutes: offset, sensorMinute: minute,
                                            timestamp: timestamp, glucoseMGDL: integer, decoderVersion: decoderVersion))
    }

    private static func quantize(_ value: Double) -> Int? {
        guard value.isFinite, (20.0...600.0).contains(value) else { return nil }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        guard rounded.isFinite, let integer = Int(exactly: rounded), (20...600).contains(integer) else { return nil }
        return integer
    }

    private static func usableDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && storeDateRange.contains(seconds)
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
