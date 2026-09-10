import Foundation

enum LibreSensorKind: String, Codable, Sendable {
    case libre2_9D
    case libre2_C5
    case libre2_7F
}

struct LibreSensorSession: Codable, Sendable, Equatable {
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
        clockAnchor: LibreSensorClockAnchor? = nil
    ) {
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
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
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
