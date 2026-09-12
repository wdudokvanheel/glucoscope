import Foundation

@main
enum ReadingStoreBroadcastSmoke {
    static func main() async throws {
        let store = ReadingStore(configuration: .init(storage: .inMemory(identifier: UUID().uuidString)))
        try await store.load()
        let first = await store.commitStream()
        let second = await store.commitStream()
        let now = Date(timeIntervalSince1970: 1_742_644_800)
        let session = ReadingSessionSnapshot(
            id: UUID(),
            stableIdentityFingerprint: Data([1, 2, 3]),
            sensorRevision: "test",
            firstObservedAt: now,
            observedAt: now,
            lifecycleState: .active,
            clock: ReadingClockSnapshot(referenceSensorMinute: 100, referenceDate: now, provenance: "test")
        )
        let committed = try await store.ingest(ReadingSubmission(
            sequence: 1,
            session: session,
            candidates: [ReadingCandidate(
                sensorMinute: 100,
                kind: .trend,
                receivedAt: now,
                glucoseMGDL: 123,
                quality: "valid",
                origin: .bleLive,
                decoderVersion: "test"
            )]
        ))
        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        let receivedFirst = await firstIterator.next()
        let receivedSecond = await secondIterator.next()
        precondition(receivedFirst == committed, "first subscriber missed commit")
        precondition(receivedSecond == committed, "second subscriber missed commit")
        try await store.close()
        let firstFinished = await firstIterator.next()
        let secondFinished = await secondIterator.next()
        precondition(firstFinished == nil, "first stream should finish on close")
        precondition(secondFinished == nil, "second stream should finish on close")
        print("ReadingStoreBroadcastSmoke: PASS")
    }
}
