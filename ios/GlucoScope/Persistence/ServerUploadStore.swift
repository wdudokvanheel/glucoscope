import Foundation

actor ServerUploadStore {
    private struct State: Codable {
        var schemaVersion = 1
        var destinations: [ServerUploadDestination] = []
        var deliveries: [ServerUploadDelivery] = []
        var attempts: [ServerUploadAttempt] = []
    }

    private let fileURL: URL
    private let logRetention: TimeInterval
    private var state = State()
    private var loaded = false

    init(fileURL: URL, logRetention: TimeInterval = 30 * 24 * 60 * 60) {
        self.fileURL = fileURL
        self.logRetention = logRetention
    }

    func load(now: Date = Date()) throws {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                state = try JSONDecoder().decode(State.self, from: data)
            } catch {
                throw ServerUploadError.persistence("Upload state could not be decoded")
            }
        }
        // A process can disappear during a request. The remote outcome is unknown,
        // so retry with the same stable reading identity and endpoint revision.
        for index in state.deliveries.indices where state.deliveries[index].state == .sending {
            state.deliveries[index].state = .queued
            state.deliveries[index].nextEligibleAt = nil
            appendAttempt(
                destinationID: state.deliveries[index].destinationID,
                readingID: state.deliveries[index].readingID,
                endpointRevision: state.deliveries[index].endpointRevision,
                outcome: .interrupted,
                message: "Previous send was interrupted; queued for an idempotent retry",
                now: now
            )
        }
        pruneLogs(now: now)
        loaded = true
        try persist()
    }

    func snapshot() -> ServerUploadSnapshot {
        ServerUploadSnapshot(
            destinations: state.destinations,
            deliveries: state.deliveries.sorted(by: Self.deliveryOrder),
            attempts: state.attempts.sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    func performMaintenance(now: Date = Date()) throws {
        let previousCount = state.attempts.count
        pruneLogs(now: now)
        if state.attempts.count != previousCount { try persist() }
    }

    func addDestination(
        name: String,
        backend: ServerUploadBackend,
        endpoint: String,
        credentialReference: String,
        now: Date = Date()
    ) throws -> ServerUploadDestination {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ServerUploadError.invalidName }
        let destination = ServerUploadDestination(
            id: UUID(),
            name: String(trimmedName.prefix(80)),
            backend: backend,
            endpoint: try ServerUploadEndpoint.normalize(endpoint),
            credentialReference: credentialReference,
            endpointRevision: 1,
            enabled: true,
            paused: false,
            createdAt: now,
            automaticUploadSince: now,
            disabledAt: nil
        )
        state.destinations.append(destination)
        try persist()
        return destination
    }

    func updateCredentialReference(destinationID: UUID, reference: String, name: String) throws {
        guard let index = destinationIndex(destinationID) else {
            throw ServerUploadError.destinationNotFound
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServerUploadError.invalidName }
        state.destinations[index].name = String(trimmed.prefix(80))
        state.destinations[index].credentialReference = reference
        try persist()
    }

    func migrateDestination(
        destinationID: UUID,
        name: String,
        backend: ServerUploadBackend,
        endpoint: String,
        credentialReference: String,
        transferPending: Bool,
        backfill: ServerUploadHistorySelection?,
        readings: [StoredReadingSnapshot],
        now: Date = Date()
    ) throws {
        guard let index = destinationIndex(destinationID) else {
            throw ServerUploadError.destinationNotFound
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ServerUploadError.invalidName }
        let normalized = try ServerUploadEndpoint.normalize(endpoint)
        let oldRevision = state.destinations[index].endpointRevision
        let pending = state.deliveries.filter {
            $0.destinationID == destinationID &&
            $0.endpointRevision == oldRevision &&
            $0.state != .acknowledged
        }
        let pendingIDs = Set(pending.map(\.readingID))

        // Queued old-address work is explicitly retired. An in-flight request may
        // finish; its eventual acknowledgement remains attributed to oldRevision.
        discard(
            destinationID: destinationID,
            where: { $0.endpointRevision == oldRevision && $0.state != .acknowledged },
            reason: transferPending ? "Pending work transferred to edited address" : "Pending work declined for edited address",
            now: now
        )
        state.destinations[index].name = String(trimmedName.prefix(80))
        state.destinations[index].backend = backend
        state.destinations[index].endpoint = normalized
        state.destinations[index].credentialReference = credentialReference
        state.destinations[index].endpointRevision += 1
        state.destinations[index].automaticUploadSince = now
        let newRevision = state.destinations[index].endpointRevision

        if transferPending {
            enqueue(
                readings: readings.filter { pendingIDs.contains($0.id) },
                destinationID: destinationID,
                endpointRevision: newRevision,
                kind: .migratedPending,
                now: now
            )
        }
        if let backfill {
            enqueue(
                readings: filter(readings, selection: backfill),
                destinationID: destinationID,
                endpointRevision: newRevision,
                kind: .migrationBackfill,
                now: now
            )
        }
        try persist()
    }

    func removeDestination(_ destinationID: UUID, now: Date = Date()) throws {
        guard destinationIndex(destinationID) != nil else {
            throw ServerUploadError.destinationNotFound
        }
        discard(destinationID: destinationID, where: { $0.state != .acknowledged }, reason: "Destination removed", now: now)
        state.destinations.removeAll { $0.id == destinationID }
        state.deliveries.removeAll { $0.destinationID == destinationID }
        try persist()
    }

    func setEnabled(
        _ enabled: Bool,
        destinationID: UUID,
        catchUpFrom: Date?,
        readings: [StoredReadingSnapshot],
        now: Date = Date()
    ) throws {
        guard let index = destinationIndex(destinationID) else {
            throw ServerUploadError.destinationNotFound
        }
        if !enabled {
            if state.destinations[index].enabled {
                state.destinations[index].disabledAt = now
            }
            state.destinations[index].enabled = false
        } else {
            let disabledAt = state.destinations[index].disabledAt
            state.destinations[index].enabled = true
            state.destinations[index].automaticUploadSince = now
            state.destinations[index].disabledAt = nil
            if let disabledAt, let selected = catchUpFrom {
                let lowerBound = max(disabledAt, selected)
                enqueue(
                    readings: readings.filter { $0.createdAt >= lowerBound && $0.createdAt <= now },
                    destinationID: destinationID,
                    endpointRevision: state.destinations[index].endpointRevision,
                    kind: .disabledCatchUp,
                    now: now
                )
            }
        }
        try persist()
    }

    func setPaused(_ paused: Bool, destinationID: UUID) throws {
        guard let index = destinationIndex(destinationID) else {
            throw ServerUploadError.destinationNotFound
        }
        state.destinations[index].paused = paused
        try persist()
    }

    func reconcileNewReadings(_ readings: [StoredReadingSnapshot], now: Date = Date()) throws {
        for destination in state.destinations where destination.enabled {
            enqueue(
                readings: readings.filter { $0.createdAt >= destination.automaticUploadSince },
                destinationID: destination.id,
                endpointRevision: destination.endpointRevision,
                kind: .newReading,
                now: now
            )
        }
        try persist()
    }

    func enqueueHistory(
        destinationID: UUID,
        selection: ServerUploadHistorySelection,
        readings: [StoredReadingSnapshot],
        now: Date = Date()
    ) throws {
        guard let destination = state.destinations.first(where: { $0.id == destinationID }) else {
            throw ServerUploadError.destinationNotFound
        }
        enqueue(
            readings: filter(readings, selection: selection),
            destinationID: destinationID,
            endpointRevision: destination.endpointRevision,
            kind: .history,
            now: now
        )
        try persist()
    }

    func nextDelivery(destinationID: UUID, now: Date = Date()) throws -> ServerUploadDelivery? {
        guard let destination = state.destinations.first(where: { $0.id == destinationID }) else {
            throw ServerUploadError.destinationNotFound
        }
        guard destination.enabled, !destination.paused else { return nil }
        guard let index = state.deliveries.indices
            .filter({
                let item = state.deliveries[$0]
                return item.destinationID == destinationID &&
                    item.endpointRevision == destination.endpointRevision &&
                    (item.state == .queued || item.state == .failed) &&
                    (item.nextEligibleAt == nil || item.nextEligibleAt! <= now)
            })
            .sorted(by: { Self.deliveryOrder(state.deliveries[$0], state.deliveries[$1]) })
            .first else { return nil }
        state.deliveries[index].state = .sending
        state.deliveries[index].attemptCount += 1
        state.deliveries[index].nextEligibleAt = nil
        try persist()
        return state.deliveries[index]
    }

    func complete(
        deliveryID: UUID,
        result: Result<Int, ServerUploadError>,
        secrets: [String] = [],
        now: Date = Date()
    ) throws {
        guard let index = state.deliveries.firstIndex(where: { $0.id == deliveryID }) else {
            // Clear can remove queued rows, but deliberately retains an in-flight row.
            return
        }
        let delivery = state.deliveries[index]
        switch result {
        case .success(let code):
            appendAttempt(
                destinationID: delivery.destinationID,
                readingID: delivery.readingID,
                endpointRevision: delivery.endpointRevision,
                outcome: .succeeded,
                responseCode: code,
                message: "Reading accepted",
                now: now
            )
            state.deliveries[index].state = .acknowledged
            state.deliveries[index].acknowledgedAt = now
            state.deliveries[index].lastError = nil
        case .failure(let error):
            let redacted = ServerUploadRedactor.message(error.localizedDescription, secrets: secrets)
            appendAttempt(
                destinationID: delivery.destinationID,
                readingID: delivery.readingID,
                endpointRevision: delivery.endpointRevision,
                outcome: .failed,
                message: redacted,
                now: now
            )
            state.deliveries[index].state = .failed
            state.deliveries[index].lastError = redacted
            let exponent = min(6, max(0, state.deliveries[index].attemptCount - 1))
            state.deliveries[index].nextEligibleAt = now.addingTimeInterval(pow(2, Double(exponent)) * 60)
        }
        if state.deliveries[index].discardAfterAttempt {
            appendAttempt(
                destinationID: delivery.destinationID,
                readingID: delivery.readingID,
                endpointRevision: delivery.endpointRevision,
                outcome: .cancelled,
                message: "Queue removal took effect after the in-flight request completed",
                now: now
            )
            state.deliveries.remove(at: index)
        }
        pruneLogs(now: now)
        try persist()
    }

    func retryFailures(destinationID: UUID) throws {
        guard let destination = state.destinations.first(where: { $0.id == destinationID }) else {
            throw ServerUploadError.destinationNotFound
        }
        guard destination.enabled else { throw ServerUploadError.destinationDisabled }
        for index in state.deliveries.indices where
            state.deliveries[index].destinationID == destinationID &&
            state.deliveries[index].state == .failed {
            state.deliveries[index].state = .queued
            state.deliveries[index].nextEligibleAt = nil
        }
        try persist()
    }

    /// Cancels only bulk/backfill work. Live new-reading deliveries remain queued.
    func cancelRemainingBulk(destinationID: UUID, now: Date = Date()) throws {
        discard(
            destinationID: destinationID,
            where: { $0.batchKind.isBulk && $0.state != .acknowledged },
            reason: "Remaining history upload cancelled",
            now: now
        )
        try persist()
    }

    /// Removes all pending work. A request already in flight records its outcome,
    /// then its delivery row is removed; remote writes cannot be undone.
    func clearQueue(destinationID: UUID, now: Date = Date()) throws {
        discard(
            destinationID: destinationID,
            where: { $0.state != .acknowledged },
            reason: "Upload queue cleared",
            now: now
        )
        try persist()
    }

    private func destinationIndex(_ id: UUID) -> Int? {
        state.destinations.firstIndex { $0.id == id }
    }

    private func filter(
        _ readings: [StoredReadingSnapshot],
        selection: ServerUploadHistorySelection
    ) -> [StoredReadingSnapshot] {
        switch selection {
        case .allAvailable: return readings
        case .since(let date): return readings.filter { $0.sampleDate >= date }
        }
    }

    private func enqueue(
        readings: [StoredReadingSnapshot],
        destinationID: UUID,
        endpointRevision: Int,
        kind: ServerUploadBatchKind,
        now: Date
    ) {
        let existing = Set(state.deliveries.lazy
            .filter { $0.destinationID == destinationID && $0.endpointRevision == endpointRevision }
            .map(\.readingID))
        for reading in readings where !existing.contains(reading.id) {
            state.deliveries.append(ServerUploadDelivery(
                id: UUID(),
                destinationID: destinationID,
                readingID: reading.id,
                endpointRevision: endpointRevision,
                sampleDate: reading.sampleDate,
                committedAt: reading.createdAt,
                glucoseMGDL: reading.glucoseMGDL,
                batchKind: kind,
                queuedAt: now,
                state: .queued,
                attemptCount: 0,
                nextEligibleAt: nil,
                lastError: nil,
                acknowledgedAt: nil,
                discardAfterAttempt: false
            ))
        }
    }

    private func discard(
        destinationID: UUID,
        where predicate: (ServerUploadDelivery) -> Bool,
        reason: String,
        now: Date
    ) {
        var retained: [ServerUploadDelivery] = []
        for var delivery in state.deliveries {
            guard delivery.destinationID == destinationID, predicate(delivery) else {
                retained.append(delivery)
                continue
            }
            if delivery.state == .sending {
                delivery.discardAfterAttempt = true
                retained.append(delivery)
            } else {
                appendAttempt(
                    destinationID: delivery.destinationID,
                    readingID: delivery.readingID,
                    endpointRevision: delivery.endpointRevision,
                    outcome: .cancelled,
                    message: reason,
                    now: now
                )
            }
        }
        state.deliveries = retained
    }

    private func appendAttempt(
        destinationID: UUID,
        readingID: UUID?,
        endpointRevision: Int,
        outcome: ServerUploadAttemptOutcome,
        responseCode: Int? = nil,
        message: String,
        now: Date
    ) {
        state.attempts.append(ServerUploadAttempt(
            id: UUID(),
            destinationID: destinationID,
            readingID: readingID,
            endpointRevision: endpointRevision,
            occurredAt: now,
            outcome: outcome,
            responseCode: responseCode,
            message: ServerUploadRedactor.message(message)
        ))
    }

    private func pruneLogs(now: Date) {
        let cutoff = now.addingTimeInterval(-logRetention)
        state.attempts.removeAll { $0.occurredAt < cutoff }
    }

    private func persist() throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw ServerUploadError.persistence("Upload state could not be written")
        }
    }

    private static func deliveryOrder(_ lhs: ServerUploadDelivery, _ rhs: ServerUploadDelivery) -> Bool {
        if lhs.sampleDate != rhs.sampleDate { return lhs.sampleDate > rhs.sampleDate }
        return lhs.readingID.uuidString < rhs.readingID.uuidString
    }
}
