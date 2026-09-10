import Foundation

enum LibrePersistenceBridgeError: LocalizedError, Equatable {
    case staleSession
    case clockUnavailable
    case unsupportedClock
    case clockDisagreement
    case canonicalMetadataMissing

    var errorDescription: String? {
        switch self {
        case .staleSession:
            return "The Libre sensor session changed before persistence completed."
        case .clockUnavailable:
            return "The saved Libre clock is unavailable; deliberate repair is required."
        case .unsupportedClock:
            return "The saved Libre clock cannot be represented by this persistence version."
        case .clockDisagreement:
            return "The saved Libre clock disagrees with canonical metadata; deliberate repair is required."
        case .canonicalMetadataMissing:
            return "No canonical Libre metadata exists for missing-clock repair."
        }
    }
}

struct LibrePersistencePreparation: Equatable, Sendable {
    let session: LibreSensorSession
    let sessionSnapshot: ReadingSessionSnapshot
}

typealias LibrePersistenceCurrentTransaction = (
    _ operation: @escaping () throws -> LibreSensorSession
) throws -> LibreSensorSession

struct LibrePersistenceBridgeDependencies {
    let loadForIngestion: (LibreSensorSession) throws -> LibreSensorSession
    let restoreMissingClockAnchor: (
        LibreSensorClockAnchor,
        LibreSensorSession
    ) throws -> LibreSensorSession
    let resolveSessionMetadata: (ReadingSessionSnapshot) async throws -> StoredSessionSnapshot
    let querySessionMetadata: (UUID, Data, String) async throws -> StoredSessionSnapshot?
    let openStore: () async throws -> Void
    let retryStoreAfterFailure: () async throws -> Void
    let currentStoreHealth: () async -> ReadingStoreHealth

    init(
        loadForIngestion: @escaping (LibreSensorSession) throws -> LibreSensorSession,
        restoreMissingClockAnchor: @escaping (
            LibreSensorClockAnchor,
            LibreSensorSession
        ) throws -> LibreSensorSession,
        resolveSessionMetadata: @escaping (
            ReadingSessionSnapshot
        ) async throws -> StoredSessionSnapshot,
        querySessionMetadata: @escaping (
            UUID,
            Data,
            String
        ) async throws -> StoredSessionSnapshot?,
        openStore: @escaping () async throws -> Void = {},
        retryStoreAfterFailure: @escaping () async throws -> Void = {},
        currentStoreHealth: @escaping () async -> ReadingStoreHealth = { .healthy }
    ) {
        self.loadForIngestion = loadForIngestion
        self.restoreMissingClockAnchor = restoreMissingClockAnchor
        self.resolveSessionMetadata = resolveSessionMetadata
        self.querySessionMetadata = querySessionMetadata
        self.openStore = openStore
        self.retryStoreAfterFailure = retryStoreAfterFailure
        self.currentStoreHealth = currentStoreHealth
    }
}

/// Reconciles wear identity and non-secret clock metadata only. No decoder result,
/// glucose candidate, display value or upload payload crosses this boundary.
actor LibrePersistenceBridge {
    private let dependencies: LibrePersistenceBridgeDependencies

    init(dependencies: LibrePersistenceBridgeDependencies) {
        self.dependencies = dependencies
    }

    init(readingStore: ReadingStore, sessionStore: LibreSessionStore) {
        self.dependencies = LibrePersistenceBridgeDependencies(
            loadForIngestion: { try sessionStore.loadForIngestion(matching: $0) },
            restoreMissingClockAnchor: {
                try sessionStore.restoreMissingClockAnchor($0, matching: $1)
            },
            resolveSessionMetadata: { try await readingStore.resolveSessionMetadata($0) },
            querySessionMetadata: {
                try await readingStore.sessionMetadata(
                    id: $0,
                    stableIdentityFingerprint: $1,
                    sensorRevision: $2
                )
            },
            openStore: { try await readingStore.load() },
            retryStoreAfterFailure: { _ = try await readingStore.retryAfterFailure() },
            currentStoreHealth: { await readingStore.currentHealth() }
        )
    }

    func openStore() async throws {
        try await dependencies.openStore()
    }

    func retryStoreAfterFailure() async throws {
        try await dependencies.retryStoreAfterFailure()
    }

    func currentStoreHealth() async -> ReadingStoreHealth {
        await dependencies.currentStoreHealth()
    }

    func prepare(
        session capturedSession: LibreSensorSession,
        receivedAt: Date,
        isCurrent: @escaping () -> Bool
    ) async throws -> LibrePersistencePreparation {
        guard isCurrent() else { throw LibrePersistenceBridgeError.staleSession }
        let latest = try dependencies.loadForIngestion(capturedSession)
        guard isCurrent() else { throw LibrePersistenceBridgeError.staleSession }

        // A later counter reservation or peripheral discovery does not invalidate
        // authenticated bytes. Calibration, clock and exact sensor bytes do: never
        // relabel an older callback with a newer Keychain snapshot.
        guard latest.uid == capturedSession.uid,
              latest.patchInfo == capturedSession.patchInfo,
              latest.calibration == capturedSession.calibration,
              latest.clockAnchor == capturedSession.clockAnchor else {
            throw LibrePersistenceBridgeError.staleSession
        }
        if capturedSession.persistenceSessionID != nil {
            guard try capturedSession.validatedPersistenceSessionID()
                    == latest.validatedPersistenceSessionID() else {
                throw LibrePersistenceBridgeError.staleSession
            }
        }
        let frameSession = try capturedSession.retainingDurableIdentity(from: latest)

        let proposed = try Self.makeSessionSnapshot(session: frameSession, observedAt: receivedAt)
        let stored = try await dependencies.resolveSessionMetadata(proposed)
        guard isCurrent() else { throw LibrePersistenceBridgeError.staleSession }
        guard Self.clocksMatch(stored.clock, proposed.clock) else {
            throw LibrePersistenceBridgeError.clockDisagreement
        }
        return LibrePersistencePreparation(
            session: frameSession,
            sessionSnapshot: Self.ingestionSnapshot(from: stored)
        )
    }

    /// Explicit same-wear repair for an unavailable Keychain anchor. The caller's
    /// transaction must hold its generation/session lock while invoking `operation`.
    /// A valid but different Keychain clock is always rejected.
    func repairMissingClockAnchor(
        session capturedSession: LibreSensorSession,
        receivedAt: Date,
        withCurrent: LibrePersistenceCurrentTransaction
    ) async throws -> LibrePersistencePreparation {
        let latest = try dependencies.loadForIngestion(capturedSession)
        if capturedSession.persistenceSessionID != nil {
            guard try capturedSession.validatedPersistenceSessionID()
                    == latest.validatedPersistenceSessionID() else {
                throw LibrePersistenceBridgeError.staleSession
            }
        }
        guard latest.needsClockAnchor else {
            throw LibrePersistenceBridgeError.clockDisagreement
        }
        let id = try latest.validatedPersistenceSessionID()
        let fingerprint = try latest.stableIdentityFingerprint()
        let revision = latest.sensorKind.rawValue
        guard let stored = try await dependencies.querySessionMetadata(id, fingerprint, revision) else {
            throw LibrePersistenceBridgeError.canonicalMetadataMissing
        }
        let anchor: LibreSensorClockAnchor
        do {
            anchor = try LibreSensorClockAnchor.restoreCanonical(
                referenceDate: stored.clock.referenceDate,
                referenceSensorMinute: stored.clock.referenceSensorMinute,
                provenance: stored.clock.provenance,
                ownerUID: latest.uid,
                ownerPatchInfo: latest.patchInfo
            )
        } catch {
            throw LibrePersistenceBridgeError.unsupportedClock
        }
        let repaired = try withCurrent {
            try self.dependencies.restoreMissingClockAnchor(anchor, latest)
        }
        let proposed = try Self.makeSessionSnapshot(session: repaired, observedAt: receivedAt)
        let resolved = try await dependencies.resolveSessionMetadata(proposed)
        guard Self.clocksMatch(resolved.clock, proposed.clock) else {
            throw LibrePersistenceBridgeError.clockDisagreement
        }
        _ = try withCurrent { repaired }
        return LibrePersistencePreparation(
            session: repaired,
            sessionSnapshot: Self.ingestionSnapshot(from: resolved)
        )
    }
}

private extension LibrePersistenceBridge {
    static func makeSessionSnapshot(
        session: LibreSensorSession,
        observedAt: Date
    ) throws -> ReadingSessionSnapshot {
        let id = try session.validatedPersistenceSessionID()
        let fingerprint = try session.stableIdentityFingerprint()
        guard let anchor = session.clockAnchor else {
            throw LibrePersistenceBridgeError.clockUnavailable
        }
        try anchor.validateOwnership(uid: session.uid, patchInfo: session.patchInfo)
        guard anchor.uncertaintySeconds == 60 else {
            throw LibrePersistenceBridgeError.unsupportedClock
        }
        return ReadingSessionSnapshot(
            id: id,
            stableIdentityFingerprint: fingerprint,
            sensorRevision: session.sensorKind.rawValue,
            firstObservedAt: observedAt,
            observedAt: observedAt,
            lifecycleState: .active,
            clock: ReadingClockSnapshot(
                referenceSensorMinute: Int64(anchor.referenceSensorMinute),
                referenceDate: anchor.referenceDate,
                provenance: LibreSensorClockAnchor.canonicalPersistenceProvenance
            )
        )
    }

    static func clocksMatch(_ lhs: ReadingClockSnapshot, _ rhs: ReadingClockSnapshot) -> Bool {
        lhs.referenceSensorMinute == rhs.referenceSensorMinute &&
        abs(lhs.referenceDate.timeIntervalSince(rhs.referenceDate)) <= 0.001 &&
        lhs.provenance == rhs.provenance
    }

    static func ingestionSnapshot(from stored: StoredSessionSnapshot) -> ReadingSessionSnapshot {
        ReadingSessionSnapshot(
            id: stored.id,
            stableIdentityFingerprint: stored.stableIdentityFingerprint,
            sensorRevision: stored.sensorRevision,
            firstObservedAt: stored.firstObservedAt,
            observedAt: stored.lastObservedAt,
            lifecycleState: stored.lifecycleState,
            clock: stored.clock
        )
    }
}
