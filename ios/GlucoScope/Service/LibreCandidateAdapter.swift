import Foundation

/// Collector candidate boundary. The ordinary entry point always invokes the
/// closed production decoder; it has no caller-supplied decoder/result/policy.
final class LibreCandidateAdapter: @unchecked Sendable {
    private let readingStore: ReadingStore
    private let bridge: LibrePersistenceBridge
    private let gate: LibreFrameGenerationGate
    private let recoveryLock = NSLock()
    private var pendingRecoveryKeys: [ReadingRecoverySampleKey]?
    private var isProcessing = false

    init(readingStore: ReadingStore, bridge: LibrePersistenceBridge, gate: LibreFrameGenerationGate) {
        self.readingStore = readingStore
        self.bridge = bridge
        self.gate = gate
    }

    func open() async throws { try await bridge.openStore() }
    func recover() async throws {
        switch await bridge.currentStoreHealth() {
        case .healthy: return // A prior recovery may still need a committed refetch.
        case .notLoaded: try await bridge.openStore()
        case .unhealthy: try await bridge.retryStoreAfterFailure()
        case .closed: throw ReadingStoreError.unavailable(.closed)
        }
    }
    /// Engineering storage checkpoint only. Runtime graph consumers still need
    /// their own bounded refetch; this does not replay a lost notification.
    func refetchCommitted() async throws {
        let keys = recoveryState { pendingRecoveryKeys }
        guard let keys else { throw ReadingStoreError.invalidInput("No durable recovery checkpoint") }
        let checkpoint = try await readingStore.verifyCommittedSamples(keys)
        guard checkpoint.verifiedSampleCount == keys.count else {
            throw ReadingStoreError.invalidInput("Incomplete durable recovery checkpoint")
        }
        recoveryState {
            if pendingRecoveryKeys == keys { pendingRecoveryKeys = nil }
        }
    }

    private func recoveryState<T>(_ body: () -> T) -> T {
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        return body()
    }

    func process(
        _ frame: LibreVerifiedFrame, context: LibreOrderedFrameContext
    ) async -> LibreOrderedFrameOutcome {
        await processOwned(frame, context: context, evaluation: .production)
    }

    private enum EvaluationMode {
        case production
        #if LIBRE2_CANDIDATE_ADAPTER_FIXTURES && LIBRE2_ENGINEERING_DECODER_FIXTURES
        case fixture(LibreCandidateAdapterFixtureMutation)
        #endif
    }

    /// These private copies can only originate in this operation's decoder call.
    /// They are not detached production results or a reusable adaptation API.
    private struct CheckedSlot {
        var index: Int
        var offset: Int
        var minute: Int
        var timestamp: Date
        var glucose: Int
        var quality: String
        var version: String

        init(_ slot: Libre2AcceptedSlot) {
            index = slot.index
            offset = slot.offsetMinutes
            minute = slot.sensorMinute
            timestamp = slot.timestamp
            glucose = slot.glucoseMGDL
            quality = slot.quality
            version = slot.decoderVersion
        }
    }

    private enum Slot {
        case accepted(CheckedSlot)
        case rejected(Libre2SlotRejection)

        init(_ outcome: Libre2SlotOutcome) {
            switch outcome {
            case .accepted(let slot): self = .accepted(CheckedSlot(slot))
            case .rejected(let rejection): self = .rejected(rejection)
            }
        }
        var index: Int {
            switch self {
            case .accepted(let slot): return slot.index
            case .rejected(let slot): return slot.index
            }
        }
        var offset: Int {
            switch self {
            case .accepted(let slot): return slot.offset
            case .rejected(let slot): return slot.offsetMinutes
            }
        }
    }

    private struct Evaluation {
        let payload: Data
        let capturedSession: LibreSensorSession
        var canonicalSession: ReadingSessionSnapshot
        var context: Libre2DecodeContext
        var rejection: Libre2FrameRejection?
        var slots: [Slot]
    }

    private func processOwned(
        _ frame: LibreVerifiedFrame,
        context: LibreOrderedFrameContext,
        evaluation mode: EvaluationMode
    ) async -> LibreOrderedFrameOutcome {
        let reserved = recoveryState {
            guard !isProcessing, pendingRecoveryKeys == nil else { return false }
            isProcessing = true
            return true
        }
        guard reserved else { return LibreOrderedFrameOutcome(disposition: .storageFailure) }
        defer { recoveryState { isProcessing = false } }
        var acceptedCount: Int?
        var attemptedKeys: [ReadingRecoverySampleKey] = []
        var rejectionCounts: [String: Int] = [:]
        func result(_ disposition: LibreOrderedFrameOutcome.Disposition) -> LibreOrderedFrameOutcome {
            LibreOrderedFrameOutcome(disposition: disposition, acceptedCandidates: acceptedCount,
                                     slotRejections: rejectionCounts)
        }
        func discard() -> LibreOrderedDiscardReason? {
            // A context is scheduling evidence, not frame ownership authority.
            // Check this exact frame independently to prevent a mismatched context
            // from authorizing an older frame.
            guard gate.isCurrent(frame) else { return .staleOwnership }
            return context.check()
        }
        if let reason = discard() { return result(.discarded(reason)) }
        do {
            let preparation = try await bridge.prepareCandidates(frame: frame, isCurrent: {
                self.gate.isCurrent(frame)
            })
            if let reason = discard() { return result(.discarded(reason)) }
            guard preparation.session == frame.sessionSnapshot else {
                return result(.invariantFailure)
            }
            // Keep frame, canonical snapshot and decoder output in this single
            // invocation. Redacted context equality alone cannot bind payloads.
            let session = preparation.sessionSnapshot
            let ownership = Libre2DecodeOwnership(generation: frame.generation,
                                                  session: frame.sessionSnapshot,
                                                  persistenceSessionID: frame.persistenceSessionID)
            var decoded: Evaluation
            let permitsMapping: Bool
            let expectedQuality: String
            switch mode {
            case .production:
                let output = Libre2ProductionDecoder.decode(frame: frame, session: session,
                                                           ownership: ownership)
                decoded = Evaluation(payload: frame.payload, capturedSession: frame.sessionSnapshot,
                                     canonicalSession: session, context: output.context, rejection: output.rejection,
                                     slots: output.slots.map(Slot.init))
                permitsMapping = Libre2ProductionPolicy.engineeringV1.canIngestCanonical
                // No qualified quality exists. Adding a qualified policy requires
                // an explicit reviewed adapter change, never a caller-set string.
                expectedQuality = ""
            #if LIBRE2_CANDIDATE_ADAPTER_FIXTURES && LIBRE2_ENGINEERING_DECODER_FIXTURES
            case .fixture(let mutation):
                let output = Libre2ProductionDecoder.evaluateEngineering(
                    frame: frame, session: session, ownership: ownership
                )
                decoded = Evaluation(payload: frame.payload, capturedSession: frame.sessionSnapshot,
                                     canonicalSession: session, context: output.context, rejection: output.rejection,
                                     slots: output.slots.map(Slot.init))
                applyFixtureMutation(mutation, to: &decoded, frame: frame, session: session)
                permitsMapping = true
                expectedQuality = "engineeringChecksPassed-v1"
            #endif
            }
            guard decoded.payload == frame.payload, decoded.capturedSession == frame.sessionSnapshot,
                  decoded.canonicalSession == session, Self.contextMatches(decoded.context, frame: frame) else {
                return result(.invariantFailure)
            }
            if decoded.rejection != nil {
                guard decoded.slots.isEmpty else { return result(.invariantFailure) }
                acceptedCount = 0
                return result(.wholeFrameRejected)
            }
            guard permitsMapping else { return result(.invariantFailure) }
            let candidates = try Self.map(decoded, frame: frame, session: session,
                                          expectedQuality: expectedQuality)
            acceptedCount = candidates.count
            for case .rejected(let rejection) in decoded.slots {
                rejectionCounts[rejection.reason.rawValue, default: 0] += 1
            }
            guard !candidates.isEmpty else { return result(.allSlotsRejected) }
            if let reason = discard() { return result(.discarded(reason)) }
            let submission = ReadingSubmission(sequence: frame.sequence, session: session,
                                               candidates: candidates)
            attemptedKeys = Array(Set(candidates.map {
                ReadingRecoverySampleKey(sessionID: session.id, sensorMinute: $0.sensorMinute, kind: $0.kind)
            })).sorted { $0.sensorMinute < $1.sensorMinute }
            let admission = try gate.makeCommitAdmission(for: frame, session: session)
            if let reason = discard() { return result(.discarded(reason)) }
            _ = try await readingStore.ingest(submission, admission: admission)
            // A save that wins revocation is durable. Do not turn its later
            // completion into a stale discard; the queue owns readiness updates.
            return result(.completed)
        } catch {
            // Durability takes priority over later revocation or cancellation.
            if case ReadingStoreError.operationFailed(let failure) = error,
               failure.durableCommitAwaitingPublication {
                // Retain only this transaction's bounded redacted coordinates,
                // never a resubmission buffer or the complete history snapshot.
                recoveryState { pendingRecoveryKeys = attemptedKeys }
                return result(.durablePublicationFailure)
            }
            if case ReadingStoreError.ownershipRejected(.submissionMismatch) = error {
                return result(.invariantFailure)
            }
            if error is AdapterInvariant { return result(.invariantFailure) }
            if case ReadingStoreError.invalidInput = error { return result(.invariantFailure) }
            // An actual persistence failure pauses the queue even when its frame
            // was revoked concurrently; otherwise unhealthy storage is hidden.
            switch error {
            case ReadingStoreError.operationFailed, ReadingStoreError.unavailable,
                 ReadingStoreError.retriesExhausted:
                return result(.storageFailure)
            default: break
            }
            if !gate.isCurrent(frame) { return result(.discarded(.staleOwnership)) }
            switch error {
            case LibrePersistenceBridgeError.staleSession,
                 LibreFrameOwnershipError.staleFrame,
                 ReadingStoreError.ownershipRejected(.staleFrame):
                return result(.discarded(.staleOwnership))
            case is LibrePersistenceBridgeError, is LibreFrameOwnershipError,
                 is LibrePersistenceIdentityError, is LibreSensorClockAnchorError,
                 ReadingStoreError.repairRequired:
                return result(.repairRequired)
            default:
                return result(.storageFailure)
            }
        }
    }

    private struct AdapterInvariant: Error {}

    private static func contextMatches(_ context: Libre2DecodeContext, frame: LibreVerifiedFrame) -> Bool {
        let receipt = frame.receivedAt.timeIntervalSince1970
        let usableReceipt = receipt.isFinite && (946_684_800...4_102_444_800).contains(receipt)
        return context.persistenceSessionID == frame.persistenceSessionID &&
            context.generation == frame.generation && context.sequence == frame.sequence &&
            context.receivedAt == (usableReceipt ? frame.receivedAt : nil) &&
            context.policyVersion == Libre2ProductionPolicy.engineeringV1.rawValue &&
            context.decoderVersion == Libre2ProductionDecoder.version
    }

    private static func map(
        _ decoded: Evaluation, frame: LibreVerifiedFrame, session: ReadingSessionSnapshot,
        expectedQuality: String
    ) throws -> [ReadingCandidate] {
        let bytes = [UInt8](frame.payload)
        guard bytes.count == 44, decoded.context.receivedAt == frame.receivedAt,
              decoded.slots.count == 7, Set(decoded.slots.map(\.index)) == Set(0..<7),
              session.id == frame.persistenceSessionID, session.lifecycleState == .active else {
            throw AdapterInvariant()
        }
        let minute = Int(bytes[40]) | Int(bytes[41]) << 8
        var candidates: [ReadingCandidate] = []
        for outcome in decoded.slots {
            guard Libre2ProductionDecoder.sampleOffsets[outcome.index] == outcome.offset else {
                throw AdapterInvariant()
            }
            let expectedMinute = minute.subtractingReportingOverflow(outcome.offset)
            guard !expectedMinute.overflow else { throw AdapterInvariant() }
            switch outcome {
            case .rejected(let rejection):
                guard rejection.sensorMinute == expectedMinute.partialValue else { throw AdapterInvariant() }
            case .accepted(let slot):
                guard slot.minute == expectedMinute.partialValue,
                      (60...20_880).contains(slot.minute),
                      let sensorMinute = Int64(exactly: slot.minute),
                      (20...600).contains(slot.glucose),
                      slot.version == Libre2ProductionDecoder.version,
                      slot.quality == expectedQuality else { throw AdapterInvariant() }
                let delta = sensorMinute.subtractingReportingOverflow(session.clock.referenceSensorMinute)
                guard !delta.overflow else { throw AdapterInvariant() }
                let seconds = session.clock.referenceDate.timeIntervalSince1970 + Double(delta.partialValue) * 60
                guard seconds.isFinite, (946_684_800...4_102_444_800).contains(seconds),
                      slot.timestamp == Date(timeIntervalSince1970: seconds),
                      slot.timestamp == session.clock.referenceDate.addingTimeInterval(
                        Double(delta.partialValue) * 60
                      ) else { throw AdapterInvariant() }
                candidates.append(ReadingCandidate(sensorMinute: sensorMinute, kind: .trend,
                                                    receivedAt: frame.receivedAt, glucoseMGDL: slot.glucose,
                                                    quality: slot.quality,
                                                    origin: slot.offset == 0 ? .bleLive : .bleHistory,
                                                    decoderVersion: slot.version))
            }
        }
        return candidates.sorted { $0.sensorMinute < $1.sensorMinute }
    }
}

#if LIBRE2_CANDIDATE_ADAPTER_FIXTURES && LIBRE2_ENGINEERING_DECODER_FIXTURES
/// Adversarial mapping harness only. It never constructs a production decode
/// result, changes its policy, or exists in the application's source shape.
enum LibreCandidateAdapterFixtureMutation {
    case none, missingSlot, duplicateIndex, wrongOffset, wrongMinute, wrongDate
    case wrongGlucose, wrongQuality, wrongVersion, wrongReceipt, wrongPolicy, wrongSequence
    case wrongGeneration, wrongWear, wrongContextVersion, wrongCanonicalSession
    case swappedEvaluation(LibreVerifiedFrame)
}

extension LibreCandidateAdapter {
    func processFixture(
        _ frame: LibreVerifiedFrame, context: LibreOrderedFrameContext,
        mutation: LibreCandidateAdapterFixtureMutation = .none
    ) async -> LibreOrderedFrameOutcome {
        await processOwned(frame, context: context, evaluation: .fixture(mutation))
    }

    private func applyFixtureMutation(
        _ mutation: LibreCandidateAdapterFixtureMutation, to evaluation: inout Evaluation,
        frame: LibreVerifiedFrame, session: ReadingSessionSnapshot
    ) {
        switch mutation {
        case .none: return
        case .missingSlot: evaluation.slots.removeLast(); return
        case .wrongCanonicalSession:
            let old = evaluation.canonicalSession
            evaluation.canonicalSession = ReadingSessionSnapshot(
                id: UUID(), stableIdentityFingerprint: old.stableIdentityFingerprint,
                sensorRevision: old.sensorRevision, firstObservedAt: old.firstObservedAt,
                observedAt: old.observedAt, lifecycleState: old.lifecycleState, clock: old.clock
            )
            return
        case .swappedEvaluation(let other):
            let output = Libre2ProductionDecoder.evaluateEngineering(
                frame: other, session: session,
                ownership: Libre2DecodeOwnership(generation: other.generation,
                                                session: other.sessionSnapshot,
                                                persistenceSessionID: other.persistenceSessionID)
            )
            evaluation = Evaluation(payload: other.payload, capturedSession: other.sessionSnapshot,
                                    canonicalSession: session, context: output.context, rejection: output.rejection,
                                    slots: output.slots.map(Slot.init))
            return
        case .wrongReceipt, .wrongPolicy, .wrongSequence, .wrongGeneration, .wrongWear, .wrongContextVersion:
            let old = evaluation.context
            evaluation.context = Libre2DecodeContext(
                persistenceSessionID: mutation.isWrongWear ? UUID() : old.persistenceSessionID,
                generation: mutation.isWrongGeneration ? old.generation &+ 1 : old.generation,
                sequence: mutation.isWrongSequence ? old.sequence &+ 1 : old.sequence,
                receivedAt: mutation.isWrongReceipt ? old.receivedAt?.addingTimeInterval(1) : old.receivedAt,
                policyVersion: mutation.isWrongPolicy ? "fixture-wrong-policy" : old.policyVersion,
                decoderVersion: mutation.isWrongContextVersion ? "fixture-wrong-decoder" : old.decoderVersion
            )
            return
        default: break
        }
        guard case .accepted(var slot) = evaluation.slots[0] else { return }
        switch mutation {
        case .duplicateIndex: slot.index = 1
        case .wrongOffset: slot.offset += 1
        case .wrongMinute: slot.minute += 1
        case .wrongDate: slot.timestamp = slot.timestamp.addingTimeInterval(1)
        case .wrongGlucose: slot.glucose = 601
        case .wrongQuality: slot.quality = "fixture-wrong-quality"
        case .wrongVersion: slot.version = "fixture-wrong-version"
        default: break
        }
        evaluation.slots[0] = .accepted(slot)
    }
}

private extension LibreCandidateAdapterFixtureMutation {
    var isWrongWear: Bool { if case .wrongWear = self { return true }; return false }
    var isWrongGeneration: Bool { if case .wrongGeneration = self { return true }; return false }
    var isWrongContextVersion: Bool { if case .wrongContextVersion = self { return true }; return false }
    var isWrongSequence: Bool { if case .wrongSequence = self { return true }; return false }
    var isWrongReceipt: Bool { if case .wrongReceipt = self { return true }; return false }
    var isWrongPolicy: Bool { if case .wrongPolicy = self { return true }; return false }
}
#endif
