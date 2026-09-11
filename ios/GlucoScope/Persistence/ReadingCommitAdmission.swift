import CoreData
import Foundation

/// Ownership authority for exactly one frame sequence and reconciled session.
/// It does not qualify a decoder or certify candidate glucose values. Runtime BLE
/// ingestion must use the guarded writer entry point once that adapter exists.
struct ReadingCommitAdmission: Sendable {
    private let ownership: ReadingCommitOwnership
    private let sequence: UInt64
    private let session: ReadingSessionSnapshot
    private let receivedAt: Date

    // The epoch has no initializer or factory outside the generation-gate file.
    // Accepting that otherwise inaccessible instance keeps issuance restricted.
    init(ownership: ReadingCommitOwnership, sequence: UInt64,
         session: ReadingSessionSnapshot, receivedAt: Date) {
        self.ownership = ownership
        self.sequence = sequence
        self.session = session
        self.receivedAt = receivedAt
    }

    func validateSubmission(_ submission: ReadingSubmission) throws {
        guard submission.sequence == sequence, submission.session == session,
              submission.candidates.allSatisfy({ $0.receivedAt == receivedAt }) else {
            throw ReadingStoreError.ownershipRejected(.submissionMismatch)
        }
    }

    /// Called only on the private writer context's queue, after staging changes.
    /// The validity decision and synchronous save share invalidate()'s lock. A
    /// revocation that wins the lock rejects the whole staged transaction; if the
    /// writer wins, the commit completes before revocation takes effect. Even a
    /// no-change duplicate must pass this decision. No client callbacks or await
    /// are accepted here; publication and rollback happen after releasing the lock.
    func save(
        _ context: NSManagedObjectContext,
        submission: ReadingSubmission,
        faultInjector: ReadingStoreFaultInjector?
    ) throws {
        try validateSubmission(submission)
        try ownership.save(context, faultInjector: faultInjector)
    }
}
