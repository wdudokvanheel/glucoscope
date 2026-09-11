import Foundation

/// Isolated adapter fixtures, not production decoder or sensor qualification.
@main
struct CandidateAdapterSmoke {
    static let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
    static let patch7F = Data([0x7F, 0, 0, 0, 0, 0])
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    struct Rig {
        let gate: LibreFrameGenerationGate
        let frame: LibreVerifiedFrame
        let store: ReadingStore
        let adapter: LibreCandidateAdapter
        let faults: ReadingStoreFaultInjector
    }

    static func main() async throws {
        try await ordinaryDevelopmentBoundary()
        #if LIBRE2_CANDIDATE_ADAPTER_FIXTURES && LIBRE2_ENGINEERING_DECODER_FIXTURES && LIBRE2_ORDERED_INGESTION_FIXTURES
        try await mappingAndDuplicates()
        try await orderedReversedMinutesAndConflicts()
        try await malformedBindings()
        try await rejectionAndResidence()
        try await preparationRevocation()
        try await failureAndRecovery()
        try await boundedRecoveryCheckpoint()
        #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
        try await guardedRevocation()
        #endif
        print("Libre candidate adapter fixture mapping/guarded persistence passed with development ingestion enabled.")
#else
        print("Libre candidate adapter ordinary development source persisted checked readings.")
        #endif
    }

    static func rig(glucose: Int = 1000, date: Date = epoch,
                    calibrationMinute: Int = 1000, frameMinute: Int = 1000,
                    suspendQuery: Suspension? = nil) async throws -> Rig {
        let sensorCalibration = try calibration(minute: calibrationMinute, capturedAt: date)
        let session = LibreSensorSession(uid: uid, patchInfo: patch7F, advertisedName: "ABBOTTTEST",
                                         unlockCode: 1234, setupComplete: true, sensorKind: .libre2_7F,
                                         createdAt: date, calibration: sensorCalibration,
                                         persistenceSessionID: UUID())
        let gate = LibreFrameGenerationGate()
        gate.activate(session: session, persistenceSessionID: session.persistenceSessionID)
        let frame = gate.makeFrame(payload: payload(minute: frameMinute, glucose: glucose), receivedAt: date)!
        let faults = ReadingStoreFaultInjector()
        let store = ReadingStore(configuration: ReadingStoreConfiguration(
            storage: .inMemory(identifier: UUID().uuidString)), faultInjector: faults)
        let bridge = LibrePersistenceBridge(dependencies: LibrePersistenceBridgeDependencies(
            loadForIngestion: { _ in throw Failure(message: "candidate preparation touched Keychain") },
            restoreMissingClockAnchor: { _, _ in throw Failure(message: "candidate preparation repaired clock") },
            resolveSessionMetadata: { _ in throw Failure(message: "candidate preparation mutated metadata") },
            querySessionMetadata: { id, fingerprint, revision in
                if let suspendQuery { await suspendQuery.pause() }
                return try await store.sessionMetadata(id: id, stableIdentityFingerprint: fingerprint,
                                                       sensorRevision: revision)
            },
            openStore: { try await store.load() },
            retryStoreAfterFailure: { _ = try await store.retryAfterFailure() },
            currentStoreHealth: { await store.currentHealth() }
        ))
        let adapter = LibreCandidateAdapter(readingStore: store, bridge: bridge, gate: gate)
        try await adapter.open()
        return Rig(gate: gate, frame: frame, store: store, adapter: adapter, faults: faults)
    }

    static func ordinaryDevelopmentBoundary() async throws {
        let rig = try await rig()
        let queue = LibreOrderedIngestion(adapter: rig.adapter, gate: rig.gate)
        queue.start()
        try await waitIdle(queue)
        try expect(queue.snapshot.state == .ready, "ordinary fixed adapter opens queue")
        try expect(queue.offer(rig.frame), "ordinary queue accepts current frame")
        try await waitIdle(queue)
        try expect(queue.snapshot.completedFrames == 1 && queue.snapshot.rejectedWholeFrames == 0,
                   "ordinary checked decoder completes through the guarded writer")
        let snapshot = try await rig.store.snapshot()
        try expect(snapshot.sessions.count == 1 && snapshot.readings.count == 7 &&
                   snapshot.deliveries.count == 7 && snapshot.readings.allSatisfy {
                       $0.quality == "engineeringChecksPassed-v1" &&
                       $0.decoderVersion == Libre2ProductionDecoder.version
                   }, "ordinary development source persists checked readings with provenance")
        try expect(Libre2ProductionPolicy.engineeringV1.canIngestCanonical,
                   "development policy enables local ingestion")
    }

    static func waitIdle(_ queue: LibreOrderedIngestion) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while queue.snapshot.workerScheduled {
            guard ContinuousClock.now < deadline else { throw Failure(message: "queue failed to become idle") }
            await Task.yield()
        }
    }

    static func expectEmpty(_ store: ReadingStore, _ message: String) async throws {
        let snapshot = try await store.snapshot()
        try expect(snapshot.sessions.isEmpty && snapshot.readings.isEmpty && snapshot.deliveries.isEmpty &&
                   snapshot.conflicts.isEmpty && snapshot.publishedCommits.isEmpty, message)
    }

    #if LIBRE2_CANDIDATE_ADAPTER_FIXTURES && LIBRE2_ENGINEERING_DECODER_FIXTURES && LIBRE2_ORDERED_INGESTION_FIXTURES
    static func context(_ rig: Rig, now: @escaping @Sendable () -> Double = { 0 }) -> LibreOrderedFrameContext {
        .fixture(gate: rig.gate, frame: rig.frame, now: now)
    }

    static func mappingAndDuplicates() async throws {
        for date in [epoch, epoch.addingTimeInterval(0.0005),
                     Date(timeIntervalSince1970: 946_684_800.0005 + 900),
                     Date(timeIntervalSince1970: 4_102_444_800 - 0.0005)] {
            let rig = try await rig(date: date)
            let outcome = await rig.adapter.processFixture(rig.frame, context: context(rig))
            guard case .completed = outcome.disposition else { throw Failure(message: "valid mapping rejected") }
            try expect(outcome.acceptedCandidates == 7, "seven exact accepted slots")
            let snapshot = try await rig.store.snapshot()
            try expect(snapshot.readings.map(\.sensorMinute) == [985, 988, 993, 994, 996, 998, 1000],
                       "accepted candidates are chronological sparse minutes, with gaps retained")
            try expect(snapshot.readings.allSatisfy { reading in
                reading.glucoseMGDL == 112 && reading.kind == .trend && reading.receivedAt == date &&
                reading.decoderVersion == Libre2ProductionDecoder.version &&
                reading.quality == "engineeringChecksPassed-v1" &&
                reading.primaryOrigin == (reading.sensorMinute == 1000 ? .bleLive : .bleHistory) &&
                reading.sampleDate == date.addingTimeInterval(Double(reading.sensorMinute - 1000) * 60)
            }, "mapping keeps canonical values, identifiers, original receipt, origin and writer-derived dates")
            try expect(snapshot.sessions.count == 1 && snapshot.deliveries.count == 7 &&
                       snapshot.deliveries.allSatisfy { $0.state == .unassigned && $0.payload == nil } &&
                       snapshot.publishedCommits.count == 1, "one guarded atomic reading/delivery transaction")
            let again = await rig.adapter.processFixture(rig.frame, context: context(rig))
            guard case .completed = again.disposition else { throw Failure(message: "duplicate incorrectly failed") }
            let duplicate = try await rig.store.snapshot()
            try expect(duplicate.readings.count == 7 && duplicate.deliveries.count == 7 &&
                       duplicate.publishedCommits.count == 1, "duplicate no-change is success without new publication")
        }
    }

    static func orderedReversedMinutesAndConflicts() async throws {
        let firstReceived = epoch.addingTimeInterval(120)
        let secondReceived = firstReceived.addingTimeInterval(60)
        let rig = try await rig(glucose: 1000, date: firstReceived,
                                calibrationMinute: 980, frameMinute: 1000)
        guard let second = rig.gate.makeFrame(
            payload: payload(minute: 998, glucose: 1100), receivedAt: secondReceived
        ) else { throw Failure(message: "second current frame was not created") }
        let first = rig.frame
        let anchorFloor = first.sessionSnapshot.clockAnchor!.referenceSensorMinute
        try expect(first.sequence < second.sequence &&
                   payloadMinute(first.payload) == 1000 && payloadMinute(second.payload) == 998 &&
                   payloadMinute(first.payload) >= anchorFloor && payloadMinute(second.payload) >= anchorFloor,
                   "process sequence increases while both valid frame minutes reverse above the anchor floor")

        let firstPaused = Suspension()
        let trace = AdapterStoreTrace()
        let queue = LibreOrderedIngestion.fixture(gate: rig.gate) { frame, context in
            if frame.sequence == first.sequence { await firstPaused.pause() }
            let outcome = await rig.adapter.processFixture(frame, context: context)
            await trace.record(sequence: frame.sequence, snapshot: try? await rig.store.snapshot())
            return outcome
        }
        queue.start()
        try await waitIdle(queue)
        try expect(queue.offer(first), "first newer-minute frame enters the combined fixture")
        try await firstPaused.waitReached()
        try expect(queue.offer(second), "second older-minute frame queues behind the suspended head")
        await firstPaused.resume()
        try await waitIdle(queue)

        let sequences = await trace.sequences
        let batches = await trace.snapshots
        try expect(sequences == [first.sequence, second.sequence] && batches.count == 2 &&
                   queue.snapshot.completedFrames == 2 &&
                   queue.snapshot.knownAcceptedCandidatesNotCommitted == 0,
                   "ordered queue processes each frame once in increasing process sequence")

        let firstBatch = batches[0]
        let final = batches[1]
        let firstMinutes: [Int64] = [985, 988, 993, 994, 996, 998, 1000]
        let secondNewMinutes: [Int64] = [983, 986, 991, 992]
        let overlap: Set<Int64> = [994, 996, 998]
        let expectedFinalMinutes: [Int64] = [983, 985, 986, 988, 991, 992, 993, 994, 996, 998, 1000]
        let meaningfulGaps: Set<Int64> = [984, 987, 989, 990, 995, 997, 999]
        try expect(firstBatch.readings.map(\.sensorMinute) == firstMinutes &&
                   final.readings.map(\.sensorMinute) == expectedFinalMinutes &&
                   meaningfulGaps.isDisjoint(with: Set(final.readings.map(\.sensorMinute))),
                   "older sparse slots insert uniquely while every unreported minute remains a gap")

        let firstByMinute = Dictionary(uniqueKeysWithValues: firstBatch.readings.map { ($0.sensorMinute, $0) })
        let finalByMinute = Dictionary(uniqueKeysWithValues: final.readings.map { ($0.sensorMinute, $0) })
        try expect(overlap.allSatisfy { finalByMinute[$0] == firstByMinute[$0] } &&
                   overlap.allSatisfy { firstByMinute[$0]?.glucoseMGDL == 112 },
                   "conflicting overlap retains the first committed canonical values and provenance")
        try expect(secondNewMinutes.allSatisfy {
            finalByMinute[$0]?.glucoseMGDL == 125 &&
            finalByMinute[$0]?.receivedAt == secondReceived &&
            finalByMinute[$0]?.primaryOrigin == .bleHistory
        }, "the second frame contributes valid distinct numerical values only at its unique older slots")

        let readingIDs = Set(final.readings.map(\.id))
        try expect(Set(final.deliveries.map(\.readingID)) == readingIDs &&
                   final.deliveries.count == expectedFinalMinutes.count &&
                   final.deliveries.allSatisfy { $0.state == .unassigned },
                   "every unique reading key has exactly one required delivery")
        let conflictIDs = Set(final.conflicts.map(\.readingID))
        let overlapIDs = Set(overlap.compactMap { firstByMinute[$0]?.id })
        try expect(final.conflicts.count == overlap.count && conflictIDs == overlapIDs &&
                   final.conflicts.allSatisfy { $0.discrepancyFlags == ["canonicalValue"] },
                   "each conflicting numerical overlap records one redacted conflict")

        let minuteByID = Dictionary(uniqueKeysWithValues: final.readings.map { ($0.id, $0.sensorMinute) })
        try expect(final.publishedCommits.count == 2 &&
                   final.publishedCommits.map(\.submissionSequence) == [first.sequence, second.sequence] &&
                   final.publishedCommits[0].readingIDs.compactMap { minuteByID[$0] } == firstMinutes &&
                   final.publishedCommits[1].readingIDs.compactMap { minuteByID[$0] } == secondNewMinutes,
                   "each batch publishes its new reading IDs in chronological order")
        try expect(firstBatch.sessions.count == 1 && final.sessions.count == 1 &&
                   firstBatch.sessions[0].firstObservedAt == firstReceived &&
                   firstBatch.sessions[0].lastObservedAt == firstReceived &&
                   final.sessions[0].firstObservedAt == firstReceived &&
                   final.sessions[0].lastObservedAt == secondReceived,
                   "each processed frame advances only its own monotonic observation metadata")
    }

    static func malformedBindings() async throws {
        let rig = try await rig()
        let mutations: [LibreCandidateAdapterFixtureMutation] = [
            .missingSlot, .duplicateIndex, .wrongOffset, .wrongMinute, .wrongDate,
            .wrongGlucose, .wrongQuality, .wrongVersion, .wrongReceipt, .wrongPolicy, .wrongSequence,
            .wrongGeneration, .wrongWear, .wrongContextVersion, .wrongCanonicalSession
        ]
        for mutation in mutations {
            let result = await rig.adapter.processFixture(rig.frame, context: context(rig), mutation: mutation)
            guard case .invariantFailure = result.disposition else { throw Failure(message: "malformed mapping accepted") }
            try await expectEmpty(rig.store, "malformed mapping persisted nothing")
        }
        let other = rig.gate.makeFrame(payload: payload(minute: 1000), receivedAt: epoch)!
        let sameContextDifferentPayload = LibreVerifiedFrame(
            payload: payload(minute: 1000, glucose: 1100), receivedAt: rig.frame.receivedAt,
            sequence: rig.frame.sequence, generation: rig.frame.generation,
            sessionSnapshot: rig.frame.sessionSnapshot, persistenceSessionID: rig.frame.persistenceSessionID)
        var calibrationChanged = rig.frame.sessionSnapshot
        calibrationChanged.calibration = try calibration(index: 513)
        let sameContextDifferentCalibration = LibreVerifiedFrame(
            payload: rig.frame.payload, receivedAt: rig.frame.receivedAt,
            sequence: rig.frame.sequence, generation: rig.frame.generation,
            sessionSnapshot: calibrationChanged, persistenceSessionID: rig.frame.persistenceSessionID)
        for swapped in [other, sameContextDifferentPayload, sameContextDifferentCalibration] {
            let result = await rig.adapter.processFixture(rig.frame, context: context(rig),
                                                         mutation: .swappedEvaluation(swapped))
            guard case .invariantFailure = result.disposition else { throw Failure(message: "swapped evaluation accepted") }
        }
        try await expectEmpty(rig.store, "swapped provenance cannot cross the private bound work item")
    }

    static func rejectionAndResidence() async throws {
        let rejected = try await rig(glucose: 0)
        let noSlots = await rejected.adapter.processFixture(rejected.frame, context: context(rejected))
        guard case .allSlotsRejected = noSlots.disposition else { throw Failure(message: "zero slots submitted") }
        try expect(noSlots.acceptedCandidates == 0 && noSlots.slotRejections["zeroGlucose"] == 7,
                   "zero accepted has stable per-slot counts")
        try await expectEmpty(rejected.store, "all rejected cannot create session metadata")

        let expired = try await rig()
        let before = await expired.adapter.processFixture(expired.frame, context: context(expired, now: { 121 }))
        guard case .discarded(.residenceExpired) = before.disposition else { throw Failure(message: "expired frame accepted") }
        try expect(before.acceptedCandidates == nil, "undecoded expired frame has unknown candidate count")
        let clock = StepClock()
        let after = await expired.adapter.processFixture(expired.frame, context: context(expired, now: { clock.next() }))
        guard case .discarded(.residenceExpired) = after.disposition else { throw Failure(message: "post-decode expiry accepted") }
        try expect(after.acceptedCandidates == 7, "post-decode expiry has exact accepted count")
        try await expectEmpty(expired.store, "expired mapping cannot persist")
    }

    static func preparationRevocation() async throws {
        let suspension = Suspension()
        let rig = try await rig(suspendQuery: suspension)
        let task = Task { await rig.adapter.processFixture(rig.frame, context: context(rig)) }
        try await suspension.waitReached()
        rig.gate.invalidate()
        await suspension.resume()
        let result = await task.value
        guard case .discarded(.staleOwnership) = result.disposition else { throw Failure(message: "stale preparation accepted") }
        try await expectEmpty(rig.store, "read-only preparation invalidation cannot persist metadata")
    }

    static func failureAndRecovery() async throws {
        let rig = try await rig()
        rig.faults.failNext(at: .beforeSave)
        let failed = await rig.adapter.processFixture(rig.frame, context: context(rig))
        guard case .storageFailure = failed.disposition else { throw Failure(message: "save failure not classified") }
        try expect(failed.acceptedCandidates == 7, "pre-save failure reports exact uncommitted candidates")
        try await expectEmpty(rig.store, "save failure rolls back all effects")
        try await rig.adapter.recover()
        // A healthy recovery is a no-op so a separately failed refetch can retry.
        try await rig.adapter.recover()
        rig.faults.failNext(at: .afterSaveBeforePublication)
        let durable = await rig.adapter.processFixture(rig.frame, context: context(rig))
        guard case .durablePublicationFailure = durable.disposition else { throw Failure(message: "durable save misclassified") }
        let retained = try await rig.store.snapshot()
        try expect(retained.readings.count == 7 && retained.deliveries.count == 7 &&
                   retained.publishedCommits.isEmpty, "post-save interruption is durable without publication")
        try await rig.adapter.recover()
        try await rig.adapter.refetchCommitted()
        let reconciled = try await rig.store.snapshot()
        try expect(reconciled.readings.count == 7 && reconciled.publishedCommits.isEmpty,
                   "recovery refetches without replaying candidates or manufacturing a commit")
    }

    static func boundedRecoveryCheckpoint() async throws {
        let rig = try await rig()
        _ = await rig.adapter.processFixture(rig.frame, context: context(rig))
        let initial = try await rig.store.snapshot()
        let stored = initial.sessions[0]
        let session = ReadingSessionSnapshot(
            id: stored.id, stableIdentityFingerprint: stored.stableIdentityFingerprint,
            sensorRevision: stored.sensorRevision, firstObservedAt: stored.firstObservedAt,
            observedAt: stored.lastObservedAt, lifecycleState: stored.lifecycleState, clock: stored.clock)
        let keys = initial.readings.map {
            ReadingRecoverySampleKey(sessionID: $0.sessionID, sensorMinute: $0.sensorMinute, kind: $0.kind)
        }
        let unrelated = try await rig.store.ingest(ReadingSubmission(
            sequence: rig.frame.sequence + 10_000, session: session,
            candidates: [ReadingCandidate(sensorMinute: 1100, kind: .trend, receivedAt: epoch,
                                          glucoseMGDL: 112, quality: "fixture", origin: .bleLive,
                                          decoderVersion: "fixture")]))
        try await rig.store.removeDeliveryForRecoveryFixture(readingID: unrelated.readingIDs[0])
        let checkpoint = try await rig.store.verifyCommittedSamples(keys)
        try expect(checkpoint.verifiedSampleCount == 7,
                   "seven indexed keys verify without traversing unrelated history or its missing delivery")
        for invalid in [[], keys + [ReadingRecoverySampleKey(sessionID: stored.id, sensorMinute: 1100, kind: .trend)],
                        [keys[0], keys[0]]] {
            do {
                _ = try await rig.store.verifyCommittedSamples(invalid)
                throw Failure(message: "unbounded/duplicate/empty checkpoint accepted")
            } catch ReadingStoreError.invalidInput { }
        }

        let failed = try await self.rig()
        failed.faults.failNext(at: .afterSaveBeforePublication)
        _ = await failed.adapter.processFixture(failed.frame, context: context(failed))
        let saved = try await failed.store.snapshot()
        try await failed.adapter.recover()
        try await failed.store.removeDeliveryForRecoveryFixture(readingID: saved.readings[0].id)
        do {
            try await failed.adapter.refetchCommitted()
            throw Failure(message: "missing required delivery passed checkpoint")
        } catch ReadingStoreError.operationFailed { }
        try await failed.adapter.recover()
        let blocked = await failed.adapter.processFixture(failed.frame, context: context(failed))
        guard case .storageFailure = blocked.disposition else {
            throw Failure(message: "unverified durable checkpoint was overwritten by later processing")
        }
        try expect(blocked.acceptedCandidates == nil,
                   "retained redacted checkpoint blocks decode after failed verification")
        do {
            try await failed.adapter.refetchCommitted()
            throw Failure(message: "failed checkpoint was silently cleared")
        } catch ReadingStoreError.operationFailed { }
    }

    #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
    static func guardedRevocation() async throws {
        let rig = try await rig()
        let barrier = rig.faults.pauseNext(at: .beforeCommitAdmission)
        let task = Task.detached { await rig.adapter.processFixture(rig.frame, context: context(rig)) }
        try expect(barrier.waitUntilReached(), "guarded writer reached staged boundary")
        rig.gate.invalidate()
        barrier.resume()
        let result = await task.value
        guard case .discarded(.staleOwnership) = result.disposition else { throw Failure(message: "revocation did not reject") }
        try expect(result.acceptedCandidates == 7, "revoked staged transaction counts exact candidates")
        try await expectEmpty(rig.store, "revocation rolls back session, readings and deliveries")

        let failedRig = try await self.rig()
        let failBarrier = failedRig.faults.pauseNext(at: .afterCommitAdmission)
        failedRig.faults.failNext(at: .beforeSave)
        let failureTask = Task.detached {
            await failedRig.adapter.processFixture(failedRig.frame, context: context(failedRig))
        }
        try expect(failBarrier.waitUntilReached(), "failing writer owns epoch")
        let revoked = Task.detached { failedRig.gate.invalidate() }
        failBarrier.resume()
        let failure = await failureTask.value
        await revoked.value
        guard case .storageFailure = failure.disposition else { throw Failure(message: "concurrent revocation hid storage fault") }
        try await expectEmpty(failedRig.store, "failed save with revocation rolls back")
    }
    #endif
    #endif

    final class StepClock: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        func next() -> Double {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return calls <= 2 ? 0 : 121
        }
    }

    actor Suspension {
        private var reached = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            reached = true
            await withCheckedContinuation { continuation = $0 }
        }
        func resume() { continuation?.resume(); continuation = nil }
        func waitReached() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !reached {
                guard ContinuousClock.now < deadline else { throw Failure(message: "query did not suspend") }
                await Task.yield()
            }
        }
    }

    actor AdapterStoreTrace {
        private(set) var sequences: [UInt64] = []
        private(set) var snapshots: [ReadingStoreSnapshot] = []
        func record(sequence: UInt64, snapshot: ReadingStoreSnapshot?) {
            sequences.append(sequence)
            if let snapshot { snapshots.append(snapshot) }
        }
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

    static func payloadMinute(_ payload: Data) -> Int {
        Int(payload[40]) | Int(payload[41]) << 8
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
