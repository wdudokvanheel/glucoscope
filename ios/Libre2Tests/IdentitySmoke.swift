import Foundation

/// Synthetic identity/Keychain-boundary fixtures; no NFC or actual Keychain operations.
@main
struct IdentitySmoke {
    static let uid = Data([1, 2, 3, 4, 5, 6, 7, 8])
    static let patch = Data([0x9D, 0, 0, 0, 0, 0])
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func main() throws {
        let original = try session()
        let restored = try roundTrip(original)
        try expect(restored == original, "identity and clock survive restart")
        var legacyObject = try object(original)
        legacyObject.removeValue(forKey: "persistenceSessionID")
        legacyObject.removeValue(forKey: "persistenceIdentityVersion")
        let legacy = try decode(legacyObject)
        try expect(legacy.persistenceSessionID == nil, "decode never invents legacy identity")
        try rejects(.missingIdentity) { _ = try legacy.validatedPersistenceSessionID() }
        var saved: LibreSensorSession?
        let migrated = try legacy.requiringPersistenceIdentity { saved = try roundTrip($0) }
        try expect(saved == migrated && migrated.persistenceSessionID != nil, "upgrade saved before returned")
        let relaunched = try saved!.requiringPersistenceIdentity { _ in throw Failure(message: "second migration") }
        try expect(relaunched.persistenceSessionID == migrated.persistenceSessionID, "crash after Keychain save before store insertion retains ID")
        do {
            _ = try legacy.requiringPersistenceIdentity { _ in throw WriteFailure() }
            throw Failure(message: "migration write failure swallowed")
        } catch is WriteFailure { }
        try expect(legacy.persistenceSessionID == nil, "failed migration leaves caller unchanged")
        var staleCounter = legacy; staleCounter.nextUnlockCount += 1
        let counterSave = try staleCounter.retainingDurableIdentity(from: migrated)
        try expect(counterSave.persistenceSessionID == migrated.persistenceSessionID && counterSave.nextUnlockCount == staleCounter.nextUnlockCount,
                   "stale BLE counter save cannot erase durable migration")
        try rejects(.repairRequired) { _ = try original.retainingDurableIdentity(from: migrated) }
        try expect(try migrated.retainingDurableIdentity(from: legacy) == migrated, "first durable migration may replace absent identity")

        for corrupt in [NSNull(), "bad UUID", 123, ["unexpected": true]] as [Any] {
            var damagedObject = try object(original)
            damagedObject["persistenceSessionID"] = corrupt
            var damaged = try decode(damagedObject)
            try expect(damaged.uid == original.uid && damaged.unlockCode == original.unlockCode,
                       "bad identity does not discard established pairing")
            damaged.nextUnlockCount += 1
            damaged = try roundTrip(damaged)
            try rejects(.invalidIdentity) {
                _ = try damaged.requiringPersistenceIdentity { _ in throw Failure(message: "corrupt identity migrated") }
            }
        }
        var unsupportedObject = try object(original)
        unsupportedObject["persistenceIdentityVersion"] = 99
        let unsupported = try roundTrip(decode(unsupportedObject))
        let staleOverInvalid = try roundTrip(legacy.retainingDurableIdentity(from: unsupported))
        try rejects(.invalidIdentity) { _ = try staleOverInvalid.validatedPersistenceSessionID() }
        try rejects(.invalidIdentity) { _ = try unsupported.validatedPersistenceSessionID() }

        var mutablePatch = patch
        mutablePatch[4] = 0xAA; mutablePatch[5] = 0xBB
        var freshSetup = try session(minute: 1010, capturedAt: date.addingTimeInterval(622), patch: mutablePatch)
        freshSetup.createdAt = date.addingTimeInterval(1000)
        freshSetup.peripheralID = UUID()
        freshSetup.unlockCode = 456
        let repaired = try freshSetup.preservingWearIdentity(from: original)
        try expect(repaired.persistenceSessionID == original.persistenceSessionID && repaired.clockAnchor == original.clockAnchor,
                   "same-wear setup retains UUID and original clock despite recapture and pairing changes")
        try expect(repaired.createdAt == freshSetup.createdAt && repaired.calibration == freshSetup.calibration,
                   "new pairing metadata survives repair")
        try expect(try repaired.stableIdentityFingerprint() == original.stableIdentityFingerprint(), "mutable patch bytes excluded from fingerprint")
        let expectedHash = "2537f0a92065d0ab243cdd4f29cd7cc1add7a675f52f74c1127a59ceaad4052d"
        try expect(try original.stableIdentityFingerprint().map { String(format: "%02x", $0) }.joined() == expectedHash,
                   "SHA256 identity matches independently evaluated fixture")
        let extendedPatch = patch + Data([1])
        let extended = try session(patch: extendedPatch)
        try expect(try extended.stableIdentityFingerprint() != original.stableIdentityFingerprint(), "stable trailing patch bytes remain identity")
        try expect(try repaired.clockAnchor!.timestamp(for: 1000) == date, "old minute retains UTC date")
        let recaptured = try calibration(minute: 1015, capturedAt: date.addingTimeInterval(907), patch: mutablePatch)
        let merged = try repaired.mergingCalibration(recaptured, expectedSession: repaired)
        try expect(merged.persistenceSessionID == original.persistenceSessionID && merged.clockAnchor == original.clockAnchor,
                   "read-only calibration preserves UUID and clock")

        // A clock correction is uncertainty, not proof of a new wear. The 120 s
        // tolerance is an engineering policy awaiting hardware qualification.
        let clockCorrected = try session(minute: 1010, capturedAt: date.addingTimeInterval(4200))
        try rejects(.repairRequired) { _ = try clockCorrected.preservingWearIdentity(from: original) }
        try rejects(.repairRequired) { _ = try session(minute: 990).preservingWearIdentity(from: original) }
        try rejects(.repairRequired) { _ = try session(state: 2).preservingWearIdentity(from: original) }
        var missing = original; missing.calibration = nil
        try rejects(.missingWearEvidence) { _ = try freshSetup.preservingWearIdentity(from: missing) }
        let starting = try session(state: 2)
        let nowActive = try session(minute: 1001, capturedAt: date.addingTimeInterval(60))
        try expect(try nowActive.preservingWearIdentity(from: starting).persistenceSessionID == starting.persistenceSessionID,
                   "forward lifecycle transition retains wear")
        var replacementUID = uid; replacementUID[0] = 99
        let replacement = try session(uid: replacementUID)
        let newWear = try replacement.preservingWearIdentity(from: original)
        try expect(newWear.persistenceSessionID == replacement.persistenceSessionID && newWear.persistenceSessionID != original.persistenceSessionID,
                   "replacement receives independent identity")
        try expect(try newWear.stableIdentityFingerprint() != original.stableIdentityFingerprint(), "replacement fingerprint differs")
        let afterCorruption = try replacement.preservingWearIdentity(from: unsupported)
        try expect(afterCorruption.persistenceSessionID == replacement.persistenceSessionID, "damaged old identity does not block different physical sensor")
        try expect(try freshSetup.preservingWearIdentity(from: nil) == freshSetup, "first setup unchanged")
        print("Libre 2 wear identity synthetic fixtures passed (no hardware validation).")
    }

    static func session(minute: Int = 1000, capturedAt: Date = date, state: UInt8 = 3,
                        uid: Data = uid, patch: Data = patch) throws -> LibreSensorSession {
        LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "fixture", unlockCode: 42,
                           setupComplete: true, sensorKind: .libre2_9D, createdAt: date,
                           calibration: try calibration(minute: minute, capturedAt: capturedAt, state: state, uid: uid, patch: patch))
    }

    static func calibration(minute: Int, capturedAt: Date, state: UInt8 = 3,
                            uid: Data = uid, patch: Data = patch) throws -> LibreCalibration {
        // Identity tests need only validated capture metadata; decoding a synthetic
        // versioned calibration avoids coupling this suite to FRAM/CRC arithmetic.
        let value: [String: Any] = ["ownerUID": uid.base64EncodedString(), "ownerPatchInfo": patch.base64EncodedString(),
            "formatVersion": 1, "capturedAt": capturedAt.timeIntervalSinceReferenceDate, "sensorMinute": minute,
            "lifecycle": state, "calibrationSource": Data(repeating: 0, count: 10).base64EncodedString()]
        return try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: value))
    }

    static func object(_ session: LibreSensorSession) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
    }
    static func decode(_ value: [String: Any]) throws -> LibreSensorSession {
        try JSONDecoder().decode(LibreSensorSession.self, from: JSONSerialization.data(withJSONObject: value))
    }
    static func roundTrip(_ value: LibreSensorSession) throws -> LibreSensorSession {
        try JSONDecoder().decode(LibreSensorSession.self, from: JSONEncoder().encode(value))
    }
    static func rejects(_ expected: LibrePersistenceIdentityError, _ operation: () throws -> Void) throws {
        do { try operation(); throw Failure(message: "expected identity failure: \(expected)") }
        catch let error as LibrePersistenceIdentityError { try expect(error == expected, "correct identity failure") }
    }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    struct Failure: Error { let message: String }
    struct WriteFailure: Error { }
}
