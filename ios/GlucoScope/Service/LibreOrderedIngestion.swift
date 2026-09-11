import Foundation

/// Engineering work bounds only; neither sample freshness nor decoder qualification.
enum LibreOrderedDiscardReason: String, CaseIterable, Sendable {
    case staleOwnership, residenceExpired, backlogFull, nonIncreasingSequence
    case unavailableStore, repairRequired, invariantFailure, flushedAfterStorageFailure
}

struct LibreOrderedFrameOutcome: Sendable {
    enum Disposition: Sendable {
        case completed, wholeFrameRejected, allSlotsRejected
        case discarded(LibreOrderedDiscardReason)
        case invariantFailure, repairRequired, storageFailure, durablePublicationFailure
    }
    let disposition: Disposition
    let acceptedCandidates: Int?
    let slotRejections: [String: Int]

    init(disposition: Disposition, acceptedCandidates: Int? = nil,
         slotRejections: [String: Int] = [:]) {
        self.disposition = disposition
        self.acceptedCandidates = acceptedCandidates
        self.slotRejections = slotRejections
    }
}

/// The adapter checks this before preparation, after each preparation suspension,
/// and immediately before guarded submission. The writer owns revocation after that.
struct LibreOrderedFrameContext: Sendable {
    private let gate: LibreFrameGenerationGate
    private let frame: LibreVerifiedFrame
    private let enqueuedAt: Double
    private let now: @Sendable () -> Double

    fileprivate init(gate: LibreFrameGenerationGate, frame: LibreVerifiedFrame,
                     enqueuedAt: Double, now: @escaping @Sendable () -> Double) {
        self.gate = gate
        self.frame = frame
        self.enqueuedAt = enqueuedAt
        self.now = now
    }

    func check() -> LibreOrderedDiscardReason? {
        guard gate.isCurrent(frame) else { return .staleOwnership }
        return now() - enqueuedAt > 120 ? .residenceExpired : nil
    }

    #if LIBRE2_ORDERED_INGESTION_FIXTURES
    static func fixture(gate: LibreFrameGenerationGate, frame: LibreVerifiedFrame,
                        enqueuedAt: Double = 0,
                        now: @escaping @Sendable () -> Double = { 0 }) -> Self {
        Self(gate: gate, frame: frame, enqueuedAt: enqueuedAt, now: now)
    }
    #endif
}

/// Disconnected canonical mailbox. The transport's serial producer must call offer
/// immediately after makeFrame, BEFORE dispatching anything that captures the frame.
/// This type is deliberately not connected to the existing diagnostic/main relay.
final class LibreOrderedIngestion: @unchecked Sendable {
    static let capacity = 8
    enum State: String, Sendable { case idle, opening, ready, unavailable, repair, invariant }
    enum Opportunity: Sendable { case foregroundEntry, deliberateReconnect }
    struct Snapshot: Sendable {
        var state: State = .idle
        var lastOfferedSequence: UInt64?
        var readyGeneration: UInt64?
        var retainedFrames = 0
        var peakRetainedFrames = 0
        var workerScheduled = false
        var wakeups: UInt64 = 0
        var completedFrames: UInt64 = 0
        var rejectedWholeFrames: UInt64 = 0
        var allSlotsRejectedFrames: UInt64 = 0
        var discardedFrames: [LibreOrderedDiscardReason: UInt64] = [:]
        var undecodedDiscardedFrames: UInt64 = 0
        var knownAcceptedCandidatesNotCommitted: UInt64 = 0
        var durablePublicationFailureFrames: UInt64 = 0
        var slotRejections: [String: UInt64] = [:]
        var recoveryAttempts = 0
        var operation = "idle"
        var updatedAt = Date()
    }
    private final class Item {
        let frame: LibreVerifiedFrame
        let enqueuedAt: Double
        let invalidationEpoch: UInt64
        #if LIBRE2_ORDERED_INGESTION_FIXTURES
        let references: ReferenceProbe?
        init(_ frame: LibreVerifiedFrame, _ enqueuedAt: Double, _ epoch: UInt64, _ references: ReferenceProbe?) {
            self.frame = frame; self.enqueuedAt = enqueuedAt; self.invalidationEpoch = epoch; self.references = references
            references?.retain()
        }
        deinit { references?.release() }
        #else
        init(_ frame: LibreVerifiedFrame, _ enqueuedAt: Double, _ epoch: UInt64) {
            self.frame = frame; self.enqueuedAt = enqueuedAt; self.invalidationEpoch = epoch
        }
        #endif
    }
    private enum Work { case open, recover(Bool), frame(Item) }
    private let lock = NSLock()
    private let gate: LibreFrameGenerationGate
    private let now: @Sendable () -> Double
    private let open: @Sendable () async throws -> Void
    private let recover: @Sendable () async throws -> Void
    private let refetch: @Sendable () async throws -> Void
    private let process: @Sendable (LibreVerifiedFrame, LibreOrderedFrameContext) async -> LibreOrderedFrameOutcome
    private var status = Snapshot()
    private var pending: [Item] = []
    private var active = false
    private var invalidationEpoch: UInt64 = 0
    private var requestedWork: Work?
    private var requiresRefetch = false
    private var repairGeneration: UInt64?
    #if LIBRE2_ORDERED_INGESTION_FIXTURES
    private var references: ReferenceProbe?
    private var afterFrameCompletion: @Sendable () async -> Void = {}
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    #endif

    convenience init(adapter: LibreCandidateAdapter, gate: LibreFrameGenerationGate) {
        let origin = ContinuousClock.now
        self.init(gate: gate, now: {
            let duration = origin.duration(to: ContinuousClock.now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        }, open: { try await adapter.open() }, recover: { try await adapter.recover() },
           refetch: { try await adapter.refetchCommitted() },
           process: { await adapter.process($0, context: $1) })
    }

    private init(gate: LibreFrameGenerationGate, now: @escaping @Sendable () -> Double,
                 open: @escaping @Sendable () async throws -> Void,
                 recover: @escaping @Sendable () async throws -> Void,
                 refetch: @escaping @Sendable () async throws -> Void,
                 process: @escaping @Sendable (LibreVerifiedFrame, LibreOrderedFrameContext) async -> LibreOrderedFrameOutcome) {
        self.gate = gate; self.now = now; self.open = open; self.recover = recover
        self.refetch = refetch; self.process = process
    }

    var snapshot: Snapshot { locked { status } }

    func start() {
        let launch = locked {
            guard status.state == .idle else { return false }
            status.state = .opening
            requestedWork = .open
            return reserveWorker()
        }
        launchWorker(if: launch)
    }

    /// Returns synchronously without retaining rejected payloads or dispatching a
    /// per-offer closure. Even state/overflow rejection advances current high water.
    @discardableResult
    func offer(_ frame: LibreVerifiedFrame) -> Bool {
        let current = gate.isCurrent(frame) // Never acquire the generation gate under mailbox lock.
        let instant = now()
        var launch = false
        let accepted = locked {
            guard current else { discard(.staleOwnership); return false }
            guard status.lastOfferedSequence.map({ frame.sequence > $0 }) ?? true else {
                discard(.nonIncreasingSequence); return false
            }
            status.lastOfferedSequence = frame.sequence
            guard status.state == .ready else {
                discard(status.state == .repair ? .repairRequired :
                        status.state == .invariant ? .invariantFailure : .unavailableStore)
                return false
            }
            guard status.retainedFrames < Self.capacity else { discard(.backlogFull); return false }
            #if LIBRE2_ORDERED_INGESTION_FIXTURES
            pending.append(Item(frame, instant, invalidationEpoch, references))
            #else
            pending.append(Item(frame, instant, invalidationEpoch))
            #endif
            status.retainedFrames += 1
            status.peakRetainedFrames = max(status.peakRetainedFrames, status.retainedFrames)
            launch = reserveWorker()
            return true
        }
        launchWorker(if: launch)
        return accepted
    }

    /// Caller MUST revoke/activate the gate first, then call this after releasing
    /// the gate lock. A suspended active item keeps its reservation and worker.
    func transportInvalidated() {
        locked {
            invalidationEpoch = plus(invalidationEpoch, 1)
            purge(.staleOwnership)
            status.readyGeneration = nil
        }
    }

    /// Only deliberate successful supported repair followed by a fresh activation
    /// may resume repair; lifecycle opportunities never clear a repair/invariant.
    func repairSucceededAndActivated() {
        let generation = gate.activeGeneration
        locked {
            guard status.state == .repair, !active,
                  let generation, generation != repairGeneration else { return }
            // A completed frame may still have its sole drain scheduled. That
            // worker can pick up new offers; the one-shot repair must not be lost.
            status.state = .ready
            repairGeneration = nil
        }
    }

    func lifecycleOpportunity(_ opportunity: Opportunity) {
        let launch = locked {
            guard status.state == .unavailable, !status.workerScheduled,
                  status.recoveryAttempts < 3 else { return false }
            status.recoveryAttempts += 1
            status.state = .opening
            requestedWork = .recover(requiresRefetch)
            return reserveWorker()
        }
        launchWorker(if: launch)
    }

    private func reserveWorker() -> Bool {
        guard !status.workerScheduled else { return false }
        status.workerScheduled = true
        status.wakeups = plus(status.wakeups, 1)
        return true
    }

    private func launchWorker(if launch: Bool) {
        guard launch else { return }
        // Exactly one coalesced signal captures only the mailbox, never an offer.
        Task { await self.drain() }
    }

    private func takeWork() -> Work? {
        locked {
            if let work = requestedWork { requestedWork = nil; return work }
            guard status.state == .ready, !pending.isEmpty else { return nil }
            active = true
            status.operation = "prepare"
            status.updatedAt = Date()
            return .frame(pending.removeFirst())
        }
    }

    private func drain() async {
        while true {
            var work = takeWork()
            guard work != nil else {
                // Recheck under the lock: an offer may have raced takeWork's nil.
                let done = locked {
                    guard requestedWork == nil, pending.isEmpty else { return false }
                    status.workerScheduled = false
                    return true
                }
                if done {
                    #if LIBRE2_ORDERED_INGESTION_FIXTURES
                    resumeIdleWaiters()
                    #endif
                    return
                }
                continue
            }
            var completion: (outcome: LibreOrderedFrameOutcome, generation: UInt64, current: Bool, epoch: UInt64)?
            switch work! {
            case .open:
                do { try await open(); storeRecovered() }
                catch { storeUnavailable() }
                work = nil
            case .recover(let needsRefetch):
                do {
                    try await recover()
                    if needsRefetch { try await refetch() }
                    storeRecovered()
                } catch { storeUnavailable() }
                work = nil
            case .frame:
                // The helper's entire frame/context lifetime ends before releasing
                // its reservation, so the next source offer cannot create a ninth.
                completion = await processWork(work!)
            }
            work = nil
            if let result = completion {
                finish(result.outcome, generation: result.generation, current: result.current, epoch: result.epoch)
                #if LIBRE2_ORDERED_INGESTION_FIXTURES
                await afterFrameCompletion()
                #endif
            }
        }
    }

    private func processWork(_ work: Work) async -> (outcome: LibreOrderedFrameOutcome, generation: UInt64, current: Bool, epoch: UInt64) {
        guard case .frame(let item) = work else { preconditionFailure() }
        let context = LibreOrderedFrameContext(gate: gate, frame: item.frame,
                                              enqueuedAt: item.enqueuedAt, now: now)
        let outcome: LibreOrderedFrameOutcome
        if let reason = context.check() { outcome = .init(disposition: .discarded(reason)) }
        else { outcome = await process(item.frame, context) }
        return (outcome, item.frame.generation, gate.isCurrent(item.frame), item.invalidationEpoch)
    }

    private func finish(_ outcome: LibreOrderedFrameOutcome, generation: UInt64, current: Bool, epoch: UInt64) {
        locked {
            active = false
            status.retainedFrames -= 1
            for (reason, count) in outcome.slotRejections where Libre2SlotRejectionReason(rawValue: reason) != nil {
                status.slotRejections[reason] = plus(status.slotRejections[reason] ?? 0, UInt64(max(0, count)))
            }
            var uncommitted = true
            switch outcome.disposition {
            case .completed:
                status.completedFrames = plus(status.completedFrames, 1)
                // No cached readiness is published: invalidation can happen between
                // the outside-lock check and this lock. Runtime readiness needs its
                // own generation-aware consumer, not a mutable completion flag.
                uncommitted = false
            case .wholeFrameRejected: status.rejectedWholeFrames = plus(status.rejectedWholeFrames, 1)
            case .allSlotsRejected: status.allSlotsRejectedFrames = plus(status.allSlotsRejectedFrames, 1)
            case .discarded(let reason): discard(reason, undecoded: outcome.acceptedCandidates == nil)
            case .invariantFailure:
                discard(.invariantFailure, undecoded: outcome.acceptedCandidates == nil)
                status.state = .invariant
                purge(.invariantFailure)
            case .repairRequired:
                if current && epoch == invalidationEpoch {
                    discard(.repairRequired, undecoded: outcome.acceptedCandidates == nil)
                    status.state = .repair
                    repairGeneration = generation
                    purge(.repairRequired)
                } else { discard(.staleOwnership, undecoded: outcome.acceptedCandidates == nil) }
            case .storageFailure:
                discard(.unavailableStore, undecoded: outcome.acceptedCandidates == nil)
                status.state = .unavailable
                purge(.flushedAfterStorageFailure)
            case .durablePublicationFailure:
                status.durablePublicationFailureFrames = plus(status.durablePublicationFailureFrames, 1)
                uncommitted = false
                requiresRefetch = true
                status.state = .unavailable
                purge(.flushedAfterStorageFailure)
            }
            if uncommitted, let count = outcome.acceptedCandidates {
                status.knownAcceptedCandidatesNotCommitted = plus(status.knownAcceptedCandidatesNotCommitted, UInt64(max(0, count)))
            }
            status.operation = status.state == .ready ? "waiting" : status.state.rawValue
            status.updatedAt = Date()
        }
    }

    private func storeRecovered() {
        locked { status.state = .ready; requiresRefetch = false; status.operation = "waiting"; status.updatedAt = Date() }
    }
    private func storeUnavailable() {
        locked { status.state = .unavailable; purge(.flushedAfterStorageFailure); status.operation = "storage"; status.updatedAt = Date() }
    }
    private func purge(_ reason: LibreOrderedDiscardReason) {
        let count = pending.count
        pending.removeAll(keepingCapacity: true)
        status.retainedFrames -= count
        status.undecodedDiscardedFrames = plus(status.undecodedDiscardedFrames, UInt64(count))
        status.discardedFrames[reason] = plus(status.discardedFrames[reason] ?? 0, UInt64(count))
    }
    private func discard(_ reason: LibreOrderedDiscardReason, undecoded: Bool = true) {
        if undecoded { status.undecodedDiscardedFrames = plus(status.undecodedDiscardedFrames, 1) }
        status.discardedFrames[reason] = plus(status.discardedFrames[reason] ?? 0, 1)
    }
    private func plus(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    #if LIBRE2_ORDERED_INGESTION_FIXTURES
    /// Fixture telemetry observes actual item lifetimes, independent of counters.
    final class ReferenceProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var live = 0
        private var peak = 0
        fileprivate func retain() { lock.lock(); live += 1; peak = max(peak, live); lock.unlock() }
        fileprivate func release() { lock.lock(); live -= 1; lock.unlock() }
        var counts: (live: Int, peak: Int) { lock.lock(); defer { lock.unlock() }; return (live, peak) }
    }
    static func fixture(gate: LibreFrameGenerationGate, now: @escaping @Sendable () -> Double = { 0 },
                        references: ReferenceProbe? = nil,
                        afterFrameCompletion: @escaping @Sendable () async -> Void = {},
                        open: @escaping @Sendable () async throws -> Void = {},
                        recover: @escaping @Sendable () async throws -> Void = {},
                        refetch: @escaping @Sendable () async throws -> Void = {},
                        process: @escaping @Sendable (LibreVerifiedFrame, LibreOrderedFrameContext) async -> LibreOrderedFrameOutcome) -> LibreOrderedIngestion {
        let mailbox = LibreOrderedIngestion(gate: gate, now: now, open: open, recover: recover, refetch: refetch, process: process)
        mailbox.references = references
        mailbox.afterFrameCompletion = afterFrameCompletion
        return mailbox
    }
    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            let immediate = locked {
                if !status.workerScheduled { return true }
                idleWaiters.append(continuation)
                return false
            }
            if immediate { continuation.resume() }
        }
    }
    private func resumeIdleWaiters() {
        let waiters: [CheckedContinuation<Void, Never>] = locked {
            guard !status.workerScheduled else { return [] }
            let result = idleWaiters; idleWaiters.removeAll(); return result
        }
        for waiter in waiters { waiter.resume() }
    }
    #endif
}
