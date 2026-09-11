import Foundation

public enum ReadingSampleKind: String, Codable, CaseIterable, Sendable {
    case trend
    case history15Minute
}

public enum ReadingOrigin: String, Codable, CaseIterable, Sendable {
    case bleLive
    case bleHistory
    case nfcTrend
    case nfcHistory

    var observationFlag: Int64 {
        switch self {
        case .bleLive: return 1 << 0
        case .bleHistory: return 1 << 1
        case .nfcTrend: return 1 << 2
        case .nfcHistory: return 1 << 3
        }
    }
}

public enum ReadingSessionLifecycle: String, Codable, CaseIterable, Sendable {
    case active
    case ended
    case replaced
}

public struct ReadingClockSnapshot: Equatable, Sendable {
    public let referenceSensorMinute: Int64
    public let referenceDate: Date
    public let provenance: String

    public init(referenceSensorMinute: Int64, referenceDate: Date, provenance: String) {
        self.referenceSensorMinute = referenceSensorMinute
        self.referenceDate = referenceDate
        self.provenance = provenance
    }
}

public struct ReadingSessionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let stableIdentityFingerprint: Data
    public let sensorRevision: String
    public let firstObservedAt: Date
    public let observedAt: Date
    public let lifecycleState: ReadingSessionLifecycle
    public let clock: ReadingClockSnapshot

    public init(
        id: UUID,
        stableIdentityFingerprint: Data,
        sensorRevision: String,
        firstObservedAt: Date,
        observedAt: Date,
        lifecycleState: ReadingSessionLifecycle,
        clock: ReadingClockSnapshot
    ) {
        self.id = id
        self.stableIdentityFingerprint = stableIdentityFingerprint
        self.sensorRevision = sensorRevision
        self.firstObservedAt = firstObservedAt
        self.observedAt = observedAt
        self.lifecycleState = lifecycleState
        self.clock = clock
    }
}

public struct ReadingCandidate: Equatable, Sendable {
    public let sensorMinute: Int64
    public let kind: ReadingSampleKind
    public let receivedAt: Date
    public let glucoseMGDL: Int
    public let quality: String
    public let origin: ReadingOrigin
    public let decoderVersion: String

    public init(
        sensorMinute: Int64,
        kind: ReadingSampleKind,
        receivedAt: Date,
        glucoseMGDL: Int,
        quality: String,
        origin: ReadingOrigin,
        decoderVersion: String
    ) {
        self.sensorMinute = sensorMinute
        self.kind = kind
        self.receivedAt = receivedAt
        self.glucoseMGDL = glucoseMGDL
        self.quality = quality
        self.origin = origin
        self.decoderVersion = decoderVersion
    }
}

public struct ReadingSubmission: Equatable, Sendable {
    public let sequence: UInt64
    public let session: ReadingSessionSnapshot
    public let candidates: [ReadingCandidate]

    public init(sequence: UInt64, session: ReadingSessionSnapshot, candidates: [ReadingCandidate]) {
        self.sequence = sequence
        self.session = session
        self.candidates = candidates
    }
}

public struct ReadingDestination: Equatable, Sendable {
    public let id: UUID
    public let backendKind: String
    public let normalizedEndpointIdentity: String
    public let credentialReference: String
    public let configurationRevision: Int
    public let enabled: Bool

    public init(
        id: UUID,
        backendKind: String,
        normalizedEndpointIdentity: String,
        credentialReference: String,
        configurationRevision: Int,
        enabled: Bool
    ) {
        self.id = id
        self.backendKind = backendKind
        self.normalizedEndpointIdentity = normalizedEndpointIdentity
        self.credentialReference = credentialReference
        self.configurationRevision = configurationRevision
        self.enabled = enabled
    }
}

public enum ReadingDeliveryState: String, Codable, CaseIterable, Sendable {
    case unassigned
    case queued
    case claimed
    case acknowledged
    case quarantined
}

public struct ReadingCommit: Equatable, Sendable {
    public let submissionSequence: UInt64
    public let readingIDs: [UUID]

    public init(submissionSequence: UInt64, readingIDs: [UUID]) {
        self.submissionSequence = submissionSequence
        self.readingIDs = readingIDs
    }
}

public struct DestinationAssignmentCommit: Equatable, Sendable {
    public let destinationID: UUID
    public let readingIDs: [UUID]

    public init(destinationID: UUID, readingIDs: [UUID]) {
        self.destinationID = destinationID
        self.readingIDs = readingIDs
    }
}

public enum ReadingStoreOperation: String, Codable, Sendable {
    case load
    case ingest
    case assignDestination
    case clearDestination
    case publication
    case retry
    case query
    case close
}

public struct ReadingStoreFailure: Error, Equatable, Sendable {
    public let operation: ReadingStoreOperation
    public let occurredAt: Date
    public let redactedReason: String
    public let droppedCandidateCount: Int
    public let durableCommitAwaitingPublication: Bool

    public init(
        operation: ReadingStoreOperation,
        occurredAt: Date = Date(),
        redactedReason: String,
        droppedCandidateCount: Int,
        durableCommitAwaitingPublication: Bool = false
    ) {
        self.operation = operation
        self.occurredAt = occurredAt
        self.redactedReason = redactedReason
        self.droppedCandidateCount = droppedCandidateCount
        self.durableCommitAwaitingPublication = durableCommitAwaitingPublication
    }
}

public enum ReadingStoreHealth: Equatable, Sendable {
    case notLoaded
    case healthy
    case unhealthy(ReadingStoreFailure)
    case closed
}

public enum ReadingStoreError: Error, Equatable, Sendable {
    case unavailable(ReadingStoreHealth)
    case invalidInput(String)
    case repairRequired(String)
    case retriesExhausted
    case operationFailed(ReadingStoreFailure)
    case ownershipRejected(ReadingCommitRejection)
}

/// Expected cancellation or binding rejection, not a persistence health failure.
public enum ReadingCommitRejection: Equatable, Sendable {
    case staleFrame
    case submissionMismatch
}

public enum ReadingStoreFaultPoint: String, CaseIterable, Sendable {
    case beforeLoad
    case beforeSave
    case beforeCommitAdmission
    case afterCommitAdmission
    case afterSaveBeforePublication
}

public final class ReadingStoreFaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [ReadingStoreFaultPoint: [String]] = [:]
    #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
    private var pauses: [ReadingStoreFaultPoint: [ReadingStoreTestBarrier]] = [:]

    func pauseNext(at point: ReadingStoreFaultPoint) -> ReadingStoreTestBarrier {
        let barrier = ReadingStoreTestBarrier()
        lock.lock()
        pauses[point, default: []].append(barrier)
        lock.unlock()
        return barrier
    }
    #endif

    public init() {}

    public func failNext(at point: ReadingStoreFaultPoint, message: String = "injected failure") {
        lock.lock()
        failures[point, default: []].append(message)
        lock.unlock()
    }

    func check(_ point: ReadingStoreFaultPoint) throws {
        #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
        lock.lock()
        let barrier = pauses[point]?.isEmpty == false ? pauses[point]?.removeFirst() : nil
        lock.unlock()
        try barrier?.arriveAndWait(at: point)
        #endif
        lock.lock()
        defer { lock.unlock() }
        guard var messages = failures[point], !messages.isEmpty else { return }
        let message = messages.removeFirst()
        failures[point] = messages
        throw ReadingStoreInjectedFault(point: point, message: message)
    }
}

#if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
/// Portable race fixtures only. Bounded semaphore waits cannot run application
/// callbacks or ship in the app target, which never defines this compilation flag.
final class ReadingStoreTestBarrier: @unchecked Sendable {
    private let reached = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func waitUntilReached(timeout: TimeInterval = 5) -> Bool {
        reached.wait(timeout: .now() + timeout) == .success
    }

    func resume() { released.signal() }

    fileprivate func arriveAndWait(at point: ReadingStoreFaultPoint) throws {
        reached.signal()
        guard released.wait(timeout: .now() + 10) == .success else {
            throw ReadingStoreInjectedFault(point: point,
                                            message: "ownership fixture barrier timed out")
        }
    }
}
#endif

public struct ReadingStoreInjectedFault: Error, Equatable, Sendable {
    public let point: ReadingStoreFaultPoint
    public let message: String

    public init(point: ReadingStoreFaultPoint, message: String) {
        self.point = point
        self.message = message
    }
}

public struct ReadingStoreConfiguration: Equatable, Sendable {
    public enum Storage: Equatable, Sendable {
        case inMemory(identifier: String)
        case sqlite(url: URL)
    }

    public let storage: Storage
    public let maxCandidatesPerSubmission: Int
    public let maxExplicitRetries: Int
    public let sampleDateTolerance: TimeInterval
    public let publishedCommitHistoryLimit: Int

    public init(
        storage: Storage,
        maxCandidatesPerSubmission: Int = 64,
        maxExplicitRetries: Int = 3,
        sampleDateTolerance: TimeInterval = 1,
        publishedCommitHistoryLimit: Int = 64
    ) {
        self.storage = storage
        self.maxCandidatesPerSubmission = maxCandidatesPerSubmission
        self.maxExplicitRetries = maxExplicitRetries
        self.sampleDateTolerance = sampleDateTolerance
        self.publishedCommitHistoryLimit = publishedCommitHistoryLimit
    }
}

public struct StoredSessionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let stableIdentityFingerprint: Data
    public let sensorRevision: String
    public let firstObservedAt: Date
    public let lastObservedAt: Date
    public let lifecycleState: ReadingSessionLifecycle
    public let clock: ReadingClockSnapshot
}

public struct StoredReadingSnapshot: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let sensorMinute: Int64
    public let kind: ReadingSampleKind
    public let sampleDate: Date
    public let receivedAt: Date
    public let glucoseMGDL: Int
    public let quality: String
    public let primaryOrigin: ReadingOrigin
    public let observedOriginFlags: Int64
    public let decoderVersion: String
    public let createdAt: Date
}

public struct ReadingDeliverySnapshot: Equatable, Sendable {
    public let readingID: UUID
    public let destinationID: UUID?
    public let state: ReadingDeliveryState
    public let payload: Data?
    public let payloadVersion: Int?
    public let attemptCount: Int
    public let leaseID: UUID?
    public let leaseExpiresAt: Date?
    public let nextEligibleAt: Date?
    public let lastError: String?
    public let acknowledgedAt: Date?
}

public struct ReadingDestinationSnapshot: Equatable, Sendable {
    public let id: UUID
    public let backendKind: String
    public let normalizedEndpointIdentity: String
    public let credentialReference: String
    public let configurationRevision: Int
    public let enabled: Bool
    public let selected: Bool
}

public struct ReadingConflictSnapshot: Equatable, Sendable {
    public let id: UUID
    public let readingID: UUID
    public let observedAt: Date
    public let candidateOrigin: ReadingOrigin
    public let discrepancyFlags: [String]
}

public struct ReadingStoreSnapshot: Equatable, Sendable {
    public let health: ReadingStoreHealth
    public let sessions: [StoredSessionSnapshot]
    public let readings: [StoredReadingSnapshot]
    public let deliveries: [ReadingDeliverySnapshot]
    public let destinations: [ReadingDestinationSnapshot]
    public let conflicts: [ReadingConflictSnapshot]
    public let publishedCommits: [ReadingCommit]
}
