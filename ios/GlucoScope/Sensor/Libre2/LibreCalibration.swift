import Foundation

enum LibreCalibrationError: LocalizedError, Equatable {
    case invalidFRAMLength(Int)
    case invalidFRAMCRC
    case invalidUIDLength(Int)
    case unsupportedLifecycle(UInt8)
    case unsupportedFormatVersion(Int)
    case malformedSource(Int)
    case invalidCaptureMetadata
    case wrongSensor
    case replacedPairing

    var errorDescription: String? {
        switch self {
        case .invalidFRAMLength(let length): return "Libre sensor memory must be exactly 344 bytes (received \(length))."
        case .invalidFRAMCRC: return "Libre sensor memory failed its integrity check."
        case .invalidUIDLength(let length): return "Libre sensor UID must be 8 bytes (received \(length))."
        case .unsupportedLifecycle(let state): return String(format: "Libre sensor lifecycle state %02X cannot supply calibration.", state)
        case .unsupportedFormatVersion(let version): return "Unsupported Libre calibration format version \(version)."
        case .malformedSource(let length): return "Libre calibration source is malformed (received \(length) bytes)."
        case .invalidCaptureMetadata: return "Libre calibration capture time or sensor minute is invalid."
        case .wrongSensor: return "The calibration belongs to a different Libre sensor."
        case .replacedPairing: return "The Libre pairing changed while calibration was being captured."
        }
    }
}

/// A sensor-owned snapshot of the FRAM fields needed by the Libre calibration formula.
/// This type only extracts protocol fields; it does not assert that they yield valid glucose values.
struct LibreCalibration: Codable, Sendable, Equatable {
    static let currentFormatVersion = 1

    let ownerUID: Data
    let ownerPatchInfo: Data
    let formatVersion: Int
    let capturedAt: Date
    let sensorMinute: Int
    let lifecycle: UInt8
    private let calibrationSource: Data

    var i1: Int { Self.readBits(calibrationSource, byteOffset: 0, bitOffset: 0, count: 3) }
    var i2: Int { Self.readBits(calibrationSource, byteOffset: 0, bitOffset: 3, count: 10) }
    var i3: Int {
        let magnitude = Self.readBits(calibrationSource, byteOffset: 2, bitOffset: 0, count: 8)
        return Self.readBits(calibrationSource, byteOffset: 2, bitOffset: 0x21, count: 1) == 0 ? magnitude : -magnitude
    }
    var i4: Int { Self.readBits(calibrationSource, byteOffset: 2, bitOffset: 8, count: 0xE) }
    var i5: Int { Self.readBits(calibrationSource, byteOffset: 2, bitOffset: 0x28, count: 0xC) << 2 }
    var i6: Int { Self.readBits(calibrationSource, byteOffset: 2, bitOffset: 0x34, count: 0xC) << 2 }

    static func capture(fram: Data, uid: Data, patchInfo: Data, capturedAt: Date = Date()) throws -> LibreCalibration {
        guard fram.count == 344 else { throw LibreCalibrationError.invalidFRAMLength(fram.count) }
        guard uid.count == 8 else { throw LibreCalibrationError.invalidUIDLength(uid.count) }
        guard capturedAt.timeIntervalSince1970.isFinite,
              capturedAt >= .distantPast, capturedAt <= .distantFuture else {
            throw LibreCalibrationError.invalidCaptureMetadata
        }
        _ = try Libre2Protocol.classify(patchInfo: patchInfo)
        guard Libre2Protocol.validateFRAM(fram) else { throw LibreCalibrationError.invalidFRAMCRC }
        let lifecycle = fram[4]
        guard lifecycle == 0x02 || lifecycle == 0x03 else { throw LibreCalibrationError.unsupportedLifecycle(lifecycle) }

        var source = Data(fram[2..<4])
        source.append(fram[336..<344])
        return LibreCalibration(ownerUID: uid, ownerPatchInfo: patchInfo,
                                formatVersion: currentFormatVersion, capturedAt: capturedAt,
                                sensorMinute: Int(fram[316]) | Int(fram[317]) << 8,
                                lifecycle: lifecycle, calibrationSource: source)
    }

    func validateOwnership(uid: Data, patchInfo: Data) throws {
        guard formatVersion == Self.currentFormatVersion else { throw LibreCalibrationError.unsupportedFormatVersion(formatVersion) }
        guard Libre2Protocol.hasSameStableIdentity(uid: ownerUID, patchInfo: ownerPatchInfo,
                                                   otherUID: uid, otherPatchInfo: patchInfo) else {
            throw LibreCalibrationError.wrongSensor
        }
    }

    private init(ownerUID: Data, ownerPatchInfo: Data, formatVersion: Int, capturedAt: Date,
                 sensorMinute: Int, lifecycle: UInt8, calibrationSource: Data) {
        self.ownerUID = ownerUID
        self.ownerPatchInfo = ownerPatchInfo
        self.formatVersion = formatVersion
        self.capturedAt = capturedAt
        self.sensorMinute = sensorMinute
        self.lifecycle = lifecycle
        self.calibrationSource = calibrationSource
    }

    private enum CodingKeys: String, CodingKey {
        case ownerUID, ownerPatchInfo, formatVersion, capturedAt, sensorMinute, lifecycle, calibrationSource
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let uid = try values.decode(Data.self, forKey: .ownerUID)
        let patchInfo = try values.decode(Data.self, forKey: .ownerPatchInfo)
        let version = try values.decode(Int.self, forKey: .formatVersion)
        let state = try values.decode(UInt8.self, forKey: .lifecycle)
        let source = try values.decode(Data.self, forKey: .calibrationSource)
        guard uid.count == 8 else { throw LibreCalibrationError.invalidUIDLength(uid.count) }
        _ = try Libre2Protocol.classify(patchInfo: patchInfo)
        guard version == Self.currentFormatVersion else { throw LibreCalibrationError.unsupportedFormatVersion(version) }
        guard state == 0x02 || state == 0x03 else { throw LibreCalibrationError.unsupportedLifecycle(state) }
        guard source.count == 10 else { throw LibreCalibrationError.malformedSource(source.count) }
        let minute = try values.decode(Int.self, forKey: .sensorMinute)
        guard (0...Int(UInt16.max)).contains(minute) else { throw LibreCalibrationError.malformedSource(source.count) }
        let capturedAt = try values.decode(Date.self, forKey: .capturedAt)
        guard capturedAt.timeIntervalSince1970.isFinite,
              capturedAt >= .distantPast, capturedAt <= .distantFuture else {
            throw LibreCalibrationError.invalidCaptureMetadata
        }
        self.init(ownerUID: uid, ownerPatchInfo: patchInfo, formatVersion: version,
                  capturedAt: capturedAt,
                  sensorMinute: minute,
                  lifecycle: state, calibrationSource: source)
    }

    private static func readBits(_ bytes: Data, byteOffset: Int, bitOffset: Int, count: Int) -> Int {
        var result = 0
        for index in 0..<count {
            let position = bitOffset + index
            if bytes[byteOffset + position / 8] & (1 << (position % 8)) != 0 {
                result |= 1 << index
            }
        }
        return result
    }
}
