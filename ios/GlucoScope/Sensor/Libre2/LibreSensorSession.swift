import Foundation
import CryptoKit

enum LibreSensorKind: String, Codable, Sendable {
    case libre2_9D
    case libre2_C5
    case libre2_7F
}

enum LibrePersistenceIdentityError: LocalizedError, Equatable {
    case missingIdentity
    case invalidIdentity
    case repairRequired
    case missingWearEvidence

    var errorDescription: String? {
        switch self {
        case .missingIdentity: return "The Libre wear identity must be saved before ingestion."
        case .invalidIdentity: return "The saved Libre wear identity is unreadable; collection requires repair."
        case .missingWearEvidence: return "Capture read-only calibration for the saved sensor before retrying setup."
        case .repairRequired: return "The Libre wear session cannot be reconciled safely; collection requires repair."
        }
    }
}

struct LibreSensorSession: Codable, Sendable, Equatable {
    static let currentPersistenceIdentityVersion = 1
    private(set) var persistenceSessionID: UUID?
    // Invalid-present identity is distinct from an absent legacy field. Keep pairing
    // credentials usable, but never replace corrupted durable identity with a new UUID.
    private var hasInvalidPersistenceIdentity = false
    var uid: Data
    var patchInfo: Data
    var advertisedName: String
    var peripheralID: UUID?
    var unlockCode: UInt32
    var nextUnlockCount: UInt32
    var setupComplete: Bool
    var sensorKind: LibreSensorKind
    var createdAt: Date
    var calibration: LibreCalibration?
    var clockAnchor: LibreSensorClockAnchor?

    init(
        uid: Data,
        patchInfo: Data,
        advertisedName: String,
        peripheralID: UUID? = nil,
        unlockCode: UInt32,
        nextUnlockCount: UInt32 = 1,
        setupComplete: Bool,
        sensorKind: LibreSensorKind,
        createdAt: Date = Date(),
        calibration: LibreCalibration? = nil,
        clockAnchor: LibreSensorClockAnchor? = nil,
        persistenceSessionID: UUID = UUID()
    ) {
        self.persistenceSessionID = persistenceSessionID
        self.uid = uid
        self.patchInfo = patchInfo
        self.advertisedName = advertisedName
        self.peripheralID = peripheralID
        self.unlockCode = unlockCode
        self.nextUnlockCount = nextUnlockCount
        self.setupComplete = setupComplete
        self.sensorKind = sensorKind
        self.createdAt = createdAt
        self.calibration = calibration
        self.clockAnchor = clockAnchor ?? calibration.flatMap { try? LibreSensorClockAnchor.capture(from: $0) }
    }

    /// Returns an identity only after any legacy upgrade has been durably saved.
    /// A thrown write leaves the caller's value unchanged and must block ingestion.
    func requiringPersistenceIdentity(save: (LibreSensorSession) throws -> Void) throws -> LibreSensorSession {
        guard !hasInvalidPersistenceIdentity else { throw LibrePersistenceIdentityError.invalidIdentity }
        guard persistenceSessionID == nil else { return self }
        var upgraded = self
        upgraded.persistenceSessionID = UUID()
        try save(upgraded)
        return upgraded
    }

    /// A BLE owner can still hold a legacy value when ingestion migrates Keychain.
    /// Its later counter save must not erase that already durable identity. Only
    /// copy identity for the exact pairing; a new deliberate setup owns its own ID.
    func retainingDurableIdentity(from saved: LibreSensorSession?) throws -> LibreSensorSession {
        guard let saved, createdAt == saved.createdAt, unlockCode == saved.unlockCode,
              Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patchInfo,
                                                   otherUID: saved.uid, otherPatchInfo: saved.patchInfo) else { return self }
        if persistenceSessionID != nil || hasInvalidPersistenceIdentity {
            if let durableID = saved.persistenceSessionID, !saved.hasInvalidPersistenceIdentity {
                guard !hasInvalidPersistenceIdentity, persistenceSessionID == durableID else {
                    throw LibrePersistenceIdentityError.repairRequired
                }
            } else if saved.hasInvalidPersistenceIdentity, !hasInvalidPersistenceIdentity {
                throw LibrePersistenceIdentityError.invalidIdentity
            }
            return self
        }
        var result = self
        result.persistenceSessionID = saved.persistenceSessionID
        result.hasInvalidPersistenceIdentity = saved.hasInvalidPersistenceIdentity
        return result
    }

    func validatedPersistenceSessionID() throws -> UUID {
        guard !hasInvalidPersistenceIdentity else { throw LibrePersistenceIdentityError.invalidIdentity }
        guard let persistenceSessionID else { throw LibrePersistenceIdentityError.missingIdentity }
        return persistenceSessionID
    }

    /// Operational fields such as counter, peripheral and calibration may advance
    /// while a frame is in flight. These immutable fields identify the exact
    /// durable pairing whose Keychain record may be migrated or repaired.
    func hasSameDurablePairing(as other: LibreSensorSession) -> Bool {
        createdAt == other.createdAt &&
        unlockCode == other.unlockCode &&
        setupComplete == other.setupComplete &&
        sensorKind == other.sensorKind &&
        Libre2Protocol.hasSameStableIdentity(
            uid: uid,
            patchInfo: patchInfo,
            otherUID: other.uid,
            otherPatchInfo: other.patchInfo
        )
    }

    /// Pure compare-and-update used inside the Keychain store's shared lock. The
    /// receiver is the latest saved value so all newer operational fields survive.
    func restoringMissingClockAnchor(
        _ anchor: LibreSensorClockAnchor,
        expectedSession: LibreSensorSession
    ) throws -> LibreSensorSession {
        guard hasSameDurablePairing(as: expectedSession),
              try validatedPersistenceSessionID() == expectedSession.validatedPersistenceSessionID() else {
            throw LibrePersistenceIdentityError.repairRequired
        }
        guard needsClockAnchor else { throw LibrePersistenceIdentityError.repairRequired }
        try anchor.validateOwnership(uid: uid, patchInfo: patchInfo)
        var repaired = self
        repaired.clockAnchor = anchor
        return repaired
    }

    /// Versioned SHA-256 physical identity; mutable patch bytes 4–5 and all
    /// pairing secrets are excluded. The domain prefix fixes the hash format.
    func stableIdentityFingerprint() throws -> Data {
        guard uid.count == 8, patchInfo.count >= 6,
              (try? Libre2Protocol.classify(patchInfo: patchInfo)) == sensorKind else {
            throw LibrePersistenceIdentityError.repairRequired
        }
        var material = Data("GlucoScope.LibreWearIdentity.v1\0".utf8)
        material.append(uid)
        material.append(contentsOf: patchInfo.enumerated().filter { $0.offset != 4 && $0.offset != 5 }.map(\.element))
        return Data(SHA256.hash(data: material))
    }

    /// Deliberate NFC setup only. A stable physical identity is necessary but not
    /// sufficient proof of the same wear. Sensor-minute progression and lifecycle
    /// must agree with both previous calibration and the original clock. A 120 s
    /// tolerance accommodates two minute-resolution captures; it is a conservative
    /// repair policy, not a validated bound on phone-clock error or sensor drift.
    /// Conflicting/absent evidence (including phone-clock correction) blocks repair,
    /// rather than silently splitting a wear. This milestone has no qualified proof
    /// of a same-UID sensor reset and never infers one from a backward minute alone.
    func preservingWearIdentity(from previous: LibreSensorSession?) throws -> LibreSensorSession {
        guard let previous else { return self }
        guard Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patchInfo,
                                                   otherUID: previous.uid, otherPatchInfo: previous.patchInfo) else {
            return self // A replacement physical sensor starts a new wear.
        }
        let identity = try previous.validatedPersistenceSessionID()
        guard let oldCalibration = previous.calibration, let anchor = previous.clockAnchor else {
            throw LibrePersistenceIdentityError.missingWearEvidence
        }
        guard sensorKind == previous.sensorKind, let calibration,
              (try? oldCalibration.validateOwnership(uid: uid, patchInfo: patchInfo)) != nil,
              (try? calibration.validateOwnership(uid: uid, patchInfo: patchInfo)) != nil,
              (try? anchor.validateOwnership(uid: uid, patchInfo: patchInfo)) != nil,
              (0...LibreSensorClockAnchor.maximumSensorMinute).contains(calibration.sensorMinute),
              (0...LibreSensorClockAnchor.maximumSensorMinute).contains(oldCalibration.sensorMinute),
              calibration.sensorMinute >= oldCalibration.sensorMinute,
              calibration.sensorMinute >= anchor.referenceSensorMinute,
              oldCalibration.lifecycle == 0x02 || oldCalibration.lifecycle == 0x03,
              calibration.lifecycle == 0x02 || calibration.lifecycle == 0x03,
              !(oldCalibration.lifecycle == 0x03 && calibration.lifecycle == 0x02),
              let expectedDate = try? anchor.timestamp(for: calibration.sensorMinute),
              abs(calibration.capturedAt.timeIntervalSince(expectedDate)) <= 120 else {
            throw LibrePersistenceIdentityError.repairRequired
        }
        var repaired = self
        repaired.persistenceSessionID = identity
        repaired.hasInvalidPersistenceIdentity = false
        repaired.clockAnchor = anchor
        return repaired
    }

    var needsCalibration: Bool {
        guard let calibration else { return true }
        return (try? calibration.validateOwnership(uid: uid, patchInfo: patchInfo)) == nil
    }

    var needsClockAnchor: Bool {
        guard let clockAnchor else { return true }
        return (try? clockAnchor.validateOwnership(uid: uid, patchInfo: patchInfo)) == nil
    }

    func mergingCalibration(_ calibration: LibreCalibration, expectedSession: LibreSensorSession) throws -> LibreSensorSession {
        guard uid == expectedSession.uid,
              patchInfo == expectedSession.patchInfo,
              createdAt == expectedSession.createdAt,
              unlockCode == expectedSession.unlockCode,
              setupComplete == expectedSession.setupComplete else {
            throw LibreCalibrationError.replacedPairing
        }
        try calibration.validateOwnership(uid: uid, patchInfo: patchInfo)
        var merged = self
        merged.calibration = calibration
        let hasValidAnchor: Bool
        if let clockAnchor {
            hasValidAnchor = (try? clockAnchor.validateOwnership(uid: uid, patchInfo: patchInfo)) != nil
        } else {
            hasValidAnchor = false
        }
        if !hasValidAnchor {
            merged.clockAnchor = try LibreSensorClockAnchor.capture(from: calibration)
        }
        return merged
    }

    private enum CodingKeys: String, CodingKey {
        case uid, patchInfo, advertisedName, peripheralID, unlockCode, nextUnlockCount
        case setupComplete, sensorKind, createdAt, calibration, clockAnchor
        case persistenceSessionID, persistenceIdentityVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.persistenceSessionID) || values.contains(.persistenceIdentityVersion) {
            persistenceSessionID = try? values.decode(UUID.self, forKey: .persistenceSessionID)
            let version = try? values.decode(Int.self, forKey: .persistenceIdentityVersion)
            hasInvalidPersistenceIdentity = persistenceSessionID == nil || version != Self.currentPersistenceIdentityVersion
        } else {
            persistenceSessionID = nil
        }
        uid = try values.decode(Data.self, forKey: .uid)
        patchInfo = try values.decode(Data.self, forKey: .patchInfo)
        advertisedName = try values.decode(String.self, forKey: .advertisedName)
        peripheralID = try values.decodeIfPresent(UUID.self, forKey: .peripheralID)
        unlockCode = try values.decode(UInt32.self, forKey: .unlockCode)
        nextUnlockCount = try values.decode(UInt32.self, forKey: .nextUnlockCount)
        setupComplete = try values.decode(Bool.self, forKey: .setupComplete)
        sensorKind = try values.decode(LibreSensorKind.self, forKey: .sensorKind)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        // A damaged or obsolete optional snapshot must not make established pairing
        // credentials unreadable. Direct LibreCalibration decoding remains strict.
        calibration = try? values.decodeIfPresent(LibreCalibration.self, forKey: .calibration)
        if values.contains(.clockAnchor) {
            clockAnchor = try? values.decodeIfPresent(LibreSensorClockAnchor.self, forKey: .clockAnchor)
        } else {
            clockAnchor = calibration.flatMap { try? LibreSensorClockAnchor.capture(from: $0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if hasInvalidPersistenceIdentity {
            // Persist the invalid-present marker through counter/calibration saves.
            // Dropping it would incorrectly convert corruption into a migratable legacy record.
            try values.encodeNil(forKey: .persistenceSessionID)
            try values.encode(Self.currentPersistenceIdentityVersion, forKey: .persistenceIdentityVersion)
        } else if let persistenceSessionID {
            try values.encode(persistenceSessionID, forKey: .persistenceSessionID)
            try values.encode(Self.currentPersistenceIdentityVersion, forKey: .persistenceIdentityVersion)
        }
        try values.encode(uid, forKey: .uid)
        try values.encode(patchInfo, forKey: .patchInfo)
        try values.encode(advertisedName, forKey: .advertisedName)
        try values.encodeIfPresent(peripheralID, forKey: .peripheralID)
        try values.encode(unlockCode, forKey: .unlockCode)
        try values.encode(nextUnlockCount, forKey: .nextUnlockCount)
        try values.encode(setupComplete, forKey: .setupComplete)
        try values.encode(sensorKind, forKey: .sensorKind)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(calibration, forKey: .calibration)
        // Encode nil explicitly. Its presence distinguishes an unavailable/malformed
        // anchor from a legacy record that predates the field and may be migrated once.
        try values.encode(clockAnchor, forKey: .clockAnchor)
    }
}
