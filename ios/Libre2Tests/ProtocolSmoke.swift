import Foundation

@main
struct ProtocolSmoke {
    static func main() async throws {
        let uid = Data([0x5E, 0x90, 0x25, 0x00, 0x00, 0xA0, 0x07, 0xE0])
        let patch = Data([0x9D, 0x08, 0x30, 0x01, 0xEE, 0x0F])
        let session = LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "",
                                         unlockCode: 42, setupComplete: true, sensorKind: .libre2_9D)

        try expect(Libre2Protocol.classify(patchInfo: patch) == .libre2_9D, "9D classification")
        try expect(Libre2Protocol.classify(patchInfo: Data([0xC5, 0, 0, 0, 0, 0])) == .libre2_C5, "C5 classification")
        try expect(Libre2Protocol.classify(patchInfo: Data([0x7F, 0x0E, 0x30, 1, 0, 0])) == .libre2_7F, "non-Plus 7F classification")
        try expectThrows("7F Plus rejection") { _ = try Libre2Protocol.classify(patchInfo: Data([0x7F, 0x0E, 0x31, 1, 0, 0])) }
        try expect(Libre2Protocol.expectedLegacyName(uid: uid) == "ABBOTT3M00009DHCR", "legacy advertised name")

        // Fixed synthetic inputs, checked against the supplied reference implementation.
        try expect(try Libre2Protocol.enableStreamingPayload(uid: uid, patchInfo: patch, unlockCode: 42).hex == "1E2A000000739B6DA0", "enable payload oracle")
        try expect(try Libre2Protocol.unlockPayload(session: session, counter: 1).hex == "2B00000012082F5F78778950", "unlock payload oracle")
        try expectThrows("short encrypted frame rejection") { _ = try Libre2Protocol.decryptFrame(Data(repeating: 0, count: 45), uid: uid) }
        try expectThrows("corrupt encrypted frame rejection") { _ = try Libre2Protocol.decryptFrame(Data(repeating: 0, count: 46), uid: uid) }
        let bleCiphertext = Data(hex: "3412F24367954446C94D862B548AC88C3FDD54EC0EDA69C22496A58273E488F4D95A5662E40749820BB604385785")
        let blePlaintext = Data(hex: "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20212223242526272829A878")
        try expect(try Libre2Protocol.decryptFrame(bleCiphertext, uid: uid) == blePlaintext, "BLE plaintext oracle including CRC byte order")
        var corruptedFrame = bleCiphertext
        corruptedFrame[8] ^= 1
        try expectThrows("single-bit BLE corruption") { _ = try Libre2Protocol.decryptFrame(corruptedFrame, uid: uid) }
        var wrongUID = uid
        wrongUID[0] ^= 1
        try expectThrows("wrong sensor identity") { _ = try Libre2Protocol.decryptFrame(bleCiphertext, uid: wrongUID) }
        try expectThrows("truncated UID") { _ = try Libre2Protocol.decryptFrame(bleCiphertext, uid: Data(uid.prefix(7))) }
        try expectThrows("incomplete patch information") { _ = try Libre2Protocol.classify(patchInfo: Data([0x7F])) }
        try expectThrows("unsupported US sensor") { _ = try Libre2Protocol.classify(patchInfo: Data([0xE5,0,0,0,0,0])) }
        let framCiphertext = Data(hex: "D85F327FE15CBE1622FB4E314066378C41CA6878DD1B61DA9C7D7B3666231CE867C14B9D221E0E1FFAAA452D653E224D4CAF261F3FAD2F03D32B35910415D2716AA4053A00A8400652AE8D8C4F528CBCB11FAB4552AF5A6AAE1B380B6917A7D8971488202DAA35AF8AFF0610EA8A997DC202BC8A553812B5DD062F84EE006FC7E4099FAF6A3D7D303D63AABBB1CFF7AA5E528CF22CB2A1FCC1D69FBC978ADCCE7859AF17D3B7CE39E532A1A79497E26B07E4415B531C8347986052D568A47E3521EF627E6C19EC4219E5EAC823E320F8FA54CC013E1EF62EE5505F4F05A60B9CDC5FEF64411B99EBC1B46154863B35398949DBCE3989BEF1964D48C082B1C383AF42F8EB068CD174885684A5B8B658EEEB67A2EC25CB0EB874E3B1A29EF3738ACD6C8109DACE617D50078FB99DEE4D2FE602EC8BC77D40617986FF05FCC5BD13668FCFAEF8782F64F8034718B782E3DE1BB261D1AA7F3508")
        let framPlaintext = Data(hex: "DDB70E1503232A31383F464D545B626970777E858C939AA1EA9CB6BDC4CBD2D9E0E7EEF5FC030A11181F262D343B424950575E656C737A81888F969DA4ABB2B9C0C7CED5DCE3EAF1F8FF060D141B222930373E454C535A61686F767D848B9299A0A7AEB5BCC3CAD1D8DFE6EDF4FB020910171E252C333A41484F565D646B727980878E959CA3AAB1B8BFC6CDD4DBE2E9F0F7FE050C131A21282F363D444B525960676E757C838A91989FA6ADB4BBC2C9D0D7DEE5ECF3FA01080F161D242B323940474E555C636A71787F868D949BA2A9B0B7BEC5CCD3DAE1E8EFF6FD040B121920272E353C434A51585F666D747B828990979EA5ACB3BAC1C8CFD6DDE4EBF2F900070E151C232A31383F464D545B626970777E858C939AA1A8AFB6BDC4CBD2D9E0E7EEF5FC030A11181F262D343B424950575E656C737A81888F969DA4ABB2B96641CED5DCE3EAF1F8FF060D141B222930373E454C535A61")
        let decryptedFRAM = try Libre2Protocol.decryptFRAM(framCiphertext, uid: uid, patchInfo: patch)
        try expect(decryptedFRAM == framPlaintext, "FRAM header/body/footer oracle")
        try expect(Libre2Protocol.validateFRAM(decryptedFRAM), "all three FRAM CRCs")
        for offset in [4, 30, 330] {
            var corruptedFRAM = decryptedFRAM
            corruptedFRAM[offset] ^= 1
            try expect(!Libre2Protocol.validateFRAM(corruptedFRAM), "corrupt FRAM section at \(offset)")
        }
        try expect(!Libre2Protocol.validateFRAM(Data(decryptedFRAM.prefix(343))), "truncated FRAM")
        var exhaustedSession = session
        exhaustedSession.nextUnlockCount = 65536
        try expect(try Libre2Protocol.unlockPayload(session: exhaustedSession, counter: 65535).count == 12, "last reserved counter remains usable")

        // Every possible two-fragment split and a byte-at-a-time stream.
        for split in 1..<46 {
            var assembler = LibreFrameAssembler()
            try expect(assembler.append(Data(bleCiphertext.prefix(split))) == .incomplete(split), "fragment split \(split)")
            try expect(assembler.append(Data(bleCiphertext.dropFirst(split))) == .frame(bleCiphertext), "assembled split \(split)")
            try expect(assembler.buffer.isEmpty, "frame consumed")
        }
        var assembler = LibreFrameAssembler()
        for (index, byte) in bleCiphertext.enumerated() {
            let expected: LibreFrameAssembler.AppendResult = index == 45 ? .frame(bleCiphertext) : .incomplete(index + 1)
            try expect(assembler.append(Data([byte])) == expected, "single-byte fragment \(index)")
        }
        _ = assembler.append(Data(bleCiphertext.prefix(20)))
        try expect(assembler.append(Data(repeating: 0, count: 27)) == .overflow(47), "overflow rejection")
        try expect(assembler.append(bleCiphertext) == .frame(bleCiphertext), "recovery after overflow")
        _ = assembler.append(Data(bleCiphertext.prefix(20)))
        assembler.reset() // The timeout and disconnect paths both discard this partial frame.
        try expect(assembler.append(bleCiphertext) == .frame(bleCiphertext), "reset discards prior fragments")
        try expect(assembler.append(Data()) == .incomplete(0), "empty notification")

        enum RetryFixtureError: Error { case transient, permanent }
        var attempts = 0
        let recovered = try await LibreReadRetry.run(maxAttempts: 3, delayNanoseconds: 0, shouldRetry: { _ in true }) { _ in
            attempts += 1
            if attempts < 3 { throw RetryFixtureError.transient }
            return 42
        }
        try expect(recovered == 42 && attempts == 3, "transient read recovery")

        attempts = 0
        do {
            _ = try await LibreReadRetry.run(maxAttempts: 2, delayNanoseconds: 0, shouldRetry: { _ in true }) { _ -> Int in
                attempts += 1
                throw RetryFixtureError.transient
            }
            throw TestError.failed("retry cap")
        } catch RetryFixtureError.transient {
            try expect(attempts == 2, "retry cap")
        }

        var cancelled = false
        attempts = 0
        do {
            _ = try await LibreReadRetry.run(maxAttempts: 3, delayNanoseconds: 0, isCancelled: { cancelled }, shouldRetry: { _ in true }, onRetry: { _, _ in cancelled = true }) { _ -> Int in
                attempts += 1
                throw RetryFixtureError.transient
            }
            throw TestError.failed("retry cancellation")
        } catch is CancellationError {
            try expect(attempts == 1, "cancellation prevents another operation")
        }

        attempts = 0
        do {
            _ = try await LibreReadRetry.run(maxAttempts: 3, delayNanoseconds: 0, shouldRetry: { _ in false }) { _ -> Int in
                attempts += 1
                throw RetryFixtureError.permanent
            }
            throw TestError.failed("non-retryable mutation")
        } catch RetryFixtureError.permanent {
            try expect(attempts == 1, "non-retryable operation remains single shot")
        }
        print("Libre2 protocol, integrity and fragment regression tests passed")
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw TestError.failed(name) }
    }
    static func expectThrows(_ name: String, _ operation: () throws -> Void) throws {
        do { try operation(); throw TestError.failed(name) } catch TestError.failed { throw TestError.failed(name) } catch {}
    }
    enum TestError: Error { case failed(String) }
}

private extension Data { var hex: String { map { String(format: "%02X", $0) }.joined() } }

private extension Data {
    init(hex: String) {
        let characters = Array(hex)
        self.init(stride(from: 0, to: characters.count, by: 2).map {
            UInt8(String(characters[$0...($0 + 1)]), radix: 16)!
        })
    }
}
