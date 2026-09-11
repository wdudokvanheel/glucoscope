import Foundation

/// Synthetic serialized-producer checks for the disconnected handoff. This does
/// not instantiate Core Bluetooth or qualify decoder output for canonical use.
@main
struct TransportHandoffSmoke {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    static func main() async throws {
        try ordinaryDecoderProducesCheckedOutcomes()
        #if LIBRE2_TRANSPORT_HANDOFF_FIXTURES && LIBRE2_ORDERED_INGESTION_FIXTURES
        try await offerPrecedesDiagnosticCapture()
        try await rejectedCompletedFramesRetainNoBody()
        try await blockedSchedulerCoalescesAndBoundsBodies()
        try await notificationMetadataIsBodyFreeAndBounded()
        try await queuedStaleDiagnosticsAreSuppressed()
        try await lifecyclePurgesQueueAndRevokesDiagnostics()
        print("Libre transport handoff checks passed (synthetic, disconnected; driver integration unverified).")
        #else
        print("Libre transport handoff ordinary source shape passed with checked development decoding.")
        #endif
    }

    static func ordinaryDecoderProducesCheckedOutcomes() throws {
        let sensor = try session()
        let gate = LibreFrameGenerationGate()
        let generation = gate.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        let frame = gate.makeFrame(payload: verifiedPayload(marker: 1), receivedAt: epoch)!
        let anchor = sensor.clockAnchor!
        let stored = ReadingSessionSnapshot(
            id: try sensor.validatedPersistenceSessionID(),
            stableIdentityFingerprint: try sensor.stableIdentityFingerprint(),
            sensorRevision: sensor.sensorKind.rawValue,
            firstObservedAt: sensor.createdAt,
            observedAt: epoch,
            lifecycleState: .active,
            clock: ReadingClockSnapshot(
                referenceSensorMinute: Int64(anchor.referenceSensorMinute),
                referenceDate: anchor.referenceDate,
                provenance: LibreSensorClockAnchor.canonicalPersistenceProvenance
            )
        )
        let decoded = Libre2ProductionDecoder.decode(
            frame: frame,
            session: stored,
            ownership: Libre2DecodeOwnership(
                generation: generation,
                session: sensor,
                persistenceSessionID: sensor.persistenceSessionID
            )
        )
        try expect(decoded.rejection == nil && decoded.slots.count == 7,
                   "ordinary development decoder emits seven checked slot outcomes")
        try expect(Libre2ProductionPolicy.engineeringV1.canIngestCanonical,
                   "engineering policy enables local development ingestion")
    }

    #if LIBRE2_TRANSPORT_HANDOFF_FIXTURES && LIBRE2_ORDERED_INGESTION_FIXTURES
    static func offerPrecedesDiagnosticCapture() async throws {
        let producer = DispatchQueue(label: "transport-handoff.offer")
        let scheduler = ManualScheduler()
        let callbacks = SnapshotLog()
        let processor = BlockingBarrier()
        let processed = FrameLog()
        let offerScheduleCounts = IntegerLog()
        let sensor = try session()
        let gate = LibreFrameGenerationGate()
        gate.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        let queue = LibreOrderedIngestion.fixture(
            gate: gate,
            beforeOfferCurrentnessCheck: { _ in offerScheduleCounts.append(scheduler.scheduleCount) },
            afterOfferCurrentnessCheck: { _, _ in offerScheduleCounts.append(scheduler.scheduleCount) }
        ) { frame, _ in
            processed.append(frame)
            processor.pause()
            return .init(disposition: .completed, acceptedCandidates: 2)
        }
        queue.start()
        try await waitUntilIdle(queue)
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule, onDiagnostics: callbacks.append
        )
        let raw = sliced(Data((0..<46).map(UInt8.init)))
        let plaintext = sliced(verifiedPayload(marker: 7))
        let accepted = producer.sync {
            handoff.completeFrame(raw: raw, verifiedPayload: plaintext, receivedAt: epoch)
        }
        try expect(accepted, "valid complete frame reaches canonical mailbox")
        try processor.waitUntilReached("canonical processor did not receive offered frame")
        try expect(offerScheduleCounts.values == [0, 0],
                   "no diagnostic schedule or capture occurs before real offer returns")
        try expect(queue.snapshot.retainedFrames == 1 && scheduler.scheduleCount == 1,
                   "real queue reserves the frame before the first diagnostic signal")
        try expect(handoff.stats.pendingDiagnostics == 1 && handoff.stats.retainedPayloadBytes == 90,
                   "accepted complete diagnostics retain one bounded raw/plain pair")
        try scheduler.runNext()
        guard let snapshot = callbacks.values.only else { throw Failure("accepted snapshot missing") }
        try expect(snapshot.raw?.data == raw && snapshot.raw?.data.startIndex == 0 &&
                   snapshot.verified?.payload == plaintext && snapshot.verified?.payload.startIndex == 0,
                   "handoff owns normalized copies of sliced raw/plain data")
        try expect(snapshot.verified?.sequence == processed.values.only?.sequence &&
                   snapshot.verified?.payload == processed.values.only?.payload,
                   "diagnostic snapshot describes the exact frame offered to the real queue")
        processor.release()
        try await waitUntilIdle(queue)
        try expect(queue.snapshot.completedFrames == 1, "accepted processor fixture completes once")
    }

    static func rejectedCompletedFramesRetainNoBody() async throws {
        try await rejectedByUnavailableStore()
        try await rejectedByFullQueue()
    }

    static func rejectedByUnavailableStore() async throws {
        let producer = DispatchQueue(label: "transport-handoff.unavailable")
        let scheduler = ManualScheduler()
        let callbacks = SnapshotLog()
        let sensor = try session()
        let gate = LibreFrameGenerationGate()
        gate.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        let queue = LibreOrderedIngestion.fixture(gate: gate, open: { throw Failure("closed") }) { _, _ in
            preconditionFailure("unavailable queue processed a frame")
        }
        queue.start()
        try await waitUntilIdle(queue)
        try expect(queue.snapshot.state == .unavailable, "synthetic closed store is unavailable")
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule, onDiagnostics: callbacks.append
        )
        producer.sync { handoff.notification(data: Data(repeating: 0xA5, count: 46), receivedAt: epoch) }
        let accepted = producer.sync {
            handoff.completeFrame(raw: rawFrame(2), verifiedPayload: verifiedPayload(marker: 2), receivedAt: epoch)
        }
        try expect(!accepted && handoff.stats.counts.canonicalRejected == 1,
                   "closed store rejects the real canonical offer")
        try expect(handoff.stats.retainedPayloadBytes == 0 && scheduler.scheduleCount == 1,
                   "rejection clears complete notification and frame state before queued delivery")
        try scheduler.runNext()
        guard let snapshot = callbacks.values.only else { throw Failure("redacted rejection snapshot missing") }
        try expect(snapshot.raw == nil && snapshot.verified == nil && snapshot.notification == nil,
                   "closed-store rejection never delivers complete payload or session snapshot")
    }

    static func rejectedByFullQueue() async throws {
        let producer = DispatchQueue(label: "transport-handoff.full")
        let scheduler = ManualScheduler()
        let callbacks = SnapshotLog()
        let processor = BlockingBarrier()
        let sensor = try session()
        let gate = LibreFrameGenerationGate()
        gate.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        let queue = LibreOrderedIngestion.fixture(gate: gate) { _, _ in
            processor.pause()
            return .init(disposition: .completed)
        }
        queue.start()
        try await waitUntilIdle(queue)
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule, onDiagnostics: callbacks.append
        )
        for marker in UInt8(10)...UInt8(17) {
            try expect(producer.sync {
                handoff.completeFrame(raw: rawFrame(marker), verifiedPayload: verifiedPayload(marker: marker), receivedAt: epoch)
            }, "eight active/pending canonical frames fit")
            if marker == 10 { try processor.waitUntilReached("first full-queue frame did not become active") }
        }
        producer.sync { handoff.notification(data: Data(repeating: 0xCC, count: 46), receivedAt: epoch) }
        let rejected = producer.sync {
            handoff.completeFrame(raw: rawFrame(18), verifiedPayload: verifiedPayload(marker: 18), receivedAt: epoch)
        }
        try expect(!rejected && queue.snapshot.retainedFrames == LibreOrderedIngestion.capacity,
                   "ninth canonical frame is synchronously rejected at the real bound")
        try expect(handoff.stats.pendingDiagnostics == 1 && handoff.stats.retainedPayloadBytes == 0 &&
                   handoff.stats.counts.canonicalAccepted == 8 && handoff.stats.counts.canonicalRejected == 1,
                   "full-queue rejection clears completed payload while preserving redacted counts")
        try scheduler.runNext()
        guard let snapshot = callbacks.values.only else { throw Failure("full-queue rejection snapshot missing") }
        try expect(snapshot.raw == nil && snapshot.verified == nil && snapshot.notification == nil,
                   "full-queue rejected frame never escapes through diagnostics")
        processor.release()
        try await waitUntilIdle(queue)
        try expect(queue.snapshot.completedFrames == 8, "eight reserved canonical frames drain FIFO")
    }

    static func blockedSchedulerCoalescesAndBoundsBodies() async throws {
        let producer = DispatchQueue(label: "transport-handoff.bound")
        let scheduler = ManualScheduler()
        let callbackBarrier = BlockingBarrier()
        let callbacks = SnapshotLog()
        let sensor = try session()
        let gate = LibreFrameGenerationGate()
        gate.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        let processed = FrameLog()
        let queue = LibreOrderedIngestion.fixture(gate: gate) { frame, _ in
            processed.append(frame)
            return .init(disposition: .completed, acceptedCandidates: 1)
        }
        queue.start()
        try await waitUntilIdle(queue)
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule, onDiagnostics: callbacks.append
        )
        for category in LibreTransportHandoff.DiagnosticCategory.allCases {
            producer.sync { handoff.control(category) }
        }
        for count in 1...46 {
            producer.sync { handoff.notification(data: Data(repeating: UInt8(count), count: count), receivedAt: epoch) }
        }
        try expect(handoff.stats.pendingDiagnostics == 1 && handoff.stats.inFlightDiagnostics == 0 &&
                   handoff.stats.scheduled && handoff.stats.scheduleCount == 1 && scheduler.scheduleCount == 1,
                   "blocked scheduler storm remains one pending snapshot and one signal")
        try expect(handoff.stats.counts.coalescedUpdates == 50,
                   "all updates after the first are explicitly coalesced")

        let firstAccepted = producer.sync {
            handoff.completeFrame(raw: rawFrame(30), verifiedPayload: verifiedPayload(marker: 30), receivedAt: epoch)
        }
        try expect(firstAccepted, "first bounded diagnostic frame accepted")
        callbacks.blockNext(with: callbackBarrier)
        let running = try scheduler.runNextAsync()
        try callbackBarrier.waitUntilReached("diagnostic callback did not enter")
        let secondAccepted = producer.sync {
            handoff.completeFrame(raw: rawFrame(31), verifiedPayload: verifiedPayload(marker: 31), receivedAt: epoch)
        }
        try expect(secondAccepted, "next frame accepted while prior diagnostic is in flight")
        let held = handoff.stats
        try expect(held.inFlightDiagnostics == 1 && held.pendingDiagnostics == 1 &&
                   held.retainedPayloadBytes == 180 && held.peakRetainedPayloadBytes == 180,
                   "bound counts one in-flight and one pending raw/plain pair")
        try expect(held.scheduleCount == 1 && scheduler.scheduleCount == 1,
                   "in-flight drain does not schedule a concurrent successor")
        callbackBarrier.release()
        try running.wait()
        try expect(scheduler.scheduleCount == 2 && handoff.stats.pendingDiagnostics == 1,
                   "completed callback enqueues exactly one successor turn")
        try scheduler.runNext()
        try await waitUntilIdle(queue)
        let delivered = callbacks.values
        try expect(delivered.count == 2 && delivered[0].sourceSequence < delivered[1].sourceSequence,
                   "delayed serial diagnostic dispatch preserves source sequence")
        try expect(delivered[1].verified?.sequence == processed.values.last?.sequence,
                   "successor delivers the newest actually offered canonical frame")
        try expect(handoff.stats.pendingDiagnostics == 0 && handoff.stats.inFlightDiagnostics == 0 &&
                   handoff.stats.retainedPayloadBytes == 0 && !handoff.stats.scheduled,
                   "drain releases all relay-owned bodies and returns idle")
    }

    static func notificationMetadataIsBodyFreeAndBounded() async throws {
        let producer = DispatchQueue(label: "transport-handoff.notification")
        let scheduler = ManualScheduler()
        let callbacks = SnapshotLog()
        let gate = LibreFrameGenerationGate()
        let queue = LibreOrderedIngestion.fixture(gate: gate) { _, _ in .init(disposition: .completed) }
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule, onDiagnostics: callbacks.append
        )
        producer.sync { handoff.notification(data: sliced(Data(repeating: 0x11, count: 23)), receivedAt: epoch) }
        try expect(handoff.stats.retainedPayloadBytes == 0, "partial notification retains metadata only")
        try scheduler.runNext()
        producer.sync { handoff.notification(data: sliced(Data(repeating: 0x22, count: 46)), receivedAt: epoch.addingTimeInterval(1)) }
        try scheduler.runNext()
        producer.sync { handoff.notification(data: Data(repeating: 0x33, count: 47), receivedAt: epoch.addingTimeInterval(2)) }
        try expect(handoff.stats.retainedPayloadBytes == 0 && handoff.stats.counts.oversizedNotifications == 1,
                   "oversized notification is classified without retaining or formatting its body")
        try scheduler.runNext()
        let delivered = callbacks.values
        try expect(delivered.map { $0.notification?.byteCount } == [23, 46, 47] &&
                   delivered.map { $0.notification?.oversized } == [false, false, true],
                   "partial, full and oversized notification lengths survive as bounded metadata")
        try expect(delivered.allSatisfy { $0.raw == nil && $0.verified == nil },
                   "notification path cannot retain raw/plain complete-frame bytes")

        let before = scheduler.scheduleCount
        let oversizedRaw = producer.sync {
            handoff.completeFrame(raw: Data(repeating: 1, count: 47), verifiedPayload: nil, receivedAt: epoch)
        }
        try expect(!oversizedRaw && handoff.stats.retainedPayloadBytes == 0 &&
                   handoff.stats.counts.oversizedRaw == 1 && scheduler.scheduleCount == before + 1,
                   "oversized completed raw is rejected and redacted before its diagnostic turn")
        try scheduler.runNext()
        try expect(callbacks.values.last?.raw == nil && callbacks.values.last?.verified == nil,
                   "oversized completed input never appears in a diagnostic snapshot")
    }

    static func queuedStaleDiagnosticsAreSuppressed() async throws {
        let producer = DispatchQueue(label: "transport-handoff.stale")
        let scheduler = ManualScheduler()
        let callbacks = SnapshotLog()
        let precheck = BlockingBarrier()
        let sensor = try session()
        let gate = LibreFrameGenerationGate()
        gate.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        let queue = LibreOrderedIngestion.fixture(gate: gate) { _, _ in .init(disposition: .completed) }
        queue.start()
        try await waitUntilIdle(queue)
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule,
            beforeDiagnosticCurrentnessCheck: { _ in precheck.pause() },
            onDiagnostics: callbacks.append
        )
        try expect(producer.sync {
            handoff.completeFrame(raw: rawFrame(39), verifiedPayload: verifiedPayload(marker: 39), receivedAt: epoch)
        }, "stale-race frame accepted before revocation")
        let running = try scheduler.runNextAsync()
        try precheck.waitUntilReached("diagnostic drain did not reach currentness precheck")
        producer.sync { handoff.invalidate() }
        precheck.release()
        try running.wait()
        try expect(callbacks.values.isEmpty && handoff.stats.counts.suppressedStale == 1 &&
                   handoff.stats.retainedPayloadBytes == 0 && scheduler.scheduleCount == 2,
                   "dequeued old-generation payload is suppressed and releases its body")
        try scheduler.runNext()
        guard let invalidated = callbacks.values.only else { throw Failure("invalidation summary missing") }
        try expect(!invalidated.transportActive && handoff.isCurrent(invalidated) &&
                   invalidated.raw == nil && invalidated.verified == nil,
                   "successor turn delivers only current body-free invalidation state")
    }

    static func lifecyclePurgesQueueAndRevokesDiagnostics() async throws {
        let producer = DispatchQueue(label: "transport-handoff.lifecycle")
        let scheduler = ManualScheduler()
        let callbackBarrier = BlockingBarrier()
        let callbacks = SnapshotLog()
        let processorBarrier = BlockingBarrier()
        let processed = FrameLog()
        let first = try session(firstUIDByte: 1)
        let second = try session(firstUIDByte: 9)
        let gate = LibreFrameGenerationGate()
        gate.activate(session: first, persistenceSessionID: first.persistenceSessionID)
        let queue = LibreOrderedIngestion.fixture(gate: gate) { frame, context in
            processed.append(frame)
            if processed.values.count == 1 { processorBarrier.pause() }
            if let reason = context.check() { return .init(disposition: .discarded(reason)) }
            return .init(disposition: .completed)
        }
        queue.start()
        try await waitUntilIdle(queue)
        let handoff = LibreTransportHandoff.fixture(
            gate: gate, ingestion: queue, producerQueue: producer,
            schedule: scheduler.schedule, onDiagnostics: callbacks.append
        )
        for marker in UInt8(40)...UInt8(42) {
            try expect(producer.sync {
                handoff.completeFrame(raw: rawFrame(marker), verifiedPayload: verifiedPayload(marker: marker), receivedAt: epoch)
            }, "old generation canonical frame accepted")
            if marker == 40 { try processorBarrier.waitUntilReached("old frame did not become active") }
        }
        try expect(queue.snapshot.retainedFrames == 3 && handoff.stats.retainedPayloadBytes == 90,
                   "old generation holds one active and two pending canonical frames")
        producer.sync { handoff.invalidate() }
        try expect(queue.snapshot.retainedFrames == 1 && handoff.stats.retainedPayloadBytes == 0,
                   "invalidation directly purges queued canonical and diagnostic payloads")
        producer.sync { _ = handoff.activate(session: second, persistenceSessionID: second.persistenceSessionID) }
        try scheduler.runNext()
        guard let lifecycle = callbacks.values.only else { throw Failure("lifecycle snapshot missing") }
        try expect(lifecycle.raw == nil && lifecycle.verified == nil && lifecycle.transportActive &&
                   lifecycle.generation == gate.currentGeneration,
                   "queued stale payload is replaced by current body-free activation state")

        let newAccepted = producer.sync {
            handoff.completeFrame(raw: rawFrame(50), verifiedPayload: verifiedPayload(marker: 50), receivedAt: epoch)
        }
        try expect(newAccepted, "new generation frame accepted while old processor is suspended")
        callbacks.blockNext(with: callbackBarrier)
        let running = try scheduler.runNextAsync()
        try callbackBarrier.waitUntilReached("new-generation callback did not enter")
        guard let started = callbacks.values.last else { throw Failure("in-flight snapshot missing") }
        producer.sync { handoff.invalidate() }
        producer.sync { _ = handoff.activate(session: first, persistenceSessionID: first.persistenceSessionID) }
        let replacementAccepted = producer.sync {
            handoff.completeFrame(raw: rawFrame(51), verifiedPayload: verifiedPayload(marker: 51), receivedAt: epoch)
        }
        try expect(replacementAccepted && !handoff.isCurrent(started),
                   "in-flight callback loses eligibility after revoke/activate")
        try expect(handoff.stats.inFlightDiagnostics == 1 && handoff.stats.pendingDiagnostics == 1 &&
                   handoff.stats.retainedPayloadBytes == 180,
                   "old in-flight body and next current body both count toward the hard bound")
        callbackBarrier.release()
        try running.wait()
        try expect(handoff.stats.pendingDiagnostics == 1 && scheduler.scheduleCount == 3,
                   "old callback completion cannot clear or restore eligibility over current pending work")
        try scheduler.runNext()
        guard let newest = callbacks.values.last else { throw Failure("replacement snapshot missing") }
        try expect(handoff.isCurrent(newest) && newest.verified?.payload == verifiedPayload(marker: 51),
                   "successor callback publishes only current replacement-generation work")
        processorBarrier.release()
        try await waitUntilIdle(queue)
        try expect(queue.snapshot.discardedFrames[.staleOwnership] == 4 &&
                   processed.values.last?.payload == verifiedPayload(marker: 51),
                   "queue purge plus active revocation suppress old generation before new FIFO work")
    }

    static func waitUntilIdle(_ queue: LibreOrderedIngestion) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while queue.snapshot.workerScheduled {
            guard ContinuousClock.now < deadline else { throw Failure("canonical queue failed to become idle") }
            await Task.yield()
        }
    }
    #endif

    static func rawFrame(_ marker: UInt8) -> Data {
        var bytes = Data(repeating: marker, count: 46)
        bytes[0] = marker
        return bytes
    }

    static func verifiedPayload(marker: UInt8) -> Data {
        var bytes = Data(repeating: marker, count: 44)
        bytes[40] = 0xE8
        bytes[41] = 0x03
        let checksum = fixtureCRC(Array(bytes.prefix(42)))
        bytes[42] = UInt8(truncatingIfNeeded: checksum)
        bytes[43] = UInt8(checksum >> 8)
        return bytes
    }

    static func fixtureCRC(_ bytes: [UInt8]) -> UInt16 {
        var checksum: UInt16 = 0xFFFF
        for byte in bytes {
            for bit in 0..<8 {
                let feedback = ((checksum >> 15) ^ UInt16((byte >> bit) & 1)) != 0
                checksum <<= 1
                if feedback { checksum ^= 0x1021 }
            }
        }
        return checksum
    }

    static func sliced(_ data: Data) -> Data {
        (Data([0xFF]) + data).dropFirst()
    }

    static func session(firstUIDByte: UInt8 = 1) throws -> LibreSensorSession {
        let uid = Data([firstUIDByte, 2, 3, 4, 5, 6, 7, 8])
        let patch = Data([0x9D, 0, 0, 0, 0, 0])
        let header = UInt16(1 << 3)
        let footer = UInt64(10_000) << 8 | UInt64(2_000) << 52
        var source = Data([UInt8(truncatingIfNeeded: header), UInt8(header >> 8)])
        for byte in 0..<8 { source.append(UInt8(truncatingIfNeeded: footer >> (byte * 8))) }
        let object: [String: Any] = [
            "ownerUID": uid.base64EncodedString(),
            "ownerPatchInfo": patch.base64EncodedString(),
            "formatVersion": 1,
            "capturedAt": epoch.timeIntervalSinceReferenceDate,
            "sensorMinute": 1000,
            "lifecycle": 3,
            "calibrationSource": source.base64EncodedString()
        ]
        let calibration = try JSONDecoder().decode(
            LibreCalibration.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        return LibreSensorSession(
            uid: uid, patchInfo: patch, advertisedName: "synthetic", unlockCode: 42,
            setupComplete: true, sensorKind: .libre2_9D, createdAt: epoch,
            calibration: calibration, persistenceSessionID: UUID()
        )
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message) }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    final class BlockingBarrier: @unchecked Sendable {
        private let reached = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var used = false

        func pause() {
            lock.lock()
            let shouldPause = !used
            used = true
            lock.unlock()
            guard shouldPause else { return }
            reached.signal()
            precondition(released.wait(timeout: .now() + 10) == .success, "fixture barrier timed out")
        }

        func waitUntilReached(_ message: String) throws {
            try expect(reached.wait(timeout: .now() + 10) == .success, message)
        }

        func release() { released.signal() }
    }

    final class Completion: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func finish() { semaphore.signal() }
        func wait() throws {
            try expect(semaphore.wait(timeout: .now() + 10) == .success,
                       "scheduled diagnostic drain did not finish")
        }
    }

    final class ManualScheduler: @unchecked Sendable {
        private let lock = NSLock()
        private var jobs: [@Sendable () -> Void] = []
        private var total: UInt64 = 0

        lazy var schedule: @Sendable (@escaping @Sendable () -> Void) -> Void = { [weak self] job in
            guard let self else { return }
            lock.lock()
            jobs.append(job)
            total += 1
            lock.unlock()
        }

        var scheduleCount: UInt64 {
            lock.lock(); defer { lock.unlock() }
            return total
        }

        func runNext() throws {
            let job = try take()
            job()
        }

        func runNextAsync() throws -> Completion {
            let job = try take()
            let completion = Completion()
            DispatchQueue.global().async {
                job()
                completion.finish()
            }
            return completion
        }

        private func take() throws -> @Sendable () -> Void {
            lock.lock(); defer { lock.unlock() }
            guard !jobs.isEmpty else { throw Failure("manual scheduler has no queued drain") }
            return jobs.removeFirst()
        }
    }

    final class SnapshotLog: @unchecked Sendable {
        private let lock = NSLock()
        private var snapshots: [LibreTransportHandoff.Snapshot] = []
        private var blockNext: BlockingBarrier?

        func blockNext(with barrier: BlockingBarrier) {
            lock.lock(); defer { lock.unlock() }
            precondition(blockNext == nil, "snapshot log already has a blocking callback")
            blockNext = barrier
        }

        lazy var append: @Sendable (LibreTransportHandoff.Snapshot) -> Void = { [weak self] snapshot in
            guard let self else { return }
            lock.lock()
            snapshots.append(snapshot)
            let barrier = blockNext
            blockNext = nil
            lock.unlock()
            barrier?.pause()
        }

        var values: [LibreTransportHandoff.Snapshot] {
            lock.lock(); defer { lock.unlock() }
            return snapshots
        }
    }

    final class FrameLog: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [LibreVerifiedFrame] = []
        func append(_ frame: LibreVerifiedFrame) { lock.lock(); frames.append(frame); lock.unlock() }
        var values: [LibreVerifiedFrame] { lock.lock(); defer { lock.unlock() }; return frames }
    }

    final class IntegerLog: @unchecked Sendable {
        private let lock = NSLock()
        private var integers: [UInt64] = []
        func append(_ value: UInt64) { lock.lock(); integers.append(value); lock.unlock() }
        var values: [UInt64] { lock.lock(); defer { lock.unlock() }; return integers }
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
