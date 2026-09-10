import Foundation

enum Libre2ProtocolError: LocalizedError, Equatable {
    case invalidUIDLength(Int)
    case incompletePatchInfo(Int)
    case unsupportedSensor(UInt8)
    case unsupportedLibre2Plus
    case unlockCounterExhausted
    case invalidFrameLength(Int)
    case invalidFrameCRC

    var errorDescription: String? {
        switch self {
        case .invalidUIDLength(let length): return "Libre sensor UID must be 8 bytes (received \(length))."
        case .incompletePatchInfo(let length): return "Libre patch information is incomplete (received \(length) bytes)."
        case .unsupportedSensor(let revision): return String(format: "Unsupported Libre sensor revision %02X.", revision)
        case .unsupportedLibre2Plus: return "Libre 2 Plus sensors are not supported."
        case .unlockCounterExhausted: return "The Libre Bluetooth unlock counter is exhausted. Scan the sensor again."
        case .invalidFrameLength(let length): return "Libre Bluetooth frame must be 46 bytes (received \(length))."
        case .invalidFrameCRC: return "Libre Bluetooth frame failed its integrity check."
        }
    }
}

enum Libre2Protocol {
    // Derived from the protocol behavior in the supplied xDripSwift snapshot
    // (LibreNFC, Libre2BLEUtilities and PreLibre2). This implementation is app-owned
    // and intentionally expressed as small value transformations rather than copied bodies.
    private static let polynomialKeys: [UInt16] = [0xA0C5, 0x6860, 0, 0x14C6]

    static func classify(patchInfo: Data) throws -> LibreSensorKind {
        guard patchInfo.count >= 6 else { throw Libre2ProtocolError.incompletePatchInfo(patchInfo.count) }
        switch patchInfo[0] {
        case 0x9D: return .libre2_9D
        case 0xC5: return .libre2_C5
        case 0x7F:
            guard patchInfo[2] & 0x0F == 0 else { throw Libre2ProtocolError.unsupportedLibre2Plus }
            return .libre2_7F
        default: throw Libre2ProtocolError.unsupportedSensor(patchInfo[0])
        }
    }

    static func expectedLegacyName(uid: Data) throws -> String {
        guard uid.count == 8 else { throw Libre2ProtocolError.invalidUIDLength(uid.count) }
        let alphabet = Array("0123456789ACDEFGHJKLMNPQRTUVWXYZ")
        let bytes = Array(uid.reversed().suffix(6))
        let packed = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } << 2
        let serial = "3" + String((0..<10).map { index in
            alphabet[Int((packed >> UInt64(45 - index * 5)) & 0x1F)]
        })
        return "ABBOTT" + serial
    }

    static func enableStreamingPayload(uid: Data, patchInfo: Data, unlockCode: UInt32) throws -> Data {
        _ = try classify(patchInfo: patchInfo)
        try validateUID(uid)
        let codeBytes = littleEndianBytes(unlockCode)
        let infoWord = UInt16(patchInfo[4]) | UInt16(patchInfo[5]) << 8
        let authenticator = usefulFunction(uid: uid, command: 0x1E, argument: infoWord ^ UInt16(codeBytes[0]) ^ UInt16(codeBytes[1]) << 8)
        return Data([0x1E] + codeBytes + authenticator)
    }

    static func unlockPayload(session: LibreSensorSession, counter: UInt16) throws -> Data {
        try validateUID(session.uid)
        guard session.patchInfo.count >= 6 else { throw Libre2ProtocolError.incompletePatchInfo(session.patchInfo.count) }
        let rollingValue = session.unlockCode &+ UInt32(counter)
        let rollingBytes = littleEndianBytes(rollingValue)
        let activation = usefulFunction(uid: session.uid, command: 0x1B, argument: 0x1B6A)
        let infoWord = UInt16(session.patchInfo[4]) | UInt16(session.patchInfo[5]) << 8
        let enable = usefulFunction(uid: session.uid, command: 0x1E, argument: UInt16(truncatingIfNeeded: session.unlockCode) ^ infoWord)

        let stageOne = crypt(words(uid: session.uid,
                                   additions: [word(enable[0], enable[1]) ^ word(rollingBytes[2], rollingBytes[3]),
                                               word(activation[0], activation[1]),
                                               word(enable[2], enable[3]) ^ word(rollingBytes[0], rollingBytes[1]),
                                               word(activation[2], activation[3])]))
        let stageBytes = stageOne.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
        let checks: [UInt16] = [
            crc16(Data([0xC1, 0xC4, 0xC3, 0xC0, 0xD4, 0xE1, 0xE7, 0xBA, stageBytes[0], stageBytes[1]])).byteSwapped,
            crc16(Data(stageBytes[2...7])).byteSwapped,
            crc16(Data(activation + Array(enable[0...1]))).byteSwapped,
            crc16(Data(Array(enable[2...3]) + rollingBytes)).byteSwapped
        ]
        let result = crypt(words(uid: session.uid, additions: checks))
            .flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
        return Data(rollingBytes + result)
    }

    static func decryptFrame(_ data: Data, uid: Data) throws -> Data {
        try validateUID(uid)
        guard data.count == 46 else { throw Libre2ProtocolError.invalidFrameLength(data.count) }
        let activation = usefulFunction(uid: uid, command: 0x1B, argument: 0x1B6A)
        let x = (word(activation[0], activation[1]) ^ word(activation[2], activation[3])) | 0x63
        let y = word(data[0], data[1]) ^ 0x63
        var block = crypt(words(uid: uid, x: x, y: y))
        var stream = [UInt8]()
        while stream.count < 44 {
            stream += block.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
            block = crypt(block)
        }
        let plain = zip(data.dropFirst(2), stream).map(^)
        let transmittedCRC = UInt16(plain[42]) << 8 | UInt16(plain[43])
        guard crc16(Data(plain.prefix(42))) == transmittedCRC else {
            throw Libre2ProtocolError.invalidFrameCRC
        }
        return Data(plain)
    }

    static func decryptFRAM(_ data: Data, uid: Data, patchInfo: Data) throws -> Data {
        try validateUID(uid)
        guard patchInfo.count >= 6 else { throw Libre2ProtocolError.incompletePatchInfo(patchInfo.count) }
        guard data.count >= 344 else { throw Libre2ProtocolError.invalidFrameLength(data.count) }
        var output = [UInt8](); output.reserveCapacity(344)
        for blockIndex in 0..<43 {
            let i = UInt16(blockIndex)
            let patchWord = UInt16(patchInfo[4]) | UInt16(patchInfo[5]) << 8
            let s1 = word(uid[4], uid[5]) &+ (patchWord ^ 0x0044) &+ i
            let s2 = word(uid[2], uid[3])
            let s3 = word(uid[0], uid[1]) &+ (i << 1)
            let key = crypt([s1, s2, s3, 0x30DC])
            let keyBytes = key.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
            output += zip(data[(blockIndex * 8)..<(blockIndex * 8 + 8)], keyBytes).map(^)
        }
        return Data(output.prefix(344))
    }

    static func validateFRAM(_ data: Data) -> Bool {
        guard data.count >= 344 else { return false }
        return [0..<24, 24..<320, 320..<344].allSatisfy { range in
            let section = data[range]
            let enclosed = UInt16(section[section.startIndex]) << 8 | UInt16(section[section.startIndex + 1])
            return crc16(Data(section.dropFirst(2))) == enclosed
        }
    }

    private static func validateUID(_ uid: Data) throws {
        guard uid.count == 8 else { throw Libre2ProtocolError.invalidUIDLength(uid.count) }
    }
    private static func word(_ low: UInt8, _ high: UInt8) -> UInt16 { UInt16(low) | UInt16(high) << 8 }
    private static func littleEndianBytes(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32($0 * 8)) } }
    private static func usefulFunction(uid: Data, command: UInt16, argument: UInt16) -> [UInt8] {
        let block = crypt(words(uid: uid, x: command, y: argument))
        let a = block[0] ^ 0x4163, b = block[1] ^ 0x4344
        return [UInt8(truncatingIfNeeded: a), UInt8(truncatingIfNeeded: a >> 8), UInt8(truncatingIfNeeded: b), UInt8(truncatingIfNeeded: b >> 8)]
    }
    private static func words(uid: Data, x: UInt16, y: UInt16) -> [UInt16] {
        [word(uid[4], uid[5]) &+ x &+ y, word(uid[2], uid[3]), word(uid[0], uid[1]) &+ x &+ x, 0x30DC]
    }
    private static func words(uid: Data, additions: [UInt16]) -> [UInt16] {
        [word(uid[4], uid[5]) &+ additions[0], word(uid[2], uid[3]) &+ additions[1], word(uid[0], uid[1]) &+ additions[2], additions[3] &+ polynomialKeys[3]]
    }
    private static func crypt(_ input: [UInt16]) -> [UInt16] {
        func shift(_ v: UInt16) -> UInt16 {
            (v >> 2) ^ (v & 1 == 0 ? 0 : polynomialKeys[1]) ^ (v & 2 == 0 ? 0 : polynomialKeys[0])
        }
        let r0 = shift(input[0]) ^ input[3], r1: UInt16
        r1 = shift(r0) ^ input[2]
        let r2 = shift(r1) ^ input[1], r3 = shift(r2) ^ input[0]
        let r4 = shift(r3), r5 = shift(r4 ^ r0), r6 = shift(r5 ^ r1), r7 = shift(r6 ^ r2)
        return [r3 ^ r7, r2 ^ r6, r1 ^ r5, r0 ^ r4]
    }
    private static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1 != 0) ? (crc >> 1) ^ 0x8408 : crc >> 1 }
        }
        var reversed: UInt16 = 0
        for _ in 0..<16 { reversed = (reversed << 1) | (crc & 1); crc >>= 1 }
        return reversed.byteSwapped
    }
}
