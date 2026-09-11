import Foundation

/// App-owned composition of the protected store, candidate adapter and bounded
/// ordered ingestion worker. Transport offers frames directly to `ingestion`.
@MainActor
final class LibreCollectionCoordinator {
    struct Status: Equatable, Sendable {
        var summary = "Storage not opened"
        var operation = "idle"
        var updatedAt = Date()
        var staleFrameCount: UInt64 = 0
        var lastSequence: UInt64?
        var queuedFrames = 0
        var completedFrames: UInt64 = 0
        var rejectedFrames: UInt64 = 0
        var discardedFrames: UInt64 = 0
        var droppedCandidateCount: UInt64 = 0
        let canonicalIngestionEnabled = true
        var recentReadings: [StoredReadingSnapshot] = []
        var savedReadingsStatus = "Waiting for storage"
    }

    private(set) var status = Status()
    private let gate: LibreFrameGenerationGate
    private let adapter: LibreCandidateAdapter
    private let readingStore: ReadingStore
    private var isRefreshingReadings = false
    private var refreshRequested = false
    private var lastCompletedFrames: UInt64?
    private var lastRecoveryAttempt = 0
    private var lastStoreWasReady = false
    private let onStatus: (Status) -> Void
    lazy var ingestion = LibreOrderedIngestion(adapter: adapter, gate: gate) { [weak self] snapshot in
        MainActor.assumeIsolated { self?.receive(snapshot) }
    }
    var isWorking: Bool { ingestion.snapshot.workerScheduled || isRefreshingReadings }

    init(gate: LibreFrameGenerationGate, readingStore: ReadingStore,
         bridge: LibrePersistenceBridge, onStatus: @escaping (Status) -> Void = { _ in }) {
        self.gate = gate
        self.readingStore = readingStore
        self.adapter = LibreCandidateAdapter(readingStore: readingStore, bridge: bridge, gate: gate)
        self.onStatus = onStatus
    }

    func start() { ingestion.start() }

    func lifecycleOpportunity(_ opportunity: LibreOrderedIngestion.Opportunity = .foregroundEntry) {
        ingestion.lifecycleOpportunity(opportunity)
    }

    private func receive(_ snapshot: LibreOrderedIngestion.Snapshot) {
        status.operation = snapshot.operation
        status.updatedAt = snapshot.updatedAt
        status.lastSequence = snapshot.lastOfferedSequence
        status.queuedFrames = snapshot.retainedFrames
        status.completedFrames = snapshot.completedFrames
        status.rejectedFrames = snapshot.rejectedWholeFrames + snapshot.allSlotsRejectedFrames
        status.discardedFrames = snapshot.undecodedDiscardedFrames
        status.staleFrameCount = snapshot.discardedFrames[.staleOwnership, default: 0]
            + snapshot.discardedFrames[.nonIncreasingSequence, default: 0]
        status.droppedCandidateCount = snapshot.knownAcceptedCandidatesNotCommitted
        switch snapshot.state {
        case .idle: status.summary = "Storage not opened"
        case .opening: status.summary = "Opening protected reading storage"
        case .ready:
            status.summary = "Storage open; saving experimental readings"
        case .unavailable:
            status.summary = "Reading storage unavailable; incoming frames are discarded"
        case .repair:
            status.summary = "Sensor metadata requires repair; incoming frames are discarded"
        case .invariant:
            status.summary = "Reading ingestion stopped after an internal consistency failure"
        }
        let ready = snapshot.state == .ready
        if ready && (!lastStoreWasReady || lastCompletedFrames != snapshot.completedFrames ||
                     lastRecoveryAttempt != snapshot.recoveryAttempts) {
            refreshSavedReadings()
        }
        lastStoreWasReady = ready
        lastCompletedFrames = snapshot.completedFrames
        lastRecoveryAttempt = snapshot.recoveryAttempts
        onStatus(status)
    }

    /// One running query plus a coalesced request, never one task per frame.
    /// The displayed values originate exclusively in committed SQLite records.
    private func refreshSavedReadings() {
        refreshRequested = true
        guard !isRefreshingReadings else { return }
        isRefreshingReadings = true
        Task { [self] in
            while refreshRequested {
                refreshRequested = false
                do {
                    let readings = try await readingStore.recentReadings(limit: 15)
                    status.recentReadings = readings
                    status.savedReadingsStatus = readings.isEmpty
                        ? "No saved readings yet" : "Latest \(readings.count) saved readings"
                } catch {
                    status.savedReadingsStatus = "Saved readings could not be loaded"
                }
                onStatus(status)
            }
            isRefreshingReadings = false
        }
    }
}
