import Foundation

/// App-owned composition of the protected store, candidate adapter and bounded
/// ordered ingestion worker. Transport offers frames directly to `ingestion`.
@MainActor
final class LibreCollectionCoordinator {
    private struct NFCHistoryDecodeError: LocalizedError {
        let rejection: Libre2NFCHistoryRejection
        var errorDescription: String? { "Sensor history was rejected (\(rejection.rawValue))." }
    }

    struct NFCHistorySaveResult: Equatable, Sendable {
        let trendCount: Int
        let historyCount: Int
        let rejectedCount: Int
        let insertedCount: Int
        let oldestSampleDate: Date?
        let newestSampleDate: Date?
    }

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
    private let bridge: LibrePersistenceBridge
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
        self.bridge = bridge
        self.adapter = LibreCandidateAdapter(readingStore: readingStore, bridge: bridge, gate: gate)
        self.onStatus = onStatus
    }

    func start() { ingestion.start() }

    func lifecycleOpportunity(_ opportunity: LibreOrderedIngestion.Opportunity = .foregroundEntry) {
        ingestion.lifecycleOpportunity(opportunity)
    }

    /// A deliberate bounded NFC import shares SQLite deduplication and the saved
    /// sensor clock with BLE. It never changes the paired sensor or transport.
    func saveNFCHistory(
        fram: Data, pairedSession: LibreSensorSession, receivedAt: Date,
        isCurrent: @escaping () -> Bool
    ) async throws -> NFCHistorySaveResult {
        guard isCurrent() else { throw LibrePersistenceBridgeError.staleSession }
        let prepared = try await bridge.prepareCandidates(
            session: pairedSession, receivedAt: receivedAt
        )
        guard isCurrent() else { throw LibrePersistenceBridgeError.staleSession }
        let decoded = Libre2NFCHistoryDecoder.decode(
            fram: fram, pairedSession: pairedSession,
            session: prepared.sessionSnapshot, receivedAt: receivedAt
        )
        if let rejection = decoded.rejection { throw NFCHistoryDecodeError(rejection: rejection) }
        var candidates: [ReadingCandidate] = []
        var rejected = 0
        var sampleDates: [Date] = []
        for sample in decoded.samples {
            switch sample.outcome {
            case .accepted(let slot):
                sampleDates.append(slot.timestamp)
                candidates.append(ReadingCandidate(
                    sensorMinute: Int64(slot.sensorMinute),
                    kind: sample.kind == .trend ? .trend : .history15Minute,
                    receivedAt: receivedAt, glucoseMGDL: slot.glucoseMGDL,
                    quality: slot.quality,
                    origin: sample.kind == .trend ? .nfcTrend : .nfcHistory,
                    decoderVersion: slot.decoderVersion
                ))
            case .rejected: rejected += 1
            }
        }
        guard isCurrent() else { throw LibrePersistenceBridgeError.staleSession }
        // Submission sequence is informational in the common store. NFC does
        // not consume or reset the BLE process sequence.
        let commit = try await readingStore.ingest(ReadingSubmission(
            sequence: 0, session: prepared.sessionSnapshot, candidates: candidates
        ))
        refreshSavedReadings()
        return NFCHistorySaveResult(
            trendCount: candidates.filter { $0.kind == .trend }.count,
            historyCount: candidates.filter { $0.kind == .history15Minute }.count,
            rejectedCount: rejected, insertedCount: commit.readingIDs.count,
            oldestSampleDate: sampleDates.min(), newestSampleDate: sampleDates.max()
        )
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
