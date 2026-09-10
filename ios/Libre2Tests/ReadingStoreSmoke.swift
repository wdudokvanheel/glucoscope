import Foundation
import CoreData

/// Synthetic candidates only: the diagnostic decoder deliberately is not linked.
@main
struct ReadingStoreSmoke {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func main() async throws {
        try await sparseOrderingAndOrigins()
        try await concurrentDeduplication()
        try await concurrentFailureStopsWriter()
        try await destinationAssignment()
        try await saveAndLoadFailures()
        try await assignmentRollback()
        try await invalidBoundsAndConfiguration()
        try await sessionDisagreements()
        try await durableRestart()
        try await corruptStoreIsRetained()
        print("Libre reading store: all synthetic transaction and restart checks passed")
    }

    static func session(fingerprint: Data = Data(repeating: 0x42, count: 32),
                        clockShift: TimeInterval = 0) -> ReadingSessionSnapshot {
        ReadingSessionSnapshot(id: sessionID, stableIdentityFingerprint: fingerprint,
                               sensorRevision: "libre2_7F", firstObservedAt: epoch,
                               observedAt: epoch.addingTimeInterval(3_600), lifecycleState: .active,
                               clock: ReadingClockSnapshot(referenceSensorMinute: 1_000,
                                                           referenceDate: epoch.addingTimeInterval(clockShift),
                                                           provenance: "synthetic-nfc"))
    }

    static func candidate(_ minute: Int64, kind: ReadingSampleKind = .trend,
                          origin: ReadingOrigin = .bleLive, value: Int = 110) -> ReadingCandidate {
        ReadingCandidate(sensorMinute: minute, kind: kind, receivedAt: epoch.addingTimeInterval(3_600),
                         glucoseMGDL: value, quality: "synthetic", origin: origin,
                         decoderVersion: "synthetic-fixture-v1")
    }

    static func submission(_ sequence: UInt64, _ minutes: [Int64],
                           session snapshot: ReadingSessionSnapshot = session()) -> ReadingSubmission {
        ReadingSubmission(sequence: sequence, session: snapshot, candidates: minutes.map { candidate($0) })
    }

    static func memoryStore(faults: ReadingStoreFaultInjector? = nil) async throws -> ReadingStore {
        let store = ReadingStore(configuration: .init(storage: .inMemory(identifier: UUID().uuidString)),
                                 faultInjector: faults)
        try await store.load()
        return store
    }

    static func sparseOrderingAndOrigins() async throws {
        let store = try await memoryStore()
        let first = try await store.ingest(submission(1, [1_000, 985, 998, 990]))
        let initial = try await store.snapshot()
        let byID = Dictionary(uniqueKeysWithValues: initial.readings.map { ($0.id, $0.sensorMinute) })
        try expect(first.readingIDs.compactMap { byID[$0] } == [985, 990, 998, 1_000],
                   "commit IDs must follow sample chronology")
        _ = try await store.ingest(submission(2, [990, 985, 980]))
        _ = try await store.ingest(submission(3, [1_000, 985, 998, 990]))
        _ = try await store.ingest(ReadingSubmission(sequence: 4, session: session(), candidates: [
            candidate(1_000, origin: .nfcTrend),
            candidate(1_000, kind: .history15Minute, origin: .nfcHistory),
            candidate(998, origin: .bleHistory)
        ]))
        let result = try await store.snapshot()
        try expect(result.sessions.count == 1, "one wear session")
        try expect(result.readings.count == 6 && result.deliveries.count == 6,
                   "overlaps and origins deduplicate; history kind stays distinct")
        try expect(Set(result.readings.map(\.sensorMinute)) == [980, 985, 990, 998, 1_000],
                   "sparse ingestion must preserve genuine missing minutes")
        try expect(result.deliveries.allSatisfy { $0.state == .unassigned && $0.payload == nil && $0.destinationID == nil },
                   "every reading commits with an unassigned delivery when unconfigured")
        try expect(Set(result.deliveries.map(\.readingID)) == Set(result.readings.map(\.id)),
                   "delivery and reading identity form a bijection")
        let live = result.readings.first { $0.sensorMinute == 1_000 && $0.kind == .trend }!
        try expect(live.sampleDate == epoch, "store derives UTC from sensor clock")
        try expect(live.primaryOrigin == .bleLive, "duplicate origin cannot replace primary provenance")
        try expect(live.observedOriginFlags & ReadingOrigin.bleLive.observationFlag != 0 && live.observedOriginFlags & ReadingOrigin.nfcTrend.observationFlag != 0,
                   "exact duplicates merge observed origins")
    }

    static func concurrentDeduplication() async throws {
        let store = try await memoryStore()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for sequence in 1...24 {
                group.addTask {
                    _ = try await store.ingest(submission(UInt64(sequence), [980, 985, 990, 998, 1_000]))
                }
            }
            try await group.waitForAll()
        }
        let result = try await store.snapshot()
        try expect(result.readings.count == 5 && result.deliveries.count == 5,
                   "concurrent overlapping submissions cannot duplicate readings or deliveries")
    }

    static func destination() -> ReadingDestination {
        ReadingDestination(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                           backendKind: "synthetic", normalizedEndpointIdentity: "https://example.invalid/",
                           credentialReference: "test-keychain-reference", configurationRevision: 1, enabled: true)
    }

    static func concurrentFailureStopsWriter() async throws {
        let faults = ReadingStoreFaultInjector()
        let store = try await memoryStore(faults: faults)
        faults.failNext(at: .beforeSave)
        let failures = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for sequence in 1...24 {
                group.addTask {
                    do {
                        _ = try await store.ingest(submission(UInt64(sequence), [Int64(1_000 + sequence)]))
                        return false
                    } catch { return true }
                }
            }
            var failed = 0
            for await failure in group where failure { failed += 1 }
            return failed
        }
        let result = try await store.snapshot()
        try expect(failures == 24 && result.readings.isEmpty && result.deliveries.isEmpty && result.publishedCommits.isEmpty,
                   "first concurrent writer failure blocks every queued submission until explicit retry")
        _ = try await store.retryAfterFailure()
        _ = try await store.ingest(submission(25, [1_001]))
        let recovered = try await store.snapshot()
        try expect(recovered.readings.count == 1 && recovered.deliveries.count == 1,
                   "writer resumes only after explicit retry")
    }

    static func destinationAssignment() async throws {
        let store = try await memoryStore()
        _ = try await store.ingest(submission(1, [990, 1_000]))
        let assignment = try await store.selectDestination(destination())
        try expect(assignment.readingIDs.count == 2, "later destination assigns all unassigned rows")
        let queued = try await store.snapshot()
        try expect(queued.deliveries.allSatisfy { $0.state == .queued && $0.destinationID == destination().id && $0.payload != nil },
                   "assignment freezes a payload and destination for every reading")
        let payloads = Dictionary(uniqueKeysWithValues: queued.deliveries.map { ($0.readingID, $0.payload) })
        let repeatAssignment = try await store.selectDestination(destination())
        try expect(repeatAssignment.readingIDs.isEmpty, "repeat assignment is idempotent")
        _ = try await store.ingest(ReadingSubmission(sequence: 2, session: session(), candidates: [
            candidate(1_000, origin: .nfcTrend, value: 190), candidate(1_001)
        ]))
        let final = try await store.snapshot()
        try expect(final.readings.first { $0.sensorMinute == 1_000 }?.glucoseMGDL == 110,
                   "conflicting candidate retains first canonical glucose")
        try expect(final.readings.first { $0.sensorMinute == 1_000 }?.observedOriginFlags == ReadingOrigin.bleLive.observationFlag,
                   "conflicting origin stays in conflict diagnostic instead of exact-observation metadata")
        try expect(final.conflicts.count == 1, "conflicting duplicate records a diagnostic")
        try expect(final.deliveries.count == 3 && final.deliveries.allSatisfy { $0.state == .queued },
                   "a selected destination queues reading and delivery atomically")
        for delivery in final.deliveries where payloads.keys.contains(delivery.readingID) {
            try expect(delivery.payload == payloads[delivery.readingID]!, "queued payload is immutable on replay/conflict")
        }
        for delivery in final.deliveries {
            let data = delivery.payload!
            let reading = final.readings.first { $0.id == delivery.readingID }!
            let expectedMilliseconds: Int64 = reading.sensorMinute == 990 ? 1_699_999_400_000
                : reading.sensorMinute == 1_000 ? 1_700_000_000_000 : 1_700_000_060_000
            let expected = "{\"decoder_version\":\"synthetic-fixture-v1\",\"glucose_mg_dl\":110,\"payload_version\":1,\"reading_id\":\"\(reading.id.uuidString.lowercased())\",\"sample_date_ms\":\(expectedMilliseconds),\"sample_kind\":\"trend\",\"sensor_minute\":\(reading.sensorMinute),\"session_id\":\"11111111-2222-3333-4444-555555555555\"}"
            try expect(data == Data(expected.utf8) && delivery.payloadVersion == 1,
                       "payload has exact deterministic v1 bytes, IDs, integer units and UTC milliseconds")
        }
    }

    static func saveAndLoadFailures() async throws {
        let faults = ReadingStoreFaultInjector()
        let store = try await memoryStore(faults: faults)
        let observed = Task { () -> [ReadingCommit] in
            var result: [ReadingCommit] = []
            for await commit in store.commits { result.append(commit) }
            return result
        }
        faults.failNext(at: .beforeSave, message: "SECRET fixture path and raw payload must be redacted")
        try await expectFailure("injected save rejects transaction") {
            _ = try await store.ingest(submission(1, [990, 1_000]))
        }
        let failed = try await store.snapshot()
        try expect(failed.sessions.isEmpty && failed.readings.isEmpty && failed.deliveries.isEmpty,
                   "failed save rolls back session, every reading and delivery")
        try expect(failed.publishedCommits.isEmpty, "failed save publishes zero commits")
        guard case .unhealthy(let failure) = failed.health else { throw Failure(message: "save failure must expose unhealthy status") }
        try expect(failure.operation == .ingest && failure.droppedCandidateCount == 2,
                   "save failure status names operation and uncommitted candidates")
        try expect(!failure.redactedReason.contains("SECRET"), "health redacts injected error contents")
        try await expectFailure("unhealthy store rejects further candidates") {
            _ = try await store.ingest(submission(2, [1_001]))
        }
        _ = try await store.retryAfterFailure()
        _ = try await store.ingest(submission(3, [990, 1_000]))
        let recovered = try await store.snapshot()
        try expect(recovered.readings.count == 2 && recovered.deliveries.count == 2,
                   "explicit recovery leaves no partial rows")
        try await store.close()
        let events = await observed.value
        try expect(events.count == 1 && events[0].submissionSequence == 3,
                   "actual commit stream contains only the successful retried transaction")

        let loadFaults = ReadingStoreFaultInjector()
        loadFaults.failNext(at: .beforeLoad)
        let unloaded = ReadingStore(configuration: .init(storage: .inMemory(identifier: UUID().uuidString)),
                                    faultInjector: loadFaults)
        try await expectFailure("injected store load fails") { try await unloaded.load() }
        try await expectFailure("failed load blocks ingest") { _ = try await unloaded.ingest(submission(1, [1_000])) }
        _ = try await unloaded.retryAfterFailure()
        _ = try await unloaded.ingest(submission(2, [1_000]))
        let loaded = try await unloaded.snapshot()
        try expect(loaded.readings.count == 1 && loaded.deliveries.count == 1, "load retry can commit a complete pair")
    }

    static func sessionDisagreements() async throws {
        for mismatch in [session(fingerprint: Data(repeating: 0x99, count: 32)), session(clockShift: 30)] {
            let store = try await memoryStore()
            _ = try await store.ingest(submission(1, [1_000]))
            try await expectFailure("session identity or clock disagreement requires repair") {
                _ = try await store.ingest(submission(2, [1_001], session: mismatch))
            }
            let result = try await store.snapshot()
            try expect(result.sessions.count == 1 && result.readings.count == 1 && result.deliveries.count == 1,
                       "disagreement cannot mutate known session or commit candidate")
            try expect(result.readings[0].sampleDate == epoch, "clock disagreement retains original UTC date")
        }
    }

    static func assignmentRollback() async throws {
        let faults = ReadingStoreFaultInjector()
        let store = try await memoryStore(faults: faults)
        _ = try await store.ingest(submission(1, [990, 1_000]))
        faults.failNext(at: .beforeSave)
        try await expectFailure("assignment save failure rolls back every delivery") {
            _ = try await store.selectDestination(destination())
        }
        let failed = try await store.snapshot()
        try expect(failed.destinations.isEmpty && failed.deliveries.allSatisfy { $0.state == .unassigned && $0.payload == nil && $0.destinationID == nil },
                   "failed destination assignment leaves every original delivery unassigned")
        try expect(failed.readings.count == 2 && failed.deliveries.count == 2 && failed.publishedCommits.count == 1,
                   "assignment failure retains prior committed readings and emits no reading commit")
        _ = try await store.retryAfterFailure()
        let committed = try await store.selectDestination(destination())
        try expect(committed.readingIDs.count == 2, "assignment retry queues all eligible readings")
    }

    static func invalidBoundsAndConfiguration() async throws {
        let store = try await memoryStore()
        _ = try await store.selectDestination(destination())
        try await expectFailure("out-of-range minute rejects without integer payload trap") {
            _ = try await store.ingest(submission(1, [Int64.max]))
        }
        try expect(await store.currentHealth() == .healthy, "invalid minute is rejected before a writer transaction")
        try await expectFailure("finite out-of-range date rejects without integer payload trap") {
            _ = try await store.ingest(submission(2, [1_000], session: session(clockShift: 1e20)))
        }
        try expect(await store.currentHealth() == .healthy, "invalid date is rejected before a writer transaction")
        let result = try await store.snapshot()
        try expect(result.readings.isEmpty && result.deliveries.isEmpty && result.publishedCommits.isEmpty,
                   "invalid numeric inputs produce no canonical rows or publications")

        let invalid = ReadingStore(configuration: .init(storage: .inMemory(identifier: UUID().uuidString), maxCandidatesPerSubmission: 0))
        try await expectFailure("invalid store configuration fails load") { try await invalid.load() }
        try await expectFailure("retry must revalidate configuration") { _ = try await invalid.retryAfterFailure() }
        try await expectFailure("invalid configuration never becomes ingestible") { _ = try await invalid.ingest(submission(1, [1_000])) }
    }

    static func durableRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("libre-store-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ReadingStoreConfiguration(storage: .sqlite(url: directory.appendingPathComponent("readings.sqlite")))
        let faults = ReadingStoreFaultInjector()
        let first = ReadingStore(configuration: configuration, faultInjector: faults)
        let observed = Task { () -> [ReadingCommit] in
            var result: [ReadingCommit] = []
            for await commit in first.commits { result.append(commit) }
            return result
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { try await first.load() } }
            try await group.waitForAll()
        }
        _ = try await first.selectDestination(destination())
        faults.failNext(at: .afterSaveBeforePublication)
        try await expectFailure("fault after durable save withholds commit") {
            _ = try await first.ingest(submission(1, [990, 1_000]))
        }
        let durable = try await first.snapshot()
        try expect(durable.readings.count == 2 && durable.deliveries.count == 2,
                   "save-before-publication fault retains complete durable transaction")
        try expect(durable.publishedCommits.isEmpty, "durable-save interruption publishes zero commits")
        guard case .unhealthy(let failure) = durable.health else { throw Failure(message: "post-save fault must expose unhealthy status") }
        try expect(failure.durableCommitAwaitingPublication && failure.droppedCandidateCount == 0,
                   "post-save failure distinguishes committed rows from dropped candidates")
        try await first.close()
        try expect(await observed.value.isEmpty, "post-save interruption emits no actual stream event")

        let reopened = ReadingStore(configuration: configuration)
        try await reopened.load()
        let restored = try await reopened.snapshot()
        try expect(Set(restored.readings.map(\.id)) == Set(durable.readings.map(\.id)), "SQLite reopen preserves reading IDs")
        try expect(restored.sessions.first?.id == sessionID, "SQLite session upsert retains bridged identity")
        let durablePayloads = Dictionary(uniqueKeysWithValues: durable.deliveries.map { ($0.readingID, $0.payload) })
        try expect(restored.deliveries.allSatisfy { $0.payload == durablePayloads[$0.readingID]! },
                   "SQLite reopen preserves frozen payload bytes")
        let assignment = try await reopened.selectDestination(destination())
        try expect(assignment.readingIDs.isEmpty, "destination re-selection after restart cannot requeue frozen rows")
        _ = try await reopened.ingest(submission(2, [990, 1_000, 1_001]))
        let final = try await reopened.snapshot()
        try expect(final.readings.count == 3 && final.deliveries.count == 3, "replay after restart deduplicates durable rows")
        try expect(final.deliveries.allSatisfy { $0.state == .queued }, "selected destination survives restart")
        for delivery in final.deliveries where durablePayloads.keys.contains(delivery.readingID) {
            try expect(delivery.payload == durablePayloads[delivery.readingID]!, "assignment and replay after restart retain payload bytes")
        }
        try await reopened.close()
    }

    static func corruptStoreIsRetained() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("libre-corrupt-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("readings.sqlite")
        let original = Data(repeating: 0xA5, count: 4_096)
        try original.write(to: file)
        let store = ReadingStore(configuration: .init(storage: .sqlite(url: file)))
        try await expectFailure("real unreadable SQLite store fails to open") { try await store.load() }
        try await expectFailure("unreadable SQLite store blocks ingest") { _ = try await store.ingest(submission(1, [1_000])) }
        try expect(try Data(contentsOf: file) == original, "unreadable store remains intact instead of deletion or recreation")
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    static func expectFailure(_ message: String, operation: () async throws -> Void) async throws {
        do { try await operation() } catch { return }
        throw Failure(message: "Expected failure: \(message)")
    }

    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
