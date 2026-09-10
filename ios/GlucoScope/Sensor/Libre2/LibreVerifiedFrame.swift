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

/// Shared by the serial BLE queue and the main-actor consumer. Invalidation happens
/// before dispatching lifecycle events, so already queued callbacks become stale.
final class LibreFrameGenerationGate: @unchecked Sendable {
    private static let sequenceLock = NSLock()
    private static var nextSequence: UInt64 = 0
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var session: LibreSensorSession?
    private var durableID: UUID?

    @discardableResult
    func activate(session: LibreSensorSession, persistenceSessionID: UUID?) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        precondition(generation < UInt64.max)
        generation += 1
        self.session = session
        durableID = persistenceSessionID
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

enum LibreFrameOwnershipError: Error {
    case staleFrame
}
