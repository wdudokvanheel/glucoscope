import Foundation

@main
enum ServerUploadStoreSmoke {
    static func main() async throws {
        try await newOnlyCursorSurvivesRestart()
        try await multipleTargetsAndNewestFirstHistory()
        try await disabledCatchUpRequiresConsent()
        try await migrationKeepsEndpointProvenanceAndDeduplicatesOverlap()
        try await credentialOnlyEditPreservesQueue()
        try await clearWaitsForInflightOutcome()
        try await diagnosticsExpireWithoutRemovingPendingWork()
        print("ServerUploadStoreSmoke: PASS")
    }

    private static func credentialOnlyEditPreservesQueue() async throws {
        let store = try await makeStore("credential-edit")
        let destination = try await store.addDestination(
            name: "Target", backend: .nightscout, endpoint: "target.example",
            credentialReference: "old-secret", now: date(450)
        )
        try await store.enqueueHistory(
            destinationID: destination.id,
            selection: .allAvailable,
            readings: [reading(1, sample: 440, committed: 440)],
            now: date(451)
        )
        let before = await store.snapshot()
        try await store.updateCredentialReference(
            destinationID: destination.id,
            reference: "new-secret",
            name: "Renamed"
        )
        let after = await store.snapshot()
        let edited = after.destinations.first { $0.id == destination.id }!
        expect(edited.endpointRevision == destination.endpointRevision, "credential edit must preserve endpoint revision")
        expect(edited.credentialReference == "new-secret", "credential reference should be replaced")
        expect(after.deliveries == before.deliveries, "credential-only edit must preserve every queue row")
    }

    private static func newOnlyCursorSurvivesRestart() async throws {
        let location = temporaryURL("new-only")
        let store = ServerUploadStore(fileURL: location)
        try await store.load(now: date(100))
        let old = reading(1, sample: 10, committed: 90)
        let destination = try await store.addDestination(
            name: "Home",
            backend: .nightscout,
            endpoint: "https://nightscout.example/?token=must-not-persist",
            credentialReference: "keychain-1",
            now: date(100)
        )
        try await store.reconcileNewReadings([old], now: date(101))
        var current = await store.snapshot()
        expect(current.pendingCount == 0, "new destination must not receive older commits")

        let new = reading(2, sample: 50, committed: 102)
        try await store.reconcileNewReadings([old, new], now: date(103))
        current = await store.snapshot()
        expect(current.pendingCount == 1, "new commit should be queued")
        let disk = try String(contentsOf: location, encoding: .utf8)
        expect(!disk.contains("must-not-persist"), "URL query credential must be removed")
        let subpath = try ServerUploadEndpoint.normalize("https://example.test/base/")
        expect(subpath == "https://example.test/base", "server subpath must remain valid")

        let reopened = ServerUploadStore(fileURL: location)
        try await reopened.load(now: date(104))
        try await reopened.reconcileNewReadings([old, new], now: date(105))
        let snapshot = await reopened.snapshot()
        expect(snapshot.pendingCount == 1, "durable cursor and dedupe must survive restart")
        expect(snapshot.deliveries[0].destinationID == destination.id, "delivery destination mismatch")
    }

    private static func multipleTargetsAndNewestFirstHistory() async throws {
        let store = try await makeStore("multi")
        let first = try await store.addDestination(
            name: "A", backend: .nightscout, endpoint: "a.example", credentialReference: "a", now: date(200)
        )
        let second = try await store.addDestination(
            name: "B", backend: .glucoScope, endpoint: "b.example", credentialReference: "b", now: date(200)
        )
        let readings = [
            reading(1, sample: 120, committed: 150),
            reading(2, sample: 180, committed: 151),
            reading(3, sample: 60, committed: 152)
        ]
        try await store.enqueueHistory(destinationID: first.id, selection: .allAvailable, readings: readings, now: date(201))
        try await store.enqueueHistory(destinationID: second.id, selection: .since(date(100)), readings: readings, now: date(201))
        let firstClaim = try await store.nextDelivery(destinationID: first.id, now: date(202))
        expect(firstClaim?.sampleDate == date(180), "history must send newest first")
        let snapshot = await store.snapshot()
        expect(snapshot.progress(for: first.id).targetStartDate == date(60), "progress start should be oldest queued sample")
        expect(snapshot.progress(for: second.id).pendingCount == 2, "destinations need independent queues")
    }

    private static func disabledCatchUpRequiresConsent() async throws {
        let store = try await makeStore("catchup")
        let destination = try await store.addDestination(
            name: "Paused", backend: .nightscout, endpoint: "paused.example", credentialReference: "p", now: date(300)
        )
        try await store.setEnabled(false, destinationID: destination.id, catchUpFrom: nil, readings: [], now: date(310))
        let missed = reading(1, sample: 305, committed: 315)
        try await store.reconcileNewReadings([missed], now: date(316))
        try await store.setEnabled(true, destinationID: destination.id, catchUpFrom: nil, readings: [missed], now: date(320))
        try await store.reconcileNewReadings([missed], now: date(321))
        var current = await store.snapshot()
        expect(current.pendingCount == 0, "re-enable without consent must not catch up")

        try await store.setEnabled(false, destinationID: destination.id, catchUpFrom: nil, readings: [], now: date(330))
        let missedLater = reading(2, sample: 325, committed: 335)
        try await store.setEnabled(
            true,
            destinationID: destination.id,
            catchUpFrom: date(332),
            readings: [missed, missedLater],
            now: date(340)
        )
        current = await store.snapshot()
        expect(current.pendingCount == 1, "explicit interval catch-up should use commit time")
    }

    private static func migrationKeepsEndpointProvenanceAndDeduplicatesOverlap() async throws {
        let store = try await makeStore("migration")
        let destination = try await store.addDestination(
            name: "Old", backend: .nightscout, endpoint: "old.example", credentialReference: "old", now: date(400)
        )
        let readings = [reading(1, sample: 350, committed: 350), reading(2, sample: 410, committed: 410)]
        try await store.enqueueHistory(destinationID: destination.id, selection: .allAvailable, readings: readings, now: date(420))
        try await store.migrateDestination(
            destinationID: destination.id,
            name: "New",
            backend: .glucoScope,
            endpoint: "new.example",
            credentialReference: "new",
            transferPending: true,
            backfill: .allAvailable,
            readings: readings,
            now: date(430)
        )
        let snapshot = await store.snapshot()
        let current = snapshot.destinations.first { $0.id == destination.id }!
        expect(current.endpointRevision == 2, "address edit must advance endpoint provenance")
        let active = snapshot.deliveries.filter { $0.endpointRevision == 2 && $0.state != .acknowledged }
        expect(active.count == 2, "pending transfer and backfill overlap must deduplicate")
        expect(Set(active.map(\.readingID)).count == 2, "one delivery per reading/revision required")
        expect(snapshot.attempts.allSatisfy { $0.endpointRevision == 1 }, "retired work must remain attributed to old endpoint")
    }

    private static func clearWaitsForInflightOutcome() async throws {
        let store = try await makeStore("inflight")
        let destination = try await store.addDestination(
            name: "Target", backend: .nightscout, endpoint: "target.example", credentialReference: "t", now: date(500)
        )
        try await store.enqueueHistory(
            destinationID: destination.id,
            selection: .allAvailable,
            readings: [reading(1, sample: 490, committed: 490)],
            now: date(501)
        )
        let claimed = try await store.nextDelivery(destinationID: destination.id, now: date(502))!
        try await store.clearQueue(destinationID: destination.id, now: date(503))
        var snapshot = await store.snapshot()
        expect(snapshot.pendingCount == 1, "in-flight row must survive until outcome")
        try await store.complete(deliveryID: claimed.id, result: .success(201), now: date(504))
        snapshot = await store.snapshot()
        expect(snapshot.deliveries.isEmpty, "clear should remove row after recording in-flight outcome")
        expect(snapshot.attempts.contains { $0.outcome == .succeeded }, "in-flight outcome must be logged")
    }

    private static func diagnosticsExpireWithoutRemovingPendingWork() async throws {
        let location = temporaryURL("retention")
        let store = ServerUploadStore(fileURL: location, logRetention: 30)
        try await store.load(now: date(600))
        let destination = try await store.addDestination(
            name: "Logs", backend: .nightscout, endpoint: "logs.example", credentialReference: "l", now: date(600)
        )
        try await store.enqueueHistory(
            destinationID: destination.id,
            selection: .allAvailable,
            readings: [reading(1, sample: 590, committed: 590), reading(2, sample: 591, committed: 591)],
            now: date(601)
        )
        let claimed = try await store.nextDelivery(destinationID: destination.id, now: date(602))!
        try await store.complete(deliveryID: claimed.id, result: .failure(.network("token=secret")), now: date(603))
        let reopened = ServerUploadStore(fileURL: location, logRetention: 30)
        try await reopened.load(now: date(700))
        let snapshot = await reopened.snapshot()
        expect(snapshot.attempts.isEmpty, "expired diagnostic attempts should be pruned")
        expect(snapshot.pendingCount == 2, "log expiry must never remove pending or failed delivery state")
        expect(!snapshot.deliveries.compactMap(\.lastError).joined().contains("secret"), "failure state must be redacted")
    }

    private static func makeStore(_ name: String) async throws -> ServerUploadStore {
        let store = ServerUploadStore(fileURL: temporaryURL(name))
        try await store.load(now: date(1))
        return store
    }

    private static func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("glucoscope-upload-\(name)-\(UUID().uuidString)")
            .appendingPathComponent("state.json")
    }

    private static func reading(_ number: UInt8, sample: TimeInterval, committed: TimeInterval) -> StoredReadingSnapshot {
        StoredReadingSnapshot(
            id: UUID(uuid: (number, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number, 0, 0, 0, number)),
            sessionID: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9)),
            sensorMinute: Int64(sample / 60),
            kind: .trend,
            sampleDate: date(sample),
            receivedAt: date(committed),
            glucoseMGDL: 100 + Int(number),
            quality: "valid",
            primaryOrigin: .bleLive,
            observedOriginFlags: 1,
            decoderVersion: "test",
            createdAt: date(committed)
        )
    }

    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
