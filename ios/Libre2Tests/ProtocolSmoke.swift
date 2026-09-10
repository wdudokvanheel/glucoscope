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
        var observedPatch = patch
        observedPatch[4] ^= 0x5A
        observedPatch[5] ^= 0xA5
        try expect(Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patch,
                                                        otherUID: uid, otherPatchInfo: observedPatch),
                   "mutable patch word does not change sensor identity")
        try expect(!Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patch,
                                                         otherUID: Data(uid.reversed()), otherPatchInfo: observedPatch),
                   "stable identity rejects different UID")
        var changedStablePatch = observedPatch
        changedStablePatch[1] ^= 1
        try expect(!Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patch,
                                                         otherUID: uid, otherPatchInfo: changedStablePatch),
                   "stable identity rejects changed patch byte")
        try expect(!Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patch,
                                                         otherUID: uid, otherPatchInfo: Data(observedPatch.dropLast())),
                   "stable identity rejects patch length change")
        try expect(!Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patch + Data([0x11]),
                                                         otherUID: uid, otherPatchInfo: observedPatch + Data([0x22])),
                   "stable identity rejects changed trailing patch bytes")
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

        var calibrationFRAM = decryptedFRAM
        writeBits(&calibrationFRAM, byteOffset: 2, bitOffset: 0, count: 3, value: 5)
        writeBits(&calibrationFRAM, byteOffset: 2, bitOffset: 3, count: 10, value: 777)
        writeBits(&calibrationFRAM, byteOffset: 336, bitOffset: 0, count: 8, value: 201)
        writeBits(&calibrationFRAM, byteOffset: 336, bitOffset: 8, count: 14, value: 12_345)
        writeBits(&calibrationFRAM, byteOffset: 336, bitOffset: 33, count: 1, value: 1)
        writeBits(&calibrationFRAM, byteOffset: 336, bitOffset: 40, count: 12, value: 2_345)
        writeBits(&calibrationFRAM, byteOffset: 336, bitOffset: 52, count: 12, value: 3_000)
        calibrationFRAM[4] = 0x03
        calibrationFRAM[316] = 0x34
        calibrationFRAM[317] = 0x12
        refreshFRAMCRCs(&calibrationFRAM)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let calibration = try LibreCalibration.capture(fram: calibrationFRAM, uid: uid, patchInfo: patch, capturedAt: capturedAt)
        try expectThrows("nonfinite calibration capture time") {
            _ = try LibreCalibration.capture(fram: calibrationFRAM, uid: uid, patchInfo: patch,
                                             capturedAt: Date(timeIntervalSince1970: .infinity))
        }
        try expect(calibration.i1 == 5 && calibration.i2 == 777, "header calibration bit extraction")
        try expect(calibration.i3 == -201, "signed i3 extraction")
        try expect(calibration.i4 == 12_345 && calibration.i5 == 9_380 && calibration.i6 == 12_000, "footer calibration bit extraction")
        try expect(calibration.sensorMinute == 0x1234 && calibration.lifecycle == 0x03, "capture metadata")
        try calibration.validateOwnership(uid: uid, patchInfo: patch)
        try calibration.validateOwnership(uid: uid, patchInfo: observedPatch)
        try expectThrows("wrong calibration owner") { try calibration.validateOwnership(uid: wrongUID, patchInfo: patch) }
        try expectThrows("exact FRAM length") { _ = try LibreCalibration.capture(fram: calibrationFRAM + Data([0]), uid: uid, patchInfo: patch) }
        var badCalibrationFRAM = calibrationFRAM
        badCalibrationFRAM[100] ^= 1
        try expectThrows("calibration CRC") { _ = try LibreCalibration.capture(fram: badCalibrationFRAM, uid: uid, patchInfo: patch) }
        for rejectedState: UInt8 in [0x01, 0x04, 0x05, 0xFF] {
            var inactiveFRAM = calibrationFRAM
            inactiveFRAM[4] = rejectedState
            refreshFRAMCRCs(&inactiveFRAM)
            try expectThrows("lifecycle \(rejectedState)") { _ = try LibreCalibration.capture(fram: inactiveFRAM, uid: uid, patchInfo: patch) }
        }
        var startingFRAM = calibrationFRAM
        startingFRAM[4] = 0x02
        refreshFRAMCRCs(&startingFRAM)
        try expect(try LibreCalibration.capture(fram: startingFRAM, uid: uid, patchInfo: patch).lifecycle == 0x02, "starting lifecycle permitted")

        let calibrationRoundTrip = try JSONDecoder().decode(LibreCalibration.self, from: JSONEncoder().encode(calibration))
        try expect(calibrationRoundTrip == calibration, "calibration persistence roundtrip")
        var malformedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calibration)) as! [String: Any]
        malformedObject["calibrationSource"] = Data([1, 2]).base64EncodedString()
        try expectThrows("malformed persisted source") {
            _ = try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: malformedObject))
        }
        malformedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calibration)) as! [String: Any]
        malformedObject["formatVersion"] = 999
        try expectThrows("unsupported persisted version") {
            _ = try JSONDecoder().decode(LibreCalibration.self, from: JSONSerialization.data(withJSONObject: malformedObject))
        }

        let peripheral = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let creation = Date(timeIntervalSince1970: 1_600_000_000)
        var oldSession = LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "ABBOTT",
                                            peripheralID: peripheral, unlockCode: 42, nextUnlockCount: 93,
                                            setupComplete: true, sensorKind: .libre2_9D, createdAt: creation)
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldSession)) as! [String: Any]
        oldJSON.removeValue(forKey: "calibration")
        oldJSON.removeValue(forKey: "clockAnchor")
        let migrated = try JSONDecoder().decode(LibreSensorSession.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        try expect(migrated.needsCalibration, "old session needs calibration")
        try expect(migrated.peripheralID == peripheral && migrated.unlockCode == 42 && migrated.nextUnlockCount == 93,
                   "old JSON migration preserves credentials")

        let expectedSnapshot = oldSession
        oldSession.peripheralID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        oldSession.nextUnlockCount = 104
        let merged = try oldSession.mergingCalibration(calibration, expectedSession: expectedSnapshot)
        try expect(merged.calibration == calibration && !merged.needsCalibration, "session calibration merge")
        try expect(merged.peripheralID == oldSession.peripheralID && merged.nextUnlockCount == 104,
                   "stale NFC merge preserves advanced BLE state")
        let originalAnchor = try require(merged.clockAnchor, "first calibration seeds clock anchor")
        let overlappingTimestamp = try originalAnchor.timestamp(for: calibration.sensorMinute - 7)
        let laterCalibration = try LibreCalibration.capture(fram: calibrationFRAM, uid: uid, patchInfo: observedPatch,
                                                            capturedAt: capturedAt.addingTimeInterval(22))
        let recaptured = try merged.mergingCalibration(laterCalibration, expectedSession: merged)
        try expect(recaptured.clockAnchor == originalAnchor, "recapture preserves original clock anchor")
        try expect(try recaptured.clockAnchor?.timestamp(for: calibration.sensorMinute - 7) == overlappingTimestamp,
                   "overlapping sensor minute keeps stable timestamp")
        let encryptedWithObservedPatch = try Libre2Protocol.decryptFRAM(calibrationFRAM, uid: uid, patchInfo: observedPatch)
        let recoveredWithObservedPatch = try Libre2Protocol.decryptFRAM(encryptedWithObservedPatch, uid: uid, patchInfo: observedPatch)
        let observedCalibration = try LibreCalibration.capture(fram: recoveredWithObservedPatch, uid: uid,
                                                               patchInfo: observedPatch, capturedAt: capturedAt)
        let mutablePatchMerged = try oldSession.mergingCalibration(observedCalibration, expectedSession: expectedSnapshot)
        try expect(mutablePatchMerged.patchInfo == patch && mutablePatchMerged.nextUnlockCount == 104 &&
                   mutablePatchMerged.peripheralID == oldSession.peripheralID,
                   "capture-time patch decrypt preserves paired authentication material")
        try expect(try JSONDecoder().decode(LibreSensorSession.self, from: JSONEncoder().encode(merged)) == merged,
                   "session persistence roundtrip")
        var legacyAnchoredObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as! [String: Any]
        legacyAnchoredObject.removeValue(forKey: "clockAnchor")
        let migratedAnchorSession = try JSONDecoder().decode(LibreSensorSession.self,
                                                             from: JSONSerialization.data(withJSONObject: legacyAnchoredObject))
        try expect(migratedAnchorSession.clockAnchor == originalAnchor, "legacy calibration seeds clock anchor")
        var nullAnchorObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as! [String: Any]
        nullAnchorObject["clockAnchor"] = NSNull()
        let nullAnchorSession = try JSONDecoder().decode(LibreSensorSession.self,
                                                        from: JSONSerialization.data(withJSONObject: nullAnchorObject))
        try expect(nullAnchorSession.clockAnchor == nil && nullAnchorSession.needsClockAnchor &&
                   nullAnchorSession.calibration == calibration,
                   "explicit null clock remains unavailable instead of migrating from calibration")
        var malformedAnchorObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as! [String: Any]
        var malformedAnchor = malformedAnchorObject["clockAnchor"] as! [String: Any]
        malformedAnchor["formatVersion"] = 999
        malformedAnchorObject["clockAnchor"] = malformedAnchor
        let malformedAnchorSession = try JSONDecoder().decode(LibreSensorSession.self,
                                                               from: JSONSerialization.data(withJSONObject: malformedAnchorObject))
        try expect(malformedAnchorSession.clockAnchor == nil && malformedAnchorSession.calibration == calibration &&
                   malformedAnchorSession.nextUnlockCount == merged.nextUnlockCount,
                   "malformed present clock preserves pairing without silent reanchor")
        let unavailableAnchorRoundTrip = try JSONDecoder().decode(LibreSensorSession.self,
                                                                  from: JSONEncoder().encode(malformedAnchorSession))
        try expect(unavailableAnchorRoundTrip.clockAnchor == nil,
                   "explicit unavailable clock survives another persistence roundtrip")
        var foreignAnchorObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as! [String: Any]
        var foreignAnchor = foreignAnchorObject["clockAnchor"] as! [String: Any]
        foreignAnchor["ownerUID"] = Data(uid.reversed()).base64EncodedString()
        foreignAnchorObject["clockAnchor"] = foreignAnchor
        let foreignAnchorSession = try JSONDecoder().decode(LibreSensorSession.self,
                                                            from: JSONSerialization.data(withJSONObject: foreignAnchorObject))
        try expect(foreignAnchorSession.clockAnchor != nil && foreignAnchorSession.needsClockAnchor,
                   "foreign well-formed clock is retained but unavailable")
        let repairedAnchorSession = try foreignAnchorSession.mergingCalibration(laterCalibration,
                                                                                expectedSession: foreignAnchorSession)
        try expect(repairedAnchorSession.clockAnchor != nil && !repairedAnchorSession.needsClockAnchor &&
                   repairedAnchorSession.clockAnchor != foreignAnchorSession.clockAnchor,
                   "deliberate calibration recapture repairs an unavailable clock")
        try expect(repairedAnchorSession.peripheralID == foreignAnchorSession.peripheralID &&
                   repairedAnchorSession.nextUnlockCount == foreignAnchorSession.nextUnlockCount &&
                   repairedAnchorSession.patchInfo == foreignAnchorSession.patchInfo,
                   "clock repair preserves live pairing state")
        var outOfLifetimeAnchorObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as! [String: Any]
        var outOfLifetimeAnchor = outOfLifetimeAnchorObject["clockAnchor"] as! [String: Any]
        outOfLifetimeAnchor["referenceSensorMinute"] = LibreSensorClockAnchor.maximumSensorMinute + 1
        outOfLifetimeAnchorObject["clockAnchor"] = outOfLifetimeAnchor
        let outOfLifetimeAnchorSession = try JSONDecoder().decode(
            LibreSensorSession.self,
            from: JSONSerialization.data(withJSONObject: outOfLifetimeAnchorObject)
        )
        try expect(outOfLifetimeAnchorSession.clockAnchor == nil && outOfLifetimeAnchorSession.needsClockAnchor &&
                   outOfLifetimeAnchorSession.calibration == calibration &&
                   outOfLifetimeAnchorSession.peripheralID == merged.peripheralID &&
                   outOfLifetimeAnchorSession.nextUnlockCount == merged.nextUnlockCount,
                   "out-of-lifetime clock is unavailable without discarding pairing")
        let repairedLifetimeAnchorSession = try outOfLifetimeAnchorSession.mergingCalibration(
            laterCalibration,
            expectedSession: outOfLifetimeAnchorSession
        )
        try expect(!repairedLifetimeAnchorSession.needsClockAnchor &&
                   repairedLifetimeAnchorSession.peripheralID == outOfLifetimeAnchorSession.peripheralID &&
                   repairedLifetimeAnchorSession.nextUnlockCount == outOfLifetimeAnchorSession.nextUnlockCount,
                   "deliberate recapture repairs out-of-lifetime clock without resetting BLE state")
        var lifetimeBoundaryFRAM = calibrationFRAM
        lifetimeBoundaryFRAM[316] = UInt8(truncatingIfNeeded: LibreSensorClockAnchor.maximumSensorMinute)
        lifetimeBoundaryFRAM[317] = UInt8(LibreSensorClockAnchor.maximumSensorMinute >> 8)
        refreshFRAMCRCs(&lifetimeBoundaryFRAM)
        let lifetimeBoundaryCalibration = try LibreCalibration.capture(
            fram: lifetimeBoundaryFRAM, uid: uid, patchInfo: patch, capturedAt: capturedAt
        )
        try expect(try LibreSensorClockAnchor.capture(from: lifetimeBoundaryCalibration).referenceSensorMinute ==
                   LibreSensorClockAnchor.maximumSensorMinute,
                   "clock accepts supported sensor lifetime endpoint")
        lifetimeBoundaryFRAM[316] = UInt8(truncatingIfNeeded: LibreSensorClockAnchor.maximumSensorMinute + 1)
        lifetimeBoundaryFRAM[317] = UInt8((LibreSensorClockAnchor.maximumSensorMinute + 1) >> 8)
        refreshFRAMCRCs(&lifetimeBoundaryFRAM)
        let outOfLifetimeCalibration = try LibreCalibration.capture(
            fram: lifetimeBoundaryFRAM, uid: uid, patchInfo: patch, capturedAt: capturedAt
        )
        try expectThrows("clock rejects reference after supported sensor lifetime") {
            _ = try LibreSensorClockAnchor.capture(from: outOfLifetimeCalibration)
        }
        try expectThrows("extreme sensor minute cannot overflow clock arithmetic") {
            _ = try originalAnchor.timestamp(for: .max)
        }
        var replaced = oldSession
        replaced.createdAt = replaced.createdAt.addingTimeInterval(1)
        try expectThrows("replaced pairing rejection") { _ = try replaced.mergingCalibration(calibration, expectedSession: expectedSnapshot) }
        let replacementSession = LibreSensorSession(uid: uid, patchInfo: patch, advertisedName: "ABBOTT",
                                                    peripheralID: peripheral, unlockCode: 42,
                                                    setupComplete: true, sensorKind: .libre2_9D,
                                                    createdAt: creation.addingTimeInterval(1), calibration: laterCalibration)
        try expect(replacementSession.clockAnchor != originalAnchor, "replacement pairing receives a separate clock anchor")
        let otherPatch = Data([0xC5, 0, 0, 0, 0, 0])
        let otherCalibration = try LibreCalibration.capture(fram: calibrationFRAM, uid: uid, patchInfo: otherPatch)
        try expectThrows("wrong sensor calibration rejection") { _ = try oldSession.mergingCalibration(otherCalibration, expectedSession: expectedSnapshot) }

        var damagedSessionObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as! [String: Any]
        var damagedCalibration = damagedSessionObject["calibration"] as! [String: Any]
        damagedCalibration["formatVersion"] = 999
        damagedSessionObject["calibration"] = damagedCalibration
        let recoveredSession = try JSONDecoder().decode(LibreSensorSession.self, from: JSONSerialization.data(withJSONObject: damagedSessionObject))
        try expect(recoveredSession.calibration == nil && recoveredSession.nextUnlockCount == 104 && recoveredSession.peripheralID == oldSession.peripheralID,
                   "invalid optional calibration does not discard pairing")
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

    static func require<Value>(_ value: Value?, _ name: String) throws -> Value {
        guard let value else { throw TestError.failed(name) }
        return value
    }

    static func writeBits(_ bytes: inout Data, byteOffset: Int, bitOffset: Int, count: Int, value: Int) {
        for index in 0..<count {
            let position = byteOffset * 8 + bitOffset + index
            let mask = UInt8(1 << (position % 8))
            if value & (1 << index) == 0 { bytes[position / 8] &= ~mask }
            else { bytes[position / 8] |= mask }
        }
    }

    static func refreshFRAMCRCs(_ bytes: inout Data) {
        for range in [0..<24, 24..<320, 320..<344] {
            let crc = crc16(Data(bytes[range].dropFirst(2)))
            bytes[range.lowerBound] = UInt8(truncatingIfNeeded: crc >> 8)
            bytes[range.lowerBound + 1] = UInt8(truncatingIfNeeded: crc)
        }
    }

    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0x8408 }
        }
        var reversed: UInt16 = 0
        for _ in 0..<16 { reversed = (reversed << 1) | (crc & 1); crc >>= 1 }
        return reversed.byteSwapped
    }
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
