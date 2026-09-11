import Foundation

enum Libre2NFCSampleKind: String, Sendable {
    case trend, history
}

struct Libre2NFCSample: Sendable, Equatable {
    let kind: Libre2NFCSampleKind
    let outcome: Libre2SlotOutcome
}

typealias Libre2NFCHistoryRejection = Libre2FrameRejection

struct Libre2NFCHistoryDecodeResult: Sendable, Equatable {
    let rejection: Libre2NFCHistoryRejection?
    let sensorMinute: Int?
    let samples: [Libre2NFCSample]
}

/// Decodes one read-only scan after NFC has matched the tag to the paired sensor.
/// Samples use the existing wear's clock; scan receipt never establishes an anchor.
enum Libre2NFCHistoryDecoder {
    static let version = "libre2-nfc-nonlinear-v1"
    private static let maximumSensorMinute = LibreSensorClockAnchor.maximumSensorMinute
    private static let storeDateRange = 946_684_800.0...4_102_444_800.0

    static func decode(
        fram: Data,
        pairedSession: LibreSensorSession,
        session: ReadingSessionSnapshot,
        receivedAt: Date
    ) -> Libre2NFCHistoryDecodeResult {
        func rejected(_ reason: Libre2NFCHistoryRejection) -> Libre2NFCHistoryDecodeResult {
            Libre2NFCHistoryDecodeResult(rejection: reason, sensorMinute: nil, samples: [])
        }
        guard fram.count == 344 else { return rejected(.invalidLength) }
        let normalizedFRAM = Data(Array(fram))
        guard Libre2Protocol.validateFRAM(normalizedFRAM) else { return rejected(.invalidCRC) }
        let bytes = Array(normalizedFRAM)
        guard bytes[26] < 16, bytes[27] < 32 else { return rejected(.invalidRingIndex) }
        guard bytes[4] == 0x02 || bytes[4] == 0x03 else { return rejected(.lifecycleNotSupported) }
        guard pairedSession.setupComplete else { return rejected(.collectionDisabled) }
        guard let wearID = try? pairedSession.validatedPersistenceSessionID() else {
            return rejected(.missingWearIdentity)
        }
        var paired = pairedSession
        paired.uid = Data(Array(paired.uid))
        paired.patchInfo = Data(Array(paired.patchInfo))
        guard let revision = try? Libre2Protocol.classify(patchInfo: paired.patchInfo),
              revision == paired.sensorKind else { return rejected(.unsupportedRevision) }
        guard session.id == wearID,
              let fingerprint = try? paired.stableIdentityFingerprint(),
              fingerprint == session.stableIdentityFingerprint,
              session.sensorRevision == revision.rawValue else { return rejected(.sessionMismatch) }
        guard session.lifecycleState == .active else { return rejected(.inactiveSession) }
        guard usableDate(receivedAt), usableDate(paired.createdAt),
              usableDate(session.firstObservedAt), usableDate(session.observedAt),
              session.firstObservedAt <= session.observedAt else { return rejected(.invalidSessionMetadata) }
        guard let anchor = paired.clockAnchor else { return rejected(.missingAnchor) }
        guard anchor.formatVersion == LibreSensorClockAnchor.currentFormatVersion,
              anchor.ownerUID.count == 8,
              (try? anchor.validateOwnership(uid: paired.uid, patchInfo: paired.patchInfo)) != nil,
              anchor.uncertaintySeconds == 60,
              usableDate(anchor.referenceDate),
              (0...maximumSensorMinute).contains(anchor.referenceSensorMinute),
              usableDate(session.clock.referenceDate),
              (0...Int64(maximumSensorMinute)).contains(session.clock.referenceSensorMinute),
              session.clock.provenance == LibreSensorClockAnchor.canonicalPersistenceProvenance else {
            return rejected(.invalidAnchor)
        }
        guard session.clock.referenceSensorMinute == Int64(anchor.referenceSensorMinute),
              abs(session.clock.referenceDate.timeIntervalSince(anchor.referenceDate)) <= 0.001 else {
            return rejected(.clockDisagreement)
        }
        let minute = Int(bytes[316]) | Int(bytes[317]) << 8
        guard minute >= anchor.referenceSensorMinute else { return rejected(.sensorMinuteBeforeAnchor) }
        guard minute <= maximumSensorMinute else { return rejected(.sensorLifetimeExceeded) }
        guard let calibration = try? LibreCalibration.capture(
            fram: normalizedFRAM, uid: paired.uid, patchInfo: paired.patchInfo, capturedAt: receivedAt
        ) else { return rejected(.invalidCalibrationMetadata) }
        guard let coefficients = Libre2DiagnosticDecoder.calibrationCoefficients(index: calibration.i2),
              coefficients.offset.isFinite, coefficients.sensitivity.isFinite, coefficients.sensitivity > 0,
              calibration.i4 > calibration.i3, calibration.i6 > 0 else {
            return rejected(.invalidCalibrationDomain)
        }

        func sample(kind: Libre2NFCSampleKind, index: Int, ringSlot: Int,
                    start: Int, sampleMinute: Int) -> Libre2NFCSample {
            guard sampleMinute <= minute else {
                return Libre2NFCSample(kind: kind, outcome: .rejected(Libre2SlotRejection(
                    index: index, offsetMinutes: minute - sampleMinute, sensorMinute: sampleMinute,
                    reason: .sampleAfterCurrentMinute
                )))
            }
            let position = start + ringSlot * 6
            let glucose = Int(bytes[position]) | Int(bytes[position + 1] & 0x1F) << 8
            let temperature = Int(bytes[position + 3]) | Int(bytes[position + 4] & 0x3F) << 8
            let magnitude = (Int(bytes[position + 4] >> 6) | Int(bytes[position + 5] & 0x7F) << 2) * 4
            let adjustment = bytes[position + 5] & 0x80 == 0 ? magnitude : -magnitude
            let outcome = Libre2ProductionDecoder.evaluateRawSlot(
                index: index, offset: minute - sampleMinute, frameMinute: minute,
                glucose: Double(glucose), temperature: Double(temperature), adjustment: Double(adjustment),
                calibration: calibration, clock: session.clock,
                calibrationOffset: coefficients.offset, sensitivity: coefficients.sensitivity,
                decoderVersion: version
            )
            return Libre2NFCSample(kind: kind, outcome: outcome)
        }

        let trendCursor = Int(bytes[26])
        let historyCursor = Int(bytes[27])
        var samples = (0..<16).map { index in
            sample(kind: .trend, index: index, ringSlot: (trendCursor + 15 - index) % 16,
                   start: 28, sampleMinute: minute - index)
        }
        // History represents quarter-hour sensor minutes and is normally written
        // three minutes later. The cursor can advance before the age counter.
        let completedQuarters = (minute - 3) / 15
        let newestHistoryMinute = (completedQuarters + (historyCursor == completedQuarters % 32 ? 0 : 1)) * 15
        samples += (0..<32).map { index in
            sample(kind: .history, index: index, ringSlot: (historyCursor + 31 - index) % 32,
                   start: 124, sampleMinute: newestHistoryMinute - index * 15)
        }
        return Libre2NFCHistoryDecodeResult(rejection: nil, sensorMinute: minute, samples: samples)
    }

    private static func usableDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && storeDateRange.contains(seconds)
    }
}
