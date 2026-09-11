import Foundation

/// Synthetic contract fixtures only. They exercise the checked development decoder
/// and do not establish physical sensor accuracy.
@main
struct ProductionDecoderSmoke {
    static let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
    static let patch7F = Data([0x7F, 0, 0, 0, 0, 0])
    static let wearID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static let storeMinimum = Date(timeIntervalSince1970: 946_684_800)
    static let storeMaximum = Date(timeIntervalSince1970: 4_102_444_800)

    struct Fixture {
        let frame: LibreVerifiedFrame
        let session: ReadingSessionSnapshot
        let ownership: Libre2DecodeOwnership
    }

    static func main() throws {
        let fixture = try makeFixture()

        let blockers = Libre2ProductionPolicy.engineeringV1.qualificationBlockers
        try expect(Libre2ProductionPolicy.engineeringV1.canIngestCanonical,
                   "the development policy authorizes checked local ingestion")
        try expect(blockers == Set(Libre2QualificationBlocker.allCases) && blockers.count == 4,
                   "all qualification blockers remain explicit")
        let canonical = decode(fixture)
        try expect(canonical.rejection == nil && canonical.slots.count == 7,
                   "a structurally valid frame produces seven checked development outcomes")
        try expect(canonical.context.persistenceSessionID == wearID &&
                   canonical.context.generation == fixture.frame.generation &&
                   canonical.context.sequence == fixture.frame.sequence &&
                   canonical.context.receivedAt == fixture.frame.receivedAt &&
                   canonical.context.policyVersion == Libre2ProductionPolicy.engineeringV1.rawValue &&
                   canonical.context.decoderVersion == Libre2ProductionDecoder.version,
                   "redacted immutable context identifies the evaluated callback")

        try wholeFrameRejections(fixture)
        try immutableOwnershipAndSlices(fixture)
        try recognizedRevisionsDecode()

#if LIBRE2_ENGINEERING_DECODER_FIXTURES
        try slotOutcomesAndIndependentMath()
        try dateAndMinuteBoundaries()
        try roundingBoundaries()
        print("Libre 2 checked development decoder and engineering fixtures passed (not accuracy validation).")
#else
        print("Libre 2 checked development decoder passed with engineering seam excluded.")
#endif
    }

    static func wholeFrameRejections(_ valid: Fixture) throws {
        let disabled = Libre2ProductionDecoder.decode(frame: valid.frame, session: valid.session,
                                                      ownership: nil)
        try expect(disabled.rejection == .collectionDisabled && disabled.slots.isEmpty,
                   "disabled collection")
        try expectReject(valid,
                         ownership: Libre2DecodeOwnership(generation: valid.frame.generation + 1,
                                                          session: valid.frame.sessionSnapshot,
                                                          persistenceSessionID: valid.frame.persistenceSessionID),
                         .staleOwnership, "stale generation")
        var advancedSession = valid.frame.sessionSnapshot
        advancedSession.nextUnlockCount += 1
        try expectReject(valid,
                         ownership: Libre2DecodeOwnership(generation: valid.frame.generation,
                                                          session: advancedSession,
                                                          persistenceSessionID: valid.frame.persistenceSessionID),
                         .staleOwnership, "a later counter cannot relabel captured bytes")

        let noWearFrame = LibreVerifiedFrame(payload: valid.frame.payload,
                                             receivedAt: valid.frame.receivedAt,
                                             sequence: valid.frame.sequence,
                                             generation: valid.frame.generation,
                                             sessionSnapshot: valid.frame.sessionSnapshot,
                                             persistenceSessionID: nil)
        let noWear = Fixture(frame: noWearFrame, session: valid.session,
                             ownership: Libre2DecodeOwnership(generation: noWearFrame.generation,
                                                              session: noWearFrame.sessionSnapshot,
                                                              persistenceSessionID: nil))
        try expectReject(noWear, .missingWearIdentity, "missing durable wear identity")

        var disabledSession = valid.frame.sessionSnapshot
        disabledSession.setupComplete = false
        let disabledFrame = copiedFrame(valid.frame, sessionSnapshot: disabledSession)
        try expectReject(reown(disabledFrame, session: valid.session), .collectionDisabled,
                         "incomplete transport session")

        try expectReject(Fixture(frame: valid.frame,
                                 session: copySession(valid.session, id: UUID()),
                                 ownership: valid.ownership),
                         .sessionMismatch, "reconciled UUID mismatch")
        try expectReject(Fixture(frame: valid.frame,
                                 session: copySession(valid.session,
                                                      fingerprint: Data(repeating: 0xA5, count: 32)),
                                 ownership: valid.ownership),
                         .sessionMismatch, "stable fingerprint mismatch")
        try expectReject(Fixture(frame: valid.frame,
                                 session: copySession(valid.session, revision: LibreSensorKind.libre2_C5.rawValue),
                                 ownership: valid.ownership),
                         .sessionMismatch, "reconciled revision mismatch")

        let shortFrame = copiedFrame(valid.frame, payload: Data(valid.frame.payload.dropLast()))
        try expectReject(reown(shortFrame, session: valid.session), .invalidLength, "non-44-byte plaintext")
        var corrupt = valid.frame.payload
        corrupt[0] ^= 1
        let corruptFrame = copiedFrame(valid.frame, payload: corrupt)
        try expectReject(reown(corruptFrame, session: valid.session), .invalidCRC, "payload corruption")

        var plusSession = valid.frame.sessionSnapshot
        plusSession.patchInfo = Data([0x7F, 0, 1, 0, 0, 0])
        let plusFrame = copiedFrame(valid.frame, sessionSnapshot: plusSession)
        try expectReject(reown(plusFrame, session: valid.session), .unsupportedRevision,
                         "Libre 2 Plus remains unsupported")

        let noCalibrationSession = try makeTransport(calibration: nil, patch: patch7F, includeClock: false)
        let noCalibrationFrame = copiedFrame(valid.frame, sessionSnapshot: noCalibrationSession)
        let noCalibrationReading = try makeReadingSession(for: noCalibrationSession, clock: valid.session.clock)
        try expectReject(reown(noCalibrationFrame, session: noCalibrationReading), .missingCalibration,
                         "missing calibration")

        let expiredCalibration = try calibration(minute: 20_881)
        let expiredSession = try makeTransport(calibration: expiredCalibration, patch: patch7F, includeClock: false)
        let expiredFrame = copiedFrame(valid.frame, sessionSnapshot: expiredSession)
        let expiredReading = try makeReadingSession(for: expiredSession, clock: valid.session.clock)
        try expectReject(reown(expiredFrame, session: expiredReading), .invalidCalibrationMetadata,
                         "calibration minute beyond supported lifetime")

        let foreignCalibration = try calibration(uid: Data(repeating: 9, count: 8))
        let foreignSession = try makeTransport(calibration: foreignCalibration, patch: patch7F)
        let foreignFrame = copiedFrame(valid.frame, sessionSnapshot: foreignSession)
        let foreignReading = try makeReadingSession(for: foreignSession, clock: valid.session.clock)
        try expectReject(reown(foreignFrame, session: foreignReading), .wrongCalibrationOwner,
                         "calibration owner mismatch")

        let missingClockSession = try sessionWithoutClock(valid.frame.sessionSnapshot)
        let missingClockFrame = copiedFrame(valid.frame, sessionSnapshot: missingClockSession)
        try expectReject(reown(missingClockFrame, session: valid.session), .missingAnchor,
                         "missing captured clock")

        var invalidClockObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(valid.frame.sessionSnapshot.clockAnchor!)
        ) as! [String: Any]
        invalidClockObject["uncertaintySeconds"] = 61
        let invalidClock = try JSONDecoder().decode(
            LibreSensorClockAnchor.self, from: JSONSerialization.data(withJSONObject: invalidClockObject)
        )
        var invalidClockSession = valid.frame.sessionSnapshot
        invalidClockSession.clockAnchor = invalidClock
        let invalidClockFrame = copiedFrame(valid.frame, sessionSnapshot: invalidClockSession)
        try expectReject(reown(invalidClockFrame, session: valid.session), .invalidAnchor,
                         "unsupported clock resolution")

        let shiftedClock = ReadingClockSnapshot(referenceSensorMinute: valid.session.clock.referenceSensorMinute,
                                                referenceDate: valid.session.clock.referenceDate.addingTimeInterval(0.002),
                                                provenance: valid.session.clock.provenance)
        try expectReject(Fixture(frame: valid.frame,
                                 session: copySession(valid.session, clock: shiftedClock),
                                 ownership: valid.ownership),
                         .clockDisagreement, "clock mismatch outside representation tolerance")
        let wrongProvenance = ReadingClockSnapshot(referenceSensorMinute: valid.session.clock.referenceSensorMinute,
                                                   referenceDate: valid.session.clock.referenceDate,
                                                   provenance: "caller-clock")
        try expectReject(Fixture(frame: valid.frame,
                                 session: copySession(valid.session, clock: wrongProvenance),
                                 ownership: valid.ownership),
                         .invalidAnchor, "unqualified canonical clock provenance")

        let reversedDates = ReadingSessionSnapshot(
            id: valid.session.id, stableIdentityFingerprint: valid.session.stableIdentityFingerprint,
            sensorRevision: valid.session.sensorRevision,
            firstObservedAt: valid.session.observedAt.addingTimeInterval(1), observedAt: valid.session.observedAt,
            lifecycleState: .active, clock: valid.session.clock
        )
        try expectReject(Fixture(frame: valid.frame, session: reversedDates, ownership: valid.ownership),
                         .invalidSessionMetadata, "incoherent observation order")
        try expectReject(Fixture(frame: valid.frame,
                                 session: copySession(valid.session, lifecycle: .ended),
                                 ownership: valid.ownership),
                         .inactiveSession, "inactive wear")

        for seconds in [Double.nan, Double.infinity, -Double.infinity,
                        storeMinimum.timeIntervalSince1970 - 1,
                        storeMaximum.timeIntervalSince1970 + 1] {
            let invalidReceipt = copiedFrame(valid.frame,
                                             receivedAt: Date(timeIntervalSince1970: seconds))
            let rejected = decode(reown(invalidReceipt, session: valid.session))
            try expect(rejected.rejection == .invalidSessionMetadata &&
                       rejected.context.receivedAt == nil,
                       "invalid receipt date rejects without unsafe context date")
        }

        let oldPayload = payload(minute: 999)
        let oldFrame = copiedFrame(valid.frame, payload: oldPayload)
        try expectReject(reown(oldFrame, session: valid.session), .sensorMinuteBeforeAnchor,
                         "whole frame before canonical anchor")
        let overLifetimeFrame = copiedFrame(valid.frame, payload: payload(minute: 20_881))
        try expectReject(reown(overLifetimeFrame, session: valid.session), .sensorLifetimeExceeded,
                         "frame after supported lifetime")

        let invalidDomainCalibration = try calibration(index: 0)
        let invalidDomain = try makeFixture(calibration: invalidDomainCalibration)
        try expectReject(invalidDomain, .invalidCalibrationDomain, "unsupported coefficient regime")
    }

    static func immutableOwnershipAndSlices(_ valid: Fixture) throws {
        var sourcePayload = valid.frame.payload
        var sourceSession = valid.frame.sessionSnapshot
        let ownedFrame = LibreVerifiedFrame(payload: sourcePayload, receivedAt: valid.frame.receivedAt,
                                            sequence: 88, generation: 99, sessionSnapshot: sourceSession,
                                            persistenceSessionID: valid.frame.persistenceSessionID)
        let owned = Libre2DecodeOwnership(generation: 99, session: sourceSession,
                                          persistenceSessionID: valid.frame.persistenceSessionID)
        sourcePayload[0] ^= 1
        sourceSession.patchInfo[0] = 0xC5
        let immutable = Fixture(frame: ownedFrame, session: valid.session, ownership: owned)
        try expect(decode(immutable).rejection == nil && ownedFrame.payload != sourcePayload &&
                   ownedFrame.sessionSnapshot != sourceSession,
                   "frame owns payload and session values independently of later mutation")

        let prefixedPayload = Data([0xFF]) + valid.frame.payload
        let slicedPayload = prefixedPayload.dropFirst()
        let slicedPayloadFrame = copiedFrame(valid.frame, payload: slicedPayload)
        try expect(decode(reown(slicedPayloadFrame, session: valid.session)).rejection == nil,
                   "sliced payload indices are normalized")

        var slicedSession = valid.frame.sessionSnapshot
        let prefixedUID = Data([0xFF]) + slicedSession.uid
        let prefixedPatch = Data([0xFF]) + slicedSession.patchInfo
        slicedSession.uid = prefixedUID.dropFirst()
        slicedSession.patchInfo = prefixedPatch.dropFirst()
        let slicedMetadataFrame = copiedFrame(valid.frame, sessionSnapshot: slicedSession)
        try expect(decode(reown(slicedMetadataFrame, session: valid.session)).rejection == nil,
                   "sliced UID and patch metadata are normalized before fixed indexing")
    }

    static func recognizedRevisionsDecode() throws {
        for patch in [Data([0x9D, 0, 0, 0, 0, 0]), Data([0xC5, 0, 0, 0, 0, 0]), patch7F] {
            let fixture = try makeFixture(patch: patch)
            let result = decode(fixture)
            try expect(result.rejection == nil && result.slots.count == 7,
                       "recognized revision \(patch[0]) decodes for development storage")
        }
    }

#if LIBRE2_ENGINEERING_DECODER_FIXTURES
    static func slotOutcomesAndIndependentMath() throws {
        let valid = try makeFixture()
        let evaluation = evaluate(valid)
        let accepted = evaluation.slots.compactMap { outcome -> Libre2AcceptedSlot? in
            guard case .accepted(let slot) = outcome else { return nil }
            return slot
        }
        try expect(evaluation.rejection == nil && evaluation.slots.count == 7 && accepted.count == 7,
                   "engineering evaluation returns seven explicit outcomes")
        try expect(accepted.map(\.index) == Array(0..<7) &&
                   accepted.map(\.offsetMinutes) == [0, 2, 4, 6, 7, 12, 15] &&
                   accepted.map(\.sensorMinute) == [1000, 998, 996, 994, 993, 988, 985],
                   "seven sparse slots remain in wire order")
        try expect(accepted.allSatisfy { $0.glucoseMGDL == 112 &&
                   $0.decoderVersion == Libre2ProductionDecoder.version &&
                   $0.quality == "engineeringChecksPassed-v1" },
                   "accepted slots contain only canonical integer and fixed identifiers")

        var mixedPayload = payload(minute: 1000)
        writeWord(&mixedPayload, slot: 1, glucose: 0, temperature: 6000, adjustment: 0)
        writeWord(&mixedPayload, slot: 2, glucose: 1000, temperature: 0, adjustment: 0)
        writeWord(&mixedPayload, slot: 3, glucose: 1000, temperature: 4, adjustment: 0)
        writeWord(&mixedPayload, slot: 4, glucose: 1000, temperature: 200, adjustment: 0)
        writeWord(&mixedPayload, slot: 5, glucose: 1, temperature: 6000, adjustment: 0)
        refreshCRC(&mixedPayload)
        let mixed = evaluate(reown(copiedFrame(valid.frame, payload: mixedPayload), session: valid.session))
        try expect(mixed.slots.map(rejectionReason) ==
                   [nil, .zeroGlucose, .zeroTemperature, .invalidTemperatureDomain,
                    .temperatureOutsideEngineeringRange, .glucoseOutsideCanonicalRange, nil],
                   "a bad raw/domain slot preserves good siblings and every rejection outcome")

        // Expected unrounded values were independently evaluated with Python Decimal
        // at precision 60 from the documented nonlinear equation.
        let oracles: [(Int, Int, Int, Int, Int, Int)] = [
            (1, 1000, 6000, 0, 0, 112),       // 112.106692953321622526
            (513, 1000, 6000, 4, -10, 60),   // 59.893508751123186787
            (720, 3000, 9000, -124, 100, 234), // 234.168126218974318035
            (952, 1000, 6000, 124, 0, 33),   // 32.619765752110341839
            (1023, 3000, 9000, 0, 0, 150)    // 149.637745952544577726
        ]
        for (index, glucose, temperature, adjustment, i3, expected) in oracles {
            let sensor = try calibration(index: index, i3: i3)
            let oracleFixture = try makeFixture(calibration: sensor,
                                                payload: payload(minute: 1000, glucose: glucose,
                                                                 temperature: temperature, adjustment: adjustment))
            guard case .accepted(let slot) = evaluate(oracleFixture).slots[0] else {
                throw Failure(message: "independent nonlinear oracle \(index) rejected")
            }
            try expect(slot.glucoseMGDL == expected, "independent nonlinear oracle \(index)")
        }
    }

    static func dateAndMinuteBoundaries() throws {
        let shifted = try makeFixture(sessionClockShift: 0.0005)
        guard case .accepted(let shiftedSlot) = evaluate(shifted).slots[0] else {
            throw Failure(message: "representational clock tolerance rejected")
        }
        try expect(shiftedSlot.timestamp == shifted.session.clock.referenceDate,
                   "accepted date derives from canonical SQLite clock")

        let recovery = try makeFixture(frameMinute: 1002)
        let recoverySlots = evaluate(recovery).slots
        guard case .accepted(let beforeAnchor) = recoverySlots[2] else {
            throw Failure(message: "pre-anchor recovery slot rejected")
        }
        try expect(beforeAnchor.sensorMinute == 998 &&
                   beforeAnchor.timestamp == epoch.addingTimeInterval(-120),
                   "recovery slot before reference uses a negative clock delta")

        let early = try makeFixture(calibration: calibration(minute: 0), frameMinute: 6)
        try expect(evaluate(early).slots.map(rejectionReason) ==
                   [.warmup, .warmup, .warmup, .warmup,
                    .sampleBeforeStart, .sampleBeforeStart, .sampleBeforeStart],
                   "negative and warmup outcomes are per-slot")

        let warmupEdge = try makeFixture(calibration: calibration(minute: 0), frameMinute: 60)
        let warmupEdgeOutcomes = evaluate(warmupEdge).slots
        guard case .accepted(let firstUsableMinute) = warmupEdgeOutcomes[0] else {
            throw Failure(message: "first post-warmup minute rejected")
        }
        try expect(firstUsableMinute.sensorMinute == 60 &&
                   warmupEdgeOutcomes.dropFirst().allSatisfy { rejectionReason($0) == .warmup },
                   "warmup endpoint preserves the first usable sibling")

        let lower = try makeFixture(calibration: calibration(minute: 1000, capturedAt: storeMinimum),
                                    receivedAt: storeMinimum)
        let lowerOutcomes = evaluate(lower).slots
        guard case .accepted(let lowerEndpoint) = lowerOutcomes[0] else {
            throw Failure(message: "inclusive lower store date rejected")
        }
        try expect(lowerEndpoint.timestamp == storeMinimum &&
                   lowerOutcomes.dropFirst().allSatisfy { rejectionReason($0) == .invalidSampleDate },
                   "date lower endpoint is inclusive while older siblings reject individually")

        let upper = try makeFixture(calibration: calibration(minute: 1000, capturedAt: storeMaximum),
                                    receivedAt: storeMaximum)
        guard case .accepted(let upperEndpoint) = evaluate(upper).slots[0] else {
            throw Failure(message: "inclusive upper store date rejected")
        }
        try expect(upperEndpoint.timestamp == storeMaximum,
                   "date upper endpoint is inclusive")

        let beyondUpper = try makeFixture(
            calibration: calibration(minute: 1000, capturedAt: storeMaximum),
            frameMinute: 1002, receivedAt: storeMaximum
        )
        let beyondUpperOutcomes = evaluate(beyondUpper).slots
        guard case .accepted(let upperRecovery) = beyondUpperOutcomes[1] else {
            throw Failure(message: "upper-bound recovery sibling rejected")
        }
        try expect(rejectionReason(beyondUpperOutcomes[0]) == .invalidSampleDate &&
                   upperRecovery.sensorMinute == 1000 && upperRecovery.timestamp == storeMaximum,
                   "future out-of-range slot does not discard an in-range older sibling")

        let lifetime = try makeFixture(frameMinute: 20_880)
        guard case .accepted(let lifetimeSlot) = evaluate(lifetime).slots[0] else {
            throw Failure(message: "supported lifetime endpoint rejected")
        }
        try expect(lifetimeSlot.sensorMinute == 20_880,
                   "sensor lifetime endpoint is inclusive")
    }

    static func roundingBoundaries() throws {
        let values: [(Double, Int?)] = [
            (19.9, nil), (20, 20), (20.5, 21), (599.5, 600), (600, 600), (600.1, nil),
            (.infinity, nil), (-.infinity, nil), (.nan, nil)
        ]
        for (value, expected) in values {
            try expect(Libre2ProductionDecoder.quantizeForEngineeringFixture(value) == expected,
                       "canonical rounding boundary \(value)")
        }
    }

    static func evaluate(_ fixture: Fixture) -> Libre2EngineeringEvaluation {
        Libre2ProductionDecoder.evaluateEngineering(frame: fixture.frame, session: fixture.session,
                                                    ownership: fixture.ownership)
    }

    static func rejectionReason(_ outcome: Libre2SlotOutcome) -> Libre2SlotRejectionReason? {
        guard case .rejected(let rejection) = outcome else { return nil }
        return rejection.reason
    }
#endif

    static func decode(_ fixture: Fixture) -> Libre2ProductionDecodeResult {
        Libre2ProductionDecoder.decode(frame: fixture.frame, session: fixture.session,
                                       ownership: fixture.ownership)
    }

    static func expectReject(_ fixture: Fixture, ownership: Libre2DecodeOwnership? = nil,
                             _ reason: Libre2FrameRejection, _ message: String) throws {
        let actualOwnership = ownership ?? fixture.ownership
        let result = Libre2ProductionDecoder.decode(frame: fixture.frame, session: fixture.session,
                                                    ownership: actualOwnership)
        try expect(result.rejection == reason && result.slots.isEmpty, message)
    }

    static func makeFixture(
        calibration suppliedCalibration: LibreCalibration? = nil,
        patch: Data = patch7F,
        frameMinute: Int = 1000,
        payload suppliedPayload: Data? = nil,
        receivedAt suppliedReceivedAt: Date? = nil,
        sessionClockShift: TimeInterval = 0
    ) throws -> Fixture {
        let sensorCalibration = try suppliedCalibration ?? calibration(patch: patch)
        let transport = try makeTransport(calibration: sensorCalibration, patch: patch)
        let anchor = transport.clockAnchor!
        let canonicalClock = ReadingClockSnapshot(
            referenceSensorMinute: Int64(anchor.referenceSensorMinute),
            referenceDate: anchor.referenceDate.addingTimeInterval(sessionClockShift),
            provenance: LibreSensorClockAnchor.canonicalPersistenceProvenance
        )
        let reading = try makeReadingSession(for: transport, clock: canonicalClock)
        let receivedAt = suppliedReceivedAt ?? anchor.referenceDate
        let frame = LibreVerifiedFrame(payload: suppliedPayload ?? payload(minute: frameMinute),
                                       receivedAt: receivedAt, sequence: 7, generation: 11,
                                       sessionSnapshot: transport, persistenceSessionID: wearID)
        return Fixture(frame: frame, session: reading,
                       ownership: Libre2DecodeOwnership(generation: frame.generation, session: transport,
                                                        persistenceSessionID: wearID))
    }

    static func makeTransport(calibration: LibreCalibration?, patch: Data,
                              includeClock: Bool = true) throws -> LibreSensorSession {
        let kind = (try? Libre2Protocol.classify(patchInfo: Data(Array(patch)))) ?? .libre2_7F
        let capturedAt = calibration?.capturedAt ?? epoch
        var session = LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "ABBOTTTEST",
                                         unlockCode: 1234, setupComplete: true, sensorKind: kind,
                                         createdAt: capturedAt, calibration: calibration,
                                         persistenceSessionID: wearID)
        if !includeClock { session.clockAnchor = nil }
        return session
    }

    static func makeReadingSession(for transport: LibreSensorSession,
                                   clock: ReadingClockSnapshot) throws -> ReadingSessionSnapshot {
        ReadingSessionSnapshot(id: wearID, stableIdentityFingerprint: try transport.stableIdentityFingerprint(),
                               sensorRevision: transport.sensorKind.rawValue,
                               firstObservedAt: transport.createdAt, observedAt: transport.createdAt,
                               lifecycleState: .active, clock: clock)
    }

    static func copySession(_ source: ReadingSessionSnapshot, id: UUID? = nil,
                            fingerprint: Data? = nil, revision: String? = nil,
                            lifecycle: ReadingSessionLifecycle? = nil,
                            clock: ReadingClockSnapshot? = nil) -> ReadingSessionSnapshot {
        ReadingSessionSnapshot(id: id ?? source.id,
                               stableIdentityFingerprint: fingerprint ?? source.stableIdentityFingerprint,
                               sensorRevision: revision ?? source.sensorRevision,
                               firstObservedAt: source.firstObservedAt, observedAt: source.observedAt,
                               lifecycleState: lifecycle ?? source.lifecycleState, clock: clock ?? source.clock)
    }

    static func copiedFrame(_ source: LibreVerifiedFrame, payload: Data? = nil,
                            receivedAt: Date? = nil,
                            sessionSnapshot: LibreSensorSession? = nil) -> LibreVerifiedFrame {
        LibreVerifiedFrame(payload: payload ?? source.payload, receivedAt: receivedAt ?? source.receivedAt,
                           sequence: source.sequence, generation: source.generation,
                           sessionSnapshot: sessionSnapshot ?? source.sessionSnapshot,
                           persistenceSessionID: source.persistenceSessionID)
    }

    static func reown(_ frame: LibreVerifiedFrame, session: ReadingSessionSnapshot) -> Fixture {
        Fixture(frame: frame, session: session,
                ownership: Libre2DecodeOwnership(generation: frame.generation,
                                                 session: frame.sessionSnapshot,
                                                 persistenceSessionID: frame.persistenceSessionID))
    }

    static func sessionWithoutClock(_ session: LibreSensorSession) throws -> LibreSensorSession {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        object["clockAnchor"] = NSNull()
        return try JSONDecoder().decode(LibreSensorSession.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    static func calibration(index: Int = 1, i3: Int = 0, i4: Int = 10_000, i6: Int = 8_000,
                            minute: Int = 1000, state: UInt8 = 3, capturedAt: Date = epoch,
                            uid: Data = uid, patch: Data = patch7F) throws -> LibreCalibration {
        var fram = Data(repeating: 0, count: 344)
        let header = UInt16(index << 3)
        fram[2] = UInt8(truncatingIfNeeded: header)
        fram[3] = UInt8(header >> 8)
        fram[4] = state
        fram[316] = UInt8(truncatingIfNeeded: minute)
        fram[317] = UInt8(truncatingIfNeeded: minute >> 8)
        let footer = UInt64(abs(i3)) | UInt64(i4) << 8 |
            (i3 < 0 ? UInt64(1) << 33 : 0) | UInt64(i6 / 4) << 52
        for byte in 0..<8 { fram[336 + byte] = UInt8(truncatingIfNeeded: footer >> (byte * 8)) }
        for range in [0..<24, 24..<320, 320..<344] {
            let checksum = fixtureCRC(Array(fram[(range.lowerBound + 2)..<range.upperBound]))
            fram[range.lowerBound] = UInt8(truncatingIfNeeded: checksum)
            fram[range.lowerBound + 1] = UInt8(checksum >> 8)
        }
        return try LibreCalibration.capture(fram: fram, uid: uid, patchInfo: patch, capturedAt: capturedAt)
    }

    static func payload(minute: Int, glucose: Int = 1000,
                        temperature: Int = 6000, adjustment: Int = 0) -> Data {
        var bytes = Data(repeating: 0, count: 44)
        for slot in 0..<7 {
            writeWord(&bytes, slot: slot, glucose: glucose, temperature: temperature, adjustment: adjustment)
        }
        bytes[40] = UInt8(truncatingIfNeeded: minute)
        bytes[41] = UInt8(truncatingIfNeeded: minute >> 8)
        refreshCRC(&bytes)
        return bytes
    }

    static func writeWord(_ bytes: inout Data, slot: Int, glucose: Int,
                          temperature: Int, adjustment: Int) {
        let word = UInt32(glucose) | UInt32(temperature / 4) << 14 |
            UInt32(abs(adjustment) / 4) << 26 | (adjustment < 0 ? UInt32(1) << 31 : 0)
        for byte in 0..<4 {
            bytes[slot * 4 + byte] = UInt8(truncatingIfNeeded: word >> (byte * 8))
        }
    }

    static func refreshCRC(_ bytes: inout Data) {
        let checksum = fixtureCRC(Array(bytes.prefix(42)))
        bytes[42] = UInt8(truncatingIfNeeded: checksum)
        bytes[43] = UInt8(checksum >> 8)
    }

    // Independent unreflected recurrence; it does not call the production CRC.
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

    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
}
