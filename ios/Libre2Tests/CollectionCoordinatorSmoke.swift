import Foundation

/// Pure synthetic transport envelopes; no diagnostic decoder or ReadingStore is linked.
@main
@MainActor
struct CollectionCoordinatorSmoke {
    nonisolated static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    static func main() async throws {
        try capturedEnvelopeAndGeneration()
        try currentFrameCriticalSection()
        try await rejectionBeforeDecode()
        try await failuresRemainDiagnosticOnly()
        try await delayedPreparationCannotRestoreReadiness()
        print("Libre collection coordinator synthetic generation checks passed (no hardware validation).")
    }

    static func currentFrameCriticalSection() throws {
        let gate = LibreFrameGenerationGate()
        let original = try session()
        let generation = gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        let frame = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let saveFinished = DispatchSemaphore(value: 0)
        let invalidationStarted = DispatchSemaphore(value: 0)
        let invalidationFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            try! gate.withCurrent(frame) {
                entered.signal()
                release.wait()
            }
            saveFinished.signal()
        }
        try expect(entered.wait(timeout: .now() + 2) == .success, "critical-section fixture entered")
        DispatchQueue.global().async {
            invalidationStarted.signal()
            gate.invalidate()
            invalidationFinished.signal()
        }
        _ = invalidationStarted.wait(timeout: .now() + 2)
        let invalidatedDuringSave = invalidationFinished.wait(timeout: .now() + 0.02) == .success
        release.signal()
        _ = saveFinished.wait(timeout: .now() + 2)
        if !invalidatedDuringSave { _ = invalidationFinished.wait(timeout: .now() + 2) }
        try expect(!invalidatedDuringSave && !gate.isGenerationCurrent(generation),
                   "generation invalidation waits for the current frame's short atomic save boundary")
        var staleBodyCalled = false
        do {
            try gate.withCurrent(frame) { staleBodyCalled = true }
            throw Failure(message: "stale critical-section callback accepted")
        } catch is LibreFrameOwnershipError { }
        try expect(!staleBodyCalled, "stale frame is rejected before any compare-and-save body runs")
    }

    static func rejectionBeforeDecode() async throws {
        let gate = LibreFrameGenerationGate()
        var prepared: [LibreVerifiedFrame] = []
        var decoded: [LibreVerifiedFrame] = []
        let coordinator = LibreCollectionCoordinator(gate: gate, openStore: {}, prepareSession: { prepared.append($0) })
        coordinator.start()
        try await eventually { !coordinator.isWorking }
        let original = try session()
        gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        let late = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        let current = gate.makeFrame(payload: Data([2]), receivedAt: epoch)!
        func receive(_ frame: LibreVerifiedFrame) {
            if coordinator.receive(frame) { decoded.append(frame) }
        }
        receive(current)
        receive(late)
        receive(current)
        try await eventually { !coordinator.isWorking }
        try expect(decoded.count == 1 && prepared.count == 1 && coordinator.status.lastSequence == current.sequence,
                   "duplicates and reverse callbacks are rejected before the synthetic decode seam")
        gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        receive(current)
        let reconnected = gate.makeFrame(payload: Data([3]), receivedAt: epoch)!
        receive(reconnected)
        try await eventually { !coordinator.isWorking }
        try expect(decoded.count == 2 && prepared.count == 2 && coordinator.status.staleFrameCount == 3,
                   "a delayed prior-generation frame never reaches decoding or metadata preparation")
        let replacement = try session(firstUIDByte: 9)
        gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
        receive(reconnected)
        let replacementFrame = gate.makeFrame(payload: Data([4]), receivedAt: epoch)!
        receive(replacementFrame)
        try await eventually { !coordinator.isWorking }
        try expect(decoded.last?.sessionSnapshot == replacement && decoded.first?.sessionSnapshot == original,
                   "accepted callbacks retain the exact wear snapshot that authenticated them")
        try expect(coordinator.status.readyGeneration == replacementFrame.generation && !coordinator.status.canonicalIngestionEnabled,
                   "metadata readiness cannot promote diagnostic calculations to ingestion")
    }

    static func failuresRemainDiagnosticOnly() async throws {
        let gate = LibreFrameGenerationGate()
        let original = try session()
        gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        var opens = 0
        var prepares = 0
        let coordinator = LibreCollectionCoordinator(gate: gate, openStore: {
            opens += 1
            throw SecretFailure()
        }, prepareSession: { _ in prepares += 1 })
        coordinator.start()
        try await eventually { !coordinator.isWorking }
        for _ in 0..<5 {
            try expect(coordinator.receive(gate.makeFrame(payload: Data([1]), receivedAt: epoch)!),
                       "unavailable storage must not stop current experimental diagnostics")
        }
        try expect(opens == 1 && prepares == 0 && coordinator.status.readyGeneration == nil,
                   "frames cannot repeatedly retry an unavailable store")
        try expect(!coordinator.status.summary.contains("SENSITIVE") && !coordinator.status.canonicalIngestionEnabled,
                   "underlying load details remain redacted and ingestion disabled")
        for _ in 0..<5 {
            coordinator.lifecycleOpportunity()
            try await eventually { !coordinator.isWorking }
        }
        try expect(opens == 4, "store retries are bounded to three lifecycle opportunities")

        var bridgeCalls = 0
        let bridgeFailure = LibreCollectionCoordinator(gate: gate, openStore: {}, prepareSession: { _ in
            bridgeCalls += 1
            throw SecretFailure()
        })
        bridgeFailure.start()
        try await eventually { !bridgeFailure.isWorking }
        try expect(bridgeFailure.receive(gate.makeFrame(payload: Data([2]), receivedAt: epoch)!), "bridge failure does not disable diagnostics")
        try await eventually { !bridgeFailure.isWorking }
        try expect(bridgeFailure.receive(gate.makeFrame(payload: Data([3]), receivedAt: epoch)!), "diagnostics continue after bridge failure")
        try expect(bridgeCalls == 1 && bridgeFailure.status.readyGeneration == nil && !bridgeFailure.status.summary.contains("SENSITIVE"),
                   "failed metadata preparation stays unavailable and redacted without automatic per-frame retry")
    }

    static func delayedPreparationCannotRestoreReadiness() async throws {
        let gate = LibreFrameGenerationGate()
        let original = try session()
        gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        let first = gate.makeFrame(payload: Data([1]), receivedAt: epoch)!
        let latch = Suspension()
        var prepared: [LibreVerifiedFrame] = []
        let coordinator = LibreCollectionCoordinator(gate: gate, openStore: {}, prepareSession: { frame in
            prepared.append(frame)
            if prepared.count == 1 { await latch.pause() }
        })
        coordinator.start()
        try await eventually { !coordinator.isWorking }
        _ = coordinator.receive(first)
        try await eventually { latch.waiting }
        gate.invalidate()
        coordinator.transportInvalidated()
        latch.release()
        try await eventually { !coordinator.isWorking }
        try expect(coordinator.status.readyGeneration == nil, "completion after stop cannot restore metadata readiness")

        let oldLatch = Suspension()
        var calls: [UInt64] = []
        let replacing = LibreCollectionCoordinator(gate: gate, openStore: {}, prepareSession: { frame in
            calls.append(frame.sequence)
            if calls.count == 1 { await oldLatch.pause() }
        })
        replacing.start()
        try await eventually { !replacing.isWorking }
        gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        let delayed = gate.makeFrame(payload: Data([2]), receivedAt: epoch)!
        _ = replacing.receive(delayed)
        try await eventually { oldLatch.waiting }
        let replacement = try session(firstUIDByte: 9)
        gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
        replacing.transportInvalidated()
        var latest: LibreVerifiedFrame!
        for _ in 0..<10 {
            latest = gate.makeFrame(payload: Data([3]), receivedAt: epoch)!
            _ = replacing.receive(latest)
        }
        oldLatch.release()
        try await eventually { !replacing.isWorking }
        try expect(calls == [delayed.sequence, latest.sequence] && replacing.status.readyGeneration == latest.generation,
                   "only latest pending metadata is prepared after replacement; old completion cannot reactivate old generation")
    }

    static func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            guard Date() < deadline else { throw Failure(message: "asynchronous fixture timed out") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    final class Suspension {
        var waiting: Bool { continuation != nil }
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async { await withCheckedContinuation { continuation = $0 } }
        func release() { let pending = continuation; continuation = nil; pending?.resume() }
    }

    struct SecretFailure: LocalizedError {
        var errorDescription: String? { "SENSITIVE pairing material, credentials, and filesystem path" }
    }

    static func capturedEnvelopeAndGeneration() throws {
        let gate = LibreFrameGenerationGate()
        try expect(gate.makeFrame(payload: Data([1]), receivedAt: epoch) == nil,
                   "inactive transport cannot manufacture a frame")
        var original = try session()
        var payload = Data([1, 2, 3, 4])
        let generation = gate.activate(session: original, persistenceSessionID: original.persistenceSessionID)
        let first = gate.makeFrame(payload: payload, receivedAt: epoch)!
        original.nextUnlockCount = 100
        original.uid[0] = 99
        payload[0] = 99
        try expect(first.payload == Data([1, 2, 3, 4]) && first.sessionSnapshot.nextUnlockCount == 1 && first.sessionSnapshot.uid[0] == 1,
                   "captured payload and authenticated pairing are immutable value snapshots")
        try expect(first.generation == generation && first.receivedAt == epoch && gate.isCurrent(first),
                   "frame captures receipt time and active generation")

        let samePairing = first.sessionSnapshot
        let reconnectGeneration = gate.activate(session: samePairing, persistenceSessionID: samePairing.persistenceSessionID)
        let reconnect = gate.makeFrame(payload: Data([5]), receivedAt: epoch)!
        try expect(reconnectGeneration != generation && !gate.isCurrent(first) && gate.isCurrent(reconnect),
                   "old connection is rejected even when the sensor and pairing are unchanged")
        try expect(reconnect.sequence > first.sequence, "frame sequence survives a connection generation change")

        var recaptured = samePairing
        recaptured.calibration = try calibration(minute: 1010, date: epoch.addingTimeInterval(605))
        _ = gate.activate(session: recaptured, persistenceSessionID: recaptured.persistenceSessionID)
        let calibrationFrame = gate.makeFrame(payload: Data([6]), receivedAt: epoch)!
        try expect(!gate.isCurrent(reconnect) && calibrationFrame.sessionSnapshot.calibration == recaptured.calibration,
                   "calibration change retires the captured earlier calibration")
        try expect(reconnect.sessionSnapshot.calibration == samePairing.calibration && reconnect.sessionSnapshot.clockAnchor == samePairing.clockAnchor,
                   "a delayed callback retains its own calibration and clock")

        let replacement = try session(firstUIDByte: 9)
        _ = gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
        let replacementFrame = gate.makeFrame(payload: Data([7]), receivedAt: epoch)!
        try expect(!gate.isCurrent(calibrationFrame) && replacementFrame.persistenceSessionID != calibrationFrame.persistenceSessionID,
                   "a replacement wear never relabels a preceding frame")
        gate.invalidate()
        try expect(!gate.isCurrent(replacementFrame) && gate.makeFrame(payload: Data([8]), receivedAt: epoch) == nil,
                   "stop invalidates in-flight callbacks")
        _ = gate.activate(session: replacement, persistenceSessionID: nil)
        let diagnosticOnly = gate.makeFrame(payload: Data([9]), receivedAt: epoch)!
        try expect(diagnosticOnly.persistenceSessionID == nil && gate.isCurrent(diagnosticOnly),
                   "failed durable identity leaves transport diagnostics available without an ingestion identity")
        try expect(diagnosticOnly.sequence > replacementFrame.sequence, "stop cannot reset process-local sequence")
    }

    static func session(firstUIDByte: UInt8 = 1) throws -> LibreSensorSession {
        let uid = Data([firstUIDByte, 2, 3, 4, 5, 6, 7, 8])
        return LibreSensorSession(uid: uid, patchInfo: Data([0x9D, 0, 0, 0, 0, 0]), advertisedName: "fixture",
                                  unlockCode: 42, setupComplete: true, sensorKind: .libre2_9D,
                                  createdAt: epoch, calibration: try calibration(uid: uid))
    }

    static func calibration(minute: Int = 1000, date: Date = epoch,
                            uid: Data = Data([1, 2, 3, 4, 5, 6, 7, 8])) throws -> LibreCalibration {
        let object: [String: Any] = ["ownerUID": uid.base64EncodedString(),
            "ownerPatchInfo": Data([0x9D, 0, 0, 0, 0, 0]).base64EncodedString(),
            "formatVersion": 1, "capturedAt": date.timeIntervalSinceReferenceDate, "sensorMinute": minute,
            "lifecycle": 3, "calibrationSource": Data(repeating: 0, count: 10).base64EncodedString()]
        return try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    struct Failure: Error { let message: String }
}
