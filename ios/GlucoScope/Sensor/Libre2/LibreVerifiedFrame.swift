import CoreData
import Foundation

/// Transport-owned snapshot. A missing durable ID permits experimental diagnostics only.
/// No consumer may replace this session with a newer Keychain or UI session.
struct LibreVerifiedFrame: Sendable {
    let payload: Data
    let receivedAt: Date
    let sequence: UInt64
    let generation: UInt64
    let sessionSnapshot: LibreSensorSession
    let persistenceSessionID: UUID?
}

/// One transport activation's revocation state. Only the generation gate in this
/// file can create or expose it through a bound admission. Lock order is generation
/// gate -> ownership; the writer never takes the generation lock under this lock.
final class ReadingCommitOwnership: @unchecked Sendable {
    private let lock = NSLock()
    private var isValid = true
    #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
    // Installed/consumed only while the generation lock is held. The writer
    // never touches this observer; it only holds the epoch lock being observed.
    private var invalidationContentionObserver: DispatchSemaphore?

    fileprivate func observeNextInvalidationContention(_ observer: DispatchSemaphore) {
        invalidationContentionObserver = observer
    }
    #endif

    fileprivate init() {}

    fileprivate func invalidate() {
        #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
        let observer = invalidationContentionObserver
        invalidationContentionObserver = nil
        if !lock.try() {
            observer?.signal()
            lock.lock()
        }
        #else
        lock.lock()
        #endif
        defer { lock.unlock() }
        isValid = false
    }

    fileprivate func makeAdmission(
        sequence: UInt64,
        session: ReadingSessionSnapshot,
        receivedAt: Date
    ) -> ReadingCommitAdmission {
        ReadingCommitAdmission(
            ownership: self, sequence: sequence, session: session, receivedAt: receivedAt
        )
    }

    /// Specialized writer operation: no caller-supplied closure or asynchronous
    /// work can run while invalidation is excluded. The writer context is private.
    func save(_ context: NSManagedObjectContext, faultInjector: ReadingStoreFaultInjector?) throws {
        lock.lock()
        defer { lock.unlock() }
        guard isValid else { throw ReadingStoreError.ownershipRejected(.staleFrame) }
        try faultInjector?.check(.afterCommitAdmission)
        if context.hasChanges {
            try faultInjector?.check(.beforeSave)
            try context.save()
        }
    }
}

/// Shared by the serial BLE queue and the main-actor consumer. Invalidation happens
/// before dispatching lifecycle events, so already queued callbacks become stale.
final class LibreFrameGenerationGate: @unchecked Sendable {
    private static let sequenceLock = NSLock()
    private static var nextSequence: UInt64 = 0
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var session: LibreSensorSession?
    private var durableID: UUID?
    private var commitOwnership: ReadingCommitOwnership?

    #if LIBRE2_COMMIT_OWNERSHIP_FIXTURES
    /// Observes actual revocation contention, not a scheduler-dependent delay.
    /// No callback runs, and the app target does not compile this fixture API.
    @discardableResult
    func observeNextInvalidationContention(_ observer: DispatchSemaphore) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let commitOwnership else { return false }
        commitOwnership.observeNextInvalidationContention(observer)
        return true
    }
    #endif

    @discardableResult
    func activate(session: LibreSensorSession, persistenceSessionID: UUID?) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        commitOwnership?.invalidate()
        precondition(generation < UInt64.max)
        generation += 1
        self.session = session
        durableID = persistenceSessionID
        commitOwnership = ReadingCommitOwnership()
        return generation
    }

    var activeGeneration: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return session == nil ? nil : generation
    }

    var currentGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func isGenerationCurrent(_ value: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == generation
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        commitOwnership?.invalidate()
        commitOwnership = nil
        precondition(generation < UInt64.max)
        generation += 1
        session = nil
        durableID = nil
    }

    func makeFrame(payload: Data, receivedAt: Date) -> LibreVerifiedFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard let session else { return nil }
        Self.sequenceLock.lock()
        precondition(Self.nextSequence < UInt64.max)
        Self.nextSequence += 1
        let sequence = Self.nextSequence
        Self.sequenceLock.unlock()
        return LibreVerifiedFrame(payload: payload, receivedAt: receivedAt, sequence: sequence,
                                  generation: generation, sessionSnapshot: session,
                                  persistenceSessionID: durableID)
    }

    func isCurrent(_ frame: LibreVerifiedFrame) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return matches(frame)
    }

    /// Captures revocable writer authority, without decoding or submitting work.
    /// Hash/clock checks happen outside the generation lock; current ownership is
    /// rechecked when issuing the admission. A later activation can only revoke it.
    func makeCommitAdmission(
        for frame: LibreVerifiedFrame,
        session canonical: ReadingSessionSnapshot
    ) throws -> ReadingCommitAdmission {
        guard isCurrent(frame) else { throw LibreFrameOwnershipError.staleFrame }
        var captured = frame.sessionSnapshot
        // Fingerprint/protocol helpers use zero-based byte positions; immutable
        // frame equality below still compares the original transport snapshot.
        captured.uid = Data([UInt8](captured.uid))
        captured.patchInfo = Data([UInt8](captured.patchInfo))
        guard let id = frame.persistenceSessionID,
              (try? captured.validatedPersistenceSessionID()) == id else {
            throw LibreFrameOwnershipError.missingDurableIdentity
        }
        guard captured.setupComplete, canonical.id == id,
              (try? captured.stableIdentityFingerprint()) == canonical.stableIdentityFingerprint,
              canonical.sensorRevision == captured.sensorKind.rawValue,
              let anchor = captured.clockAnchor,
              (try? anchor.validateOwnership(uid: captured.uid, patchInfo: captured.patchInfo)) != nil,
              anchor.uncertaintySeconds == 60,
              canonical.clock.referenceSensorMinute == Int64(anchor.referenceSensorMinute),
              abs(canonical.clock.referenceDate.timeIntervalSince(anchor.referenceDate)) <= 0.001,
              canonical.clock.provenance == LibreSensorClockAnchor.canonicalPersistenceProvenance else {
            throw LibreFrameOwnershipError.sessionMismatch
        }
        lock.lock()
        defer { lock.unlock() }
        guard matches(frame), let commitOwnership else {
            throw LibreFrameOwnershipError.staleFrame
        }
        return commitOwnership.makeAdmission(sequence: frame.sequence, session: canonical,
                                             receivedAt: frame.receivedAt)
    }

    /// For short synchronous Keychain compare-and-save work only; never await here.
    func withCurrent<T>(_ frame: LibreVerifiedFrame, _ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard matches(frame) else { throw LibreFrameOwnershipError.staleFrame }
        return try body()
    }

    private func matches(_ frame: LibreVerifiedFrame) -> Bool {
        generation == frame.generation && session == frame.sessionSnapshot && durableID == frame.persistenceSessionID
    }
}

enum LibreFrameOwnershipError: Error, Equatable {
    case staleFrame
    case missingDurableIdentity
    case sessionMismatch
}
