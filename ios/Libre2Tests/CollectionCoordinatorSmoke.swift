import Foundation

/// One ordinary-source runtime route: composition -> transport handoff -> ordered
/// ingestion -> checked development decoder -> SQLite. No decoder, adapter, queue, or writer fixture
/// flags are enabled for this executable.
@main
@MainActor
struct CollectionCoordinatorSmoke {
    // This captured-at value cannot round-trip through Unix epoch arithmetic
    // without moving by one representable Date instant.
    nonisolated static let epoch = Date(timeIntervalSinceReferenceDate: 810_000_000.1234568)
    nonisolated static let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
    nonisolated static let patch = Data([0x7F, 0, 0, 0, 0, 0])

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glucoscope-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ReadingStore(configuration: .init(storage: .sqlite(
            url: directory.appendingPathComponent("readings.sqlite")
        )))
        let bridge = makeBridge(for: store)
        let gate = LibreFrameGenerationGate()
        var reported: [LibreCollectionCoordinator.Status] = []
        let coordinator = LibreCollectionCoordinator(
            gate: gate, readingStore: store, bridge: bridge,
            onStatus: { reported.append($0) }
        )
        coordinator.start()
        try await waitUntilIdle(coordinator.ingestion)
        try expect(coordinator.ingestion.snapshot.state == .ready,
                   "runtime composition did not open its real SQLite store")

        let producer = DispatchQueue(label: "libre2.runtime-smoke.transport")
        let handoff = LibreTransportHandoff(
            gate: gate, ingestion: coordinator.ingestion, producerQueue: producer
        ) { _ in }
        let sensor = try session()
        producer.sync {
            _ = handoff.activate(session: sensor, persistenceSessionID: sensor.persistenceSessionID)
        }

        let firstAccepted = producer.sync {
            handoff.completeFrame(
                raw: rawFrame(marker: 0x11),
                verifiedPayload: payload(minute: 1_000, glucose: 1_000),
                receivedAt: epoch
            )
        }
        try expect(firstAccepted, "runtime handoff did not synchronously reserve the first frame")
        try await waitUntilIdle(coordinator.ingestion)
        var queue = coordinator.ingestion.snapshot
        try expect(queue.completedFrames == 1 && queue.rejectedWholeFrames == 0 &&
                   queue.lastOfferedSequence != nil,
                   "fractional-clock runtime route did not commit the first checked frame")

        let duplicateAccepted = producer.sync {
            handoff.completeFrame(
                raw: rawFrame(marker: 0x12),
                verifiedPayload: payload(minute: 1_000, glucose: 1_000),
                receivedAt: epoch
            )
        }
        try expect(duplicateAccepted, "runtime handoff did not reserve the duplicate frame")
        try await waitUntilIdle(coordinator.ingestion)
        queue = coordinator.ingestion.snapshot
        let afterDuplicate = try await store.snapshot()
        try expect(queue.completedFrames == 2 && queue.rejectedWholeFrames == 0 &&
                   afterDuplicate.readings.count == 7 && afterDuplicate.deliveries.count == 7 &&
                   afterDuplicate.conflicts.isEmpty && afterDuplicate.publishedCommits.count == 1,
                   "fractional-clock duplicate was not an idempotent completed frame")

        let secondAccepted = producer.sync {
            handoff.completeFrame(
                raw: rawFrame(marker: 0x22),
                verifiedPayload: payload(minute: 1_002, glucose: 1_000),
                receivedAt: epoch.addingTimeInterval(60)
            )
        }
        try expect(secondAccepted, "runtime handoff did not reserve the overlapping frame")
        try await waitUntilIdle(coordinator.ingestion)
        queue = coordinator.ingestion.snapshot
        try expect(queue.completedFrames == 3 && queue.rejectedWholeFrames == 0,
                   "all real ordered frames must complete exactly once")
        try await eventually { coordinator.status.completedFrames == 3 && !coordinator.isWorking }
        try expect(reported.last?.completedFrames == 3 && reported.last?.rejectedFrames == 0,
                   "coalesced runtime state did not reach the coordinator status callback")

        let committed = try await store.snapshot()
        let expectedMinutes: [Int64] = [985, 987, 988, 990, 993, 994, 995, 996, 998, 1_000, 1_002]
        try expect(committed.sessions.count == 1 && committed.readings.map(\.sensorMinute) == expectedMinutes,
                   "overlapping runtime frames did not converge to the expected sparse sample keys")
        try expect(committed.readings.allSatisfy {
            $0.glucoseMGDL == 112 && $0.quality == "engineeringChecksPassed-v1" &&
            $0.decoderVersion == Libre2ProductionDecoder.version &&
            $0.sampleDate == epoch.addingTimeInterval(Double($0.sensorMinute - 1_000) * 60)
        }, "runtime rows lost checked values, provenance, or native anchor arithmetic")
        try expect(committed.deliveries.count == expectedMinutes.count && committed.conflicts.isEmpty,
                   "same-value overlap must retain one delivery per reading with no conflicts")
        try expect(coordinator.status.recentReadings == Array(committed.readings.reversed()),
                   "runtime UI status did not read its newest values back from SQLite")

        producer.sync { handoff.invalidate() }
        let acceptedAfterStop = producer.sync {
            handoff.completeFrame(
                raw: rawFrame(marker: 0x33),
                verifiedPayload: payload(minute: 1_001, glucose: 1_200),
                receivedAt: epoch.addingTimeInterval(120)
            )
        }
        try expect(!acceptedAfterStop && gate.activeGeneration == nil &&
                   coordinator.ingestion.snapshot.retainedFrames == 0,
                   "synchronous stop must revoke ownership and purge runtime work before returning")
        try await store.close()

        let reopened = ReadingStore(configuration: .init(storage: .sqlite(
            url: directory.appendingPathComponent("readings.sqlite")
        )))
        try await reopened.load()
        let restored = try await reopened.snapshot()
        try expect(restored.readings == committed.readings && restored.deliveries == committed.deliveries,
                   "SQLite reopen changed runtime reading IDs, values, timestamps, or delivery identity")
        let recent = try await reopened.recentReadings(limit: 15)
        try expect(recent == Array(committed.readings.reversed()),
                   "store-backed current/history query did not return the durable newest-first rows")
        let limited = try await reopened.recentReadings(limit: 2)
        let none = try await reopened.recentReadings(limit: 0)
        try expect(limited == Array(recent.prefix(2)) && none.isEmpty,
                   "bounded stored-reading query did not honor its requested limit")

        let relaunched = LibreCollectionCoordinator(
            gate: LibreFrameGenerationGate(), readingStore: reopened, bridge: makeBridge(for: reopened)
        )
        relaunched.start()
        try await eventually {
            relaunched.status.recentReadings == recent && !relaunched.isWorking
        }
        try expect(relaunched.status.savedReadingsStatus == "Latest 11 saved readings",
                   "fresh runtime composition did not publish reopened readings before any frame arrived")
        try await reopened.close()
        print("Libre runtime collector persisted overlapping checked readings; stop and SQLite reopen passed.")
    }

    nonisolated static func waitUntilIdle(_ queue: LibreOrderedIngestion) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while queue.snapshot.workerScheduled {
            guard ContinuousClock.now < deadline else { throw Failure("runtime queue did not become idle") }
            await Task.yield()
        }
    }

    static func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw Failure("runtime status callback timed out") }
            await Task.yield()
        }
    }

    nonisolated static func makeBridge(for store: ReadingStore) -> LibrePersistenceBridge {
        LibrePersistenceBridge(dependencies: .init(
            loadForIngestion: { _ in throw Failure("runtime candidate route touched Keychain") },
            restoreMissingClockAnchor: { _, _ in throw Failure("runtime candidate route repaired Keychain") },
            resolveSessionMetadata: { _ in throw Failure("runtime candidate route used the retired metadata writer") },
            querySessionMetadata: { id, fingerprint, revision in
                try await store.sessionMetadata(
                    id: id, stableIdentityFingerprint: fingerprint, sensorRevision: revision
                )
            },
            openStore: {
                switch await store.currentHealth() {
                case .notLoaded: try await store.load()
                case .healthy: break
                case .unhealthy: _ = try await store.retryAfterFailure()
                case .closed: throw ReadingStoreError.unavailable(.closed)
                }
            },
            retryStoreAfterFailure: { _ = try await store.retryAfterFailure() },
            currentStoreHealth: { await store.currentHealth() }
        ))
    }

    nonisolated static func session() throws -> LibreSensorSession {
        let captured = try calibration()
        return LibreSensorSession(
            uid: uid, patchInfo: patch, advertisedName: "ABBOTTTEST", unlockCode: 1234,
            setupComplete: true, sensorKind: .libre2_7F, createdAt: epoch,
            calibration: captured.calibration, clockAnchor: captured.clock,
            persistenceSessionID: UUID()
        )
    }

    nonisolated static func calibration() throws -> (calibration: LibreCalibration, clock: LibreSensorClockAnchor) {
        var fram = Data(repeating: 0, count: 344)
        let header = UInt16(1 << 3)
        fram[2] = UInt8(truncatingIfNeeded: header)
        fram[3] = UInt8(header >> 8)
        fram[4] = 3
        fram[316] = 0xE8
        fram[317] = 0x03
        let footer = UInt64(10_000) << 8 | UInt64(8_000 / 4) << 52
        for index in 0..<8 { fram[336 + index] = UInt8(truncatingIfNeeded: footer >> (index * 8)) }
        for range in [0..<24, 24..<320, 320..<344] {
            let checksum = referenceCRC(Array(fram[(range.lowerBound + 2)..<range.upperBound]))
            fram[range.lowerBound] = UInt8(truncatingIfNeeded: checksum)
            fram[range.lowerBound + 1] = UInt8(checksum >> 8)
        }
        let calibration = try LibreCalibration.capture(
            fram: fram, uid: uid, patchInfo: patch, capturedAt: epoch
        )
        return (calibration, try LibreSensorClockAnchor.capture(from: calibration))
    }

    nonisolated static func rawFrame(marker: UInt8) -> Data {
        Data(repeating: marker, count: 46)
    }

    nonisolated static func payload(minute: Int, glucose: Int) -> Data {
        var bytes = Data(repeating: 0, count: 44)
        for index in 0..<7 {
            let word = UInt32(glucose) | UInt32(6_000 / 4) << 14
            let start = index * 4
            bytes[start] = UInt8(truncatingIfNeeded: word)
            bytes[start + 1] = UInt8(truncatingIfNeeded: word >> 8)
            bytes[start + 2] = UInt8(truncatingIfNeeded: word >> 16)
            bytes[start + 3] = UInt8(truncatingIfNeeded: word >> 24)
        }
        bytes[40] = UInt8(truncatingIfNeeded: minute)
        bytes[41] = UInt8(truncatingIfNeeded: minute >> 8)
        let checksum = referenceCRC(Array(bytes.prefix(42)))
        bytes[42] = UInt8(truncatingIfNeeded: checksum)
        bytes[43] = UInt8(checksum >> 8)
        return bytes
    }

    nonisolated static func referenceCRC(_ bytes: [UInt8]) -> UInt16 {
        var remainder: UInt16 = 0xFFFF
        for byte in bytes {
            for bit in 0..<8 {
                let feedback = ((remainder >> 15) ^ UInt16((byte >> bit) & 1)) != 0
                remainder <<= 1
                if feedback { remainder ^= 0x1021 }
            }
        }
        return remainder
    }

    nonisolated static func expect(_ condition: @autoclosure () -> Bool,
                                   _ message: String) throws {
        if !condition() { throw Failure(message) }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
