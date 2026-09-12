import Foundation

actor GatedUploadTransport: ServerUploadTransport {
    private var calls: [UUID] = []
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func test(destination: ServerUploadDestination, secret: String?) async -> Result<Int, ServerUploadError> {
        .success(200)
    }

    func send(
        _ delivery: ServerUploadDelivery,
        to destination: ServerUploadDestination,
        secret: String?
    ) async -> Result<Int, ServerUploadError> {
        calls.append(delivery.readingID)
        if calls.count == 1 {
            await withCheckedContinuation { firstContinuation = $0 }
        }
        return .success(201)
    }

    func callCount() -> Int { calls.count }
    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

@main
enum ServerUploadCoordinatorSmoke {
    static func main() async throws {
        let readingStore = ReadingStore(configuration: .init(storage: .inMemory(identifier: UUID().uuidString)))
        try await readingStore.load()
        let transport = GatedUploadTransport()
        let credentials = MemoryServerUploadCredentialStore()
        let coordinator = ServerUploadCoordinator(
            readingStore: readingStore,
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("uploads.json"),
            credentialStore: credentials,
            transport: transport
        )
        await coordinator.load()
        let destinationID = try await coordinator.addDestination(
            name: "Test", backend: .glucoScope, endpoint: "server.example", secret: "private"
        )
        await coordinator.setStandaloneActive(true)

        let session = makeSession()
        _ = try await readingStore.ingest(submission(1, minute: 100, session: session))
        try await waitUntil("first upload did not start") { await transport.callCount() == 1 }
        precondition(
            coordinator.snapshot.progress(for: destinationID).currentSampleDate != nil,
            "in-flight sample should be visible in queue progress"
        )

        // Viewer transition while a URL request is active lets that request finish,
        // records its result, and prevents the next committed row from starting.
        await coordinator.setStandaloneActive(false)
        _ = try await readingStore.ingest(submission(2, minute: 101, session: session))
        await transport.releaseFirst()
        try await waitUntil("in-flight outcome was not recorded") {
            coordinator.snapshot.attempts.contains { $0.outcome == .succeeded }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let callsWhileViewer = await transport.callCount()
        let pendingWhileViewer = coordinator.pendingReadingCount
        precondition(callsWhileViewer == 1, "Viewer mode started another upload")
        precondition(pendingWhileViewer == 1, "Viewer mode should preserve the second queued reading")

        await coordinator.setStandaloneActive(true)
        try await waitUntil("resume did not drain preserved queue") { await transport.callCount() == 2 }
        try await waitUntil("resumed delivery did not complete") { coordinator.pendingReadingCount == 0 }
        print("ServerUploadCoordinatorSmoke: PASS")
    }

    private static func makeSession() -> ReadingSessionSnapshot {
        let now = Date(timeIntervalSince1970: 1_742_644_800)
        return ReadingSessionSnapshot(
            id: UUID(), stableIdentityFingerprint: Data([1, 2, 3]), sensorRevision: "test",
            firstObservedAt: now, observedAt: now, lifecycleState: .active,
            clock: ReadingClockSnapshot(referenceSensorMinute: 100, referenceDate: now, provenance: "test")
        )
    }

    private static func submission(
        _ sequence: UInt64,
        minute: Int64,
        session: ReadingSessionSnapshot
    ) -> ReadingSubmission {
        ReadingSubmission(sequence: sequence, session: session, candidates: [ReadingCandidate(
            sensorMinute: minute, kind: .trend, receivedAt: session.observedAt,
            glucoseMGDL: 120 + Int(sequence), quality: "valid", origin: .bleLive, decoderVersion: "test"
        )])
    }

    private static func waitUntil(
        _ message: String,
        condition: @escaping () async -> Bool
    ) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        fatalError(message)
    }
}
