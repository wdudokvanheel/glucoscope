import Foundation
import SwiftUI
import UIKit

@MainActor
final class LibreDiagnosticsCoordinator: NSObject, ObservableObject {
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    static let shared = LibreDiagnosticsCoordinator()

    @Published private(set) var status = "Starting"
    @Published private(set) var collectionStatus = LibreCollectionCoordinator.Status()
    @Published private(set) var storageProbeStatus = LibreStorageProbeStatus()
    @Published private(set) var bluetoothState = "Unknown"
    @Published private(set) var sensorSummary = ""
    @Published private(set) var calibrationSummary = "No paired sensor"
    @Published private(set) var clockSummary = "No paired sensor"
    @Published private(set) var calibrationStatus = "Idle"
    @Published private(set) var canCaptureCalibration = false
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var frameCount = 0
    @Published private(set) var verifiedFrameCount = 0
    @Published private(set) var lastFrameHex = ""
    @Published private(set) var lastFrameAt: Date?
    @Published private(set) var lastVerifiedFrameAt: Date?
    @Published private(set) var lastPayloadHex = ""
    @Published private(set) var diagnosticFrame: Libre2DiagnosticFrame?
    @Published private(set) var diagnosticGlucoseStatus = "Waiting for a paired sensor"
    @Published private(set) var isRunning = false
    @Published private(set) var isScanningNFC = false
    @Published private(set) var isNFCAvailable = false
    let diagnosticsUploader = LibreDiagnosticsUploader()

    private static let maximumLogEntries = 500
    private let store = LibreSessionStore()
    private let frameGate = LibreFrameGenerationGate()
    private let readingStore = ReadingStore(configuration: ReadingStoreConfiguration(storage: .sqlite(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibreReadings", isDirectory: true)
            .appendingPathComponent("readings.sqlite")
    )))
    private lazy var persistenceBridge = LibrePersistenceBridge(readingStore: readingStore, sessionStore: store)
    private lazy var collection = LibreCollectionCoordinator(
        gate: frameGate,
        openStore: { [readingStore] in
            switch await readingStore.currentHealth() {
            case .notLoaded: try await readingStore.load()
            case .unhealthy: _ = try await readingStore.retryAfterFailure()
            case .healthy: break
            case .closed: throw ReadingStoreError.unavailable(.closed)
            }
        },
        prepareSession: { [weak self] frame in
            guard let self else { throw LibreFrameOwnershipError.staleFrame }
            try await self.prepareMetadata(for: frame)
        },
        onStatus: { [weak self] value in
            guard let self else { return }
            let changed = self.collectionStatus.summary != value.summary
            self.collectionStatus = value
            if changed { self.appendLog("Storage: \(value.summary)") }
        }
    )
    private lazy var storageProbe = LibreStorageProbe { [weak self] value in
        guard let self else { return }
        let previous = self.storageProbeStatus
        self.storageProbeStatus = value
        if !value.isRunning,
           (previous.phase != value.phase || previous.detail != value.detail) {
            self.appendLog("Storage probe: \(value.phase) — \(value.detail)")
        }
    }
    private var nfcSession: LibreNFCSession?
    private var operationGeneration: UInt64 = 0
    private var lockedProbeBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var currentSensorSession: LibreSensorSession?
    private lazy var bluetooth = LibreBluetoothCentral(store: store, frameGate: frameGate) { [weak self] event in
        self?.receive(event)
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        let header = [
            "GlucoScope Libre 2 diagnostics",
            "Diagnostics revision: v8 locked-device storage-only probe",
            "App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"))",
            "Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)",
            "Exported: \(formatter.string(from: Date()))",
            "Status: \(status)",
            "Bluetooth: \(bluetoothState)",
            "Storage: \(collectionStatus.summary)",
            "Storage operation: \(collectionStatus.operation) at \(formatter.string(from: collectionStatus.updatedAt))",
            "Canonical ingestion: disabled; metadata only; dropped candidates: \(collectionStatus.droppedCandidateCount)",
            "Stale or out-of-order frames rejected: \(collectionStatus.staleFrameCount)",
            "Last accepted process sequence: \(collectionStatus.lastSequence.map(String.init) ?? "none")",
            "Storage probe: synthetic metadata only; isolated from production readings and delivery",
            storageProbeStatus.reportLines.joined(separator: "\n"),
            "Sensor: \(sensorSummary)",
            "Calibration: \(calibrationSummary)",
            "Sensor clock: \(clockSummary)",
            "Calibration action: \(calibrationStatus)",
            "Raw frames: \(frameCount)",
            "Verified frames: \(verifiedFrameCount)",
            "Last verified: \(lastVerifiedFrameAt.map { formatter.string(from: $0) } ?? "none")",
            "Latest raw frame: \(lastFrameHex)",
            "Latest decrypted payload: \(lastPayloadHex)",
            "Experimental glucose: \(diagnosticGlucoseStatus)",
            experimentalGlucoseExport(formatter: formatter),
            ""
        ]
        return (header + logs.map { "\(formatter.string(from: $0.timestamp))  \($0.message)" }).joined(separator: "\n")
    }

    func sendDiagnostics(to endpoint: String) {
        diagnosticsUploader.send(snapshot: exportText, endpoint: endpoint)
    }

    func startStorageProbe() {
        precondition(Thread.isMainThread)
        storageProbe.start()
    }

    func verifyStorageProbeAfterRelaunch() {
        precondition(Thread.isMainThread)
        storageProbe.verifyPreviousRun()
    }

    func armLockedStorageProbe() {
        precondition(Thread.isMainThread)
        guard !isRunning, !isScanningNFC else {
            appendLog("Locked storage probe was not armed: stop sensor collection and finish NFC first")
            return
        }
        storageProbe.armLockedVerification(environment: lockedProbeEnvironment)
    }

    func cancelLockedStorageProbe() {
        precondition(Thread.isMainThread)
        storageProbe.cancelLockedVerification()
    }

    private override init() {
        super.init()
        collection.start()
        _ = bluetooth
        refreshStoredSession()
        isNFCAvailable = LibreNFCSession(store: store).isAvailable
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(protectedDataAvailabilityChanged),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(protectedDataAvailabilityChanged),
            name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil
        )
        appendLog("Diagnostics coordinator initialized")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Starts a deliberate setup scan. Existing BLE work is stopped first so credentials and
    /// callbacks from two sensors cannot be mixed.
    func startNFCSetup() {
        precondition(Thread.isMainThread)
        frameGate.invalidate()
        collection.transportInvalidated()
        operationGeneration &+= 1
        let generation = operationGeneration
        nfcSession?.cancel()
        nfcSession = nil
        isRunning = false
        isScanningNFC = true
        status = "Stopping Bluetooth before NFC setup"
        bluetooth.stop { [weak self] in
            guard let self, self.operationGeneration == generation else { return }
            self.beginNFCSetup(generation: generation)
        }
    }

    func startNFCCalibration() {
        precondition(Thread.isMainThread)
        guard !isScanningNFC else { return }
        do {
            guard let saved = try store.load(), saved.setupComplete else {
                calibrationStatus = "Complete sensor setup before reading calibration"
                return
            }
            operationGeneration &+= 1
            beginNFC(generation: operationGeneration, calibrationFor: saved)
        } catch {
            calibrationStatus = "Could not read saved sensor: \(error.localizedDescription)"
            appendLog("ERROR: \(calibrationStatus)")
        }
    }

    private func beginNFCSetup(generation: UInt64) {
        beginNFC(generation: generation, calibrationFor: nil)
    }

    private func beginNFC(generation: UInt64, calibrationFor saved: LibreSensorSession?) {
        let session = LibreNFCSession(store: store)
        let isCalibration = saved != nil
        isNFCAvailable = session.isAvailable
        guard isNFCAvailable else {
            isScanningNFC = false
            if isCalibration { calibrationStatus = "NFC is unavailable on this device" }
            else { status = "NFC is unavailable on this device" }
            appendLog("NFC is unavailable on this device")
            sendDiagnosticsAfterNFCIfEnabled()
            return
        }
        isScanningNFC = true
        if isCalibration { calibrationStatus = "Reading calibration; Bluetooth collection continues" }
        else { status = "Hold the top of the iPhone near the sensor" }
        session.onLog = { [weak self] message in
            guard let self, self.operationGeneration == generation else { return }
            self.appendLog("NFC: \(message)")
        }
        session.onCompletion = { [weak self] result in
            guard let self, self.operationGeneration == generation else { return }
            self.nfcSession = nil
            switch result {
            case .success(.setup(let sensor)):
                self.resetFrames()
                self.updateSensorSummary(sensor)
                self.appendLog("NFC setup complete for \(sensor.advertisedName)")
                self.status = "Sensor configured; connecting"
                self.isRunning = true
                self.bluetooth.use(sensor)
            case .success(.calibration(let calibration, let expectedSession)):
                self.calibrationStatus = "Saving calibration"
                self.bluetooth.applyCalibration(calibration, expectedSession: expectedSession) { [weak self] result in
                    guard let self else { return }
                    if case .success(let updated) = result {
                        self.acceptCalibrationSessionIfCurrent(updated)
                    }
                    // The durable merge can finish after stop/reconnect supersedes this
                    // action's UI. Only action-specific presentation remains gated here.
                    guard self.operationGeneration == generation else { return }
                    self.isScanningNFC = false
                    switch result {
                    case .success:
                        self.calibrationStatus = "Calibration saved"
                        self.appendLog("Read-only calibration saved; pairing and Bluetooth collection preserved")
                    case .failure(let error):
                        self.calibrationStatus = "Calibration was not saved"
                        self.appendLog("ERROR: Calibration merge failed: \(error.localizedDescription)")
                    }
                    self.sendDiagnosticsAfterNFCIfEnabled()
                }
                return
            case .failure(let error):
                if isCalibration { self.calibrationStatus = "Calibration scan failed: \(error.localizedDescription)" }
                else {
                    self.refreshStoredSession()
                    self.status = "NFC setup failed"
                }
                self.appendLog("ERROR: NFC scan failed: \(error.localizedDescription)")
            }
            self.isScanningNFC = false
            self.sendDiagnosticsAfterNFCIfEnabled()
        }
        nfcSession = session
        if let saved { session.startCalibration(for: saved) }
        else { session.start() }
    }

    func reconnect() {
        precondition(Thread.isMainThread)
        frameGate.invalidate()
        collection.transportInvalidated()
        operationGeneration &+= 1
        if isScanningNFC { calibrationStatus = "NFC action interrupted" }
        nfcSession?.cancel()
        nfcSession = nil
        isScanningNFC = false
        do {
            guard let saved = try store.load(), saved.setupComplete else {
                isRunning = false
                status = "Complete NFC setup before connecting"
                appendLog(status)
                return
            }
        } catch {
            isRunning = false
            status = "Could not read saved sensor: \(error.localizedDescription)"
            appendLog(status)
            return
        }
        isRunning = true
        status = "Reconnect requested"
        diagnosticFrame = nil
        diagnosticGlucoseStatus = waitingStatus(for: currentSensorSession)
        appendLog("Reconnect requested")
        collection.lifecycleOpportunity()
        bluetooth.reconnect()
    }

    func stop() {
        precondition(Thread.isMainThread)
        frameGate.invalidate()
        collection.transportInvalidated()
        operationGeneration &+= 1
        if isScanningNFC { calibrationStatus = "NFC action interrupted" }
        nfcSession?.cancel()
        nfcSession = nil
        isScanningNFC = false
        isRunning = false
        bluetooth.stop()
        status = "Stopped"
        diagnosticFrame = nil
        diagnosticGlucoseStatus = "Collection stopped"
        appendLog("Collection stopped deliberately")
    }

    func forgetSensor() {
        precondition(Thread.isMainThread)
        frameGate.invalidate()
        collection.transportInvalidated()
        operationGeneration &+= 1
        if isScanningNFC { calibrationStatus = "NFC action interrupted" }
        nfcSession?.cancel()
        nfcSession = nil
        isScanningNFC = false
        isRunning = false
        bluetooth.forget()
        currentSensorSession = nil
        resetFrames()
        sensorSummary = ""
        calibrationSummary = "No paired sensor"
        clockSummary = "No paired sensor"
        calibrationStatus = "Idle"
        canCaptureCalibration = false
        status = "Sensor forgotten"
        appendLog("Saved sensor pairing was removed")
    }

    func clearLog() {
        precondition(Thread.isMainThread)
        logs.removeAll()
        resetFrames()
    }

    private func resetFrames() {
        frameCount = 0
        verifiedFrameCount = 0
        lastFrameHex = ""
        lastFrameAt = nil
        lastVerifiedFrameAt = nil
        lastPayloadHex = ""
        diagnosticFrame = nil
        diagnosticGlucoseStatus = waitingStatus(for: currentSensorSession)
    }

    @objc private func appBecameActive() {
        storageProbe.lockedEnvironmentDidChange()
        collection.lifecycleOpportunity()
        bluetooth.appBecameActive()
        isNFCAvailable = LibreNFCSession(store: store).isAvailable
        appendLog("Application became active")
    }

    @objc private func appEnteredBackground() {
        storageProbe.lockedEnvironmentDidChange()
        bluetooth.appEnteredBackground()
        appendLog("Application entered background")
    }

    @objc private func protectedDataAvailabilityChanged() {
        // willBecomeUnavailable is delivered before protected files necessarily become
        // inaccessible. The probe reads UIApplication.isProtectedDataAvailable itself.
        storageProbe.lockedEnvironmentDidChange()
    }

    private var lockedProbeEnvironment: LibreStorageProbeLockEnvironment {
        LibreStorageProbeLockEnvironment(
            isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable },
            isBackground: { UIApplication.shared.applicationState == .background },
            beginBackgroundTask: { [weak self] expiration in
                guard let self, self.lockedProbeBackgroundTask == .invalid else { return false }
                let identifier = UIApplication.shared.beginBackgroundTask(
                    withName: "GlucoScope locked storage probe"
                ) {
                    // UIKit invokes this handler on the main thread. End the lease in the
                    // core expiration path, which synchronously calls endBackgroundTask.
                    MainActor.assumeIsolated {
                        expiration()
                    }
                }
                guard identifier != .invalid else { return false }
                self.lockedProbeBackgroundTask = identifier
                return true
            },
            endBackgroundTask: { [weak self] in
                self?.endLockedProbeBackgroundTask()
            }
        )
    }

    private func endLockedProbeBackgroundTask() {
        guard lockedProbeBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(lockedProbeBackgroundTask)
        lockedProbeBackgroundTask = .invalid
    }

    private func refreshStoredSession() {
        do {
            if let session = try store.load() {
                updateSensorSummary(session)
                let enabled = session.setupComplete && UserDefaults.standard.bool(forKey: "libre2.collectionEnabled")
                isRunning = enabled
                status = enabled ? "Restoring sensor connection" : "Sensor collection is stopped"
            } else {
                currentSensorSession = nil
                diagnosticFrame = nil
                diagnosticGlucoseStatus = "Waiting for a paired sensor"
                status = "Scan a Libre 2 sensor with NFC"
            }
        } catch {
            currentSensorSession = nil
            diagnosticFrame = nil
            diagnosticGlucoseStatus = "Waiting for a paired sensor"
            status = "Could not load saved sensor"
            appendLog("ERROR: \(error.localizedDescription)")
        }
    }

    private func receive(_ event: LibreBluetoothCentral.Event) {
        precondition(Thread.isMainThread)
        switch event {
        case .bluetoothState(let value):
            bluetoothState = value
            appendLog("Bluetooth state: \(value)")
        case .status(let value):
            guard isRunning || value == "Stopped" || value == "No sensor configured" else { return }
            status = value
            appendLog(value)
        case .log(let message):
            appendLog(message)
        case .sessionChanged(let session):
            guard isRunning else { return }
            updateSensorSummary(session)
        case .rawFrame(let data, let date):
            guard isRunning else { return }
            frameCount += 1
            lastFrameAt = date
            lastFrameHex = data.hexString
            diagnosticFrame = nil
            diagnosticGlucoseStatus = "Validating latest BLE frame"
            appendLog("Raw BLE frame #\(frameCount): \(data.hexString)")
        case .transportInvalidated:
            collection.transportInvalidated()
            diagnosticFrame = nil
            diagnosticGlucoseStatus = isRunning
                ? waitingStatus(for: currentSensorSession, newFrame: true) : "Collection stopped"
        case .verifiedPayload(let frame):
            guard isRunning, collection.receive(frame) else { return }
            let payload = frame.payload
            let date = frame.receivedAt
            verifiedFrameCount += 1
            lastVerifiedFrameAt = date
            lastPayloadHex = payload.hexString
            status = "Receiving CRC-valid frames"
            appendLog("Verified/decrypted payload: \(payload.hexString)")
            decodeDiagnosticPayload(frame)
        case .error(let message):
            guard isRunning else { return }
            status = message
            diagnosticFrame = nil
            diagnosticGlucoseStatus = "Latest frame unavailable: \(message)"
            appendLog("ERROR: \(message)")
        }
    }

    private func updateSensorSummary(_ session: LibreSensorSession) {
        let previous = currentSensorSession
        let pairingChanged = previous.map {
            $0.uid != session.uid || $0.patchInfo != session.patchInfo ||
                $0.createdAt != session.createdAt || $0.unlockCode != session.unlockCode ||
                $0.setupComplete != session.setupComplete
        } ?? false
        let calibrationChanged = previous?.calibration != session.calibration
        let clockChanged = previous?.clockAnchor != session.clockAnchor
        currentSensorSession = session
        if pairingChanged || calibrationChanged || clockChanged {
            diagnosticFrame = nil
            diagnosticGlucoseStatus = waitingStatus(for: session, newFrame: true)
        } else if previous == nil {
            diagnosticGlucoseStatus = waitingStatus(for: session)
        }
        canCaptureCalibration = session.setupComplete
        if !session.needsCalibration, let calibration = session.calibration {
            let captureDate = calibration.capturedAt.timeIntervalSince1970.isFinite
                ? ISO8601DateFormatter().string(from: calibration.capturedAt) : "invalid date"
            calibrationSummary = "Captured (format \(calibration.formatVersion)), sensor minute \(calibration.sensorMinute), lifecycle \(calibration.lifecycle), at \(captureDate)"
        } else {
            calibrationSummary = "Needs calibration — read the paired sensor with NFC"
        }
        if let anchor = validClockAnchor(for: session) {
            clockSummary = "Saved reference (format \(anchor.formatVersion)), sensor minute \(anchor.referenceSensorMinute), at \(ISO8601DateFormatter().string(from: anchor.referenceDate)); retained across calibration scans"
        } else {
            clockSummary = "Needs a valid sensor clock reference — read calibration with NFC"
        }
        let peripheral = session.peripheralID?.uuidString ?? "not discovered"
        sensorSummary = """
        Name: \(session.advertisedName)
        Revision: \(session.sensorKind.rawValue)
        UID: \(session.uid.hexString)
        Patch: \(session.patchInfo.hexString)
        BLE: \(peripheral)
        Next unlock counter: \(session.nextUnlockCount)
        Setup: \(session.setupComplete ? "complete" : "incomplete; repeat NFC setup")
        """
    }

    private func acceptCalibrationSessionIfCurrent(_ updated: LibreSensorSession) {
        guard let current = currentSensorSession,
              current.uid == updated.uid,
              current.patchInfo == updated.patchInfo,
              current.createdAt == updated.createdAt,
              current.unlockCode == updated.unlockCode,
              current.setupComplete == updated.setupComplete else {
            return
        }
        updateSensorSummary(updated)
    }

    private func prepareMetadata(for frame: LibreVerifiedFrame) async throws {
        guard frameGate.isCurrent(frame), let identity = frame.persistenceSessionID,
              try frame.sessionSnapshot.validatedPersistenceSessionID() == identity else {
            throw LibreFrameOwnershipError.staleFrame
        }
        let prepared = try await persistenceBridge.prepare(
            session: frame.sessionSnapshot,
            receivedAt: frame.receivedAt,
            isCurrent: { [frameGate] in frameGate.isCurrent(frame) }
        )
        guard frameGate.isCurrent(frame), prepared.session == frame.sessionSnapshot else {
            throw LibreFrameOwnershipError.staleFrame
        }
    }

    private func decodeDiagnosticPayload(_ frame: LibreVerifiedFrame) {
        guard frameGate.isCurrent(frame) else { return }
        let session = frame.sessionSnapshot
        guard !session.needsCalibration, let calibration = session.calibration else {
            diagnosticFrame = nil
            diagnosticGlucoseStatus = "Calibration is required"
            return
        }
        guard let clockAnchor = validClockAnchor(for: session) else {
            diagnosticFrame = nil
            diagnosticGlucoseStatus = "Needs a valid sensor clock reference — read calibration with NFC"
            return
        }
        let decoded = Libre2DiagnosticDecoder.decode(
            payload: frame.payload, calibration: calibration, clockAnchor: clockAnchor,
            uid: session.uid, patchInfo: session.patchInfo
        )
        guard frameGate.isCurrent(frame) else { return }
        diagnosticFrame = decoded
        if let rejection = decoded.rejection {
            diagnosticGlucoseStatus = "Frame rejected: \(rejection.description)"
            appendLog("Experimental glucose frame rejected: \(rejection.description)")
        } else {
            let accepted = decoded.slots.filter { $0.rejection == nil && $0.glucoseMgDL != nil }.count
            diagnosticGlucoseStatus = "\(accepted) of \(decoded.slots.count) samples accepted (decoder \(Libre2DiagnosticDecoder.version))"
            appendLog("Experimental glucose decoded: \(accepted) of \(decoded.slots.count) samples accepted")
        }
    }

    private func validClockAnchor(for session: LibreSensorSession) -> LibreSensorClockAnchor? {
        guard let anchor = session.clockAnchor,
              (try? anchor.validateOwnership(uid: session.uid, patchInfo: session.patchInfo)) != nil,
              (0...Libre2DiagnosticDecoder.maximumSensorMinute).contains(anchor.referenceSensorMinute),
              (try? anchor.timestamp(for: anchor.referenceSensorMinute)) != nil else { return nil }
        return anchor
    }

    private func waitingStatus(for session: LibreSensorSession?, newFrame: Bool = false) -> String {
        guard let session else { return "Waiting for a paired sensor" }
        guard !session.needsCalibration else { return "Calibration is required" }
        guard validClockAnchor(for: session) != nil else {
            return "Needs a valid sensor clock reference — read calibration with NFC"
        }
        return newFrame ? "Waiting for a new CRC-valid frame" : "Waiting for a CRC-valid frame"
    }

    private func experimentalGlucoseExport(formatter: ISO8601DateFormatter) -> String {
        guard let frame = diagnosticFrame else { return "Experimental samples: none" }
        if let rejection = frame.rejection {
            return "Experimental frame rejection: \(rejection.description)"
        }
        let lines = frame.slots.map { slot -> String in
            let prefix = "offset=\(slot.offsetMinutes)m sensorMinute=\(slot.sensorMinute) timestamp=\(formatter.string(from: slot.timestamp)) rawGlucose=\(slot.rawGlucose) rawTemperature=\(slot.rawTemperature) adjustment=\(slot.temperatureAdjustment)"
            if let rejection = slot.rejection { return "Experimental sample: \(prefix) rejected=\(rejection.description)" }
            guard let mgDL = slot.glucoseMgDL else { return "Experimental sample: \(prefix) rejected=missing calculated value" }
            let mmolL = mgDL / 18.0182
            let temperature = slot.temperatureCelsius.map { String(format: "%.2f", $0) } ?? "unavailable"
            return String(format: "Experimental sample: %@ glucose=%.1f mg/dL (%.2f mmol/L) temperature=%@ C", prefix, mgDL, mmolL, temperature)
        }
        return lines.joined(separator: "\n")
    }

    private func sendDiagnosticsAfterNFCIfEnabled() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: LibreDiagnosticsUploader.automaticUploadDefaultsKey) == nil {
            defaults.set(true, forKey: LibreDiagnosticsUploader.automaticUploadDefaultsKey)
        }
        guard defaults.bool(forKey: LibreDiagnosticsUploader.automaticUploadDefaultsKey) else { return }
        let endpoint = defaults.string(forKey: LibreDiagnosticsUploader.endpointDefaultsKey)
            ?? LibreDiagnosticsUploader.defaultEndpoint
        sendDiagnostics(to: endpoint)
    }

    private func appendLog(_ message: String) {
        precondition(Thread.isMainThread)
        logs.append(LogEntry(timestamp: Date(), message: message))
        if logs.count > Self.maximumLogEntries {
            logs.removeFirst(logs.count - Self.maximumLogEntries)
        }
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined() }
}
