import Foundation

struct LibreStorageProbeFileObservation: Equatable, Sendable {
    let fileName: String
    let phase: String
    let result: String
}

/// UIKit supplies actual state, never a notification name interpreted as lock proof.
@MainActor
struct LibreStorageProbeLockEnvironment {
    let isProtectedDataAvailable: () -> Bool
    let isBackground: () -> Bool
    let beginBackgroundTask: (@escaping @MainActor () -> Void) -> Bool
    let endBackgroundTask: () -> Void
}

struct LibreStorageProbeStatus: Equatable, Sendable {
    var isRunning = false
    var phase = "Not run"
    var detail = "Deliberate synthetic metadata test in a separate store; no sensor needed."
    var lastOperationAt: Date?
    var reopenVerified = false
    var relaunchVerified = false
    var fileObservations: [LibreStorageProbeFileObservation] = []
    var lockedVerificationArmed = false
    var lockedVerificationAttempted = false
    var lockedVerified = false
    var lockedSequenceCompleted = false
    var lockedObservations: [String] = []

    var reportLines: [String] {
        var lines = [
            "Storage probe: \(phase)",
            detail,
            "Scope: isolated synthetic session/clock metadata only; no glucose, deliveries or uploads",
            "Metadata reopen verified: \(reopenVerified)",
            "Metadata relaunch verified: \(relaunchVerified)",
            "Protection attributes alone do not establish locked-device accessibility.",
            "Locked verification armed: \(lockedVerificationArmed)",
            "Locked verification attempted: \(lockedVerificationAttempted)",
            "Locked write/read/reopen verified on iOS: \(lockedVerified)",
            "Locked scope excludes post-reboot access, readings, delivery durability and background scheduling reliability."
        ]
        if let lastOperationAt {
            lines.append("Probe operation time: \(ISO8601DateFormatter().string(from: lastOperationAt))")
        }
        lines += lockedObservations
        lines += fileObservations.map { "\($0.phase) / \($0.fileName): \($0.result)" }
        return lines
    }
}

/// A deliberately separate store with no ingestion, sensor, viewer, or delivery
/// dependency. Initializing this service performs no filesystem operation.
@MainActor
final class LibreStorageProbe {
    static let directoryName = "GlucoScopeStorageProbe-v1"
    static let databaseName = "synthetic-metadata.sqlite"
    static let manifestName = "synthetic-probe.json"
    // Shared by all service instances in this process, never saved as a preference.
    private static let processLaunchID = UUID()

    private(set) var status = LibreStorageProbeStatus()
    private let applicationSupportDirectory: URL?
    private let onStatus: (LibreStorageProbeStatus) -> Void
    private var worker: Task<Void, Never>?
    private var lockDeadlineTask: Task<Void, Never>?
    private var lockEnvironment: LibreStorageProbeLockEnvironment?
    private var lockDeadline = ContinuousClock.now
    private var lockAttemptID: UUID?
    private var backgroundTaskActive = false
    private var lockInvalidated = false
    static let lockedDirectoryName = "GlucoScopeLockedStorageProbe-v1"

    init(applicationSupportDirectory: URL? = nil,
         onStatus: @escaping (LibreStorageProbeStatus) -> Void = { _ in }) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.onStatus = onStatus
    }

    func start() { begin(allowCreation: true) }
    func verifyPreviousRun() { begin(allowCreation: false) }

    /// Lets portable fixtures await the same operation driven by the UI buttons.
    func waitForCurrentOperation() async { await worker?.value }

    private func begin(allowCreation: Bool) {
        guard !status.isRunning else { return }
        status = LibreStorageProbeStatus()
        status.isRunning = true
        status.phase = "Running"
        status.detail = "Checking the isolated synthetic metadata store."
        publish()
        worker = Task {
            do {
                let directory = try probeDirectory()
                if try itemType(at: directory) != nil {
                    try await verifyExisting(in: directory)
                } else if allowCreation {
                    try await createFixture(in: directory)
                } else {
                    throw ProbeFailure("No previous probe exists. Run the synthetic probe first.")
                }
            } catch let failure as ProbeFailure {
                status.phase = "Failed"
                status.detail = failure.message
            } catch {
                status.phase = "Failed"
                status.detail = "The isolated probe could not complete its storage operation; retained files were not reset."
            }
            status.isRunning = false
            publish()
        }
    }

    /// Explicit foreground action only. The lease and monotonic deadline bound this
    /// one attempt; neither a background transition nor an advance lock notification
    /// suffices. The ordinary v7 persistence fixture is never opened here.
    func armLockedVerification(environment: LibreStorageProbeLockEnvironment,
                               maximumWaitSeconds: TimeInterval = 120) {
        guard !status.isRunning else { return }
        status = LibreStorageProbeStatus()
        status.isRunning = true
        status.lockedVerificationArmed = true
        status.phase = "Waiting for protected data"
        status.detail = "Lock the phone now. One isolated metadata write/read/reopen will run only while protected data is unavailable and the app is in the background."
        lockEnvironment = environment
        lockInvalidated = false
        let duration = maximumWaitSeconds.isFinite ? min(120, max(0.001, maximumWaitSeconds)) : 120
        lockDeadline = ContinuousClock.now.advanced(by: .seconds(duration))
        let attemptID = UUID()
        lockAttemptID = attemptID
        backgroundTaskActive = environment.beginBackgroundTask { [weak self] in
            guard let self, self.lockAttemptID == attemptID else { return }
            self.invalidateLockedAttempt("iOS background execution expired; no locked verification was established.")
        }
        guard backgroundTaskActive, !lockInvalidated else {
            invalidateLockedAttempt("Background execution was unavailable; no locked verification was established.")
            finishLockedAttempt()
            return
        }
        publish()
        let deadline = lockDeadline
        lockDeadlineTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self, self.lockAttemptID == attemptID else { return }
            self.invalidateLockedAttempt("The bounded wait ended; no locked verification was established.")
        }
        worker = Task {
            do {
                while environment.isProtectedDataAvailable() || !environment.isBackground() {
                    try checkLockedLifetime()
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                try checkLockedLifetime()
                status.lockedVerificationAttempted = true
                status.lockedVerificationArmed = false
                status.phase = "Checking locked storage"
                publish()
                try await performLockedStorageSequence()
                try lockedCheckpoint("Sequence completed")
                status.lockedSequenceCompleted = true
                #if os(iOS)
                status.lockedVerified = true
                status.phase = "Locked storage verified"
                status.detail = "A fresh synthetic metadata mutation survived read and store reopen with protected data unavailable at every observed boundary; zero readings or deliveries."
                #else
                status.phase = "Synthetic locked sequence passed"
                status.detail = "Injected state exercised the storage sequence; this platform cannot establish iOS locked-device accessibility."
                #endif
            } catch {
                if !lockInvalidated {
                    status.phase = "Inconclusive"
                    status.detail = (error as? ProbeFailure)?.message
                        ?? "The attempted isolated storage operation failed; no locked verification was established. Retained files were not reset."
                    status.lockedVerified = false
                }
            }
            finishLockedAttempt()
        }
    }

    func cancelLockedVerification() {
        guard lockEnvironment != nil, status.isRunning else { return }
        invalidateLockedAttempt("Cancelled; no locked verification was established.")
    }

    /// Notifications only prompt a sample of current state. Once work starts, any
    /// observed availability/foreground return invalidates the whole attempt.
    func lockedEnvironmentDidChange() {
        guard let environment = lockEnvironment, status.isRunning else { return }
        if ContinuousClock.now >= lockDeadline {
            invalidateLockedAttempt("The bounded wait ended; no locked verification was established.")
        } else if status.lockedVerificationAttempted &&
                    (environment.isProtectedDataAvailable() || !environment.isBackground()) {
            invalidateLockedAttempt("Protected data became available or the app left the background during the operation; the result is inconclusive.")
        }
    }

    private func checkLockedLifetime() throws {
        try Task.checkCancellation()
        guard !lockInvalidated, backgroundTaskActive,
              ContinuousClock.now < lockDeadline else {
            throw ProbeFailure("The bounded execution window ended; no locked verification was established.")
        }
    }

    private func lockedCheckpoint(_ phase: String) throws {
        try checkLockedLifetime()
        guard let environment = lockEnvironment,
              !environment.isProtectedDataAvailable(), environment.isBackground() else {
            throw ProbeFailure("Protected data was available or the app was not in the background at a storage boundary; the result is inconclusive.")
        }
        try checkLockedLifetime()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        status.lockedObservations.append("\(timestamp) / \(phase): protected data unavailable; app background")
    }

    private func invalidateLockedAttempt(_ detail: String) {
        guard lockEnvironment != nil else { return }
        lockInvalidated = true
        status.lockedVerified = false
        status.lockedSequenceCompleted = false
        status.lockedVerificationArmed = false
        status.phase = "Inconclusive"
        status.detail = detail
        worker?.cancel()
        lockDeadlineTask?.cancel()
        endLockedBackgroundTask()
        publish()
    }

    private func endLockedBackgroundTask() {
        if backgroundTaskActive {
            backgroundTaskActive = false
            lockEnvironment?.endBackgroundTask()
        }
    }

    private func finishLockedAttempt() {
        lockDeadlineTask?.cancel()
        lockDeadlineTask = nil
        endLockedBackgroundTask()
        lockEnvironment = nil
        lockAttemptID = nil
        status.isRunning = false
        status.lockedVerificationArmed = false
        publish()
    }

    private func performLockedStorageSequence() async throws {
        try lockedCheckpoint("Before isolated directory access")
        let directory = try probeDirectory(name: Self.lockedDirectoryName)
        let type = try itemType(at: directory)
        guard type == nil || type == .typeDirectory else {
            throw ProbeFailure("The locked probe directory is not an ordinary directory; no files were changed.")
        }
        if type == nil {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path)
            #endif
        }
        let database = directory.appendingPathComponent(Self.databaseName)
        let databaseType = try itemType(at: database)
        guard type == nil || databaseType == .typeRegular else {
            throw ProbeFailure("The retained locked probe database is missing or invalid; it was not recreated.")
        }
        for suffix in ["", "-wal", "-shm"] {
            if let fileType = try itemType(at: URL(fileURLWithPath: database.path + suffix)), fileType != .typeRegular {
                throw ProbeFailure("A locked probe file is not an ordinary file; the store was not opened.")
            }
        }
        observeFiles(at: database, phase: "Locked files before open")
        let store = makeStore(at: database)
        do {
            try lockedCheckpoint("Before store open")
            try await store.load()
            try lockedCheckpoint("After store open / before initial read")
            let previous = try await store.snapshot()
            try lockedCheckpoint("After initial read")
            // A fixed isolated row bounds storage across attempts. Its timestamp
            // MUST advance, making repeat runs real saves rather than no-op upserts.
            let baseline = Date(timeIntervalSince1970: 1_700_000_000)
            let priorDate = previous.sessions.first?.lastObservedAt ?? baseline
            let priorFixture = lockedFixture(observedAt: priorDate)
            if !previous.sessions.isEmpty {
                try validate(previous, expected: priorFixture)
            } else {
                guard previous.health == .healthy, previous.readings.isEmpty,
                      previous.deliveries.isEmpty, previous.destinations.isEmpty,
                      previous.conflicts.isEmpty, previous.publishedCommits.isEmpty else {
                    throw ProbeFailure("Unexpected records were present in the locked probe; nothing was reset.")
                }
            }
            let nextDate = Date(timeIntervalSince1970: max(Date().timeIntervalSince1970,
                                                           priorDate.timeIntervalSince1970 + 1))
            guard nextDate.timeIntervalSince1970.isFinite, nextDate > priorDate else {
                throw ProbeFailure("A fresh synthetic metadata mutation could not be formed.")
            }
            let expected = lockedFixture(observedAt: nextDate)
            try lockedCheckpoint("Before fresh metadata write")
            _ = try await store.resolveSessionMetadata(expected)
            try lockedCheckpoint("After metadata save / before read")
            try validate(try await store.snapshot(), expected: expected)
            try lockedCheckpoint("After saved metadata read")
            observeFiles(at: database, phase: "Locked saved metadata, store open")
            try lockedCheckpoint("Before store close")
            try await store.close()
            try lockedCheckpoint("After store close / before reopen")
            guard try itemType(at: database) == .typeRegular else {
                throw ProbeFailure("The locked probe database disappeared; it was not recreated.")
            }
            let reopened = makeStore(at: database)
            do {
                try await reopened.load()
                try lockedCheckpoint("After store reopen / before retained read")
                try validate(try await reopened.snapshot(), expected: expected)
                try lockedCheckpoint("After reopened metadata read")
                observeFiles(at: database, phase: "Locked reopened store")
                try lockedCheckpoint("Before reopened store close")
                try await reopened.close()
                try lockedCheckpoint("After reopened store close")
            } catch {
                try? await reopened.close()
                throw error
            }
        } catch {
            // Cancellation cannot interrupt synchronous Core Data work already in
            // flight. No further evidence work is scheduled; close is cleanup only.
            try? await store.close()
            throw error
        }
    }

    private func lockedFixture(observedAt: Date) -> ReadingSessionSnapshot {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        return ReadingSessionSnapshot(
            id: UUID(uuidString: "A764E7B8-290D-4DD2-9172-C66705D81B08")!,
            stableIdentityFingerprint: Data("synthetic-locked-storage-probe-v1".utf8),
            sensorRevision: "synthetic-only", firstObservedAt: baseline,
            observedAt: observedAt, lifecycleState: .ended,
            clock: ReadingClockSnapshot(referenceSensorMinute: 120, referenceDate: baseline,
                                        provenance: "synthetic-locked-storage-probe-v1"))
    }

    private func probeDirectory(name: String? = nil) throws -> URL {
        let base: URL
        if let applicationSupportDirectory {
            base = applicationSupportDirectory
        } else if let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            base = support
        } else {
            throw ProbeFailure("Application Support is unavailable.")
        }
        guard base.isFileURL else { throw ProbeFailure("The probe requires local storage.") }
        return base.resolvingSymlinksInPath().appendingPathComponent(name ?? Self.directoryName, isDirectory: true)
    }

    private func createFixture(in directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        var manifest = Manifest(launchID: Self.processLaunchID, sessionID: UUID(), completed: false)
        // A durable incomplete marker prevents a later click from reseeding an
        // interrupted run and accidentally reporting it as persistence evidence.
        try save(manifest, in: directory)
        let database = directory.appendingPathComponent(Self.databaseName)
        let store = makeStore(at: database)
        do {
            try await store.load()
            let empty = try await store.snapshot()
            guard empty.sessions.isEmpty, empty.readings.isEmpty,
                  empty.deliveries.isEmpty, empty.destinations.isEmpty,
                  empty.conflicts.isEmpty else {
                throw ProbeFailure("The new probe store was unexpectedly populated; no fixture was written.")
            }
            _ = try await store.resolveSessionMetadata(manifest.fixture)
            try validate(try await store.snapshot(), manifest: manifest)
            observeFiles(at: database, phase: "After synthetic metadata save, store open")
            try await store.close()
        } catch {
            try? await store.close()
            throw error
        }
        observeFiles(at: database, phase: "Closed files before reopen")
        try await checkStore(at: database, manifest: manifest, phase: "Reopened store")
        manifest.completed = true
        try save(manifest, in: directory)
        status.reopenVerified = true
        status.phase = "Reopen verified"
        status.detail = "Synthetic metadata survived close and reopen; zero readings or deliveries. Relaunch the app, then verify the previous run."
    }

    private func verifyExisting(in directory: URL) async throws {
        guard try itemType(at: directory) == .typeDirectory else {
            throw ProbeFailure("The probe directory is not an ordinary directory; no files were changed.")
        }
        let database = directory.appendingPathComponent(Self.databaseName)
        // ReadingStore reapplies protection on load. Preserve the actual retained
        // attributes before it can do so; report while-open observations separately.
        observeFiles(at: database, phase: "Retained files before open")
        let manifestURL = directory.appendingPathComponent(Self.manifestName)
        guard try itemType(at: manifestURL) == .typeRegular else {
            throw ProbeFailure("The previous probe manifest is missing or invalid; no fixture was recreated.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 65_536 else {
            throw ProbeFailure("The previous probe manifest is invalid; no fixture was recreated.")
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw ProbeFailure("The previous probe manifest is unreadable or corrupt; no fixture was recreated.")
        }
        guard manifest.version == 1, manifest.completed else {
            throw ProbeFailure("The previous probe is incomplete or unsupported; no fixture was recreated.")
        }
        try await checkStore(at: database, manifest: manifest, phase: "Verified store open")
        status.reopenVerified = true
        status.relaunchVerified = manifest.launchID != Self.processLaunchID
        status.phase = status.relaunchVerified ? "Relaunch verified" : "Relaunch pending"
        status.detail = status.relaunchVerified
            ? "Retained synthetic metadata matched in a new app process; zero readings or deliveries."
            : "Retained synthetic metadata matched, but this is the same app process. Relaunch the app, then verify again."
    }

    private func checkStore(at database: URL, manifest: Manifest, phase: String) async throws {
        // Do not allow Core Data to silently create a missing database, or follow
        // a replaced SQLite/sidecar symlink into another store.
        guard try itemType(at: database) == .typeRegular else {
            throw ProbeFailure("The previous probe database is missing or invalid; it was not recreated.")
        }
        for suffix in ["-wal", "-shm"] {
            if let type = try itemType(at: URL(fileURLWithPath: database.path + suffix)), type != .typeRegular {
                throw ProbeFailure("A probe sidecar is not an ordinary file; the store was not opened.")
            }
        }
        let store = makeStore(at: database)
        do {
            try await store.load()
            // Verification never upserts, ingests, assigns, repairs or resets.
            try validate(try await store.snapshot(), manifest: manifest)
            observeFiles(at: database, phase: phase)
            try await store.close()
        } catch {
            try? await store.close()
            throw error
        }
    }

    private func makeStore(at database: URL) -> ReadingStore {
        ReadingStore(configuration: ReadingStoreConfiguration(storage: .sqlite(url: database)))
    }

    private func validate(_ snapshot: ReadingStoreSnapshot, manifest: Manifest) throws {
        try validate(snapshot, expected: manifest.fixture)
    }

    private func validate(_ snapshot: ReadingStoreSnapshot, expected: ReadingSessionSnapshot) throws {
        guard snapshot.health == .healthy, snapshot.sessions.count == 1,
              let session = snapshot.sessions.first,
              session.id == expected.id,
              session.stableIdentityFingerprint == expected.stableIdentityFingerprint,
              session.sensorRevision == expected.sensorRevision,
              session.firstObservedAt == expected.firstObservedAt,
              session.lastObservedAt == expected.observedAt,
              session.lifecycleState == expected.lifecycleState,
              session.clock == expected.clock,
              snapshot.readings.isEmpty, snapshot.deliveries.isEmpty,
              snapshot.destinations.isEmpty, snapshot.conflicts.isEmpty,
              snapshot.publishedCommits.isEmpty else {
            throw ProbeFailure("The saved synthetic fixture did not match, or unexpected records were present; no data was repaired.")
        }
    }

    private func save(_ manifest: Manifest, in directory: URL) throws {
        let url = directory.appendingPathComponent(Self.manifestName)
        let data = try JSONEncoder().encode(manifest)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func observeFiles(at database: URL, phase: String) {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: database.path + suffix)
            let result: String
            do {
                if try itemType(at: url) == nil {
                    result = "Missing at inspection time; protection not verified"
                } else if try itemType(at: url) != .typeRegular {
                    result = "Not an ordinary file; protection not verified"
                } else {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    #if os(iOS)
                    let rawProtection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
                        ?? (attributes[.protectionKey] as? String)
                    if let rawProtection {
                        result = rawProtection == FileProtectionType.completeUntilFirstUserAuthentication.rawValue
                            ? "Actual protection: completeUntilFirstUserAuthentication (expected)"
                            : "Actual protection: \(rawProtection) (does not match expected protection)"
                    } else {
                        result = "Protection attribute unavailable; protection not verified"
                    }
                    #else
                    _ = attributes
                    result = "File present; iOS protection inspection unsupported on this platform"
                    #endif
                }
            } catch {
                result = "Attributes unreadable; protection not verified"
            }
            status.fileObservations.append(.init(fileName: Self.databaseName + suffix, phase: phase, result: result))
        }
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func publish() {
        status.lastOperationAt = Date()
        onStatus(status)
    }

    private struct ProbeFailure: Error { let message: String; init(_ message: String) { self.message = message } }

    private struct Manifest: Codable {
        var version = 1
        let launchID: UUID
        let sessionID: UUID
        var completed: Bool

        var fixture: ReadingSessionSnapshot {
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            return ReadingSessionSnapshot(
                id: sessionID,
                stableIdentityFingerprint: Data("synthetic-storage-probe-v1".utf8),
                sensorRevision: "synthetic-only",
                firstObservedAt: date,
                observedAt: date,
                lifecycleState: .ended,
                clock: ReadingClockSnapshot(referenceSensorMinute: 120, referenceDate: date,
                                            provenance: "synthetic-storage-probe-v1")
            )
        }
    }
}
