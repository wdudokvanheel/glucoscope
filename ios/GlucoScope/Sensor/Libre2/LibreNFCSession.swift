import Foundation

/// Reconnection is constrained to the saved physical sensor before any streaming
/// command or pairing write. Replacement setup deliberately has no such constraint.
enum LibreNFCScanPurpose {
    case setup
    case reconnect(LibreSensorSession)
    case calibration(LibreSensorSession)
    case history(LibreSensorSession)

    var pairedSensor: LibreSensorSession? {
        switch self {
        case .setup: return nil
        case .reconnect(let sensor), .calibration(let sensor), .history(let sensor): return sensor
        }
    }

    func acceptsDetectedIdentity(uid: Data, patchInfo: Data? = nil) -> Bool {
        guard let sensor = pairedSensor else { return true }
        guard sensor.uid == uid else { return false }
        guard let patchInfo else { return true }
        return Libre2Protocol.hasSameStableIdentity(uid: sensor.uid, patchInfo: sensor.patchInfo,
                                                    otherUID: uid, otherPatchInfo: patchInfo)
    }
}

#if os(iOS)
import CoreNFC

enum LibreNFCError: LocalizedError {
    case unavailable
    case noISO15693Tag
    case multipleTags
    case invalidMemory(Int)
    case invalidMemoryCRC
    case sensorNotActivated(UInt8)
    case enableStreamingRejected(Int)
    case differentTag
    case differentSensor
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: return "NFC tag reading is unavailable on this iPhone."
        case .noISO15693Tag: return "The detected tag is not a supported Libre sensor."
        case .multipleTags: return "More than one NFC tag was detected. Hold only the sensor near the iPhone."
        case .invalidMemory(let count): return "The sensor returned \(count) memory bytes; 344 are required."
        case .invalidMemoryCRC: return "The sensor memory failed its integrity check. Try scanning again."
        case .sensorNotActivated(let state): return String(format: "The sensor is not in an active state (state %02X).", state)
        case .enableStreamingRejected(let count): return "The sensor rejected Bluetooth streaming setup (response length \(count))."
        case .differentTag: return "A different NFC tag was detected during recovery. Scan the original sensor again."
        case .differentSensor: return "This scan does not match the paired sensor. Scan the currently paired sensor."
        case .cancelled: return "The NFC scan was cancelled."
        }
    }
}

final class LibreNFCSession: NSObject {
    enum CaptureResult {
        case setup(LibreSensorSession)
        case calibration(LibreCalibration, expectedSession: LibreSensorSession)
        case history(fram: Data, expectedSession: LibreSensorSession, receivedAt: Date)
    }

    private typealias Purpose = LibreNFCScanPurpose

    var onLog: ((String) -> Void)?
    var onCompletion: ((Result<CaptureResult, Error>) -> Void)?
    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    private let store: LibreSessionStore
    private var readerSession: NFCTagReaderSession?
    private var completed = false
    private var processingTag = false
    private var generation = UUID()
    private var expectedUID: Data?
    private var pollingRestarts = 0
    private var streamingEnableAttempted = false
    private var purpose: Purpose = .setup

    private let readAttempts = 3
    private let maximumPollingRestarts = 2
    private let retryDelayNanoseconds: UInt64 = 180_000_000

    init(store: LibreSessionStore = LibreSessionStore()) {
        self.store = store
        super.init()
    }

    func start() {
        start(purpose: .setup)
    }

    func startReconnection(for sensor: LibreSensorSession) {
        start(purpose: .reconnect(sensor))
    }

    /// Reads calibration only. It neither writes sensor commands nor saves pairing state.
    func startCalibration(for sensor: LibreSensorSession) {
        start(purpose: .calibration(sensor))
    }

    /// Reads the paired sensor's memory without changing pairing or streaming.
    func startHistory(for sensor: LibreSensorSession) {
        start(purpose: .history(sensor))
    }

    private func start(purpose: Purpose) {
        precondition(Thread.isMainThread)
        readerSession?.invalidate()
        readerSession = nil
        completed = false
        processingTag = false
        self.purpose = purpose
        expectedUID = purpose.pairedSensor?.uid
        pollingRestarts = 0
        streamingEnableAttempted = false
        generation = UUID()
        guard isAvailable else { finish(.failure(LibreNFCError.unavailable)); return }
        guard let session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self, queue: .main) else {
            finish(.failure(LibreNFCError.unavailable))
            return
        }
        readerSession = session
        session.alertMessage = "Hold the top of your iPhone near the Libre 2 sensor."
        switch purpose {
        case .setup: log("NFC setup scan started")
        case .reconnect: log("NFC reconnection scan started; only the paired sensor is accepted")
        case .calibration: log("Read-only NFC calibration scan started; streaming setup will be preserved")
        case .history: log("Read-only NFC history scan started; Bluetooth collection continues")
        }
        session.begin()
    }

    func cancel() {
        precondition(Thread.isMainThread)
        guard !completed else { return }
        generation = UUID()
        readerSession?.invalidate()
        finish(.failure(LibreNFCError.cancelled))
    }

    @MainActor private func handle(tag: NFCISO15693Tag, session: NFCTagReaderSession, generation expectedGeneration: UUID) async {
        var step = "tag detection"
        do {
            let uid = Data(tag.identifier.reversed())
            if !purpose.acceptsDetectedIdentity(uid: uid) {
                throw LibreNFCError.differentSensor
            }
            if let expectedUID, expectedUID != uid {
                log("Ignoring a different ISO15693 tag during recovery: expected UID \(expectedUID.hexString), detected \(uid.hexString)")
                guard pollingRestarts < maximumPollingRestarts else { throw LibreNFCError.differentTag }
                pollingRestarts += 1
                processingTag = false
                session.alertMessage = "Keep the iPhone near the same Libre 2 sensor."
                session.restartPolling()
                return
            }
            self.expectedUID = uid
            log("Detected ISO15693 tag: UID \(uid.hexString), manufacturer \(tag.icManufacturerCode), IC \(tag.icSerialNumber.hexString)")

            step = "connect"
            try await retryRead(step: step, tag: tag, session: session, generation: expectedGeneration, reconnectBeforeRetry: false) {
                try await session.connect(to: .iso15693(tag))
            }
            log("Connected to ISO15693 sensor tag (UID \(uid.hexString))")
            session.alertMessage = "Keep the top of your iPhone against the sensor while reading."

            // Abbott custom command A1 with no parameters returns patch information.
            step = "patch query A1"
            let patchInfo = try await retryRead(step: step, tag: tag, session: session, generation: expectedGeneration) {
                try await self.customCommand(tag, code: 0xA1, parameters: Data())
            }
            log("Patch query A1 returned \(patchInfo.count) bytes: \(patchInfo.hexString)")
            let kind = try Libre2Protocol.classify(patchInfo: patchInfo)
            if !purpose.acceptsDetectedIdentity(uid: uid, patchInfo: patchInfo) {
                throw LibreNFCError.differentSensor
            }
            log("Supported sensor: \(kind.rawValue), UID \(uid.hexString), patch \(patchInfo.hexString)")

            var encryptedFRAM = Data()
            for firstBlock in stride(from: 0, to: 43, by: 3) {
                let count = min(3, 43 - firstBlock)
                let range = NSRange(location: firstBlock, length: count)
                step = "FRAM blocks \(firstBlock)-\(firstBlock + count - 1)"
                let blocks = try await retryRead(step: step, tag: tag, session: session, generation: expectedGeneration) {
                    try await self.readBlocks(tag, range: range)
                }
                for block in blocks { encryptedFRAM.append(block) }
                log("Read FRAM blocks \(firstBlock)-\(firstBlock + count - 1) (\(encryptedFRAM.count)/344 bytes)")
            }
            guard encryptedFRAM.count == 344 else { throw LibreNFCError.invalidMemory(encryptedFRAM.count) }
            let fram = try Libre2Protocol.decryptFRAM(encryptedFRAM, uid: uid, patchInfo: patchInfo)
            guard Libre2Protocol.validateFRAM(fram) else { throw LibreNFCError.invalidMemoryCRC }
            guard fram.count >= 5 else { throw LibreNFCError.invalidMemory(fram.count) }
            let state = fram[4]
            guard state == 0x02 || state == 0x03 else {
                throw LibreNFCError.sensorNotActivated(state)
            }
            log(String(format: "Sensor lifecycle state %02X; FRAM integrity validated", state))
            try requireActive(session, generation: expectedGeneration)
            if case .history(let expectedSession) = purpose {
                log("History memory read from the paired sensor; no streaming-enable command sent")
                session.alertMessage = "Sensor history read complete."
                session.invalidate()
                finish(.success(.history(fram: fram, expectedSession: expectedSession, receivedAt: Date())))
                return
            }
            step = "calibration extraction"
            let calibration = try LibreCalibration.capture(fram: fram, uid: uid, patchInfo: patchInfo)
            try requireActive(session, generation: expectedGeneration)

            // End the read-only path before any pairing persistence or A1/1E command.
            // The BLE owner will merge this capture with its latest reserved counter.
            if case .calibration(let expectedSession) = purpose {
                log("Calibration captured from the paired sensor; no streaming-enable command sent")
                session.alertMessage = "Sensor calibration read complete."
                session.invalidate()
                finish(.success(.calibration(calibration, expectedSession: expectedSession)))
                return
            }

            // The supplied implementation and fixtures use 42 as the enable-time value.
            // Keep that known interop value until hardware tests establish wider behavior.
            let enableCode: UInt32 = 42
            let temporaryName = kind == .libre2_7F ? "PENDING-MAC" : try Libre2Protocol.expectedLegacyName(uid: uid)
            var sensor = LibreSensorSession(uid: uid, patchInfo: patchInfo, advertisedName: temporaryName,
                                            unlockCode: enableCode, nextUnlockCount: 1,
                                            setupComplete: false, sensorKind: kind, calibration: calibration)

            // Read/upgrade the durable identity before replacing pairing credentials.
            // Same-wear setup retains its original clock; uncertain continuity fails
            // before saving pending credentials or sending streaming enablement.
            step = "wear session reconciliation"
            try requireActive(session, generation: expectedGeneration)
            var previous = try store.load()
            if let saved = previous,
               Libre2Protocol.hasSameStableIdentity(uid: uid, patchInfo: patchInfo,
                                                   otherUID: saved.uid, otherPatchInfo: saved.patchInfo) {
                previous = try saved.requiringPersistenceIdentity { upgraded in
                    try requireActive(session, generation: expectedGeneration)
                    try store.save(upgraded)
                }
            }
            sensor = try sensor.preservingWearIdentity(from: previous)

            // Persist credentials before the state-changing command. A crash here leaves an
            // explicit incomplete setup rather than losing the key needed for BLE login.
            try requireActive(session, generation: expectedGeneration)
            try store.save(sensor)
            log("Saved pending sensor session")
            let parameters = try Libre2Protocol.enableStreamingPayload(uid: uid, patchInfo: patchInfo, unlockCode: enableCode)
            try requireActive(session, generation: expectedGeneration)
            step = "streaming enable A1/1E"
            log("Sending streaming enable command once")
            streamingEnableAttempted = true
            let response = try await customCommand(tag, code: 0xA1, parameters: parameters)
            try requireActive(session, generation: expectedGeneration)
            guard response.count == 6 else { throw LibreNFCError.enableStreamingRejected(response.count) }

            if kind == .libre2_7F { sensor.advertisedName = response.reversed().map { String(format: "%02X", $0) }.joined() }
            sensor.setupComplete = true
            try store.save(sensor)
            log("Bluetooth streaming enabled; expected peripheral \(sensor.advertisedName)")
            session.alertMessage = "Libre 2 Bluetooth setup complete."
            session.invalidate()
            finish(.success(.setup(sensor)))
        } catch {
            guard readerSession === session, generation == expectedGeneration, !completed else { return }
            if !streamingEnableAttempted, isLostConnectionState(error), pollingRestarts < maximumPollingRestarts {
                pollingRestarts += 1
                processingTag = false
                log("NFC \(step) lost the field; restarting polling \(pollingRestarts)/\(maximumPollingRestarts) in this scan for UID \(expectedUID?.hexString ?? "unknown")")
                session.alertMessage = "Connection lost. Keep the iPhone still against the same sensor."
                session.restartPolling()
                return
            }
            log("NFC scan failed at \(step): \(describe(error))")
            session.invalidate(errorMessage: error.localizedDescription)
            finish(.failure(error))
        }
    }

    @MainActor private func retryRead<Value>(
        step: String,
        tag: NFCISO15693Tag,
        session: NFCTagReaderSession,
        generation expectedGeneration: UUID,
        reconnectBeforeRetry: Bool = true,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        try await LibreReadRetry.run(
            maxAttempts: readAttempts,
            delayNanoseconds: retryDelayNanoseconds,
            isCancelled: { [weak self, weak session] in
                guard let self, let session else { return true }
                return self.readerSession !== session || self.generation != expectedGeneration || self.completed
            },
            shouldRetry: { [weak self] error in self?.isTransientReadError(error) == true },
            onRetry: { [weak self] nextAttempt, error in
                guard let self else { return }
                self.log("NFC \(step) failed (\(self.describe(error))); retry \(nextAttempt)/\(self.readAttempts) after delay")
            },
            operation: { [weak self] attempt in
                guard let self else { throw CancellationError() }
                try self.requireActive(session, generation: expectedGeneration)
                self.log("NFC \(step) attempt \(attempt)/\(self.readAttempts)")
                if reconnectBeforeRetry, attempt > 1 {
                    try await session.connect(to: .iso15693(tag))
                    try self.requireActive(session, generation: expectedGeneration)
                }
                let value = try await operation()
                try self.requireActive(session, generation: expectedGeneration)
                return value
            }
        )
    }

    private func isTransientReadError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NFCReaderError.errorDomain else { return false }
        let tagRejected = nsError.userInfo[NFCISO15693TagResponseErrorKey] != nil
        return nsError.code == NFCReaderError.Code.readerTransceiveErrorTagConnectionLost.rawValue ||
            nsError.code == NFCReaderError.Code.readerTransceiveErrorRetryExceeded.rawValue ||
            nsError.code == NFCReaderError.Code.readerTransceiveErrorTagNotConnected.rawValue ||
            (nsError.code == NFCReaderError.Code.readerTransceiveErrorTagResponseError.rawValue && !tagRejected)
    }

    private func isLostConnectionState(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NFCReaderError.errorDomain &&
            (nsError.code == NFCReaderError.Code.readerTransceiveErrorTagConnectionLost.rawValue ||
             nsError.code == NFCReaderError.Code.readerTransceiveErrorTagNotConnected.rawValue)
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var details = ["domain=\(nsError.domain)", "code=\(nsError.code)"]
        if let response = nsError.userInfo[NFCISO15693TagResponseErrorKey] {
            details.append("iso15693Response=\(response)")
        }
        if let length = nsError.userInfo[NFCTagResponseUnexpectedLengthErrorKey] {
            details.append("unexpectedLength=\(length)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlyingDomain=\(underlying.domain)")
            details.append("underlyingCode=\(underlying.code)")
        }
        return "\(error.localizedDescription) [\(details.joined(separator: ", "))]"
    }

    @MainActor private func requireActive(_ session: NFCTagReaderSession, generation expected: UUID) throws {
        guard readerSession === session, generation == expected, !completed else { throw CancellationError() }
    }

    private func log(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onLog?(message) }
    }

    private func finish(_ result: Result<CaptureResult, Error>) {
        guard !completed else { return }
        completed = true
        DispatchQueue.main.async { [weak self] in self?.onCompletion?(result) }
    }

    @MainActor private func customCommand(_ tag: NFCISO15693Tag, code: Int, parameters: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            tag.customCommand(requestFlags: .highDataRate, customCommandCode: code,
                              customRequestParameters: parameters) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }

    @MainActor private func readBlocks(_ tag: NFCISO15693Tag, range: NSRange) async throws -> [Data] {
        try await withCheckedThrowingContinuation { continuation in
            tag.readMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: range) { blocks, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: blocks) }
            }
        }
    }
}

extension LibreNFCSession: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) { log("NFC reader active") }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard readerSession === session else { return }
        readerSession = nil
        guard !completed else { return }
        if let readerError = error as? NFCReaderError,
           readerError.code == .readerSessionInvalidationErrorUserCanceled {
            finish(.failure(LibreNFCError.cancelled))
        } else {
            finish(.failure(error))
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard readerSession === session, !processingTag, !completed else { return }
        guard tags.count == 1 else {
            session.alertMessage = LibreNFCError.multipleTags.localizedDescription
            session.restartPolling()
            return
        }
        guard case .iso15693(let tag) = tags[0] else {
            session.invalidate(errorMessage: LibreNFCError.noISO15693Tag.localizedDescription)
            finish(.failure(LibreNFCError.noISO15693Tag))
            return
        }
        processingTag = true
        let expectedGeneration = generation
        Task { @MainActor [weak self] in await self?.handle(tag: tag, session: session, generation: expectedGeneration) }
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined() }
}
#endif
