import Foundation

/// Metadata transactions and injected Keychain boundary; no diagnostic decoder linked.
@main
struct PersistenceBridgeSmoke {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    static func main() async throws {
        try await metadataOnlyAndCanonicalClock()
        try await migrationGapAndFailures()
        try await staleRepairCompletion()
        try await staleCompletionAfterRepairSave()
        try await capturedOwnershipCannotChange()
        try await candidatePreparationIsReadOnlyAndPerFrame()
        try await candidatePreparationRevocationAndMissingIdentity()
        try await terminalLifecycleCannotReopen()
        try latestPairingRepairGuards()
        print("Libre persistence bridge synthetic metadata and repair checks passed (no hardware validation).")
    }

    static func metadataOnlyAndCanonicalClock() async throws {
        let original = try session()
        let keychain = Pairing(original)
        let store = try await memoryStore()
        let bridge = makeBridge(keychain, store)
        _ = try await bridge.prepare(session: original, receivedAt: epoch, isCurrent: { true })
        let initial = try await store.snapshot()
        try expect(initial.sessions.count == 1 && initial.sessions[0].id == original.persistenceSessionID,
                   "metadata preparation records the durable wear UUID")
        try expect(initial.readings.isEmpty && initial.deliveries.isEmpty && initial.publishedCommits.isEmpty,
                   "metadata preparation creates no glucose, delivery, or canonical commit")
        var shifted = original
        shifted.clockAnchor = try LibreSensorClockAnchor.capture(from: calibration(date: epoch.addingTimeInterval(15)))
        keychain.replace(shifted)
        try await rejects { _ = try await bridge.prepare(session: shifted, receivedAt: epoch, isCurrent: { true }) }
        let unchanged = try await store.snapshot()
        try expect(unchanged.sessions[0].clock == initial.sessions[0].clock && keychain.snapshot().clockAnchor == shifted.clockAnchor,
                   "a differing valid Keychain anchor fails without silently replacing either clock")

        var missing = original
        missing.clockAnchor = nil
        missing.nextUnlockCount = 25
        missing.peripheralID = UUID()
        keychain.replace(missing)
        try await rejects { _ = try await bridge.prepare(session: missing, receivedAt: epoch, isCurrent: { true }) }
        let repaired = try await bridge.repairMissingClockAnchor(session: missing, receivedAt: epoch, withCurrent: { try $0() })
        _ = repaired
        try expect(keychain.snapshot().clockAnchor == original.clockAnchor && keychain.snapshot().nextUnlockCount == 25 && keychain.snapshot().peripheralID == missing.peripheralID,
                   "explicit missing-clock repair restores canonical store anchor and preserves newest operational fields")
        let final = try await store.snapshot()
        try expect(final.readings.isEmpty && final.deliveries.isEmpty && final.publishedCommits.isEmpty,
                   "clock repair cannot generate canonical readings")
    }

    static func migrationGapAndFailures() async throws {
        let original = try session()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "persistenceSessionID")
        object.removeValue(forKey: "persistenceIdentityVersion")
        let legacy = try JSONDecoder().decode(LibreSensorSession.self, from: JSONSerialization.data(withJSONObject: object))
        let keychain = Pairing(legacy)
        let faults = ReadingStoreFaultInjector()
        let store = try await memoryStore(faults: faults)
        let bridge = makeBridge(keychain, store)
        keychain.failWrites = true
        try await rejects { _ = try await bridge.prepare(session: legacy, receivedAt: epoch, isCurrent: { true }) }
        let failedMigration = try await store.snapshot()
        try expect(keychain.snapshot().persistenceSessionID == nil && failedMigration.sessions.isEmpty,
                   "failed Keychain migration cannot create metadata or invent a durable identity")
        keychain.failWrites = false
        faults.failNext(at: .beforeSave, message: "SENSITIVE metadata path")
        try await rejects { _ = try await bridge.prepare(session: legacy, receivedAt: epoch, isCurrent: { true }) }
        let durable = keychain.snapshot()
        let failedMetadata = try await store.snapshot()
        try expect(durable.persistenceSessionID != nil && failedMetadata.sessions.isEmpty,
                   "interruption after identity save and before metadata save leaves a durable UUID and no partial SQLite row")
        let health = await store.currentHealth()
        guard case .unhealthy(let failure) = health else { throw Failure(message: "metadata write fault must mark store unhealthy") }
        try expect(!failure.redactedReason.contains("SENSITIVE"), "store failure redacts injected underlying details")
        _ = try await store.retryAfterFailure()
        let restarted = makeBridge(keychain, store)
        _ = try await restarted.prepare(session: durable, receivedAt: epoch, isCurrent: { true })
        let afterRestart = try await store.snapshot()
        try expect(afterRestart.sessions.count == 1 && afterRestart.sessions[0].id == durable.persistenceSessionID,
                   "restart across Keychain/SQLite crash gap keeps migrated UUID")
        try expect(afterRestart.readings.isEmpty && afterRestart.deliveries.isEmpty && afterRestart.publishedCommits.isEmpty,
                   "successful retry of metadata remains disconnected from glucose ingestion")
    }

    static func staleRepairCompletion() async throws {
        let original = try session()
        let keychain = Pairing(original)
        let store = try await memoryStore()
        _ = try await makeBridge(keychain, store).prepare(session: original, receivedAt: epoch, isCurrent: { true })
        var missing = original
        missing.clockAnchor = nil
        keychain.replace(missing)
        let gate = LibreFrameGenerationGate()
        gate.activate(session: missing, persistenceSessionID: missing.persistenceSessionID)
        let frame = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        let latch = Suspension()
        let bridge = makeBridge(keychain, store, beforeQuery: { await latch.pause() })
        let pending = Task {
            try await bridge.repairMissingClockAnchor(session: missing, receivedAt: epoch, withCurrent: { body in
                try gate.withCurrent(frame, body)
            })
        }
        try await eventually { await latch.waiting }
        gate.invalidate()
        let replacement = try session(firstUIDByte: 9)
        keychain.replace(replacement)
        await latch.release()
        try await rejects { _ = try await pending.value }
        try expect(keychain.snapshot() == replacement && keychain.repairWrites == 0,
                   "delayed canonical-clock query after stop/replacement cannot overwrite newer pairing")
    }

    static func latestPairingRepairGuards() throws {
        let original = try session()
        var captured = original
        captured.clockAnchor = nil
        var latest = captured
        latest.nextUnlockCount = 100
        latest.peripheralID = UUID()
        latest.calibration = try calibration(date: epoch.addingTimeInterval(15))
        let restored = try latest.restoringMissingClockAnchor(original.clockAnchor!, expectedSession: captured)
        try expect(restored.nextUnlockCount == 100 && restored.peripheralID == latest.peripheralID && restored.calibration == latest.calibration,
                   "clock repair's real pure compare-and-update preserves operational advances made after capture")
        var replacement = captured
        replacement.createdAt = epoch.addingTimeInterval(1)
        do {
            _ = try replacement.restoringMissingClockAnchor(original.clockAnchor!, expectedSession: captured)
            throw Failure(message: "newer pairing was overwritten")
        } catch is LibrePersistenceIdentityError { }
        do {
            _ = try original.restoringMissingClockAnchor(original.clockAnchor!, expectedSession: captured)
            throw Failure(message: "valid anchor repair was allowed")
        } catch is LibrePersistenceIdentityError { }
        let foreignAnchor = try session(firstUIDByte: 9).clockAnchor!
        do {
            _ = try latest.restoringMissingClockAnchor(foreignAnchor, expectedSession: captured)
            throw Failure(message: "foreign canonical clock was copied")
        } catch is LibreSensorClockAnchorError { }
    }

    static func capturedOwnershipCannotChange() async throws {
        let captured = try session()
        var changedIDObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as! [String: Any]
        changedIDObject["persistenceSessionID"] = UUID().uuidString
        let changedID = try JSONDecoder().decode(LibreSensorSession.self, from: JSONSerialization.data(withJSONObject: changedIDObject))
        var changedClock = captured
        changedClock.clockAnchor = try LibreSensorClockAnchor.capture(from: calibration(date: epoch.addingTimeInterval(20)))
        var changedCalibration = captured
        changedCalibration.calibration = try calibration(date: epoch.addingTimeInterval(20))
        for changed in [changedID, changedClock, changedCalibration] {
            let keychain = Pairing(changed)
            let store = try await memoryStore()
            let bridge = makeBridge(keychain, store)
            try await rejects { _ = try await bridge.prepare(session: captured, receivedAt: epoch, isCurrent: { true }) }
            let snapshot = try await store.snapshot()
            try expect(snapshot.sessions.isEmpty,
                       "a captured callback cannot create metadata from a newer UUID, clock or calibration snapshot")
        }
    }

    static func staleCompletionAfterRepairSave() async throws {
        let original = try session()
        let keychain = Pairing(original)
        let store = try await memoryStore()
        _ = try await makeBridge(keychain, store).prepare(session: original, receivedAt: epoch, isCurrent: { true })
        var missing = original
        missing.clockAnchor = nil
        keychain.replace(missing)
        let gate = LibreFrameGenerationGate()
        gate.activate(session: missing, persistenceSessionID: missing.persistenceSessionID)
        let frame = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        let latch = Suspension()
        let bridge = makeBridge(keychain, store, beforeResolve: { await latch.pause() })
        let pending = Task {
            try await bridge.repairMissingClockAnchor(session: missing, receivedAt: epoch, withCurrent: { body in
                try gate.withCurrent(frame, body)
            })
        }
        try await eventually { await latch.waiting }
        try expect(keychain.repairWrites == 1 && keychain.snapshot().clockAnchor == original.clockAnchor,
                   "repair is durably saved before metadata finalization suspension")
        gate.invalidate()
        await latch.release()
        try await rejects { _ = try await pending.value }
        try expect(keychain.snapshot().clockAnchor == original.clockAnchor,
                   "stop after lawful repair preserves saved clock while rejecting stale success")
    }

    static func candidatePreparationIsReadOnlyAndPerFrame() async throws {
        var captured = try session()
        captured.uid = (Data([0xFF]) + captured.uid)[1...]
        captured.patchInfo = (Data([0xFF]) + captured.patchInfo)[1...]
        let store = try await memoryStore()
        let bridge = readOnlyBridge(store)
        let gate = LibreFrameGenerationGate()
        gate.activate(session: captured, persistenceSessionID: captured.persistenceSessionID)
        let first = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        let initial = try await bridge.prepareCandidates(frame: first, isCurrent: { gate.isCurrent(first) })
        try expect(initial.session == captured && initial.session.uid.startIndex == captured.uid.startIndex,
                   "candidate preparation retains the exact captured session, including sliced identity data")
        try expect(initial.sessionSnapshot.firstObservedAt == epoch && initial.sessionSnapshot.observedAt == epoch,
                   "absent wear proposal uses this frame's receipt for both observation dates")
        let absent = try await store.snapshot()
        try expect(absent.sessions.isEmpty && absent.readings.isEmpty && absent.deliveries.isEmpty,
                   "preparation without accepted candidates performs no metadata save")

        _ = try await store.resolveSessionMetadata(initial.sessionSnapshot)
        let second = gate.makeFrame(payload: Data([2]), receivedAt: epoch.addingTimeInterval(60))!
        let later = try await bridge.prepareCandidates(frame: second, isCurrent: { gate.isCurrent(second) })
        try expect(later.sessionSnapshot.firstObservedAt == epoch &&
                   later.sessionSnapshot.observedAt == second.receivedAt &&
                   later.sessionSnapshot.clock == initial.sessionSnapshot.clock,
                   "each frame refreshes observation date while preserving canonical first observation and clock")
        let unchanged = try await store.snapshot()
        try expect(unchanged.sessions[0].lastObservedAt == epoch,
                   "existing wear observation advances only in the eventual writer transaction")
        _ = try await store.resolveSessionMetadata(later.sessionSnapshot)
        let older = gate.makeFrame(payload: Data([3]), receivedAt: epoch.addingTimeInterval(20))!
        let monotonic = try await bridge.prepareCandidates(frame: older, isCurrent: { gate.isCurrent(older) })
        try expect(monotonic.sessionSnapshot.observedAt == second.receivedAt,
                   "an older receipt never regresses the proposed observation date")
    }

    static func candidatePreparationRevocationAndMissingIdentity() async throws {
        let captured = try session()
        let store = try await memoryStore()
        let gate = LibreFrameGenerationGate()
        gate.activate(session: captured, persistenceSessionID: nil)
        let missingID = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        do {
            _ = try await readOnlyBridge(store).prepareCandidates(frame: missingID, isCurrent: { true })
            throw Failure(message: "frame without durable identity was relabeled")
        } catch LibreFrameOwnershipError.missingDurableIdentity { }

        gate.activate(session: captured, persistenceSessionID: captured.persistenceSessionID)
        let frame = gate.makeFrame(payload: Data([2]), receivedAt: epoch)!
        let latch = Suspension()
        let bridge = readOnlyBridge(store, beforeQuery: { await latch.pause() })
        let pending = Task {
            try await bridge.prepareCandidates(frame: frame, isCurrent: { gate.isCurrent(frame) })
        }
        try await eventually { await latch.waiting }
        let replacement = try session(firstUIDByte: 9)
        gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
        await latch.release()
        do {
            _ = try await pending.value
            throw Failure(message: "stale preparation after replacement succeeded")
        } catch LibrePersistenceBridgeError.staleSession { }
        let unchanged = try await store.snapshot()
        try expect(unchanged.health == .healthy && unchanged.sessions.isEmpty && unchanged.publishedCommits.isEmpty,
                   "revocation during absent-session lookup cannot insert metadata")

        gate.activate(session: captured, persistenceSessionID: captured.persistenceSessionID)
        let admittedFrame = gate.makeFrame(payload: Data([3]), receivedAt: epoch)!
        let prepared = try await readOnlyBridge(store).prepareCandidates(frame: admittedFrame, isCurrent: { true })
        let admission = try gate.makeCommitAdmission(for: admittedFrame, session: prepared.sessionSnapshot)
        gate.invalidate()
        do {
            _ = try await store.ingest(candidateSubmission(admittedFrame, prepared.sessionSnapshot), admission: admission)
            throw Failure(message: "revoked absent-session submission succeeded")
        } catch ReadingStoreError.ownershipRejected(.staleFrame) { }
        let rolledBack = try await store.snapshot()
        try expect(rolledBack.health == .healthy && rolledBack.sessions.isEmpty && rolledBack.readings.isEmpty &&
                   rolledBack.deliveries.isEmpty && rolledBack.publishedCommits.isEmpty,
                   "writer revocation rolls back absent metadata, reading and delivery together")
    }

    static func terminalLifecycleCannotReopen() async throws {
        for lifecycle in [ReadingSessionLifecycle.ended, .replaced] {
            let captured = try session()
            let store = try await memoryStore()
            let gate = LibreFrameGenerationGate()
            gate.activate(session: captured, persistenceSessionID: captured.persistenceSessionID)
            let frame = gate.makeFrame(payload: Data([1]), receivedAt: epoch.addingTimeInterval(60))!
            let bridge = readOnlyBridge(store)
            let prepared = try await bridge.prepareCandidates(frame: frame, isCurrent: { true })
            _ = try await store.resolveSessionMetadata(prepared.sessionSnapshot)
            let admission = try gate.makeCommitAdmission(for: frame, session: prepared.sessionSnapshot)
            let active = prepared.sessionSnapshot
            let terminal = ReadingSessionSnapshot(
                id: active.id, stableIdentityFingerprint: active.stableIdentityFingerprint,
                sensorRevision: active.sensorRevision, firstObservedAt: active.firstObservedAt,
                observedAt: active.observedAt.addingTimeInterval(60), lifecycleState: lifecycle, clock: active.clock
            )
            _ = try await store.resolveSessionMetadata(terminal)
            let baseline = try await store.snapshot()
            try await expectRepairRequired {
                _ = try await bridge.prepareCandidates(frame: frame, isCurrent: { true })
            }
            try await expectRepairRequired {
                _ = try await store.ingest(candidateSubmission(frame, active), admission: admission)
            }
            try await expectRepairRequired {
                _ = try await store.resolveSessionMetadata(active)
            }
            try await expectRepairRequired {
                _ = try await makeBridge(Pairing(captured), store).prepare(
                    session: captured, receivedAt: epoch.addingTimeInterval(180), isCurrent: { true }
                )
            }
            let unchanged = try await store.snapshot()
            try expect(unchanged == baseline && unchanged.health == .healthy,
                       "terminal lifecycle blocks preparation, stale prepared writer and metadata-only bypass without mutation")
        }
    }

    static func readOnlyBridge(_ store: ReadingStore,
                               beforeQuery: @escaping @Sendable () async -> Void = {}) -> LibrePersistenceBridge {
        LibrePersistenceBridge(dependencies: LibrePersistenceBridgeDependencies(
            loadForIngestion: { _ in throw Failure(message: "candidate path accessed Keychain") },
            restoreMissingClockAnchor: { _, _ in throw Failure(message: "candidate path repaired Keychain") },
            resolveSessionMetadata: { _ in throw Failure(message: "candidate path saved metadata") },
            querySessionMetadata: { id, fingerprint, revision in
                await beforeQuery()
                return try await store.sessionMetadata(id: id, stableIdentityFingerprint: fingerprint, sensorRevision: revision)
            }
        ))
    }

    static func candidateSubmission(_ frame: LibreVerifiedFrame, _ session: ReadingSessionSnapshot) -> ReadingSubmission {
        ReadingSubmission(sequence: frame.sequence, session: session, candidates: [ReadingCandidate(
            sensorMinute: 1000, kind: .trend, receivedAt: frame.receivedAt, glucoseMGDL: 110,
            quality: "valid", origin: .bleLive, decoderVersion: "metadata-race-fixture"
        )])
    }

    static func expectRepairRequired(_ action: () async throws -> Void) async throws {
        do { try await action() }
        catch ReadingStoreError.repairRequired { return }
        throw Failure(message: "expected repair-required rejection")
    }

    static func makeBridge(_ keychain: Pairing, _ store: ReadingStore,
                           beforeQuery: @escaping @Sendable () async -> Void = {},
                           beforeResolve: @escaping @Sendable () async -> Void = {}) -> LibrePersistenceBridge {
        LibrePersistenceBridge(dependencies: LibrePersistenceBridgeDependencies(
            loadForIngestion: { try keychain.load(matching: $0) },
            restoreMissingClockAnchor: { try keychain.repair($0, matching: $1) },
            resolveSessionMetadata: {
                await beforeResolve()
                return try await store.resolveSessionMetadata($0)
            },
            querySessionMetadata: { id, fingerprint, revision in
                await beforeQuery()
                return try await store.sessionMetadata(id: id, stableIdentityFingerprint: fingerprint, sensorRevision: revision)
            }
        ))
    }

    final class Pairing: @unchecked Sendable {
        private let lock = NSRecursiveLock()
        private var value: LibreSensorSession
        var failWrites = false
        private(set) var repairWrites = 0
        init(_ session: LibreSensorSession) { value = session }
        func snapshot() -> LibreSensorSession { lock.lock(); defer { lock.unlock() }; return value }
        func replace(_ session: LibreSensorSession) { lock.lock(); defer { lock.unlock() }; value = session }
        func load(matching expected: LibreSensorSession) throws -> LibreSensorSession {
            lock.lock(); defer { lock.unlock() }
            guard value.hasSameDurablePairing(as: expected) else { throw LibreSessionStoreError.replacedSession }
            return try value.requiringPersistenceIdentity { migrated in
                if failWrites { throw Failure(message: "SENSITIVE Keychain payload") }
                value = try JSONDecoder().decode(LibreSensorSession.self, from: JSONEncoder().encode(migrated))
            }
        }
        func repair(_ anchor: LibreSensorClockAnchor, matching expected: LibreSensorSession) throws -> LibreSensorSession {
            lock.lock(); defer { lock.unlock() }
            let repaired = try value.restoringMissingClockAnchor(anchor, expectedSession: expected)
            if failWrites { throw Failure(message: "SENSITIVE Keychain payload") }
            value = repaired
            repairWrites += 1
            return value
        }
    }

    actor Suspension {
        var waiting: Bool { continuation != nil }
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async { await withCheckedContinuation { continuation = $0 } }
        func release() { let pending = continuation; continuation = nil; pending?.resume() }
    }

    static func eventually(_ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await predicate()) {
            guard Date() < deadline else { throw Failure(message: "asynchronous bridge fixture timed out") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    static func memoryStore(faults: ReadingStoreFaultInjector? = nil) async throws -> ReadingStore {
        let store = ReadingStore(configuration: .init(storage: .inMemory(identifier: UUID().uuidString)), faultInjector: faults)
        try await store.load()
        return store
    }
    static func session(firstUIDByte: UInt8 = 1) throws -> LibreSensorSession {
        let uid = Data([firstUIDByte, 2, 3, 4, 5, 6, 7, 8])
        return LibreSensorSession(uid: uid, patchInfo: Data([0x9D, 0, 0, 0, 0, 0]), advertisedName: "fixture",
                                  unlockCode: 42, setupComplete: true, sensorKind: .libre2_9D,
                                  createdAt: epoch, calibration: try calibration(uid: uid))
    }
    static func calibration(date: Date = epoch, uid: Data = Data([1, 2, 3, 4, 5, 6, 7, 8])) throws -> LibreCalibration {
        let object: [String: Any] = ["ownerUID": uid.base64EncodedString(),
            "ownerPatchInfo": Data([0x9D, 0, 0, 0, 0, 0]).base64EncodedString(),
            "formatVersion": 1, "capturedAt": date.timeIntervalSinceReferenceDate, "sensorMinute": 1000,
            "lifecycle": 3, "calibrationSource": Data(repeating: 0, count: 10).base64EncodedString()]
        return try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static func rejects(_ action: () async throws -> Void) async throws {
        do { try await action() }
        catch { return }
        throw Failure(message: "expected operation rejection")
    }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    struct Failure: Error { let message: String }
}
