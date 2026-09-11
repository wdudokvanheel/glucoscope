import Foundation

/// Deterministic disconnected mailbox tests; no BLE, UI, timing sleeps or decoder promotion.
@main
struct OrderedIngestionSmoke {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static func main() async throws {
        try await boundedFIFOAndHighWater()
        try await residenceBoundaries()
        try await invalidationKeepsActiveReservation()
        try await storageFailureAndRecoveryBudget()
        try await publicationRequiresRefetch()
        try await repairAndInvariantPauses()
        try await repairDuringWorkerCompletion()
        print("Libre ordered ingestion mailbox checks passed (synthetic, disconnected; no hardware qualification).")
    }

    static func boundedFIFOAndHighWater() async throws {
        let gate = try activeGate()
        let barrier = Barrier()
        let trace = Trace()
        let references = LibreOrderedIngestion.ReferenceProbe()
        let queue = LibreOrderedIngestion.fixture(gate: gate, references: references) { frame, context in
            await trace.record(Int(frame.sequence))
            if await trace.count == 1 { await barrier.pause() }
            if let reason = context.check() { return .init(disposition: .discarded(reason)) }
            return .init(disposition: .completed, acceptedCandidates: 2)
        }
        queue.start(); await queue.waitUntilIdle()
        let first = frame(gate)
        try expect(queue.offer(first), "first offered synchronously")
        await barrier.waitUntilReached()
        var accepted = [Int(first.sequence)]
        for _ in 0..<7 {
            _ = frame(gate) // Unobserved process sequence holes never block the FIFO.
            let next = frame(gate)
            accepted.append(Int(next.sequence))
            try expect(queue.offer(next), "seven pending admitted")
        }
        var latest = first
        for _ in 0..<100 { latest = frame(gate); try expect(!queue.offer(latest), "newest overflow rejected synchronously") }
        try expect(!queue.offer(latest) && !queue.offer(first), "overflow high water prevents equal/late callbacks")
        let held = queue.snapshot
        try expect(held.retainedFrames == 8 && held.peakRetainedFrames == 8 && references.counts.live == 8,
                   "active plus pending references total exactly eight")
        try expect(await trace.count == 1 && held.wakeups == 2, "one startup wakeup and one drain; no per-frame dispatch")
        try expect(held.discardedFrames[.backlogFull] == 100 && held.discardedFrames[.nonIncreasingSequence] == 2,
                   "overflow and sequence reasons distinct")
        try expect(held.lastOfferedSequence == latest.sequence, "rejected newest updates process high water")
        await barrier.release(); await queue.waitUntilIdle()
        try expect(await trace.values == accepted, "single FIFO drains holes immediately in source order")
        try expect(queue.snapshot.completedFrames == 8 && queue.snapshot.knownAcceptedCandidatesNotCommitted == 0,
                   "every admitted frame completes once")
        try expect(references.counts.live == 0 && references.counts.peak == 8 && queue.snapshot.retainedFrames == 0,
                   "actual work references and reservations released together")
    }

    static func residenceBoundaries() async throws {
        for elapsed in [120.0, 120.001] {
            let gate = try activeGate()
            let clock = TestClock()
            let barrier = Barrier()
            let trace = Trace()
            let queue = LibreOrderedIngestion.fixture(gate: gate, now: { clock.now }) { _, context in
                await trace.record(1)
                await barrier.pause() // Read-only preparation suspension.
                if let reason = context.check() { return .init(disposition: .discarded(reason)) }
                await trace.record(2) // Synthetic adaptation produces three known candidates.
                return .init(disposition: .completed, acceptedCandidates: 3)
            }
            queue.start(); await queue.waitUntilIdle()
            let captured = frame(gate, date: epoch.addingTimeInterval(3_000_000_000))
            _ = queue.offer(captured)
            await barrier.waitUntilReached()
            clock.set(elapsed)
            await barrier.release(); await queue.waitUntilIdle()
            try expect(queue.snapshot.completedFrames == (elapsed == 120 ? 1 : 0), "120 inclusive, greater residence expires")
            try expect(queue.snapshot.knownAcceptedCandidatesNotCommitted == 0, "predecode expiry has unknown candidates")
            try expect(await trace.count == (elapsed == 120 ? 2 : 1), "post-await expiry checked before adaptation despite wall-clock jump")
        }
        let gate = try activeGate()
        let clock = TestClock()
        let barrier = Barrier()
        let trace = Trace()
        let queue = LibreOrderedIngestion.fixture(gate: gate, now: { clock.now }) { _, context in
            await trace.record(1)
            await barrier.pause() // Candidates mapped; immediately pre-submission check remains necessary.
            if let reason = context.check() {
                return .init(disposition: .discarded(reason), acceptedCandidates: 3,
                             slotRejections: [Libre2SlotRejectionReason.warmup.rawValue: 4])
            }
            return .init(disposition: .completed, acceptedCandidates: 3)
        }
        queue.start(); await queue.waitUntilIdle()
        _ = queue.offer(frame(gate)); await barrier.waitUntilReached()
        _ = queue.offer(frame(gate))
        clock.set(121)
        await barrier.release(); await queue.waitUntilIdle()
        try expect(await trace.count == 1, "pending expiry is rejected before preparation")
        try expect(queue.snapshot.discardedFrames[.residenceExpired] == 2 && queue.snapshot.knownAcceptedCandidatesNotCommitted == 3 && queue.snapshot.undecodedDiscardedFrames == 1,
                   "known mapped candidates separated from undecoded pending potential slots")
        try expect(queue.snapshot.slotRejections[Libre2SlotRejectionReason.warmup.rawValue] == 4,
                   "decoder rejected slots accounted independently")
    }

    static func invalidationKeepsActiveReservation() async throws {
        let gate = try activeGate()
        let barrier = Barrier()
        let trace = Trace()
        let references = LibreOrderedIngestion.ReferenceProbe()
        let queue = LibreOrderedIngestion.fixture(gate: gate, references: references) { frame, context in
            await trace.record(Int(frame.sequence))
            if await trace.count == 1 { await barrier.pause() }
            if let reason = context.check() { return .init(disposition: .discarded(reason), acceptedCandidates: 2) }
            return .init(disposition: .completed, acceptedCandidates: 2)
        }
        queue.start(); await queue.waitUntilIdle()
        let old = frame(gate)
        _ = queue.offer(old); await barrier.waitUntilReached()
        for _ in 0..<7 { _ = queue.offer(frame(gate)) }
        gate.invalidate(); queue.transportInvalidated()
        try expect(queue.snapshot.retainedFrames == 1 && references.counts.live == 1, "purge preserves suspended active reference")
        try expect(!queue.offer(old), "invalidation rejects a raced old offer without decode")
        let replacement = try session(firstUIDByte: 9)
        gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
        var newSequences: [Int] = []
        for _ in 0..<7 { let next = frame(gate); newSequences.append(Int(next.sequence)); _ = queue.offer(next) }
        try expect(!queue.offer(frame(gate)) && queue.snapshot.wakeups == 2, "new generation cannot overlap old active worker")
        await barrier.release(); await queue.waitUntilIdle()
        try expect(await trace.values == [Int(old.sequence)] + newSequences, "new generation starts only after old completion")
        try expect(queue.snapshot.discardedFrames[.staleOwnership] == 9 && queue.snapshot.completedFrames == 7,
                   "seven pending, one raced offer and one active stale outcome counted once")
        try expect(queue.snapshot.knownAcceptedCandidatesNotCommitted == 2 && queue.snapshot.readyGeneration == nil,
                   "old mapped work discarded without restoring old readiness")
        try expect(references.counts.live == 0 && references.counts.peak == 8, "invalidation preserves real reference bound")
    }

    static func storageFailureAndRecoveryBudget() async throws {
        let gate = try activeGate()
        let barrier = Barrier()
        let recoveryBarrier = Barrier()
        let calls = Trace()
        let queue = LibreOrderedIngestion.fixture(gate: gate, recover: {
            await calls.record(1)
            if await calls.count == 1 { await recoveryBarrier.pause() }
            throw Failure(message: "injected storage failure")
        }) { _, _ in
            await barrier.pause()
            return .init(disposition: .storageFailure, acceptedCandidates: 3)
        }
        queue.start(); await queue.waitUntilIdle()
        _ = queue.offer(frame(gate)); await barrier.waitUntilReached()
        for _ in 0..<7 { _ = queue.offer(frame(gate)) }
        queue.lifecycleOpportunity(.foregroundEntry) // Active work ignores recovery events.
        await barrier.release(); await queue.waitUntilIdle()
        try expect(queue.snapshot.state == .unavailable && queue.snapshot.knownAcceptedCandidatesNotCommitted == 3,
                   "pre-durable failure pauses and counts exactly known candidates")
        try expect(queue.snapshot.discardedFrames[.flushedAfterStorageFailure] == 7 && queue.snapshot.retainedFrames == 0,
                   "failure flushes every pending frame")
        for _ in 0..<10 { try expect(!queue.offer(frame(gate)), "unavailable storage retains no new backlog") }
        queue.lifecycleOpportunity(.foregroundEntry); await recoveryBarrier.waitUntilReached()
        for _ in 0..<10 { queue.lifecycleOpportunity(.deliberateReconnect) }
        try expect(queue.snapshot.recoveryAttempts == 1, "overlapping explicit recovery opportunities coalesce")
        await recoveryBarrier.release(); await queue.waitUntilIdle()
        for _ in 0..<5 { queue.lifecycleOpportunity(.foregroundEntry); await queue.waitUntilIdle() }
        try expect(await calls.count == 3 && queue.snapshot.recoveryAttempts == 3 && queue.snapshot.state == .unavailable,
                   "one shared process budget ends after exactly three attempts")
        gate.invalidate(); queue.transportInvalidated()
        let fresh = try session(); gate.activate(session: fresh, persistenceSessionID: fresh.persistenceSessionID)
        queue.lifecycleOpportunity(.deliberateReconnect); await queue.waitUntilIdle()
        try expect(queue.snapshot.recoveryAttempts == 3, "generation changes never reset recovery budget")

        let opens = Trace()
        let initial = LibreOrderedIngestion.fixture(gate: gate, open: {
            await opens.record(0); throw Failure(message: "load")
        }, recover: {
            await opens.record(1); throw Failure(message: "retry")
        }) { _, _ in .init(disposition: .completed) }
        initial.start(); await initial.waitUntilIdle()
        for _ in 0..<5 { initial.lifecycleOpportunity(.foregroundEntry); await initial.waitUntilIdle() }
        try expect(await opens.values == [0, 1, 1, 1], "one initial open plus at most three lifecycle recovery attempts")
    }

    static func publicationRequiresRefetch() async throws {
        let gate = try activeGate()
        let barrier = Barrier()
        let events = Trace()
        let processed = Trace()
        let refetches = Trace()
        let queue = LibreOrderedIngestion.fixture(gate: gate, recover: {
            await events.record(1)
        }, refetch: {
            await events.record(2); await refetches.record(1)
            if await refetches.count == 1 { throw Failure(message: "refetch unavailable") }
        }) { frame, _ in
            await processed.record(Int(frame.sequence))
            if await processed.count == 1 {
                await barrier.pause() // Synthetic save already durable; publication still outstanding.
                return .init(disposition: .durablePublicationFailure, acceptedCandidates: 7)
            }
            return .init(disposition: .completed, acceptedCandidates: 7)
        }
        queue.start(); await queue.waitUntilIdle()
        let saved = frame(gate); _ = queue.offer(saved); await barrier.waitUntilReached()
        _ = queue.offer(frame(gate))
        gate.invalidate(); queue.transportInvalidated()
        await barrier.release(); await queue.waitUntilIdle()
        try expect(queue.snapshot.knownAcceptedCandidatesNotCommitted == 0 && queue.snapshot.durablePublicationFailureFrames == 1,
                   "durable old-generation candidates are never reported uncommitted")
        queue.lifecycleOpportunity(.foregroundEntry); await queue.waitUntilIdle()
        try expect(queue.snapshot.state == .unavailable, "successful recovery cannot bypass failed committed-data refetch")
        queue.lifecycleOpportunity(.foregroundEntry); await queue.waitUntilIdle()
        try expect(await events.values == [1, 2, 1, 2] && queue.snapshot.state == .ready, "later opportunity retries recovery/refetch in order")
        let replacement = try session(); gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
        let next = frame(gate); _ = queue.offer(next); await queue.waitUntilIdle()
        try expect(await processed.values == [Int(saved.sequence), Int(next.sequence)], "saved frame never decoded or submitted again to recreate publication")
    }

    static func repairAndInvariantPauses() async throws {
        for invariant in [false, true] {
            let gate = try activeGate()
            let barrier = Barrier()
            let trace = Trace()
            let queue = LibreOrderedIngestion.fixture(gate: gate, recover: { await trace.record(9) }) { _, _ in
                await trace.record(1)
                if await trace.count == 1 {
                    await barrier.pause()
                    return .init(disposition: invariant ? .invariantFailure : .repairRequired, acceptedCandidates: invariant ? 3 : nil)
                }
                return .init(disposition: .allSlotsRejected, acceptedCandidates: 0)
            }
            queue.start(); await queue.waitUntilIdle()
            _ = queue.offer(frame(gate)); await barrier.waitUntilReached()
            _ = queue.offer(frame(gate)); await barrier.release(); await queue.waitUntilIdle()
            try expect(queue.snapshot.state == (invariant ? .invariant : .repair) && queue.snapshot.retainedFrames == 0,
                       "repair and invariant failures pause and flush")
            queue.lifecycleOpportunity(.foregroundEntry); queue.repairSucceededAndActivated()
            try expect(!queue.offer(frame(gate)), "lifecycle and same activation cannot repair/relabel old work")
            gate.invalidate(); queue.transportInvalidated()
            let replacement = try session(); gate.activate(session: replacement, persistenceSessionID: replacement.persistenceSessionID)
            queue.repairSucceededAndActivated()
            try expect(queue.offer(frame(gate)) == !invariant, "only deliberate successful repair and fresh activation resumes repair")
            await queue.waitUntilIdle()
            try expect(await trace.values == (invariant ? [1] : [1, 1]), "invariant never auto retries; repair consumes future frame only")
        }
    }

    static func repairDuringWorkerCompletion() async throws {
        let gate = try activeGate()
        let completion = Barrier()
        let calls = Trace()
        let references = LibreOrderedIngestion.ReferenceProbe()
        let queue = LibreOrderedIngestion.fixture(gate: gate, references: references,
                                                  afterFrameCompletion: { await completion.pause() }) { _, _ in
            await calls.record(1)
            return .init(disposition: await calls.count == 1 ? .repairRequired : .completed)
        }
        queue.start(); await queue.waitUntilIdle()
        _ = queue.offer(frame(gate)); await completion.waitUntilReached()
        try expect(queue.snapshot.state == .repair && queue.snapshot.workerScheduled && references.counts.live == 0,
                   "frame completed and released while its drain remains scheduled")
        gate.invalidate(); queue.transportInvalidated()
        let repaired = try session()
        gate.activate(session: repaired, persistenceSessionID: repaired.persistenceSessionID)
        queue.repairSucceededAndActivated() // A one-shot event inside finish-to-idle window.
        try expect(queue.snapshot.state == .ready, "successful fresh repair cannot be lost while completed drain unwinds")
        try expect(queue.offer(frame(gate)) && queue.snapshot.wakeups == 2,
                   "repaired offer is handled by existing drain without second worker")
        await completion.release(); await queue.waitUntilIdle()
        try expect(await calls.count == 2 && queue.snapshot.completedFrames == 1 && references.counts.live == 0,
                   "existing drain consumes repaired future work exactly once")
    }

    actor Trace {
        var values: [Int] = []
        var count: Int { values.count }
        func record(_ value: Int) { values.append(value) }
    }
    actor Barrier {
        private var reached = false
        private var released = false
        private var observers: [CheckedContinuation<Void, Never>] = []
        private var blocked: CheckedContinuation<Void, Never>?
        func pause() async {
            reached = true
            for observer in observers { observer.resume() }; observers.removeAll()
            if released { return }
            await withCheckedContinuation { blocked = $0 }
        }
        func waitUntilReached() async {
            if reached { return }
            await withCheckedContinuation { observers.append($0) }
        }
        func release() { released = true; blocked?.resume(); blocked = nil }
    }
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0.0
        var now: Double { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ value: Double) { lock.lock(); self.value = value; lock.unlock() }
    }
    static func frame(_ gate: LibreFrameGenerationGate, date: Date = epoch) -> LibreVerifiedFrame {
        gate.makeFrame(payload: Data([1, 2, 3]), receivedAt: date)!
    }
    static func activeGate() throws -> LibreFrameGenerationGate {
        let gate = LibreFrameGenerationGate()
        let captured = try session()
        gate.activate(session: captured, persistenceSessionID: captured.persistenceSessionID)
        return gate
    }
    static func session(firstUIDByte: UInt8 = 1) throws -> LibreSensorSession {
        let uid = Data([firstUIDByte, 2, 3, 4, 5, 6, 7, 8])
        let patch = Data([0x9D, 0, 0, 0, 0, 0])
        let object: [String: Any] = ["ownerUID": uid.base64EncodedString(), "ownerPatchInfo": patch.base64EncodedString(),
            "formatVersion": 1, "capturedAt": epoch.timeIntervalSinceReferenceDate, "sensorMinute": 1000,
            "lifecycle": 3, "calibrationSource": Data(repeating: 0, count: 10).base64EncodedString()]
        let calibration = try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: object))
        return LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "synthetic", unlockCode: 42,
                                  setupComplete: true, sensorKind: .libre2_9D, createdAt: epoch, calibration: calibration)
    }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    struct Failure: Error { let message: String }
}
