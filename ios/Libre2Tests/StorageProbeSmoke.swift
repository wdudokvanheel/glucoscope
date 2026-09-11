import Foundation

@main
struct StorageProbeSmoke {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.count == 3 {
            let probe = LibreStorageProbe(applicationSupportDirectory: URL(fileURLWithPath: CommandLine.arguments[2]))
            if CommandLine.arguments[1] == "seed" {
                probe.start()
                await probe.waitForCurrentOperation()
                try expect(probe.status.reopenVerified && !probe.status.relaunchVerified, "seed must prove reopen only")
            } else {
                probe.verifyPreviousRun()
                await probe.waitForCurrentOperation()
                try expect(probe.status.reopenVerified && probe.status.relaunchVerified, "a separate process must verify retained metadata")
            }
            return
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("libre-probe-smoke-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await explicitActionsAndIsolation(root.appendingPathComponent("actions"))
        try await invalidRetainedState(root.appendingPathComponent("invalid"))
        try await unexpectedRecords(root.appendingPathComponent("unexpected"))
        try await symlinkIsolation(root.appendingPathComponent("symlink"))
        try await lockedStorageChecks(root.appendingPathComponent("locked"))
        let relaunch = root.appendingPathComponent("relaunch")
        try runProcess("seed", directory: relaunch)
        try runProcess("verify", directory: relaunch)
        print("Libre storage probe synthetic isolation, metadata reopen and separate-process relaunch checks passed (no iOS protection or hardware validation).")
    }

    @MainActor
    static func explicitActionsAndIsolation(_ base: URL) async throws {
        let probe = LibreStorageProbe(applicationSupportDirectory: base)
        try expect(!FileManager.default.fileExists(atPath: base.path), "initialization must do no filesystem work")
        probe.verifyPreviousRun()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && !FileManager.default.fileExists(atPath: base.path), "verify without prior fixture must not create storage")

        let production = base.appendingPathComponent("LibreReadings/readings.sqlite")
        try FileManager.default.createDirectory(at: production.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("production sentinel: never open or change".utf8)
        try sentinel.write(to: production)
        var starts = 0
        let active = LibreStorageProbe(applicationSupportDirectory: base, onStatus: { if $0.isRunning { starts += 1 } })
        active.start()
        active.start()
        active.verifyPreviousRun()
        await active.waitForCurrentOperation()
        try expect(starts == 1 && active.status.reopenVerified, "repeat clicks must not start overlapping work")
        try expect(!active.status.relaunchVerified, "reopen is not relaunch")
        try expect(try Data(contentsOf: production) == sentinel, "production store sentinel must stay untouched")
        try expect(active.status.fileObservations.count == 9, "save, before reopen and open observations must cover SQLite/WAL/SHM")
        #if !os(iOS)
        try expect(active.status.fileObservations.allSatisfy { !$0.result.contains("(expected)") }, "macOS cannot report iOS protection as verified")
        #endif
        let originalManifest = try Data(contentsOf: manifest(base))
        let newInstance = LibreStorageProbe(applicationSupportDirectory: base)
        newInstance.verifyPreviousRun()
        await newInstance.waitForCurrentOperation()
        try expect(newInstance.status.phase == "Relaunch pending" && !newInstance.status.relaunchVerified, "a second object in the same process cannot prove relaunch")
        newInstance.start()
        await newInstance.waitForCurrentOperation()
        try expect(try Data(contentsOf: manifest(base)) == originalManifest, "start with retained fixture must verify without reseeding manifest")
        let exported = newInstance.status.reportLines.joined(separator: "\n")
        try expect(!exported.contains(base.path) && !exported.contains("launchID") && !exported.contains("sessionID"), "export must omit filesystem paths and record identifiers")
    }

    @MainActor
    static func invalidRetainedState(_ base: URL) async throws {
        let probe = LibreStorageProbe(applicationSupportDirectory: base)
        probe.start()
        await probe.waitForCurrentOperation()
        try expect(probe.status.reopenVerified, "fixture setup must succeed")
        let originalManifest = try Data(contentsOf: manifest(base))
        try Data("invalid manifest".utf8).write(to: manifest(base))
        probe.start()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && !probe.status.reopenVerified, "corrupt manifest must fail without stale success")
        try expect(try Data(contentsOf: manifest(base)) == Data("invalid manifest".utf8), "corrupt manifest must not be overwritten")

        var incomplete = try JSONSerialization.jsonObject(with: originalManifest) as! [String: Any]
        incomplete["completed"] = false
        let incompleteData = try JSONSerialization.data(withJSONObject: incomplete)
        try incompleteData.write(to: manifest(base))
        probe.verifyPreviousRun()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && (try Data(contentsOf: manifest(base))) == incompleteData, "interrupted probe marker must not be repaired")

        try originalManifest.write(to: manifest(base))
        try FileManager.default.removeItem(at: database(base))
        probe.start()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && !FileManager.default.fileExists(atPath: database(base).path), "missing database must never be silently recreated")
        try expect(probe.status.fileObservations.first?.result.contains("Missing") == true, "missing actual SQLite must be reported")
        let corrupt = Data("not sqlite".utf8)
        try corrupt.write(to: database(base))
        probe.verifyPreviousRun()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && !probe.status.relaunchVerified, "corrupt SQLite must not pass")
        try expect(try Data(contentsOf: database(base)) == corrupt, "corrupt SQLite must not be reset")
        try FileManager.default.removeItem(at: manifest(base))
        probe.start()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && !FileManager.default.fileExists(atPath: manifest(base).path), "missing manifest must never reseed an existing directory")
    }

    @MainActor
    static func unexpectedRecords(_ base: URL) async throws {
        let probe = LibreStorageProbe(applicationSupportDirectory: base)
        probe.start()
        await probe.waitForCurrentOperation()
        try expect(probe.status.reopenVerified, "unexpected-record fixture setup")
        let store = ReadingStore(configuration: .init(storage: .sqlite(url: database(base))))
        try await store.load()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await store.resolveSessionMetadata(.init(
            id: UUID(), stableIdentityFingerprint: Data([1]), sensorRevision: "extra",
            firstObservedAt: date, observedAt: date, lifecycleState: .ended,
            clock: .init(referenceSensorMinute: 120, referenceDate: date, provenance: "extra")
        ))
        try await store.close()
        probe.verifyPreviousRun()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed" && !probe.status.reopenVerified, "unexpected metadata must fail exact fixture verification")
        let reopened = ReadingStore(configuration: .init(storage: .sqlite(url: database(base))))
        try await reopened.load()
        let retained = try await reopened.snapshot()
        try expect(retained.sessions.count == 2, "verification cannot delete unexpected records")
        try await reopened.close()
    }

    @MainActor
    static func symlinkIsolation(_ base: URL) async throws {
        let target = base.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let sentinel = target.appendingPathComponent("sentinel")
        try Data([1, 2, 3]).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: directory(base), withDestinationURL: target)
        let probe = LibreStorageProbe(applicationSupportDirectory: base)
        probe.start()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Failed", "probe must refuse a symlink directory")
        try expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["sentinel"], "refused symlink target must remain untouched")
    }

    @MainActor
    final class LockHarness {
        var available = true
        var background = false
        var grantsExecution = true
        var beginCount = 0
        var endCount = 0
        var sampleCount = 0
        var onSample: (() -> Void)?
        var expiration: (@MainActor () -> Void)?

        var environment: LibreStorageProbeLockEnvironment {
            .init(isProtectedDataAvailable: {
                self.sampleCount += 1
                self.onSample?()
                return self.available
            }, isBackground: { self.background }, beginBackgroundTask: { expiration in
                self.beginCount += 1
                self.expiration = expiration
                return self.grantsExecution
            }, endBackgroundTask: { self.endCount += 1 })
        }
    }

    @MainActor
    static func lockedStorageChecks(_ base: URL) async throws {
        let probe = LibreStorageProbe(applicationSupportDirectory: base)
        let state = LockHarness()
        let lockedDirectory = base.appendingPathComponent(LibreStorageProbe.lockedDirectoryName)
        let lockedDatabase = lockedDirectory.appendingPathComponent(LibreStorageProbe.databaseName)
        try expect(!FileManager.default.fileExists(atPath: base.path), "lock service init must do no filesystem work")

        // Background alone and advance lock notifications cannot authorize I/O.
        state.background = true
        probe.armLockedVerification(environment: state.environment)
        probe.lockedEnvironmentDidChange()
        await Task.yield()
        probe.cancelLockedVerification()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !probe.status.lockedVerificationAttempted,
                   "background with protected data available cannot start a locked operation")
        try expect(state.endCount == 1 && !FileManager.default.fileExists(atPath: base.path),
                   "cancelled waiting probe must end its lease without touching storage")

        // Protected-data-unavailable alone also does not establish the background condition.
        state.available = false
        state.background = false
        probe.armLockedVerification(environment: state.environment)
        await Task.yield()
        state.expiration?()
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !probe.status.lockedVerificationAttempted && state.endCount == 2,
                   "foreground and expiration must remain inconclusive")

        state.grantsExecution = false
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        try expect(!probe.status.isRunning && probe.status.phase == "Inconclusive" && state.endCount == 2,
                   "denied background execution cannot begin work or end an unowned lease")
        state.grantsExecution = true
        state.available = true
        state.background = true
        probe.armLockedVerification(environment: state.environment, maximumWaitSeconds: 0.005)
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !probe.status.lockedVerificationAttempted && state.endCount == 3,
                   "bounded wait must expire without protected-data-unavailable evidence")

        // Preserve the ordinary v7 fixture, and make two real committed mutations
        // in the separate locked-only store without accumulating session rows.
        probe.start()
        await probe.waitForCurrentOperation()
        let ordinaryManifest = try Data(contentsOf: manifest(base))
        let ordinaryDatabase = try Data(contentsOf: database(base))
        state.available = false
        let staleExpiration = state.expiration
        probe.armLockedVerification(environment: state.environment)
        staleExpiration?()
        await probe.waitForCurrentOperation()
        try expect(probe.status.lockedSequenceCompleted && probe.status.lockedVerificationAttempted,
                   "a stale lease expiration cannot invalidate a new complete storage sequence")
        try expect(probe.status.lockedObservations.count >= 12 && state.endCount == 4,
                   "all storage boundaries must carry actual sampled state and lease must finish once")
        #if !os(iOS)
        try expect(!probe.status.lockedVerified && probe.status.phase == "Synthetic locked sequence passed",
                   "portable simulation cannot report verified iOS lock evidence")
        #endif
        let reader = ReadingStore(configuration: .init(storage: .sqlite(url: lockedDatabase)))
        try await reader.load()
        let first = try await reader.snapshot()
        try await reader.close()
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        let secondReader = ReadingStore(configuration: .init(storage: .sqlite(url: lockedDatabase)))
        try await secondReader.load()
        let second = try await secondReader.snapshot()
        try await secondReader.close()
        try expect(probe.status.lockedSequenceCompleted && second.sessions.count == 1 &&
                   second.sessions[0].lastObservedAt > first.sessions[0].lastObservedAt,
                   "repeated lock probe must commit a fresh metadata mutation with bounded row count")
        try expect(second.readings.isEmpty && second.deliveries.isEmpty && second.publishedCommits.isEmpty,
                   "locked probe cannot submit readings or deliveries")
        try expect(try Data(contentsOf: manifest(base)) == ordinaryManifest, "locked run cannot change v7 manifest")
        try expect(try Data(contentsOf: database(base)) == ordinaryDatabase, "locked run cannot change v7 database")
        let report = probe.status.reportLines.joined(separator: "\n")
        try expect(!report.contains(base.path) && !report.contains(second.sessions[0].id.uuidString) &&
                   !report.contains("A764E7B8"), "locked export must remain redacted")

        // Re-entering foreground or unlocking across an awaited operation invalidates
        // the complete verdict even if earlier storage steps happened to succeed.
        state.sampleCount = 0
        state.onSample = {
            if state.sampleCount == 7 { state.available = true }
        }
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !probe.status.lockedSequenceCompleted && !probe.status.lockedVerified,
                   "unlock during storage work must invalidate the sequence")
        state.onSample = nil
        state.available = false
        state.sampleCount = 0
        state.onSample = {
            if state.sampleCount == 7 { state.expiration?() }
        }
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !probe.status.lockedSequenceCompleted,
                   "expiration during storage work cannot produce late success")
        state.onSample = nil
        state.sampleCount = 0
        state.onSample = {
            if state.sampleCount == 7 { probe.cancelLockedVerification() }
        }
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !probe.status.lockedSequenceCompleted,
                   "cancellation during storage work cannot produce late success")
        state.onSample = nil
        try expect(state.beginCount == state.endCount + 1, "all granted leases must end exactly once")

        try FileManager.default.removeItem(at: lockedDatabase)
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && !FileManager.default.fileExists(atPath: lockedDatabase.path),
                   "missing retained locked database must not be silently recreated")
        try Data("corrupt locked sqlite".utf8).write(to: lockedDatabase)
        probe.armLockedVerification(environment: state.environment)
        await probe.waitForCurrentOperation()
        try expect(probe.status.phase == "Inconclusive" && (try Data(contentsOf: lockedDatabase)) == Data("corrupt locked sqlite".utf8),
                   "corrupt locked database must not be reset")
    }

    static func runProcess(_ mode: String, directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [mode, directory.path]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "separate-process \(mode) failed")
    }

    static func directory(_ base: URL) -> URL { base.appendingPathComponent("GlucoScopeStorageProbe-v1") }
    static func manifest(_ base: URL) -> URL { directory(base).appendingPathComponent("synthetic-probe.json") }
    static func database(_ base: URL) -> URL { directory(base).appendingPathComponent("synthetic-metadata.sqlite") }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }
    struct Failure: Error { let message: String }
}
