import CoreData
import Foundation

/// Synthetic writer-ownership fixtures. No decoder, app wiring, or hardware path is linked.
@main
struct CommitOwnershipSmoke {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static let receipt = epoch.addingTimeInterval(3_600)
    static let originalID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let replacementID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    enum Revocation: CaseIterable {
        case reconnect
        case disabled
        case replacement
    }

    static func main() async throws {
        try admissionIssuanceRejectsInvalidOwnership()
        try await admissionCannotAuthorizeAnotherSubmission()
        try await everyRevocationRollsBackAllStagedEffects()
        try await staleExactDuplicateStillNeedsAdmission()
        try await saveWinsConcurrentInvalidation()
        try await failureBeforeSaveRollsBackAndRequiresRetry()
        try await failureAfterSaveRemainsDurable()
        print("Libre reading commit ownership: all guarded transaction checks passed")
    }

    static func admissionIssuanceRejectsInvalidOwnership() throws {
        var slicedSession = try sensor(id: originalID)
        let slicedCanonical = try canonicalSession(for: slicedSession)
        let uidBacking = Data([0xFF]) + slicedSession.uid
        let patchBacking = Data([0xFF]) + slicedSession.patchInfo
        slicedSession.uid = uidBacking[1...]
        slicedSession.patchInfo = patchBacking[1...]
        let slicedGate = LibreFrameGenerationGate()
        slicedGate.activate(session: slicedSession, persistenceSessionID: originalID)
        let slicedFrame = slicedGate.makeFrame(payload: Data([0]), receivedAt: receipt)!
        _ = try slicedGate.makeCommitAdmission(
            for: slicedFrame,
            session: slicedCanonical
        )

        let missingIDSession = try sensor(id: originalID)
        let missingIDGate = LibreFrameGenerationGate()
        missingIDGate.activate(session: missingIDSession, persistenceSessionID: nil)
        let missingIDFrame = missingIDGate.makeFrame(payload: Data([1]), receivedAt: receipt)!
        try expectFrameRejection(.missingDurableIdentity) {
            _ = try missingIDGate.makeCommitAdmission(
                for: missingIDFrame,
                session: canonicalSession(for: missingIDSession)
            )
        }

        let staleGate = LibreFrameGenerationGate()
        let current = try sensor(id: originalID)
        staleGate.activate(session: current, persistenceSessionID: originalID)
        let staleFrame = staleGate.makeFrame(payload: Data([2]), receivedAt: receipt)!
        staleGate.invalidate()
        try expectFrameRejection(.staleFrame) {
            _ = try staleGate.makeCommitAdmission(
                for: staleFrame,
                session: canonicalSession(for: current)
            )
        }

        let mismatchGate = LibreFrameGenerationGate()
        mismatchGate.activate(session: current, persistenceSessionID: originalID)
        let mismatchFrame = mismatchGate.makeFrame(payload: Data([3]), receivedAt: receipt)!
        let wrongIdentity = ReadingSessionSnapshot(
            id: originalID,
            stableIdentityFingerprint: Data(repeating: 0x99, count: 32),
            sensorRevision: current.sensorKind.rawValue,
            firstObservedAt: epoch,
            observedAt: receipt,
            lifecycleState: .active,
            clock: try canonicalSession(for: current).clock
        )
        try expectFrameRejection(.sessionMismatch) {
            _ = try mismatchGate.makeCommitAdmission(for: mismatchFrame, session: wrongIdentity)
        }
    }

    static func admissionCannotAuthorizeAnotherSubmission() async throws {
        let fixture = try frameFixture()
        let store = try await memoryStore()
        let valid = submission(
            sequence: fixture.frame.sequence,
            session: fixture.session,
            candidates: [candidate(1_000)]
        )

        let wrongSequence = ReadingSubmission(
            sequence: valid.sequence + 1,
            session: valid.session,
            candidates: valid.candidates
        )
        try await expectOwnershipRejection(.submissionMismatch) {
            _ = try await store.ingest(wrongSequence, admission: fixture.admission)
        }

        let otherSensor = try sensor(firstUIDByte: 9, id: replacementID)
        let otherSession = try canonicalSession(for: otherSensor)
        let wrongSession = submission(
            sequence: valid.sequence,
            session: otherSession,
            candidates: [candidate(1_000)]
        )
        try await expectOwnershipRejection(.submissionMismatch) {
            _ = try await store.ingest(wrongSession, admission: fixture.admission)
        }

        let wrongReceipt = submission(
            sequence: valid.sequence,
            session: valid.session,
            candidates: [candidate(1_000, receivedAt: receipt.addingTimeInterval(1))]
        )
        try await expectOwnershipRejection(.submissionMismatch) {
            _ = try await store.ingest(wrongReceipt, admission: fixture.admission)
        }

        let snapshot = try await store.snapshot()
        try expect(snapshot.health == .healthy && snapshot.sessions.isEmpty &&
                   snapshot.readings.isEmpty && snapshot.deliveries.isEmpty &&
                   snapshot.conflicts.isEmpty && snapshot.publishedCommits.isEmpty,
                   "a sequence, wear, or receipt mismatch cannot enter the writer transaction")
    }

    static func everyRevocationRollsBackAllStagedEffects() async throws {
        for revocation in Revocation.allCases {
            let faults = ReadingStoreFaultInjector()
            let fixture = try frameFixture()
            let store = try await memoryStore(faults: faults)
            let events = collectCommits(from: store)

            let baselineSession = ReadingSessionSnapshot(
                id: fixture.session.id,
                stableIdentityFingerprint: fixture.session.stableIdentityFingerprint,
                sensorRevision: fixture.session.sensorRevision,
                firstObservedAt: fixture.session.firstObservedAt,
                observedAt: epoch,
                lifecycleState: fixture.session.lifecycleState,
                clock: fixture.session.clock
            )
            _ = try await store.ingest(submission(
                sequence: fixture.frame.sequence,
                session: baselineSession,
                candidates: [candidate(1_000)]
            ))

            let staged = submission(
                sequence: fixture.frame.sequence,
                session: fixture.session,
                candidates: [
                    candidate(1_000, origin: .nfcTrend),
                    candidate(1_000, origin: .bleHistory, value: 190),
                    candidate(1_001, origin: .bleHistory)
                ]
            )
            let barrier = faults.pauseNext(at: .beforeCommitAdmission)
            let ingest = Task {
                try await store.ingest(staged, admission: fixture.admission)
            }
            try expect(barrier.waitUntilReached(), "staged transaction reached its bounded pre-admission barrier")

            switch revocation {
            case .reconnect:
                fixture.gate.activate(session: fixture.sensor, persistenceSessionID: originalID)
            case .disabled:
                fixture.gate.invalidate()
            case .replacement:
                let replacement = try sensor(firstUIDByte: 9, id: replacementID)
                fixture.gate.activate(session: replacement, persistenceSessionID: replacementID)
            }
            barrier.resume()
            try await expectOwnershipRejection(.staleFrame) { _ = try await ingest.value }

            let snapshot = try await store.snapshot()
            try expect(snapshot.health == .healthy, "ownership rejection leaves persistence healthy")
            try expect(snapshot.sessions.count == 1 &&
                       snapshot.sessions[0].lastObservedAt == baselineSession.observedAt &&
                       snapshot.sessions[0].lifecycleState == baselineSession.lifecycleState,
                       "revocation rolls back staged session metadata")
            try expect(snapshot.readings.count == 1 && snapshot.deliveries.count == 1,
                       "revocation rolls back every staged reading and delivery")
            try expect(snapshot.conflicts.isEmpty,
                       "revocation rolls back a staged duplicate conflict")
            try expect(snapshot.readings[0].glucoseMGDL == 110 &&
                       snapshot.readings[0].primaryOrigin == .bleLive &&
                       snapshot.readings[0].observedOriginFlags == ReadingOrigin.bleLive.observationFlag,
                       "revocation rolls back conflict and exact-duplicate origin merges")
            try expect(snapshot.publishedCommits.count == 1,
                       "revocation publishes no commit beyond the baseline")
            try await store.close()
            let published = await events.value
            try expect(published.count == 1,
                       "rejected ownership emits no commit-stream event")
        }
    }

    static func staleExactDuplicateStillNeedsAdmission() async throws {
        let fixture = try frameFixture()
        let store = try await memoryStore()
        let exact = submission(
            sequence: fixture.frame.sequence,
            session: fixture.session,
            candidates: [candidate(1_000)]
        )
        _ = try await store.ingest(exact)
        fixture.gate.invalidate()
        try await expectOwnershipRejection(.staleFrame) {
            _ = try await store.ingest(exact, admission: fixture.admission)
        }
        let snapshot = try await store.snapshot()
        try expect(snapshot.health == .healthy && snapshot.readings.count == 1 &&
                   snapshot.deliveries.count == 1 && snapshot.conflicts.isEmpty &&
                   snapshot.publishedCommits.count == 1,
                   "a stale exact duplicate cannot bypass ownership through a no-change transaction")
    }

    static func saveWinsConcurrentInvalidation() async throws {
        let faults = ReadingStoreFaultInjector()
        let fixture = try frameFixture()
        let store = try await memoryStore(faults: faults)
        let events = collectCommits(from: store)
        let owned = submission(
            sequence: fixture.frame.sequence,
            session: fixture.session,
            candidates: [candidate(1_000), candidate(1_001, origin: .bleHistory)]
        )
        let barrier = faults.pauseNext(at: .afterCommitAdmission)
        let ingest = Task { try await store.ingest(owned, admission: fixture.admission) }
        try expect(barrier.waitUntilReached(), "writer acquired ownership before the save race")

        let invalidationContended = DispatchSemaphore(value: 0)
        let invalidationFinished = DispatchSemaphore(value: 0)
        try expect(fixture.gate.observeNextInvalidationContention(invalidationContended),
                   "active ownership installs the one-shot contention observer")
        DispatchQueue.global().async {
            fixture.gate.invalidate()
            invalidationFinished.signal()
        }
        try expect(wait(invalidationContended, timeout: 2) == .success,
                   "invalidation actually contends on the admitted synchronous save boundary")
        barrier.resume()
        let commit = try await ingest.value
        try expect(wait(invalidationFinished, timeout: 2) == .success,
                   "invalidation completes after the admitted save")

        let snapshot = try await store.snapshot()
        try expect(commit.readingIDs.count == 2 && snapshot.health == .healthy &&
                   snapshot.readings.count == 2 && snapshot.deliveries.count == 2 &&
                   snapshot.publishedCommits == [commit],
                   "the save that wins ownership commits and publishes one complete transaction")
        try expect(!fixture.gate.isCurrent(fixture.frame),
                   "later invalidation revokes future work without deleting committed history")
        try await store.close()
        try expect(await events.value == [commit],
                   "the admitted transaction emits exactly one commit-stream event")
    }

    static func failureBeforeSaveRollsBackAndRequiresRetry() async throws {
        let faults = ReadingStoreFaultInjector()
        let fixture = try frameFixture()
        let store = try await memoryStore(faults: faults)
        faults.failNext(at: .beforeSave, message: "SECRET ownership fixture")
        let first = submission(
            sequence: fixture.frame.sequence,
            session: fixture.session,
            candidates: [candidate(1_000), candidate(1_001)]
        )
        let failure = try await expectOperationFailure {
            _ = try await store.ingest(first, admission: fixture.admission)
        }
        try expect(failure.operation == .ingest && failure.droppedCandidateCount == 2 &&
                   !failure.durableCommitAwaitingPublication &&
                   !failure.redactedReason.contains("SECRET"),
                   "pre-save fault reports redacted dropped candidates")
        let failed = try await store.snapshot()
        try expect(failed.sessions.isEmpty && failed.readings.isEmpty &&
                   failed.deliveries.isEmpty && failed.conflicts.isEmpty &&
                   failed.publishedCommits.isEmpty,
                   "authorized pre-save failure rolls back every side effect")
        try await expectUnavailable { _ = try await store.ingest(first, admission: fixture.admission) }

        _ = try await store.retryAfterFailure()
        let retryFrame = fixture.gate.makeFrame(payload: Data([4]), receivedAt: receipt)!
        let retryAdmission = try fixture.gate.makeCommitAdmission(for: retryFrame, session: fixture.session)
        let retry = submission(
            sequence: retryFrame.sequence,
            session: fixture.session,
            candidates: [candidate(1_000), candidate(1_001)]
        )
        let commit = try await store.ingest(retry, admission: retryAdmission)
        let recovered = try await store.snapshot()
        try expect(commit.readingIDs.count == 2 && recovered.health == .healthy &&
                   recovered.readings.count == 2 && recovered.deliveries.count == 2,
                   "explicit retry restores the writer and commits complete pairs")
    }

    static func failureAfterSaveRemainsDurable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "libre-ownership-fixture-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ReadingStoreConfiguration(
            storage: .sqlite(url: directory.appendingPathComponent("readings.sqlite"))
        )
        let faults = ReadingStoreFaultInjector()
        let fixture = try frameFixture()
        let store = ReadingStore(configuration: configuration, faultInjector: faults)
        let events = collectCommits(from: store)
        try await store.load()
        faults.failNext(at: .afterSaveBeforePublication)
        let owned = submission(
            sequence: fixture.frame.sequence,
            session: fixture.session,
            candidates: [candidate(990, origin: .bleHistory), candidate(1_000)]
        )
        let failure = try await expectOperationFailure {
            _ = try await store.ingest(owned, admission: fixture.admission)
        }
        try expect(failure.operation == .publication && failure.droppedCandidateCount == 0 &&
                   failure.durableCommitAwaitingPublication,
                   "post-save failure reports durable rows awaiting refetch")
        fixture.gate.invalidate()
        let durable = try await store.snapshot()
        try expect(durable.readings.count == 2 && durable.deliveries.count == 2 &&
                   durable.sessions.count == 1 && durable.publishedCommits.isEmpty,
                   "post-save failure retains a complete transaction and publishes nothing")
        try await store.close()
        try expect(await events.value.isEmpty,
                   "post-save publication failure emits no commit-stream event")

        let reopened = ReadingStore(configuration: configuration)
        try await reopened.load()
        let restored = try await reopened.snapshot()
        try expect(restored.health == .healthy && restored.sessions.count == 1 &&
                   Set(restored.readings.map(\.id)) == Set(durable.readings.map(\.id)) &&
                   Set(restored.deliveries.map(\.readingID)) == Set(durable.deliveries.map(\.readingID)) &&
                   restored.publishedCommits.isEmpty,
                   "SQLite reopen preserves the guarded save without fabricating publication history")
        try await reopened.close()
    }

    struct FrameFixture {
        let gate: LibreFrameGenerationGate
        let sensor: LibreSensorSession
        let frame: LibreVerifiedFrame
        let session: ReadingSessionSnapshot
        let admission: ReadingCommitAdmission
    }

    static func frameFixture() throws -> FrameFixture {
        let gate = LibreFrameGenerationGate()
        let sensor = try sensor(id: originalID)
        gate.activate(session: sensor, persistenceSessionID: originalID)
        let frame = gate.makeFrame(payload: Data([1, 2, 3]), receivedAt: receipt)!
        let session = try canonicalSession(for: sensor)
        let admission = try gate.makeCommitAdmission(for: frame, session: session)
        return FrameFixture(gate: gate, sensor: sensor, frame: frame,
                            session: session, admission: admission)
    }

    static func sensor(firstUIDByte: UInt8 = 1, id: UUID) throws -> LibreSensorSession {
        let uid = Data([firstUIDByte, 2, 3, 4, 5, 6, 7, 8])
        let patch = Data([0x9D, 0, 0, 0, 0, 0])
        return LibreSensorSession(
            uid: uid,
            patchInfo: patch,
            advertisedName: "fixture",
            unlockCode: 42,
            setupComplete: true,
            sensorKind: .libre2_9D,
            createdAt: epoch,
            calibration: try calibration(uid: uid, patch: patch),
            persistenceSessionID: id
        )
    }

    static func calibration(uid: Data, patch: Data) throws -> LibreCalibration {
        let object: [String: Any] = [
            "ownerUID": uid.base64EncodedString(),
            "ownerPatchInfo": patch.base64EncodedString(),
            "formatVersion": 1,
            "capturedAt": epoch.timeIntervalSinceReferenceDate,
            "sensorMinute": 1_000,
            "lifecycle": 3,
            "calibrationSource": Data(repeating: 0, count: 10).base64EncodedString()
        ]
        return try JSONDecoder().decode(
            LibreCalibration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    static func canonicalSession(for sensor: LibreSensorSession) throws -> ReadingSessionSnapshot {
        let anchor = sensor.clockAnchor!
        return ReadingSessionSnapshot(
            id: try sensor.validatedPersistenceSessionID(),
            stableIdentityFingerprint: try sensor.stableIdentityFingerprint(),
            sensorRevision: sensor.sensorKind.rawValue,
            firstObservedAt: sensor.createdAt,
            observedAt: receipt,
            lifecycleState: .active,
            clock: ReadingClockSnapshot(
                referenceSensorMinute: Int64(anchor.referenceSensorMinute),
                referenceDate: anchor.referenceDate,
                provenance: LibreSensorClockAnchor.canonicalPersistenceProvenance
            )
        )
    }

    static func candidate(
        _ minute: Int64,
        receivedAt: Date = receipt,
        origin: ReadingOrigin = .bleLive,
        value: Int = 110
    ) -> ReadingCandidate {
        ReadingCandidate(
            sensorMinute: minute,
            kind: .trend,
            receivedAt: receivedAt,
            glucoseMGDL: value,
            quality: "synthetic-owned",
            origin: origin,
            decoderVersion: "synthetic-owned-v1"
        )
    }

    static func submission(
        sequence: UInt64,
        session: ReadingSessionSnapshot,
        candidates: [ReadingCandidate]
    ) -> ReadingSubmission {
        ReadingSubmission(sequence: sequence, session: session, candidates: candidates)
    }

    static func memoryStore(faults: ReadingStoreFaultInjector? = nil) async throws -> ReadingStore {
        let store = ReadingStore(
            configuration: .init(storage: .inMemory(identifier: UUID().uuidString)),
            faultInjector: faults
        )
        try await store.load()
        return store
    }

    static func collectCommits(from store: ReadingStore) -> Task<[ReadingCommit], Never> {
        Task {
            var commits: [ReadingCommit] = []
            for await commit in store.commits { commits.append(commit) }
            return commits
        }
    }

    static func wait(
        _ semaphore: DispatchSemaphore,
        timeout: TimeInterval
    ) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + timeout)
    }

    static func expectFrameRejection(
        _ expected: LibreFrameOwnershipError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
        } catch let error as LibreFrameOwnershipError {
            try expect(error == expected, "frame issuance returned the expected rejection")
            return
        }
        throw Failure(message: "expected frame ownership rejection: \(expected)")
    }

    static func expectOwnershipRejection(
        _ expected: ReadingCommitRejection,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch ReadingStoreError.ownershipRejected(let actual) {
            try expect(actual == expected, "writer returned the expected ownership rejection")
            return
        }
        throw Failure(message: "expected writer ownership rejection: \(expected)")
    }

    static func expectOperationFailure(
        operation: () async throws -> Void
    ) async throws -> ReadingStoreFailure {
        do {
            try await operation()
        } catch ReadingStoreError.operationFailed(let failure) {
            return failure
        }
        throw Failure(message: "expected persistence operation failure")
    }

    static func expectUnavailable(operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch ReadingStoreError.unavailable {
            return
        }
        throw Failure(message: "expected unhealthy writer to reject work")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
