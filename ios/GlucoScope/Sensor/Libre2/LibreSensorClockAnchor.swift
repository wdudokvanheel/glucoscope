import Foundation

enum LibreSensorClockAnchorError: Error, Equatable {
    case unsupportedFormatVersion(Int)
    case wrongSensor
    case invalidReference
    case timestampOutOfRange
}

/// A session-stable mapping from sensor minutes to wall-clock time.
/// NFC supplies only minute resolution. The allowance records that nominal resolution;
/// it is not a bound on phone-clock error, capture latency, or sensor drift.
struct LibreSensorClockAnchor: Codable, Sendable, Equatable {
    static let currentFormatVersion = 1
    static let canonicalPersistenceProvenance = "libre2-nfc-minute-clock-v1-u60"
    // Supported Libre 2 revisions have a 14.5-day diagnostic lifetime. Keep
    // session recovery and decoder acceptance on the same reference domain.
    static let maximumSensorMinute = 20_880

    let formatVersion: Int
    let ownerUID: Data
    let ownerPatchInfo: Data
    let referenceDate: Date
    let referenceSensorMinute: Int
    let uncertaintySeconds: Double

    static func capture(from calibration: LibreCalibration) throws -> LibreSensorClockAnchor {
        guard Self.isUsable(date: calibration.capturedAt),
              (0...maximumSensorMinute).contains(calibration.sensorMinute) else {
            throw LibreSensorClockAnchorError.invalidReference
        }
        return LibreSensorClockAnchor(formatVersion: currentFormatVersion,
                                      ownerUID: calibration.ownerUID,
                                      ownerPatchInfo: calibration.ownerPatchInfo,
                                      referenceDate: calibration.capturedAt,
                                      referenceSensorMinute: calibration.sensorMinute,
                                      uncertaintySeconds: 60)
    }

    /// Restores the non-secret canonical clock persisted with reading metadata.
    /// Sensor ownership is supplied by the current, already matched Keychain wear;
    /// UID and patch bytes are intentionally never stored in the SQLite clock row.
    static func restoreCanonical(
        referenceDate: Date,
        referenceSensorMinute: Int64,
        provenance: String,
        ownerUID: Data,
        ownerPatchInfo: Data
    ) throws -> LibreSensorClockAnchor {
        guard provenance == canonicalPersistenceProvenance,
              let minute = Int(exactly: referenceSensorMinute),
              (0...maximumSensorMinute).contains(minute),
              ownerUID.count == 8,
              (try? Libre2Protocol.classify(patchInfo: ownerPatchInfo)) != nil,
              Self.isUsable(date: referenceDate) else {
            throw LibreSensorClockAnchorError.invalidReference
        }
        let restored = LibreSensorClockAnchor(
            formatVersion: currentFormatVersion,
            ownerUID: ownerUID,
            ownerPatchInfo: ownerPatchInfo,
            referenceDate: referenceDate,
            referenceSensorMinute: minute,
            uncertaintySeconds: 60
        )
        try restored.validateOwnership(uid: ownerUID, patchInfo: ownerPatchInfo)
        return restored
    }

    func validateOwnership(uid: Data, patchInfo: Data) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw LibreSensorClockAnchorError.unsupportedFormatVersion(formatVersion)
        }
        guard Self.isUsable(date: referenceDate),
              (0...Self.maximumSensorMinute).contains(referenceSensorMinute),
              uncertaintySeconds.isFinite, uncertaintySeconds >= 0 else {
            throw LibreSensorClockAnchorError.invalidReference
        }
        guard Libre2Protocol.hasSameStableIdentity(uid: ownerUID, patchInfo: ownerPatchInfo,
                                                   otherUID: uid, otherPatchInfo: patchInfo) else {
            throw LibreSensorClockAnchorError.wrongSensor
        }
    }

    func timestamp(for sensorMinute: Int) throws -> Date {
        guard Self.isUsable(date: referenceDate) else {
            throw LibreSensorClockAnchorError.invalidReference
        }
        let interval = (Double(sensorMinute) - Double(referenceSensorMinute)) * 60
        guard interval.isFinite else { throw LibreSensorClockAnchorError.timestampOutOfRange }
        let result = referenceDate.addingTimeInterval(interval)
        guard Self.isUsable(date: result) else { throw LibreSensorClockAnchorError.timestampOutOfRange }
        return result
    }

    private static func isUsable(date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, ownerUID, ownerPatchInfo, referenceDate, referenceSensorMinute, uncertaintySeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(formatVersion: try values.decode(Int.self, forKey: .formatVersion),
                  ownerUID: try values.decode(Data.self, forKey: .ownerUID),
                  ownerPatchInfo: try values.decode(Data.self, forKey: .ownerPatchInfo),
                  referenceDate: try values.decode(Date.self, forKey: .referenceDate),
                  referenceSensorMinute: try values.decode(Int.self, forKey: .referenceSensorMinute),
                  uncertaintySeconds: try values.decode(Double.self, forKey: .uncertaintySeconds))
        guard formatVersion == Self.currentFormatVersion else {
            throw LibreSensorClockAnchorError.unsupportedFormatVersion(formatVersion)
        }
        guard ownerUID.count == 8,
              (try? Libre2Protocol.classify(patchInfo: Data(Array(ownerPatchInfo)))) != nil,
              Self.isUsable(date: referenceDate),
              (0...Self.maximumSensorMinute).contains(referenceSensorMinute),
              uncertaintySeconds.isFinite, uncertaintySeconds >= 0 else {
            throw LibreSensorClockAnchorError.invalidReference
        }
    }

    private init(formatVersion: Int, ownerUID: Data, ownerPatchInfo: Data,
                 referenceDate: Date, referenceSensorMinute: Int, uncertaintySeconds: Double) {
        self.formatVersion = formatVersion
        self.ownerUID = ownerUID
        self.ownerPatchInfo = ownerPatchInfo
        self.referenceDate = referenceDate
        self.referenceSensorMinute = referenceSensorMinute
        self.uncertaintySeconds = uncertaintySeconds
    }
}
