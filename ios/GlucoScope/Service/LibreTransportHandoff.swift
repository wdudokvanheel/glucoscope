import Foundation

/// DISCONNECTED engineering boundary: no app or BLE owner instantiates this type.
/// All producer calls, including lifecycle calls, belong to the supplied SERIAL queue.
/// The producer must decrypt the actual raw/plain pair under that same activation.
/// CRC is checked here, but CRC alone cannot prove that cryptographic association.
/// This seam does not qualify decoding, receipt clocks, freshness, or runtime wiring.
/// Relay retention: one pending aggregate plus one in-flight snapshot, each with
/// at most 46 raw + 44 plaintext bytes (180 total payload-body bytes). Captured
/// session storage, producer transients and consumer-retained copies are separate.
/// All categories share one scheduled/running drain reservation.
final class LibreTransportHandoff: @unchecked Sendable {
    enum DiagnosticCategory: CaseIterable, Sendable {
        case bluetoothState, status, log, sessionChanged, error
    }

    struct Counts: Sendable {
        fileprivate(set) var completedFrames: UInt64 = 0
        fileprivate(set) var verifiedFrames: UInt64 = 0
        fileprivate(set) var canonicalAccepted: UInt64 = 0
        fileprivate(set) var canonicalRejected: UInt64 = 0
        fileprivate(set) var invalidFrames: UInt64 = 0
        fileprivate(set) var inactiveFrames: UInt64 = 0
        fileprivate(set) var oversizedRaw: UInt64 = 0
        fileprivate(set) var oversizedVerified: UInt64 = 0
        fileprivate(set) var notifications: UInt64 = 0
        fileprivate(set) var oversizedNotifications: UInt64 = 0
        fileprivate(set) var activations: UInt64 = 0
        fileprivate(set) var invalidations: UInt64 = 0
        fileprivate(set) var controls: [DiagnosticCategory: UInt64] = [:]
        fileprivate(set) var coalescedUpdates: UInt64 = 0
        fileprivate(set) var delivered: UInt64 = 0
        fileprivate(set) var suppressedStale: UInt64 = 0
    }

    struct RawObservation: Sendable {
        let data: Data
        let receivedAt: Date
        let sourceSequence: UInt64
        let generation: UInt64
    }

    /// Metadata only, even for a full 46-byte notification. Retaining its hex/body
    /// before assembly could otherwise bypass rejection of the completed frame.
    struct NotificationObservation: Sendable {
        let byteCount: Int
        let oversized: Bool
        let receivedAt: Date
        let sourceSequence: UInt64
        let generation: UInt64
    }

    struct Snapshot: Sendable {
        let sourceSequence: UInt64
        let generation: UInt64
        let transportActive: Bool
        let counts: Counts
        let raw: RawObservation?
        let verified: LibreVerifiedFrame?
        let notification: NotificationObservation?
        fileprivate let owner: UUID

        fileprivate init(sourceSequence: UInt64, generation: UInt64, transportActive: Bool,
                         counts: Counts, raw: RawObservation?, verified: LibreVerifiedFrame?,
                         notification: NotificationObservation?, owner: UUID) {
            self.sourceSequence = sourceSequence; self.generation = generation
            self.transportActive = transportActive; self.counts = counts
            self.raw = raw; self.verified = verified; self.notification = notification
            self.owner = owner
        }
    }

    /// Redacted observation of relay-owned retention. Consumer-owned copies and
    /// the canonical mailbox's independent eight-frame budget are not included.
    struct Stats: Sendable {
        let counts: Counts
        let sourceSequence: UInt64
        let pendingDiagnostics: Int
        let inFlightDiagnostics: Int
        let scheduled: Bool
        let scheduleCount: UInt64
        let retainedPayloadBytes: Int
        let peakRetainedPayloadBytes: Int
    }

    private struct Pending {
        var raw: RawObservation?
        var verified: LibreVerifiedFrame?
        var notification: NotificationObservation?
        var payloadBytes: Int { (raw?.data.count ?? 0) + (verified?.payload.count ?? 0) }
    }

    private let gate: LibreFrameGenerationGate
    private let ingestion: LibreOrderedIngestion
    private let producerQueue: DispatchQueue
    private let onDiagnostics: @Sendable (Snapshot) -> Void
    private let schedule: @Sendable (@escaping @Sendable () -> Void) -> Void
    #if LIBRE2_TRANSPORT_HANDOFF_FIXTURES
    private let beforeDiagnosticCurrentnessCheck: @Sendable (Snapshot) -> Void
    #endif
    private let owner = UUID()
    private let lock = NSLock()
    private var counts = Counts()
    private var sourceSequence: UInt64 = 0
    private var generation: UInt64
    private var transportActive: Bool
    private var pending = Pending()
    private var dirty = false
    private var scheduled = false
    private var scheduleCount: UInt64 = 0
    private var inFlightDiagnostics = 0
    private var inFlightPayloadBytes = 0
    private var peakRetainedPayloadBytes = 0

    convenience init(gate: LibreFrameGenerationGate, ingestion: LibreOrderedIngestion,
                     producerQueue: DispatchQueue,
                     onDiagnostics: @escaping @Sendable (Snapshot) -> Void) {
        self.init(gate: gate, ingestion: ingestion, producerQueue: producerQueue,
                  schedule: { work in DispatchQueue.main.async(execute: work) },
                  onDiagnostics: onDiagnostics)
    }

    private init(gate: LibreFrameGenerationGate, ingestion: LibreOrderedIngestion,
                 producerQueue: DispatchQueue,
                 schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                 onDiagnostics: @escaping @Sendable (Snapshot) -> Void) {
        self.gate = gate; self.ingestion = ingestion; self.producerQueue = producerQueue
        self.schedule = schedule; self.onDiagnostics = onDiagnostics
        generation = gate.currentGeneration
        transportActive = gate.activeGeneration != nil
        #if LIBRE2_TRANSPORT_HANDOFF_FIXTURES
        beforeDiagnosticCurrentnessCheck = { _ in }
        #endif
    }

    var stats: Stats {
        locked {
            Stats(counts: counts, sourceSequence: sourceSequence,
                  pendingDiagnostics: dirty ? 1 : 0, inFlightDiagnostics: inFlightDiagnostics,
                  scheduled: scheduled, scheduleCount: scheduleCount,
                  retainedPayloadBytes: pending.payloadBytes + inFlightPayloadBytes,
                  peakRetainedPayloadBytes: peakRetainedPayloadBytes)
        }
    }

    /// Diagnostic callbacks are short, synchronous observations, never ingestion or
    /// readiness authority. A consumer that suspends must recheck immediately before
    /// publishing. Revocation may race after the final sampled check; this relay
    /// cannot cancel a callback about to start or one that has already started.
    /// A newer source event also supersedes an older same-generation observation.
    func isCurrent(_ snapshot: Snapshot) -> Bool {
        guard snapshot.owner == owner, gate.isGenerationCurrent(snapshot.generation) else { return false }
        return locked { snapshot.generation == generation && snapshot.sourceSequence == sourceSequence }
    }

    @discardableResult
    func activate(session: LibreSensorSession, persistenceSessionID: UUID?) -> UInt64 {
        assertProducer()
        let next = gate.activate(session: session, persistenceSessionID: persistenceSessionID)
        ingestion.transportInvalidated() // Gate revocation has released its lock.
        publish {
            generation = next; transportActive = true; pending = Pending()
            increment(&counts.activations)
        }
        return next
    }

    func invalidate() {
        assertProducer()
        gate.invalidate()
        ingestion.transportInvalidated()
        let next = gate.currentGeneration
        publish {
            generation = next; transportActive = false; pending = Pending()
            increment(&counts.invalidations)
        }
    }

    /// Call at source BEFORE any asynchronous raw/verified relay. The nil payload
    /// case records a failed verification. Raw and plaintext must have exact wire
    /// sizes. Caller-owned arguments are transient; copied bounded buffers enter
    /// diagnostic retention only AFTER the synchronous canonical offer returns.
    @discardableResult
    func completeFrame(raw: Data, verifiedPayload: Data?, receivedAt: Date) -> Bool {
        assertProducer()
        guard raw.count == 46, verifiedPayload.map({ $0.count == 44 }) ?? true else {
            publish {
                increment(&counts.completedFrames); increment(&counts.invalidFrames)
                if raw.count > 46 { increment(&counts.oversizedRaw) }
                if let verifiedPayload, verifiedPayload.count > 44 { increment(&counts.oversizedVerified) }
                pending = Pending()
            }
            return false
        }
        guard let payload = verifiedPayload, Self.validCRC(payload) else {
            let copiedRaw = Data(Array(raw))
            publish {
                increment(&counts.completedFrames); increment(&counts.invalidFrames)
                pending.raw = RawObservation(data: copiedRaw, receivedAt: receivedAt,
                                             sourceSequence: sourceSequence, generation: generation)
                pending.verified = nil
            }
            return false
        }
        // Bound/copy plaintext before gate ownership; sliced Data must not retain
        // an arbitrary backing buffer. No diagnostic publication lies between
        // makeFrame and offer, and no closure containing this frame is dispatched.
        guard let frame = gate.makeFrame(payload: Data(Array(payload)), receivedAt: receivedAt) else {
            publish {
                increment(&counts.completedFrames); increment(&counts.verifiedFrames)
                increment(&counts.inactiveFrames); pending = Pending()
            }
            return false
        }
        let accepted = ingestion.offer(frame)
        if accepted {
            let copiedRaw = Data(Array(raw))
            publish {
                increment(&counts.completedFrames); increment(&counts.verifiedFrames)
                increment(&counts.canonicalAccepted)
                pending.raw = RawObservation(data: copiedRaw, receivedAt: receivedAt,
                                             sourceSequence: sourceSequence, generation: frame.generation)
                pending.verified = frame
            }
        } else {
            // Explicit diagnostic policy: retain no rejected completed frame body
            // or session snapshot. Counters describe undecoded frame rejection;
            // they never claim a number of missing/accepted glucose readings.
            publish {
                increment(&counts.completedFrames); increment(&counts.verifiedFrames)
                increment(&counts.canonicalRejected); pending = Pending()
            }
        }
        return accepted
    }

    func notification(data: Data, receivedAt: Date) {
        assertProducer()
        let byteCount = data.count // No body copy, slice, hex construction, or captured Data.
        publish {
            increment(&counts.notifications)
            if byteCount > 46 { increment(&counts.oversizedNotifications) }
            pending.notification = NotificationObservation(byteCount: byteCount,
                oversized: byteCount > 46, receivedAt: receivedAt,
                sourceSequence: sourceSequence, generation: generation)
        }
    }

    /// Preserve bounded categories for future integration. Specific Bluetooth
    /// states, session details and arbitrary error/log text are not relayed here.
    func control(_ category: DiagnosticCategory) {
        assertProducer()
        publish { counts.controls[category] = Self.add(counts.controls[category] ?? 0) }
    }

    private func assertProducer() { dispatchPrecondition(condition: .onQueue(producerQueue)) }

    /// Body is private synchronous state mutation, never a caller callback.
    private func publish(_ body: () -> Void) {
        let launch = locked {
            precondition(sourceSequence < UInt64.max)
            sourceSequence += 1
            if dirty { increment(&counts.coalescedUpdates) }
            body()
            dirty = true
            peakRetainedPayloadBytes = max(peakRetainedPayloadBytes,
                                           pending.payloadBytes + inFlightPayloadBytes)
            guard !scheduled else { return false }
            scheduled = true
            increment(&scheduleCount)
            return true
        }
        if launch { enqueueDrain() }
    }

    private func enqueueDrain() {
        // One coalesced signal captures only this bounded mailbox.
        schedule { [self] in
            let delivered = deliverOne()
            // deliverOne has returned and released its snapshot before a successor
            // can start. One callback per turn yields to unrelated delivery work.
            let again = locked {
                if let delivered {
                    if delivered { increment(&counts.delivered) } else { increment(&counts.suppressedStale) }
                    inFlightDiagnostics = 0; inFlightPayloadBytes = 0
                }
                if dirty { increment(&scheduleCount); return true }
                scheduled = false
                return false
            }
            if again { enqueueDrain() }
        }
    }

    private func deliverOne() -> Bool? {
        let snapshot: Snapshot? = locked {
            guard dirty else { return nil }
            let value = Snapshot(sourceSequence: sourceSequence, generation: generation,
                transportActive: transportActive, counts: counts, raw: pending.raw,
                verified: pending.verified, notification: pending.notification, owner: owner)
            inFlightDiagnostics = 1
            inFlightPayloadBytes = pending.payloadBytes
            pending = Pending(); dirty = false
            return value
        }
        guard let snapshot else { return nil }
        // Gate calls and consumer callbacks are NEVER made under the relay lock.
        #if LIBRE2_TRANSPORT_HANDOFF_FIXTURES
        beforeDiagnosticCurrentnessCheck(snapshot)
        #endif
        let current = isCurrent(snapshot)
        if current { onDiagnostics(snapshot) }
        return current
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private static func add(_ value: UInt64) -> UInt64 { value == .max ? .max : value + 1 }
    private func increment(_ value: inout UInt64) { value = Self.add(value) }

    /// Same 42-byte CRC domain and transmitted byte order as decryptFrame.
    private static func validCRC(_ payload: Data) -> Bool {
        let bytes = Array(payload)
        var crc: UInt16 = 0xFFFF
        for byte in bytes.prefix(42) {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1 }
        }
        var reversed: UInt16 = 0
        for _ in 0..<16 { reversed = (reversed << 1) | (crc & 1); crc >>= 1 }
        return reversed.byteSwapped == (UInt16(bytes[42]) << 8 | UInt16(bytes[43]))
    }

    #if LIBRE2_TRANSPORT_HANDOFF_FIXTURES
    /// Fixture scheduler must enqueue asynchronously, run each signal exactly once,
    /// and serialize executions. The immutable precheck observer runs outside all
    /// locks. There is no frame/result injection or adapter/store seam here.
    static func fixture(gate: LibreFrameGenerationGate, ingestion: LibreOrderedIngestion,
                        producerQueue: DispatchQueue,
                        schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                        beforeDiagnosticCurrentnessCheck: @escaping @Sendable (Snapshot) -> Void = { _ in },
                        onDiagnostics: @escaping @Sendable (Snapshot) -> Void) -> LibreTransportHandoff {
        LibreTransportHandoff(gate: gate, ingestion: ingestion, producerQueue: producerQueue,
                              schedule: schedule, beforeDiagnosticCurrentnessCheck: beforeDiagnosticCurrentnessCheck,
                              onDiagnostics: onDiagnostics)
    }

    private init(gate: LibreFrameGenerationGate, ingestion: LibreOrderedIngestion,
                 producerQueue: DispatchQueue,
                 schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                 beforeDiagnosticCurrentnessCheck: @escaping @Sendable (Snapshot) -> Void,
                 onDiagnostics: @escaping @Sendable (Snapshot) -> Void) {
        self.gate = gate; self.ingestion = ingestion; self.producerQueue = producerQueue
        self.schedule = schedule; self.onDiagnostics = onDiagnostics
        self.beforeDiagnosticCurrentnessCheck = beforeDiagnosticCurrentnessCheck
        generation = gate.currentGeneration
        transportActive = gate.activeGeneration != nil
    }
    #endif
}
