import Foundation

/// Metadata-only foundation. This type deliberately has no decoder, candidate, or
/// reading submission dependency. Experimental calculations never enter the store.
@MainActor
final class LibreCollectionCoordinator {
    struct Status: Equatable, Sendable {
        var summary = "Storage not opened"
        var operation = "idle"
        var updatedAt = Date()
        var staleFrameCount = 0
        var lastSequence: UInt64?
        var readyGeneration: UInt64?
        let droppedCandidateCount = 0
        let canonicalIngestionEnabled = false
    }

    private(set) var status = Status()
    private(set) var isWorking = false
    private let gate: LibreFrameGenerationGate
    private let openStore: () async throws -> Void
    private let prepareSession: (LibreVerifiedFrame) async throws -> Void
    private let onStatus: (Status) -> Void
    private var loaded = false
    private var metadataFailed = false
    private var openRequested = false
    private var retryCount = 0
    private var pending: LibreVerifiedFrame?
    private var lastPublishedSummary = ""
    private var lastPublishedOperation = ""
    private var attemptedGeneration: UInt64?

    init(gate: LibreFrameGenerationGate,
         openStore: @escaping () async throws -> Void,
         prepareSession: @escaping (LibreVerifiedFrame) async throws -> Void,
         onStatus: @escaping (Status) -> Void = { _ in }) {
        self.gate = gate
        self.openStore = openStore
        self.prepareSession = prepareSession
        self.onStatus = onStatus
    }

    func start() {
        guard !loaded, !isWorking, status.operation == "idle" else { return }
        openRequested = true
        startWorker()
    }

    /// One bounded retry opportunity on foreground entry or deliberate reconnect.
    /// There is no timer and frames cannot trigger repeated failed store opens.
    func lifecycleOpportunity() {
        guard !isWorking else { return }
        if !loaded || metadataFailed {
            guard retryCount < 3 else { return }
            retryCount += 1
            openRequested = true
        }
        attemptedGeneration = nil
        startWorker()
    }

    /// The return value gates synchronous experimental decoding by the caller.
    /// Metadata preparation is separate and can never promote those calculations.
    func receive(_ frame: LibreVerifiedFrame) -> Bool {
        guard gate.isCurrent(frame), frame.sequence > (status.lastSequence ?? 0) else {
            status.staleFrameCount += 1
            publish()
            return false
        }
        status.lastSequence = frame.sequence
        if status.readyGeneration != frame.generation {
            status.readyGeneration = nil
            if frame.persistenceSessionID == nil {
                status.summary = "Wear identity unavailable; experimental diagnostics only"
                status.operation = "identity"
            } else if attemptedGeneration != frame.generation {
                // At most one in-flight preparation and one replaceable pending frame.
                pending = frame
                startWorker()
            }
        }
        publish()
        return true
    }

    func transportInvalidated() {
        pending = nil
        status.readyGeneration = nil
        if loaded { status.summary = "Storage open; waiting for current sensor metadata" }
        publish()
    }

    private func startWorker() {
        guard !isWorking, openRequested || (loaded && pending != nil) else { return }
        isWorking = true
        Task { await runWorker() }
    }

    private func runWorker() async {
        if openRequested {
            openRequested = false
            status.operation = "load"
            status.summary = "Opening protected reading storage"
            publish()
            do {
                try await openStore()
                loaded = true
                metadataFailed = false
                status.summary = "Storage open; waiting for current sensor metadata"
            } catch {
                loaded = false
                status.summary = "Storage unavailable (load failed); experimental diagnostics only"
                pending = nil
            }
            publish()
        }
        while loaded, let frame = pending {
            pending = nil
            guard gate.isCurrent(frame) else { continue }
            attemptedGeneration = frame.generation
            status.operation = "bridge"
            status.summary = "Reconciling sensor metadata"
            publish()
            do {
                try await prepareSession(frame)
                guard gate.isCurrent(frame) else { continue }
                metadataFailed = false
                status.readyGeneration = frame.generation
                status.summary = "Sensor metadata ready; canonical ingestion disabled"
            } catch {
                guard gate.isCurrent(frame) else { continue }
                metadataFailed = true
                status.readyGeneration = nil
                // Underlying descriptions can contain pairing material or paths.
                status.summary = "Sensor metadata unavailable (bridge failed); experimental diagnostics only"
            }
            publish()
        }
        isWorking = false
    }

    private func publish() {
        if status.summary != lastPublishedSummary || status.operation != lastPublishedOperation {
            status.updatedAt = Date()
            lastPublishedSummary = status.summary
            lastPublishedOperation = status.operation
        }
        onStatus(status)
    }
}
