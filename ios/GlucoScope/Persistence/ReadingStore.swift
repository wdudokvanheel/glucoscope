import CoreData
import Foundation

/// Bounded recovery identity only; no retained frame, glucose or upload payload.
struct ReadingRecoverySampleKey: Hashable, Sendable {
    let sessionID: UUID
    let sensorMinute: Int64
    let kind: ReadingSampleKind
}

struct ReadingRecoveryCheckpoint: Equatable, Sendable {
    let verifiedSampleCount: Int
}

public actor ReadingStore {
    public nonisolated let commits: AsyncStream<ReadingCommit>

    private let configuration: ReadingStoreConfiguration
    private let faultInjector: ReadingStoreFaultInjector?
    private let commitContinuation: AsyncStream<ReadingCommit>.Continuation
    private var commitSubscribers: [UUID: AsyncStream<ReadingCommit>.Continuation] = [:]
    private var container: NSPersistentContainer?
    private var writerContext: NSManagedObjectContext?
    private var health: ReadingStoreHealth = .notLoaded
    private var explicitRetryCount = 0
    private var publishedCommits: [ReadingCommit] = []

    public init(
        configuration: ReadingStoreConfiguration,
        faultInjector: ReadingStoreFaultInjector? = nil
    ) {
        var continuation: AsyncStream<ReadingCommit>.Continuation!
        // Configuration is validated by load(). Clamp here because AsyncStream's
        // buffering policy is created earlier and must never trap on bad input.
        let safeBufferLimit = Swift.max(
            1,
            Swift.min(1_024, configuration.publishedCommitHistoryLimit)
        )
        self.commits = AsyncStream(
            bufferingPolicy: .bufferingNewest(safeBufferLimit)
        ) { continuation = $0 }
        self.commitContinuation = continuation
        self.configuration = configuration
        self.faultInjector = faultInjector
    }

    deinit {
        commitContinuation.finish()
        for continuation in commitSubscribers.values { continuation.finish() }
    }

    public func load() async throws {
        switch health {
        case .healthy:
            return
        case .closed, .unhealthy:
            throw ReadingStoreError.unavailable(health)
        case .notLoaded:
            break
        }

        do {
            try validateConfiguration()
            try faultInjector?.check(.beforeLoad)
            let loaded = try Self.loadContainer(configuration: configuration)
            container = loaded
            writerContext = loaded.newBackgroundContext()
            writerContext?.mergePolicy = NSErrorMergePolicy
            writerContext?.undoManager = nil
            health = .healthy
            explicitRetryCount = 0
        } catch {
            container = nil
            writerContext = nil
            let failure = makeFailure(
                operation: .load,
                error: error,
                droppedCandidateCount: 0
            )
            health = .unhealthy(failure)
            throw ReadingStoreError.operationFailed(failure)
        }
    }

    public func currentHealth() -> ReadingStoreHealth {
        health
    }

    /// Creates an independent commit stream for one subscriber. Unlike the
    /// legacy `commits` stream, every stream returned here receives every commit.
    public func commitStream() -> AsyncStream<ReadingCommit> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            commitSubscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeCommitSubscriber(id) }
            }
        }
    }

    /// Atomically creates metadata for a previously unseen wear or returns the
    /// canonical row for its exact UUID. Existing identity/revision disagreements
    /// require repair. A clock disagreement is returned unchanged for the bridge
    /// to classify; the existing SQLite clock is never rewritten here.
    public func resolveSessionMetadata(
        _ proposed: ReadingSessionSnapshot
    ) async throws -> StoredSessionSnapshot {
        try ensureHealthy()
        try validate(proposed)
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }

        do {
            return try Self.perform(on: context) {
                do {
                    if let existing = try Self.fetchStoredSession(id: proposed.id, in: context) {
                        let stored = try Self.makeSessionSnapshot(existing)
                        try Self.verifyIdentity(of: stored, against: proposed)
                        try Self.verifyLifecycleTransition(from: stored.lifecycleState, to: proposed.lifecycleState)

                        guard Self.clocksMatch(stored.clock, proposed.clock) else {
                            return stored
                        }
                        if proposed.observedAt > stored.lastObservedAt {
                            existing.setValue(proposed.observedAt, forKey: "lastObservedAt")
                        }
                        if stored.lifecycleState != proposed.lifecycleState {
                            existing.setValue(proposed.lifecycleState.rawValue, forKey: "lifecycleState")
                        }
                        if context.hasChanges {
                            try self.faultInjector?.check(.beforeSave)
                            try context.save()
                        }
                        return try Self.makeSessionSnapshot(existing)
                    }

                    let inserted = Self.insertSession(proposed, in: context)
                    try self.faultInjector?.check(.beforeSave)
                    try context.save()
                    return try Self.makeSessionSnapshot(inserted)
                } catch {
                    context.rollback()
                    throw error
                }
            }
        } catch let error as ReadingStoreError {
            throw error
        } catch let error as ReadingStoreInternalError {
            switch error {
            case .sessionFingerprintMismatch, .sessionRevisionMismatch, .sessionClockMismatch:
                throw ReadingStoreError.repairRequired(Self.redactedReason(for: error))
            default:
                throw markUnhealthy(operation: .query, error: error, dropped: 0)
            }
        } catch {
            throw markUnhealthy(operation: .query, error: error, dropped: 0)
        }
    }

    /// Read-only lookup for candidate preparation and missing-clock repair. The UUID,
    /// fingerprint and revision must all identify the same retained wear.
    public func sessionMetadata(
        id: UUID,
        stableIdentityFingerprint: Data,
        sensorRevision: String
    ) async throws -> StoredSessionSnapshot? {
        try ensureHealthy()
        try Self.validateIdentityFields(
            stableIdentityFingerprint: stableIdentityFingerprint,
            sensorRevision: sensorRevision
        )
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }

        do {
            return try Self.perform(on: context) {
                guard let existing = try Self.fetchStoredSession(id: id, in: context) else {
                    return nil
                }
                let stored = try Self.makeSessionSnapshot(existing)
                guard stored.stableIdentityFingerprint == stableIdentityFingerprint else {
                    throw ReadingStoreInternalError.sessionFingerprintMismatch
                }
                guard stored.sensorRevision == sensorRevision else {
                    throw ReadingStoreInternalError.sessionRevisionMismatch
                }
                return stored
            }
        } catch let error as ReadingStoreInternalError {
            switch error {
            case .sessionFingerprintMismatch, .sessionRevisionMismatch:
                throw ReadingStoreError.repairRequired(Self.redactedReason(for: error))
            default:
                throw markUnhealthy(operation: .query, error: error, dropped: 0)
            }
        } catch {
            throw markUnhealthy(operation: .query, error: error, dropped: 0)
        }
    }

    /// General/synthetic ingestion has no transport ownership authority. Future
    /// BLE candidate adapters must use ingest(_:admission:) instead.
    public func ingest(_ submission: ReadingSubmission) async throws -> ReadingCommit {
        try ingest(submission, commitAdmission: nil)
    }

    func ingest(
        _ submission: ReadingSubmission,
        admission: ReadingCommitAdmission
    ) async throws -> ReadingCommit {
        try ingest(submission, commitAdmission: admission)
    }

    private func ingest(
        _ submission: ReadingSubmission,
        commitAdmission: ReadingCommitAdmission?
    ) throws -> ReadingCommit {
        try ensureHealthy()
        try commitAdmission?.validateSubmission(submission)
        try validate(submission)
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }

        let result: IngestResult
        do {
            result = try Self.perform(on: context) {
                do {
                    let canonicalClock = try Self.resolveSession(submission.session, in: context)
                    let destination = try Self.selectedDestination(in: context)
                    var insertedReadingObjects: [NSManagedObject] = []
                    var inserted: [(id: UUID, date: Date)] = []

                    for candidate in submission.candidates {
                        let sampleDate = try Self.sampleDate(
                            sensorMinute: candidate.sensorMinute,
                            clock: canonicalClock
                        )
                        if let existing = try Self.fetchReading(
                            sessionID: submission.session.id,
                            sensorMinute: candidate.sensorMinute,
                            kind: candidate.kind,
                            in: context
                        ) {
                            guard try Self.fetchDelivery(
                                readingID: existing.value(forKey: "id") as? UUID,
                                in: context
                            ) != nil else {
                                throw ReadingStoreInternalError.malformedStore
                            }
                            try Self.mergeDuplicate(
                                candidate,
                                sampleDate: sampleDate,
                                into: existing,
                                tolerance: self.configuration.sampleDateTolerance,
                                in: context
                            )
                            continue
                        }

                        let readingID = UUID()
                        let reading = NSEntityDescription.insertNewObject(
                            forEntityName: ReadingStoreEntity.reading,
                            into: context
                        )
                        reading.setValue(readingID, forKey: "id")
                        reading.setValue(submission.session.id, forKey: "sessionID")
                        reading.setValue(candidate.sensorMinute, forKey: "sensorMinute")
                        reading.setValue(candidate.kind.rawValue, forKey: "sampleKind")
                        reading.setValue(sampleDate, forKey: "sampleDate")
                        reading.setValue(candidate.receivedAt, forKey: "receivedAt")
                        reading.setValue(candidate.glucoseMGDL, forKey: "glucoseMGDL")
                        reading.setValue(candidate.quality, forKey: "quality")
                        reading.setValue(candidate.origin.rawValue, forKey: "primaryOrigin")
                        reading.setValue(candidate.origin.observationFlag, forKey: "observedOriginFlags")
                        reading.setValue(candidate.decoderVersion, forKey: "decoderVersion")
                        reading.setValue(Date(), forKey: "createdAt")

                        let delivery = NSEntityDescription.insertNewObject(
                            forEntityName: ReadingStoreEntity.delivery,
                            into: context
                        )
                        delivery.setValue(readingID, forKey: "readingID")
                        delivery.setValue(0, forKey: "attemptCount")

                        if let destination {
                            let payload = try Self.makePayload(
                                readingID: readingID,
                                sessionID: submission.session.id,
                                candidate: candidate,
                                sampleDate: sampleDate
                            )
                            delivery.setValue(destination.id, forKey: "destinationID")
                            delivery.setValue(ReadingDeliveryState.queued.rawValue, forKey: "state")
                            delivery.setValue(payload, forKey: "payload")
                            delivery.setValue(1, forKey: "payloadVersion")
                        } else {
                            delivery.setValue(ReadingDeliveryState.unassigned.rawValue, forKey: "state")
                        }

                        insertedReadingObjects.append(reading)
                        inserted.append((readingID, sampleDate))
                    }

                    let saved = context.hasChanges
                    if let commitAdmission {
                        if saved {
                            try context.obtainPermanentIDs(for: insertedReadingObjects)
                        }
                        try self.faultInjector?.check(.beforeCommitAdmission)
                        try commitAdmission.save(context, submission: submission,
                                                 faultInjector: self.faultInjector)
                    } else if saved {
                        try self.faultInjector?.check(.beforeSave)
                        try context.obtainPermanentIDs(for: insertedReadingObjects)
                        try context.save()
                    }

                    let ids = inserted
                        .sorted { lhs, rhs in
                            lhs.date == rhs.date
                                ? lhs.id.uuidString < rhs.id.uuidString
                                : lhs.date < rhs.date
                        }
                        .map(\.id)
                    return IngestResult(
                        commit: ReadingCommit(
                            submissionSequence: submission.sequence,
                            readingIDs: ids
                        ),
                        didSave: saved
                    )
                } catch {
                    context.rollback()
                    throw error
                }
            }
        } catch let error as ReadingStoreError {
            if case .invalidInput = error { throw error }
            if case .ownershipRejected = error { throw error }
            if case .repairRequired = error { throw error }
            return try failIngest(error, submission: submission, durable: false)
        } catch {
            return try failIngest(error, submission: submission, durable: false)
        }

        if result.didSave {
            do {
                try faultInjector?.check(.afterSaveBeforePublication)
            } catch {
                return try failIngest(error, submission: submission, durable: true)
            }
        }

        if !result.commit.readingIDs.isEmpty {
            publishedCommits.append(result.commit)
            if publishedCommits.count > configuration.publishedCommitHistoryLimit {
                publishedCommits.removeFirst(
                    publishedCommits.count - configuration.publishedCommitHistoryLimit
                )
            }
            commitContinuation.yield(result.commit)
            for continuation in commitSubscribers.values {
                continuation.yield(result.commit)
            }
        }
        return result.commit
    }

    public func selectDestination(
        _ destination: ReadingDestination
    ) async throws -> DestinationAssignmentCommit {
        try ensureHealthy()
        try validate(destination)
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }

        do {
            let result = try Self.perform(on: context) {
                do {
                    let destinationObject = try Self.upsert(destination, in: context)
                    let selectedRequest = NSFetchRequest<NSManagedObject>(
                        entityName: ReadingStoreEntity.destination
                    )
                    selectedRequest.predicate = NSPredicate(format: "selected == YES")
                    for object in try context.fetch(selectedRequest) {
                        object.setValue(object == destinationObject, forKey: "selected")
                    }

                    let request = NSFetchRequest<NSManagedObject>(
                        entityName: ReadingStoreEntity.delivery
                    )
                    request.predicate = NSPredicate(
                        format: "state == %@",
                        ReadingDeliveryState.unassigned.rawValue
                    )
                    let deliveries = try context.fetch(request)
                    var assignments: [(id: UUID, date: Date)] = []

                    for delivery in deliveries {
                        guard
                            let readingID = delivery.value(forKey: "readingID") as? UUID,
                            let reading = try Self.fetchReading(id: readingID, in: context)
                        else {
                            throw ReadingStoreInternalError.malformedStore
                        }
                        let payload = try Self.makePayload(reading: reading)
                        delivery.setValue(destination.id, forKey: "destinationID")
                        delivery.setValue(ReadingDeliveryState.queued.rawValue, forKey: "state")
                        delivery.setValue(payload, forKey: "payload")
                        delivery.setValue(1, forKey: "payloadVersion")
                        guard let date = reading.value(forKey: "sampleDate") as? Date else {
                            throw ReadingStoreInternalError.malformedStore
                        }
                        assignments.append((readingID, date))
                    }

                    if context.hasChanges {
                        try self.faultInjector?.check(.beforeSave)
                        try context.save()
                    }
                    return assignments
                        .sorted { lhs, rhs in
                            lhs.date == rhs.date
                                ? lhs.id.uuidString < rhs.id.uuidString
                                : lhs.date < rhs.date
                        }
                        .map(\.id)
                } catch {
                    context.rollback()
                    throw error
                }
            }
            return DestinationAssignmentCommit(destinationID: destination.id, readingIDs: result)
        } catch let error as ReadingStoreError {
            if case .invalidInput = error { throw error }
            throw markUnhealthy(operation: .assignDestination, error: error, dropped: 0)
        } catch {
            throw markUnhealthy(operation: .assignDestination, error: error, dropped: 0)
        }
    }

    public func clearSelectedDestination() async throws {
        try ensureHealthy()
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }

        do {
            try Self.perform(on: context) {
                do {
                    let request = NSFetchRequest<NSManagedObject>(
                        entityName: ReadingStoreEntity.destination
                    )
                    request.predicate = NSPredicate(format: "selected == YES")
                    for object in try context.fetch(request) {
                        object.setValue(false, forKey: "selected")
                    }
                    if context.hasChanges {
                        try self.faultInjector?.check(.beforeSave)
                        try context.save()
                    }
                } catch {
                    context.rollback()
                    throw error
                }
            }
        } catch {
            throw markUnhealthy(operation: .clearDestination, error: error, dropped: 0)
        }
    }

    public func retryAfterFailure() async throws -> [ReadingCommit] {
        guard case .unhealthy = health else {
            throw ReadingStoreError.unavailable(health)
        }
        guard explicitRetryCount < configuration.maxExplicitRetries else {
            throw ReadingStoreError.retriesExhausted
        }
        explicitRetryCount += 1

        do {
            try validateConfiguration()
            if let writerContext {
                try Self.perform(on: writerContext) {
                    writerContext.rollback()
                    writerContext.reset()
                }
                health = .healthy
            } else {
                try faultInjector?.check(.beforeLoad)
                let loaded = try Self.loadContainer(configuration: configuration)
                container = loaded
                let context = loaded.newBackgroundContext()
                context.mergePolicy = NSErrorMergePolicy
                context.undoManager = nil
                writerContext = context
                health = .healthy
            }
            return []
        } catch {
            let failure = makeFailure(operation: .retry, error: error, droppedCandidateCount: 0)
            health = .unhealthy(failure)
            throw ReadingStoreError.operationFailed(failure)
        }
    }

    /// Checks only the at-most-seven keys of one durable BLE submission whose
    /// publication failed. Each lookup uses an existing unique key with LIMIT 2
    /// and a dictionary projection. It neither scans history nor refreshes any UI.
    func verifyCommittedSamples(_ keys: [ReadingRecoverySampleKey]) async throws -> ReadingRecoveryCheckpoint {
        try ensureHealthy()
        guard (1...7).contains(keys.count), Set(keys).count == keys.count,
              keys.allSatisfy({ (0...20_880).contains($0.sensorMinute) }) else {
            throw ReadingStoreError.invalidInput("Invalid bounded recovery keys")
        }
        guard let context = writerContext else { throw ReadingStoreError.unavailable(health) }
        do {
            return try Self.perform(on: context) {
                for key in keys {
                    let readings = NSFetchRequest<NSDictionary>(entityName: ReadingStoreEntity.reading)
                    readings.resultType = .dictionaryResultType
                    readings.propertiesToFetch = ["id"]
                    readings.includesPendingChanges = false
                    readings.fetchLimit = 2
                    readings.predicate = NSPredicate(
                        format: "sessionID == %@ AND sensorMinute == %lld AND sampleKind == %@",
                        key.sessionID as NSUUID, key.sensorMinute, key.kind.rawValue
                    )
                    let matches = try context.fetch(readings)
                    guard matches.count == 1, let id = matches[0]["id"] as? UUID else {
                        throw ReadingStoreInternalError.malformedStore
                    }
                    let deliveries = NSFetchRequest<NSDictionary>(entityName: ReadingStoreEntity.delivery)
                    deliveries.resultType = .dictionaryResultType
                    deliveries.propertiesToFetch = ["readingID", "state"]
                    deliveries.includesPendingChanges = false
                    deliveries.fetchLimit = 2
                    deliveries.predicate = NSPredicate(format: "readingID == %@", id as NSUUID)
                    let required = try context.fetch(deliveries)
                    guard required.count == 1, required[0]["readingID"] as? UUID == id,
                          let state = required[0]["state"] as? String,
                          ReadingDeliveryState(rawValue: state) != nil else {
                        throw ReadingStoreInternalError.malformedStore
                    }
                }
                return ReadingRecoveryCheckpoint(verifiedSampleCount: keys.count)
            }
        } catch {
            throw markUnhealthy(operation: .query, error: error, dropped: 0)
        }
    }

    #if LIBRE2_CANDIDATE_ADAPTER_FIXTURES
    /// Deliberate isolated corruption to prove recovery scopes its integrity check
    /// to the affected keys instead of traversing unrelated retained history.
    func removeDeliveryForRecoveryFixture(readingID: UUID) async throws {
        guard let context = writerContext else { throw ReadingStoreError.unavailable(health) }
        try Self.perform(on: context) {
            let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.delivery)
            request.predicate = NSPredicate(format: "readingID == %@", readingID as NSUUID)
            request.fetchLimit = 2
            for row in try context.fetch(request) { context.delete(row) }
            try context.save()
        }
    }
    #endif

    /// Bounded newest-first rows for the development app's local reading display.
    public func recentReadings(limit: Int = 15) async throws -> [StoredReadingSnapshot] {
        try ensureHealthy()
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }
        let boundedLimit = max(0, min(100, limit))
        guard boundedLimit > 0 else { return [] }
        do {
            return try Self.perform(on: context) {
                let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.reading)
                request.fetchLimit = boundedLimit
                request.sortDescriptors = [
                    NSSortDescriptor(key: "sampleDate", ascending: false),
                    NSSortDescriptor(key: "sampleKind", ascending: true)
                ]
                return try context.fetch(request).map(Self.makeReadingSnapshot)
            }
        } catch {
            throw markUnhealthy(operation: .query, error: error, dropped: 0)
        }
    }

    public func snapshot() async throws -> ReadingStoreSnapshot {
        guard let context = writerContext else {
            throw ReadingStoreError.unavailable(health)
        }
        let capturedHealth = health
        let capturedCommits = publishedCommits
        do {
            return try Self.perform(on: context) {
                try Self.makeSnapshot(
                    health: capturedHealth,
                    publishedCommits: capturedCommits,
                    in: context
                )
            }
        } catch {
            throw markUnhealthy(operation: .query, error: error, dropped: 0)
        }
    }

    public func close() async throws {
        if case .closed = health { return }
        do {
            if let container {
                let coordinator = container.persistentStoreCoordinator
                for store in coordinator.persistentStores {
                    try coordinator.remove(store)
                }
            }
            writerContext = nil
            container = nil
            health = .closed
            commitContinuation.finish()
            for continuation in commitSubscribers.values { continuation.finish() }
            commitSubscribers.removeAll()
        } catch {
            throw markUnhealthy(operation: .close, error: error, dropped: 0)
        }
    }
}

private extension ReadingStore {
    func removeCommitSubscriber(_ id: UUID) {
        commitSubscribers.removeValue(forKey: id)
    }
}

private extension ReadingStore {
    struct IngestResult {
        let commit: ReadingCommit
        let didSave: Bool
    }

    struct DestinationRecord {
        let id: UUID
    }

    enum ReadingStoreInternalError: Error {
        case malformedStore
        case duplicateSession
        case duplicateReading
        case duplicateDestination
        case sessionFingerprintMismatch
        case sessionRevisionMismatch
        case sessionClockMismatch
        case destinationIdentityMismatch
        case dateOverflow
    }

    func validateConfiguration() throws {
        guard (1...512).contains(configuration.maxCandidatesPerSubmission) else {
            throw ReadingStoreError.invalidInput("maxCandidatesPerSubmission must be between 1 and 512")
        }
        guard (1...10).contains(configuration.maxExplicitRetries) else {
            throw ReadingStoreError.invalidInput("maxExplicitRetries must be between 1 and 10")
        }
        guard configuration.sampleDateTolerance.isFinite,
              (0...60).contains(configuration.sampleDateTolerance) else {
            throw ReadingStoreError.invalidInput("sampleDateTolerance must be between 0 and 60 seconds")
        }
        guard (1...1_024).contains(configuration.publishedCommitHistoryLimit) else {
            throw ReadingStoreError.invalidInput("publishedCommitHistoryLimit must be between 1 and 1024")
        }
    }

    func validate(_ submission: ReadingSubmission) throws {
        guard submission.candidates.count <= configuration.maxCandidatesPerSubmission else {
            throw ReadingStoreError.invalidInput("candidate batch exceeds configured maximum")
        }
        let session = submission.session
        try validate(session)

        for candidate in submission.candidates {
            guard (0...20_880).contains(candidate.sensorMinute),
                  candidate.glucoseMGDL >= 20,
                  candidate.glucoseMGDL <= 600,
                  Self.isFinite(candidate.receivedAt) else {
                throw ReadingStoreError.invalidInput("candidate numeric fields are invalid")
            }
            try Self.validateBounded(candidate.quality, name: "quality", maximum: 64)
            try Self.validateBounded(candidate.decoderVersion, name: "decoder version", maximum: 64)
            if candidate.kind == .history15Minute && candidate.origin != .nfcHistory {
                throw ReadingStoreError.invalidInput("15-minute history must use NFC history origin")
            }
            if candidate.kind == .trend && candidate.origin == .nfcHistory {
                throw ReadingStoreError.invalidInput("NFC history must use 15-minute history kind")
            }
            _ = try Self.sampleDate(sensorMinute: candidate.sensorMinute, clock: session.clock)
        }
    }

    func validate(_ session: ReadingSessionSnapshot) throws {
        try Self.validateIdentityFields(
            stableIdentityFingerprint: session.stableIdentityFingerprint,
            sensorRevision: session.sensorRevision
        )
        try Self.validateBounded(session.clock.provenance, name: "clock provenance", maximum: 128)
        guard Self.isFinite(session.firstObservedAt),
              Self.isFinite(session.observedAt),
              Self.isFinite(session.clock.referenceDate),
              session.firstObservedAt <= session.observedAt,
              (0...20_880).contains(session.clock.referenceSensorMinute) else {
            throw ReadingStoreError.invalidInput("session timestamps or clock minute are invalid")
        }

    }

    static func validateIdentityFields(
        stableIdentityFingerprint: Data,
        sensorRevision: String
    ) throws {
        guard (1...128).contains(stableIdentityFingerprint.count) else {
            throw ReadingStoreError.invalidInput("stable identity fingerprint has an invalid length")
        }
        try validateBounded(sensorRevision, name: "sensor revision", maximum: 64)
    }

    func validate(_ destination: ReadingDestination) throws {
        guard destination.enabled else {
            throw ReadingStoreError.invalidInput("a selected destination must be enabled")
        }
        try Self.validateBounded(destination.backendKind, name: "backend kind", maximum: 64)
        try Self.validateBounded(
            destination.normalizedEndpointIdentity,
            name: "endpoint identity",
            maximum: 1024
        )
        try Self.validateBounded(
            destination.credentialReference,
            name: "credential reference",
            maximum: 256
        )
        guard destination.configurationRevision >= 0 else {
            throw ReadingStoreError.invalidInput("configuration revision must not be negative")
        }
    }

    static func validateBounded(_ value: String, name: String, maximum: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximum else {
            throw ReadingStoreError.invalidInput("\(name) is empty or too long")
        }
    }

    static func isFinite(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (946_684_800...4_102_444_800).contains(seconds)
    }

    func ensureHealthy() throws {
        guard case .healthy = health else {
            throw ReadingStoreError.unavailable(health)
        }
    }

    func failIngest(
        _ error: Error,
        submission: ReadingSubmission,
        durable: Bool
    ) throws -> ReadingCommit {
        let failure = makeFailure(
            operation: durable ? .publication : .ingest,
            error: error,
            droppedCandidateCount: durable ? 0 : submission.candidates.count,
            durable: durable
        )
        health = .unhealthy(failure)
        throw ReadingStoreError.operationFailed(failure)
    }

    func markUnhealthy(
        operation: ReadingStoreOperation,
        error: Error,
        dropped: Int
    ) -> ReadingStoreError {
        let failure = makeFailure(
            operation: operation,
            error: error,
            droppedCandidateCount: dropped
        )
        health = .unhealthy(failure)
        return .operationFailed(failure)
    }

    func makeFailure(
        operation: ReadingStoreOperation,
        error: Error,
        droppedCandidateCount: Int,
        durable: Bool = false
    ) -> ReadingStoreFailure {
        ReadingStoreFailure(
            operation: operation,
            redactedReason: Self.redactedReason(for: error),
            droppedCandidateCount: droppedCandidateCount,
            durableCommitAwaitingPublication: durable
        )
    }

    static func redactedReason(for error: Error) -> String {
        if let injected = error as? ReadingStoreInjectedFault {
            return "Injected \(injected.point.rawValue) fault"
        }
        if let storeError = error as? ReadingStoreError {
            switch storeError {
            case .invalidInput(let message), .repairRequired(let message):
                return String(message.prefix(160))
            case .retriesExhausted:
                return "Explicit retry limit reached"
            case .unavailable:
                return "Store unavailable"
            case .operationFailed(let failure):
                return failure.redactedReason
            case .ownershipRejected:
                return "Frame ownership rejected"
            }
        }
        if let internalError = error as? ReadingStoreInternalError {
            switch internalError {
            case .malformedStore: return "Stored metadata is malformed"
            case .duplicateSession: return "Session uniqueness invariant failed"
            case .duplicateReading: return "Reading uniqueness invariant failed"
            case .duplicateDestination: return "Destination uniqueness invariant failed"
            case .sessionFingerprintMismatch: return "Session fingerprint requires repair"
            case .sessionRevisionMismatch: return "Session revision requires repair"
            case .sessionClockMismatch: return "Session clock requires repair"
            case .destinationIdentityMismatch: return "Destination identity is immutable"
            case .dateOverflow: return "Sensor clock calculation overflowed"
            }
        }
        let nsError = error as NSError
        return "Persistence error \(nsError.domain) (\(nsError.code))"
    }
}

private extension ReadingStore {
    static func loadContainer(
        configuration: ReadingStoreConfiguration
    ) throws -> NSPersistentContainer {
        let model = ReadingStoreModel.make()
        let container = NSPersistentContainer(
            name: "GlucoScopeReadingStore",
            managedObjectModel: model
        )
        let description = NSPersistentStoreDescription()
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        switch configuration.storage {
        case .inMemory(let identifier):
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(identifier)")
        case .sqlite(let url):
            try prepareSQLiteDirectory(for: url)
            description.type = NSSQLiteStoreType
            description.url = url
            #if os(iOS)
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
            #endif
        }
        container.persistentStoreDescriptions = [description]

        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw loadError }

        #if os(iOS)
        if case .sqlite(let url) = configuration.storage {
            try protectSQLiteFiles(at: url)
        }
        #endif
        return container
    }

    static func prepareSQLiteDirectory(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
    }

    #if os(iOS)
    static func protectSQLiteFiles(at url: URL) throws {
        for fileURL in [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ] where FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        }
    }
    #endif

    static func perform<T>(
        on context: NSManagedObjectContext,
        _ operation: @escaping () throws -> T
    ) throws -> T {
        // Keep health check, writer transaction, and publication in one actor turn.
        // An awaiting context.perform here would allow later operations to pass the
        // health check before an earlier save failure marks the store unhealthy.
        var result: Result<T, Error>!
        context.performAndWait {
            result = Result { try operation() }
        }
        return try result.get()
    }
}

private extension ReadingStore {
    static func fetchStoredSession(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.session)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.duplicateSession }
        return matches.first
    }

    static func verifyIdentity(
        of stored: StoredSessionSnapshot,
        against proposed: ReadingSessionSnapshot
    ) throws {
        guard stored.stableIdentityFingerprint == proposed.stableIdentityFingerprint else {
            throw ReadingStoreInternalError.sessionFingerprintMismatch
        }
        guard stored.sensorRevision == proposed.sensorRevision else {
            throw ReadingStoreInternalError.sessionRevisionMismatch
        }
    }

    static func verifyLifecycleTransition(
        from stored: ReadingSessionLifecycle,
        to proposed: ReadingSessionLifecycle
    ) throws {
        guard stored == .active || proposed != .active else {
            throw ReadingStoreError.repairRequired("Terminal session requires repair")
        }
    }

    static func clocksMatch(_ lhs: ReadingClockSnapshot, _ rhs: ReadingClockSnapshot) -> Bool {
        lhs.referenceSensorMinute == rhs.referenceSensorMinute &&
        abs(lhs.referenceDate.timeIntervalSince(rhs.referenceDate)) <= 0.001 &&
        lhs.provenance == rhs.provenance
    }

    @discardableResult
    static func insertSession(
        _ snapshot: ReadingSessionSnapshot,
        in context: NSManagedObjectContext
    ) -> NSManagedObject {
        let session = NSEntityDescription.insertNewObject(
            forEntityName: ReadingStoreEntity.session,
            into: context
        )
        session.setValue(snapshot.id, forKey: "id")
        session.setValue(snapshot.stableIdentityFingerprint, forKey: "stableIdentityFingerprint")
        session.setValue(snapshot.sensorRevision, forKey: "sensorRevision")
        session.setValue(snapshot.firstObservedAt, forKey: "firstObservedAt")
        session.setValue(snapshot.observedAt, forKey: "lastObservedAt")
        session.setValue(snapshot.lifecycleState.rawValue, forKey: "lifecycleState")
        session.setValue(snapshot.clock.referenceSensorMinute, forKey: "clockReferenceSensorMinute")
        session.setValue(snapshot.clock.referenceDate, forKey: "clockReferenceDate")
        session.setValue(snapshot.clock.provenance, forKey: "clockProvenance")
        return session
    }

    static func resolveSession(
        _ snapshot: ReadingSessionSnapshot,
        in context: NSManagedObjectContext
    ) throws -> ReadingClockSnapshot {
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.session)
        request.predicate = NSPredicate(format: "id == %@", snapshot.id as CVarArg)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.duplicateSession }

        if let existing = matches.first {
            guard let lifecycleRaw = existing.value(forKey: "lifecycleState") as? String,
                  let lifecycle = ReadingSessionLifecycle(rawValue: lifecycleRaw) else {
                throw ReadingStoreInternalError.malformedStore
            }
            try verifyLifecycleTransition(from: lifecycle, to: snapshot.lifecycleState)
            guard existing.value(forKey: "stableIdentityFingerprint") as? Data
                    == snapshot.stableIdentityFingerprint else {
                throw ReadingStoreInternalError.sessionFingerprintMismatch
            }
            guard existing.value(forKey: "sensorRevision") as? String
                    == snapshot.sensorRevision else {
                throw ReadingStoreInternalError.sessionRevisionMismatch
            }
            guard
                let minute = existing.value(forKey: "clockReferenceSensorMinute") as? Int64,
                let date = existing.value(forKey: "clockReferenceDate") as? Date,
                let provenance = existing.value(forKey: "clockProvenance") as? String
            else {
                throw ReadingStoreInternalError.malformedStore
            }
            guard minute == snapshot.clock.referenceSensorMinute,
                  abs(date.timeIntervalSince(snapshot.clock.referenceDate)) <= 0.001,
                  provenance == snapshot.clock.provenance else {
                throw ReadingStoreInternalError.sessionClockMismatch
            }
            let priorLastObserved = existing.value(forKey: "lastObservedAt") as? Date
            if priorLastObserved == nil || snapshot.observedAt > priorLastObserved! {
                existing.setValue(snapshot.observedAt, forKey: "lastObservedAt")
            }
            existing.setValue(snapshot.lifecycleState.rawValue, forKey: "lifecycleState")
            return ReadingClockSnapshot(
                referenceSensorMinute: minute,
                referenceDate: date,
                provenance: provenance
            )
        }

        let session = NSEntityDescription.insertNewObject(
            forEntityName: ReadingStoreEntity.session,
            into: context
        )
        session.setValue(snapshot.id, forKey: "id")
        session.setValue(snapshot.stableIdentityFingerprint, forKey: "stableIdentityFingerprint")
        session.setValue(snapshot.sensorRevision, forKey: "sensorRevision")
        session.setValue(snapshot.firstObservedAt, forKey: "firstObservedAt")
        session.setValue(snapshot.observedAt, forKey: "lastObservedAt")
        session.setValue(snapshot.lifecycleState.rawValue, forKey: "lifecycleState")
        session.setValue(snapshot.clock.referenceSensorMinute, forKey: "clockReferenceSensorMinute")
        session.setValue(snapshot.clock.referenceDate, forKey: "clockReferenceDate")
        session.setValue(snapshot.clock.provenance, forKey: "clockProvenance")
        return snapshot.clock
    }

    static func sampleDate(
        sensorMinute: Int64,
        clock: ReadingClockSnapshot
    ) throws -> Date {
        let (delta, overflow) = sensorMinute.subtractingReportingOverflow(
            clock.referenceSensorMinute
        )
        guard !overflow else { throw ReadingStoreInternalError.dateOverflow }
        let seconds = Double(delta) * 60
        guard seconds.isFinite else { throw ReadingStoreInternalError.dateOverflow }
        let result = clock.referenceDate.addingTimeInterval(seconds)
        guard isFinite(result) else { throw ReadingStoreInternalError.dateOverflow }
        return result
    }

    static func fetchReading(
        sessionID: UUID,
        sensorMinute: Int64,
        kind: ReadingSampleKind,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.reading)
        request.predicate = NSPredicate(
            format: "sessionID == %@ AND sensorMinute == %lld AND sampleKind == %@",
            sessionID as CVarArg,
            sensorMinute,
            kind.rawValue
        )
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.duplicateReading }
        return matches.first
    }

    static func fetchReading(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.reading)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.duplicateReading }
        return matches.first
    }

    static func fetchDelivery(
        readingID: UUID?,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        guard let readingID else { throw ReadingStoreInternalError.malformedStore }
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.delivery)
        request.predicate = NSPredicate(format: "readingID == %@", readingID as CVarArg)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.malformedStore }
        return matches.first
    }

    static func mergeDuplicate(
        _ candidate: ReadingCandidate,
        sampleDate: Date,
        into reading: NSManagedObject,
        tolerance: TimeInterval,
        in context: NSManagedObjectContext
    ) throws {
        guard
            let readingID = reading.value(forKey: "id") as? UUID,
            let storedDate = reading.value(forKey: "sampleDate") as? Date,
            let storedMGDL = reading.value(forKey: "glucoseMGDL") as? Int,
            let observedFlags = reading.value(forKey: "observedOriginFlags") as? Int64
        else {
            throw ReadingStoreInternalError.malformedStore
        }

        var discrepancies: [String] = []
        if storedMGDL != candidate.glucoseMGDL { discrepancies.append("canonicalValue") }
        if abs(storedDate.timeIntervalSince(sampleDate)) > tolerance {
            discrepancies.append("sampleDate")
        }

        if discrepancies.isEmpty {
            let mergedFlags = observedFlags | candidate.origin.observationFlag
            if mergedFlags != observedFlags {
                reading.setValue(mergedFlags, forKey: "observedOriginFlags")
            }
            return
        }
        let conflict = NSEntityDescription.insertNewObject(
            forEntityName: ReadingStoreEntity.conflict,
            into: context
        )
        conflict.setValue(UUID(), forKey: "id")
        conflict.setValue(readingID, forKey: "readingID")
        conflict.setValue(Date(), forKey: "observedAt")
        conflict.setValue(candidate.origin.rawValue, forKey: "candidateOrigin")
        conflict.setValue(discrepancies.sorted().joined(separator: ","), forKey: "discrepancyFlags")
    }

    static func selectedDestination(
        in context: NSManagedObjectContext
    ) throws -> DestinationRecord? {
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.destination)
        request.predicate = NSPredicate(format: "selected == YES AND enabled == YES")
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.duplicateDestination }
        guard let object = matches.first,
              let id = object.value(forKey: "id") as? UUID else {
            if matches.isEmpty { return nil }
            throw ReadingStoreInternalError.malformedStore
        }
        return DestinationRecord(id: id)
    }

    static func upsert(
        _ destination: ReadingDestination,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.destination)
        request.predicate = NSPredicate(format: "id == %@", destination.id as CVarArg)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw ReadingStoreInternalError.duplicateDestination }
        let object = matches.first ?? NSEntityDescription.insertNewObject(
            forEntityName: ReadingStoreEntity.destination,
            into: context
        )

        if let existing = matches.first {
            guard existing.value(forKey: "backendKind") as? String == destination.backendKind,
                  existing.value(forKey: "normalizedEndpointIdentity") as? String
                    == destination.normalizedEndpointIdentity else {
                throw ReadingStoreInternalError.destinationIdentityMismatch
            }
        } else {
            object.setValue(destination.id, forKey: "id")
            object.setValue(destination.backendKind, forKey: "backendKind")
            object.setValue(
                destination.normalizedEndpointIdentity,
                forKey: "normalizedEndpointIdentity"
            )
        }
        object.setValue(destination.credentialReference, forKey: "credentialReference")
        object.setValue(destination.configurationRevision, forKey: "configurationRevision")
        object.setValue(destination.enabled, forKey: "enabled")
        object.setValue(true, forKey: "selected")
        return object
    }

    static func makePayload(
        readingID: UUID,
        sessionID: UUID,
        candidate: ReadingCandidate,
        sampleDate: Date
    ) throws -> Data {
        try deterministicJSON([
            "decoder_version": candidate.decoderVersion,
            "glucose_mg_dl": candidate.glucoseMGDL,
            "payload_version": 1,
            "reading_id": readingID.uuidString.lowercased(),
            "sample_date_ms": try epochMilliseconds(sampleDate),
            "sample_kind": candidate.kind.rawValue,
            "sensor_minute": candidate.sensorMinute,
            "session_id": sessionID.uuidString.lowercased()
        ])
    }

    static func makePayload(reading: NSManagedObject) throws -> Data {
        guard
            let readingID = reading.value(forKey: "id") as? UUID,
            let sessionID = reading.value(forKey: "sessionID") as? UUID,
            let sensorMinute = reading.value(forKey: "sensorMinute") as? Int64,
            let sampleKind = reading.value(forKey: "sampleKind") as? String,
            let sampleDate = reading.value(forKey: "sampleDate") as? Date,
            let glucoseMGDL = reading.value(forKey: "glucoseMGDL") as? Int,
            let decoderVersion = reading.value(forKey: "decoderVersion") as? String
        else {
            throw ReadingStoreInternalError.malformedStore
        }
        return try deterministicJSON([
            "decoder_version": decoderVersion,
            "glucose_mg_dl": glucoseMGDL,
            "payload_version": 1,
            "reading_id": readingID.uuidString.lowercased(),
            "sample_date_ms": try epochMilliseconds(sampleDate),
            "sample_kind": sampleKind,
            "sensor_minute": sensorMinute,
            "session_id": sessionID.uuidString.lowercased()
        ])
    }

    static func deterministicJSON(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func epochMilliseconds(_ date: Date) throws -> Int64 {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        guard milliseconds.isFinite,
              let exact = Int64(exactly: milliseconds) else {
            throw ReadingStoreInternalError.dateOverflow
        }
        return exact
    }
}

private extension ReadingStore {
    static func makeSnapshot(
        health: ReadingStoreHealth,
        publishedCommits: [ReadingCommit],
        in context: NSManagedObjectContext
    ) throws -> ReadingStoreSnapshot {
        let sessionObjects = try context.fetch(
            NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.session)
        )
        let readingRequest = NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.reading)
        readingRequest.sortDescriptors = [
            NSSortDescriptor(key: "sampleDate", ascending: true),
            NSSortDescriptor(key: "sampleKind", ascending: true)
        ]
        let readingObjects = try context.fetch(readingRequest)
        let deliveryObjects = try context.fetch(
            NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.delivery)
        )
        let destinationObjects = try context.fetch(
            NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.destination)
        )
        let conflictObjects = try context.fetch(
            NSFetchRequest<NSManagedObject>(entityName: ReadingStoreEntity.conflict)
        )
        let readingIDs = try readingObjects.map { object -> UUID in
            guard let id = object.value(forKey: "id") as? UUID else {
                throw ReadingStoreInternalError.malformedStore
            }
            return id
        }
        let deliveryReadingIDs = try deliveryObjects.map { object -> UUID in
            guard let id = object.value(forKey: "readingID") as? UUID else {
                throw ReadingStoreInternalError.malformedStore
            }
            return id
        }
        guard Set(readingIDs).count == readingIDs.count,
              Set(deliveryReadingIDs).count == deliveryReadingIDs.count,
              Set(readingIDs) == Set(deliveryReadingIDs) else {
            throw ReadingStoreInternalError.malformedStore
        }

        return ReadingStoreSnapshot(
            health: health,
            sessions: try sessionObjects.map(makeSessionSnapshot).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            readings: try readingObjects.map(makeReadingSnapshot),
            deliveries: try deliveryObjects.map(makeDeliverySnapshot).sorted {
                $0.readingID.uuidString < $1.readingID.uuidString
            },
            destinations: try destinationObjects.map(makeDestinationSnapshot).sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            conflicts: try conflictObjects.map(makeConflictSnapshot).sorted {
                $0.observedAt < $1.observedAt
            },
            publishedCommits: publishedCommits
        )
    }

    static func makeSessionSnapshot(_ object: NSManagedObject) throws -> StoredSessionSnapshot {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let fingerprint = object.value(forKey: "stableIdentityFingerprint") as? Data,
            let revision = object.value(forKey: "sensorRevision") as? String,
            let firstObservedAt = object.value(forKey: "firstObservedAt") as? Date,
            let lastObservedAt = object.value(forKey: "lastObservedAt") as? Date,
            let lifecycleRaw = object.value(forKey: "lifecycleState") as? String,
            let lifecycle = ReadingSessionLifecycle(rawValue: lifecycleRaw),
            let clockMinute = object.value(forKey: "clockReferenceSensorMinute") as? Int64,
            let clockDate = object.value(forKey: "clockReferenceDate") as? Date,
            let provenance = object.value(forKey: "clockProvenance") as? String
        else { throw ReadingStoreInternalError.malformedStore }
        return StoredSessionSnapshot(
            id: id,
            stableIdentityFingerprint: fingerprint,
            sensorRevision: revision,
            firstObservedAt: firstObservedAt,
            lastObservedAt: lastObservedAt,
            lifecycleState: lifecycle,
            clock: ReadingClockSnapshot(
                referenceSensorMinute: clockMinute,
                referenceDate: clockDate,
                provenance: provenance
            )
        )
    }

    static func makeReadingSnapshot(_ object: NSManagedObject) throws -> StoredReadingSnapshot {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let sessionID = object.value(forKey: "sessionID") as? UUID,
            let sensorMinute = object.value(forKey: "sensorMinute") as? Int64,
            let kindRaw = object.value(forKey: "sampleKind") as? String,
            let kind = ReadingSampleKind(rawValue: kindRaw),
            let sampleDate = object.value(forKey: "sampleDate") as? Date,
            let receivedAt = object.value(forKey: "receivedAt") as? Date,
            let glucoseMGDL = object.value(forKey: "glucoseMGDL") as? Int,
            let quality = object.value(forKey: "quality") as? String,
            let originRaw = object.value(forKey: "primaryOrigin") as? String,
            let origin = ReadingOrigin(rawValue: originRaw),
            let observedOriginFlags = object.value(forKey: "observedOriginFlags") as? Int64,
            let decoderVersion = object.value(forKey: "decoderVersion") as? String,
            let createdAt = object.value(forKey: "createdAt") as? Date
        else { throw ReadingStoreInternalError.malformedStore }
        return StoredReadingSnapshot(
            id: id,
            sessionID: sessionID,
            sensorMinute: sensorMinute,
            kind: kind,
            sampleDate: sampleDate,
            receivedAt: receivedAt,
            glucoseMGDL: glucoseMGDL,
            quality: quality,
            primaryOrigin: origin,
            observedOriginFlags: observedOriginFlags,
            decoderVersion: decoderVersion,
            createdAt: createdAt
        )
    }

    static func makeDeliverySnapshot(_ object: NSManagedObject) throws -> ReadingDeliverySnapshot {
        guard
            let readingID = object.value(forKey: "readingID") as? UUID,
            let stateRaw = object.value(forKey: "state") as? String,
            let state = ReadingDeliveryState(rawValue: stateRaw),
            let attemptCount = object.value(forKey: "attemptCount") as? Int
        else { throw ReadingStoreInternalError.malformedStore }
        return ReadingDeliverySnapshot(
            readingID: readingID,
            destinationID: object.value(forKey: "destinationID") as? UUID,
            state: state,
            payload: object.value(forKey: "payload") as? Data,
            payloadVersion: object.value(forKey: "payloadVersion") as? Int,
            attemptCount: attemptCount,
            leaseID: object.value(forKey: "leaseID") as? UUID,
            leaseExpiresAt: object.value(forKey: "leaseExpiresAt") as? Date,
            nextEligibleAt: object.value(forKey: "nextEligibleAt") as? Date,
            lastError: object.value(forKey: "lastError") as? String,
            acknowledgedAt: object.value(forKey: "acknowledgedAt") as? Date
        )
    }

    static func makeDestinationSnapshot(
        _ object: NSManagedObject
    ) throws -> ReadingDestinationSnapshot {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let backendKind = object.value(forKey: "backendKind") as? String,
            let endpoint = object.value(forKey: "normalizedEndpointIdentity") as? String,
            let credentialReference = object.value(forKey: "credentialReference") as? String,
            let configurationRevision = object.value(forKey: "configurationRevision") as? Int,
            let enabled = object.value(forKey: "enabled") as? Bool,
            let selected = object.value(forKey: "selected") as? Bool
        else { throw ReadingStoreInternalError.malformedStore }
        return ReadingDestinationSnapshot(
            id: id,
            backendKind: backendKind,
            normalizedEndpointIdentity: endpoint,
            credentialReference: credentialReference,
            configurationRevision: configurationRevision,
            enabled: enabled,
            selected: selected
        )
    }

    static func makeConflictSnapshot(_ object: NSManagedObject) throws -> ReadingConflictSnapshot {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let readingID = object.value(forKey: "readingID") as? UUID,
            let observedAt = object.value(forKey: "observedAt") as? Date,
            let originRaw = object.value(forKey: "candidateOrigin") as? String,
            let origin = ReadingOrigin(rawValue: originRaw),
            let flags = object.value(forKey: "discrepancyFlags") as? String
        else { throw ReadingStoreInternalError.malformedStore }
        return ReadingConflictSnapshot(
            id: id,
            readingID: readingID,
            observedAt: observedAt,
            candidateOrigin: origin,
            discrepancyFlags: flags.split(separator: ",").map(String.init)
        )
    }
}
