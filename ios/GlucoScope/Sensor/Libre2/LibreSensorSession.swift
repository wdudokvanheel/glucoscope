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

    init(
        uid: Data,
        patchInfo: Data,
        advertisedName: String,
        peripheralID: UUID? = nil,
        unlockCode: UInt32,
        nextUnlockCount: UInt32 = 1,
        setupComplete: Bool,
        sensorKind: LibreSensorKind,
        createdAt: Date = Date()
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
    }
}
