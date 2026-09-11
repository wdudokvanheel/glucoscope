import Foundation

/// Synthetic FRAM and independent expected samples; no sensor/reference exports.
@main
@MainActor
struct NFCHistorySmoke {
    static let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
    static let patch = Data([0x7F, 0, 0, 0, 0, 0])
    nonisolated static let epoch = Date(timeIntervalSinceReferenceDate: 810_000_000.1234568)

    static func main() async throws {
        try ringsAndDates()
        try historyTiming()
        try partialHistory()
        try fieldsAndUnwrittenSlots()
        try invalidFrames()
        try await persistence()
        print("Libre 2 NFC history ring, conversion and persistence fixtures passed.")
    }

    static func ringsAndDates() throws {
        let paired = try pairing()
        let metadata = try readingSession(paired)
        var bytes = fram()
        // Cursor zero means the newest trend is physical slot 15. Distinguish
        // it numerically so reversed traversal cannot pass a minutes-only check.
        writeSample(&bytes, at: 28 + 15 * 6, glucose: 1100)
        writeSample(&bytes, at: 124 + 1 * 6, glucose: 1100)
        refreshCRCs(&bytes)
        let result = decode(bytes, paired, metadata)
        try expect(result.rejection == nil && result.samples.count == 48, "all 16+32 outcomes")
        let trend = try accepted(result, kind: .trend)
        let history = try accepted(result, kind: .history)
        try expect(trend.map(\.sensorMinute) == [1000,999,998,997,996,995,994,993,992,991,990,989,988,987,986,985],
                   "trend cursor wraps newest-first through all 16 slots")
        try expect(history.map(\.sensorMinute) == [990,975,960,945,930,915,900,885,870,855,840,825,810,795,780,765,750,735,720,705,690,675,660,645,630,615,600,585,570,555,540,525],
                   "history cursor wraps through all 32 slots at 15-minute sample times")
        try expect(trend.first?.glucoseMGDL == 125 && trend.dropFirst().allSatisfy { $0.glucoseMGDL == 112 },
                   "physical trend index marker belongs to newest sample")
        try expect(history.first?.glucoseMGDL == 125 && history.dropFirst().allSatisfy { $0.glucoseMGDL == 112 },
                   "physical history index marker belongs to newest sample")
        for sample in trend + history {
            try expect(sample.timestamp == epoch.addingTimeInterval(Double(sample.sensorMinute - 1000) * 60),
                       "exact fractional established anchor arithmetic")
        }
        var recaptured = fram()
        let changedFooter = UInt64(5_000) << 8 | UInt64(2_000) << 52
        for i in 0..<8 { recaptured[336+i] = UInt8(truncatingIfNeeded: changedFooter >> (8*i)) }
        refreshCRCs(&recaptured)
        let freshCalibration = try accepted(decode(recaptured, paired, metadata), kind: .trend)
        try expect(freshCalibration.allSatisfy { $0.glucoseMGDL == 244 },
                   "scan uses its own calibration bytes while retaining the established clock")
        let reloaded = try JSONDecoder().decode(LibreSensorSession.self, from: JSONEncoder().encode(paired))
        let again = try accepted(decode(bytes, reloaded, metadata, receivedAt: epoch.addingTimeInterval(700)), kind: .history)
        try expect(again.map(\.timestamp) == history.map(\.timestamp), "later capture/reload cannot re-anchor history")

        var shifted = Data([0xAA, 0xBB])
        shifted.append(bytes)
        try expect(decode(shifted.dropFirst(2), paired, metadata).rejection == nil, "nonzero Data slice indices")
    }

    static func historyTiming() throws {
        let paired = try pairing()
        let metadata = try readingSession(paired)
        // The three-minute publication lag straddles minute1008. A ring cursor
        // already advanced at1007 identifies an early publication of sample1005.
        for (minute, cursor, newest) in [(1007,2,990), (1008,3,1005), (1007,3,1005), (1442,31,1425), (1443,0,1440)] {
            let result = decode(fram(minute: minute, historyCursor: cursor), paired, metadata,
                                receivedAt: epoch.addingTimeInterval(Double(minute - 1000) * 60))
            let history = try accepted(result, kind: .history)
            try expect(history.first?.sensorMinute == newest && history.last?.sensorMinute == newest - 465,
                       "history publication boundary minute \(minute), cursor \(cursor)")
        }
    }

    static func partialHistory() throws {
        let paired = try pairing()
        let metadata = try readingSession(paired)
        let result = decode(fram(historyCursor: 3), paired, metadata)
        let history = result.samples.filter { $0.kind == .history }
        guard case .rejected(let future) = history[0].outcome else { throw Failure("future newest history accepted") }
        try expect(future.reason == .sampleAfterCurrentMinute && future.sensorMinute == 1005,
                   "mismatched cursor cannot assign a future sample")
        try expect(history.dropFirst().allSatisfy { if case .accepted = $0.outcome { return true }; return false },
                   "valid older history survives a future newest slot")

        let youngFRAM = fram(minute: 65, historyCursor: 4)
        let calibration = try LibreCalibration.capture(fram: youngFRAM, uid: uid, patchInfo: patch, capturedAt: epoch)
        let young = LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "YOUNG", unlockCode: 1234,
                                       setupComplete: true, sensorKind: .libre2_7F, createdAt: epoch, calibration: calibration)
        let snapshot = ReadingSessionSnapshot(id: try young.validatedPersistenceSessionID(),
            stableIdentityFingerprint: try young.stableIdentityFingerprint(), sensorRevision: young.sensorKind.rawValue,
            firstObservedAt: epoch, observedAt: epoch, lifecycleState: .active,
            clock: ReadingClockSnapshot(referenceSensorMinute: 65, referenceDate: epoch,
                                        provenance: LibreSensorClockAnchor.canonicalPersistenceProvenance))
        let decoded = decode(youngFRAM, young, snapshot)
        let good = decoded.samples.compactMap { if case .accepted(let slot) = $0.outcome { return slot.sensorMinute }; return nil }
        try expect(decoded.rejection == nil && good == [65,64,63,62,61,60,60],
                   "short wear retains six trend and one history slot; older warmup/negative slots are rejected")
    }

    static func fieldsAndUnwrittenSlots() throws {
        let paired = try pairing()
        let metadata = try readingSession(paired)
        var bytes = fram()
        // Expected integers independently calculated with Python Decimal(60),
        // coefficient offset .75/sensitivity .0377442 and documented equation.
        let vectors: [(Int, Int, Int)] = [(6000,128,110), (6000,-128,114), (12000,0,237),
                                         (6000,2044,85), (6000,-2044,157)]
        for (index, vector) in vectors.enumerated() {
            writeSample(&bytes, at: 28 + (15 - index) * 6, temperature: vector.0, adjustment: vector.1)
        }
        bytes.replaceSubrange((28 + 10 * 6)..<(28 + 11 * 6), with: repeatElement(UInt8(0), count: 6))
        bytes.replaceSubrange((124 + 1 * 6)..<(124 + 2 * 6), with: repeatElement(UInt8(0xFF), count: 6))
        refreshCRCs(&bytes)
        let result = decode(bytes, paired, metadata)
        try expect(result.rejection == nil && result.samples.count == 48, "unwritten slots retain sibling outcomes")
        let trendOutcomes = result.samples.filter { $0.kind == .trend }
        for (index, vector) in vectors.enumerated() {
            guard case .accepted(let slot) = trendOutcomes[index].outcome else { throw Failure("packed numeric vector rejected") }
            try expect(slot.glucoseMGDL == vector.2, "full NFC temperature/adjustment widths and sign")
        }
        guard case .rejected = trendOutcomes[5].outcome else { throw Failure("zero unwritten trend accepted") }
        guard case .rejected = result.samples.first(where: { $0.kind == .history })!.outcome else {
            throw Failure("FF unwritten history accepted")
        }
    }

    static func invalidFrames() throws {
        let paired = try pairing()
        let metadata = try readingSession(paired)
        let valid = fram()
        try expect(decode(valid.dropLast(), paired, metadata).rejection != nil, "short FRAM")
        for offset in [10, 40, 330] {
            var corrupt = valid; corrupt[offset] ^= 1
            try expect(decode(corrupt, paired, metadata).rejection != nil, "CRC failure in each FRAM section")
        }
        for (offset,value) in [(26,16),(27,32),(4,5)] {
            var invalid = valid; invalid[offset] = UInt8(value); refreshCRCs(&invalid)
            try expect(decode(invalid, paired, metadata).rejection != nil, "bad cursor or lifecycle")
        }
        var foreign = paired; foreign.uid = Data(repeating: 9, count: 8)
        try expect(decode(valid, foreign, metadata).rejection != nil, "paired identity mismatch")
        var missingClock = paired; missingClock.clockAnchor = nil
        try expect(decode(valid, missingClock, metadata).rejection != nil, "missing established clock")
        var unsupported = paired; unsupported.patchInfo = Data([0x7F,0,1,0,0,0])
        try expect(decode(valid, unsupported, metadata).rejection != nil, "Plus rejected")
    }

    static func persistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("glucoscope-nfc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readings.sqlite")
        let store = ReadingStore(configuration: .init(storage: .sqlite(url: url)))
        let gate = LibreFrameGenerationGate()
        let coordinator = LibreCollectionCoordinator(gate: gate, readingStore: store, bridge: bridge(store))
        coordinator.start()
        try await eventually { coordinator.ingestion.snapshot.state == .ready && !coordinator.isWorking }
        let paired = try pairing()
        _ = gate.activate(session: paired, persistenceSessionID: paired.persistenceSessionID)
        let frame = gate.makeFrame(payload: blePayload(), receivedAt: epoch)!
        try expect(coordinator.ingestion.offer(frame), "BLE frame admitted before NFC import")
        try await eventually { coordinator.ingestion.snapshot.completedFrames == 1 && !coordinator.isWorking }
        let before = try await store.snapshot()
        try expect(before.readings.count == 7 && before.deliveries.count == 7, "ordinary BLE path seeded seven trend rows")

        let result = try await coordinator.saveNFCHistory(fram: fram(), pairedSession: paired,
                                                          receivedAt: epoch, isCurrent: { true })
        try expect(result.insertedCount == 41 && result.trendCount == 16 && result.historyCount == 32 && result.rejectedCount == 0, "NFC inserts nine missing trend +32 history; seven BLE overlaps")
        try await eventually { !coordinator.isWorking && coordinator.status.recentReadings.count == 15 }
        let imported = try await store.snapshot()
        try expect(imported.readings.count == 48 && imported.deliveries.count == 48 && imported.conflicts.isEmpty,
                   "NFC import creates one required delivery for each unique sample")
        try expect(imported.readings.filter { $0.kind == .trend }.count == 16 &&
                   imported.readings.filter { $0.kind == .history15Minute }.count == 32,
                   "NFC trend deduplicates with BLE; coarse history has distinct kind")
        try expect(imported.readings.filter { $0.sensorMinute == 990 }.count == 2,
                   "same-minute trend and history remain separate")
        for old in before.readings {
            let current = imported.readings.first { $0.id == old.id }
            try expect(current?.glucoseMGDL == old.glucoseMGDL && current?.sampleDate == old.sampleDate &&
                       current?.primaryOrigin == old.primaryOrigin &&
                       current?.observedOriginFlags == old.observedOriginFlags | ReadingOrigin.nfcTrend.observationFlag,
                       "NFC overlap keeps BLE canonical identity/value/date/origin")
        }
        try expect(imported.readings.allSatisfy {
            $0.glucoseMGDL == 112 && $0.sampleDate == epoch.addingTimeInterval(Double($0.sensorMinute - 1000) * 60)
        }, "all imported rows use checked values and fractional established clock")
        let repeated = try await coordinator.saveNFCHistory(fram: fram(), pairedSession: paired,
                                                            receivedAt: epoch.addingTimeInterval(10), isCurrent: { true })
        try expect(repeated.insertedCount == 0, "repeat scan inserts nothing")
        let afterRepeat = try await store.snapshot()
        try expect(afterRepeat.readings == imported.readings && afterRepeat.deliveries == imported.deliveries,
                   "repeat scan retains exact saved rows and deliveries")
        do {
            _ = try await coordinator.saveNFCHistory(fram: fram(), pairedSession: paired,
                                                     receivedAt: epoch, isCurrent: { false })
            throw Failure("stale NFC attempt was accepted")
        } catch LibrePersistenceBridgeError.staleSession { }
        var corrupt = fram(); corrupt[100] ^= 1
        var corruptRejected = false
        do {
            _ = try await coordinator.saveNFCHistory(fram: corrupt, pairedSession: paired,
                                                     receivedAt: epoch, isCurrent: { true })
        } catch { corruptRejected = true }
        try expect(corruptRejected, "CRC-corrupt NFC import was rejected")
        let afterFailures = try await store.snapshot()
        try expect(afterFailures.readings == imported.readings && afterFailures.deliveries == imported.deliveries,
                   "stale/corrupt imports do not alter existing rows")
        try await eventually { !coordinator.isWorking }
        gate.invalidate()
        try await store.close()
        let reopened = ReadingStore(configuration: .init(storage: .sqlite(url: url)))
        try await reopened.load()
        let retained = try await reopened.snapshot()
        try expect(retained.readings == imported.readings && retained.deliveries == imported.deliveries,
                   "SQLite reopen preserves actual BLE/NFC import IDs, values, dates and deliveries")
        try await reopened.close()
    }

    static func bridge(_ store: ReadingStore) -> LibrePersistenceBridge {
        LibrePersistenceBridge(dependencies: .init(
            loadForIngestion: { _ in throw Failure("unexpected Keychain lookup") },
            restoreMissingClockAnchor: { _, _ in throw Failure("unexpected Keychain repair") },
            resolveSessionMetadata: { _ in throw Failure("unexpected metadata-only writer") },
            querySessionMetadata: { id, fingerprint, revision in
                try await store.sessionMetadata(id: id, stableIdentityFingerprint: fingerprint, sensorRevision: revision)
            },
            openStore: {
                switch await store.currentHealth() {
                case .notLoaded: try await store.load()
                case .healthy: break
                case .unhealthy: _ = try await store.retryAfterFailure()
                case .closed: throw Failure("store closed")
                }
            },
            retryStoreAfterFailure: { _ = try await store.retryAfterFailure() },
            currentStoreHealth: { await store.currentHealth() }
        ))
    }

    static func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw Failure("runtime processing timed out") }
            await Task.yield()
        }
    }

    static func blePayload() -> Data {
        var bytes = Data(repeating: 0, count: 44)
        let word = UInt32(1000) | UInt32(1500) << 14
        for slot in 0..<7 {
            for byte in 0..<4 { bytes[slot*4+byte] = UInt8(truncatingIfNeeded: word >> (8*byte)) }
        }
        bytes[40] = 0xE8; bytes[41] = 0x03
        let checksum = crc(Array(bytes.prefix(42)))
        bytes[42] = UInt8(truncatingIfNeeded: checksum); bytes[43] = UInt8(checksum >> 8)
        return bytes
    }

    static func decode(_ bytes: Data, _ paired: LibreSensorSession, _ metadata: ReadingSessionSnapshot,
                       receivedAt: Date = epoch) -> Libre2NFCHistoryDecodeResult {
        Libre2NFCHistoryDecoder.decode(fram: bytes, pairedSession: paired, session: metadata, receivedAt: receivedAt)
    }

    static func accepted(_ result: Libre2NFCHistoryDecodeResult, kind: Libre2NFCSampleKind) throws -> [Libre2AcceptedSlot] {
        try result.samples.filter { $0.kind == kind }.map {
            guard case .accepted(let slot) = $0.outcome else { throw Failure("unexpected rejected \(kind) slot") }
            return slot
        }
    }

    static func pairing() throws -> LibreSensorSession {
        let calibration = try LibreCalibration.capture(fram: fram(), uid: uid, patchInfo: patch, capturedAt: epoch)
        return LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "SYNTHETIC", unlockCode: 1234,
                                  setupComplete: true, sensorKind: .libre2_7F, createdAt: epoch,
                                  calibration: calibration)
    }

    static func readingSession(_ paired: LibreSensorSession) throws -> ReadingSessionSnapshot {
        ReadingSessionSnapshot(id: try paired.validatedPersistenceSessionID(),
                               stableIdentityFingerprint: try paired.stableIdentityFingerprint(),
                               sensorRevision: paired.sensorKind.rawValue, firstObservedAt: paired.createdAt,
                               observedAt: paired.createdAt, lifecycleState: .active,
                               clock: ReadingClockSnapshot(referenceSensorMinute: 1000, referenceDate: epoch,
                                                           provenance: LibreSensorClockAnchor.canonicalPersistenceProvenance))
    }

    static func fram(minute: Int = 1000, trendCursor: Int = 0, historyCursor: Int = 2) -> Data {
        var bytes = Data(repeating: 0, count: 344)
        bytes[2] = 8; bytes[4] = 3
        bytes[26] = UInt8(trendCursor); bytes[27] = UInt8(historyCursor)
        bytes[316] = UInt8(truncatingIfNeeded: minute); bytes[317] = UInt8(minute >> 8)
        let footer = UInt64(10_000) << 8 | UInt64(2_000) << 52
        for i in 0..<8 { bytes[336+i] = UInt8(truncatingIfNeeded: footer >> (8*i)) }
        for i in 0..<16 { writeSample(&bytes, at: 28 + i*6) }
        for i in 0..<32 { writeSample(&bytes, at: 124 + i*6) }
        refreshCRCs(&bytes)
        return bytes
    }

    static func writeSample(_ bytes: inout Data, at offset: Int, glucose: Int = 1000,
                            temperature: Int = 6000, adjustment: Int = 0) {
        let word = UInt64(glucose) | UInt64(temperature) << 24 | UInt64(abs(adjustment)/4) << 38 |
            (adjustment < 0 ? UInt64(1) << 47 : 0)
        for i in 0..<6 { bytes[offset+i] = UInt8(truncatingIfNeeded: word >> (8*i)) }
    }

    static func refreshCRCs(_ bytes: inout Data) {
        for bounds in [0..<24,24..<320,320..<344] {
            let checksum = crc(Array(bytes[(bounds.lowerBound+2)..<bounds.upperBound]))
            bytes[bounds.lowerBound] = UInt8(truncatingIfNeeded: checksum)
            bytes[bounds.lowerBound+1] = UInt8(checksum >> 8)
        }
    }

    // Independent unreflected recurrence, unlike the runtime reflected CRC.
    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var remainder: UInt16 = 0xFFFF
        for byte in bytes {
            for bit in 0..<8 {
                let feedback = ((remainder >> 15) ^ UInt16((byte >> bit) & 1)) != 0
                remainder <<= 1
                if feedback { remainder ^= 0x1021 }
            }
        }
        return remainder
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message) }
    }
}
