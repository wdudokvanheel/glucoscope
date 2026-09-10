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
    @Published private(set) var bluetoothState = "Unknown"
    @Published private(set) var sensorSummary = ""
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var frameCount = 0
    @Published private(set) var verifiedFrameCount = 0
    @Published private(set) var lastFrameHex = ""
    @Published private(set) var lastFrameAt: Date?
    @Published private(set) var lastVerifiedFrameAt: Date?
    @Published private(set) var lastPayloadHex = ""
    @Published private(set) var isRunning = false
    @Published private(set) var isScanningNFC = false
    @Published private(set) var isNFCAvailable = false
    let diagnosticsUploader = LibreDiagnosticsUploader()

    private static let maximumLogEntries = 500
    private let store = LibreSessionStore()
    private var nfcSession: LibreNFCSession?
    private var operationGeneration: UInt64 = 0
    private lazy var bluetooth = LibreBluetoothCentral(store: store) { [weak self] event in
        self?.receive(event)
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        let header = [
            "GlucoScope Libre 2 diagnostics",
            "Diagnostics revision: NFC read recovery v2",
            "App: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"))",
            "Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)",
            "Exported: \(formatter.string(from: Date()))",
            "Status: \(status)",
            "Bluetooth: \(bluetoothState)",
            "Sensor: \(sensorSummary)",
            "Raw frames: \(frameCount)",
            "Verified frames: \(verifiedFrameCount)",
            "Last verified: \(lastVerifiedFrameAt.map { formatter.string(from: $0) } ?? "none")",
            "Latest raw frame: \(lastFrameHex)",
            "Latest decrypted payload: \(lastPayloadHex)",
            ""
        ]
        return (header + logs.map { "\(formatter.string(from: $0.timestamp))  \($0.message)" }).joined(separator: "\n")
    }

    func sendDiagnostics(to endpoint: String) {
        diagnosticsUploader.send(snapshot: exportText, endpoint: endpoint)
    }

    private override init() {
        super.init()
        _ = bluetooth
        refreshStoredSession()
        isNFCAvailable = LibreNFCSession(store: store).isAvailable
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil
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

    private func beginNFCSetup(generation: UInt64) {
        let session = LibreNFCSession(store: store)
        isNFCAvailable = session.isAvailable
        guard isNFCAvailable else {
            isScanningNFC = false
            status = "NFC is unavailable on this device"
            appendLog(status)
            sendDiagnosticsAfterNFCIfEnabled()
            return
        }
        isScanningNFC = true
        status = "Hold the top of the iPhone near the sensor"
        appendLog("Starting NFC sensor setup")
        session.onLog = { [weak self] message in
                guard let self, self.operationGeneration == generation else { return }
                self.appendLog("NFC: \(message)")
            }
        session.onCompletion = { [weak self] result in
                guard let self, self.operationGeneration == generation else { return }
                self.isScanningNFC = false
                self.nfcSession = nil
                switch result {
                case .success(let sensor):
                    do {
                        try self.store.save(sensor)
                        self.resetFrames()
                        self.updateSensorSummary(sensor)
                        self.appendLog("NFC setup complete for \(sensor.advertisedName)")
                        self.status = "Sensor configured; connecting"
                        self.isRunning = true
                        self.bluetooth.use(sensor)
                    } catch {
                        self.status = "Could not save sensor setup"
                        self.appendLog("ERROR: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    self.refreshStoredSession()
                    self.status = "NFC setup failed"
                    self.appendLog("ERROR: NFC setup failed: \(error.localizedDescription)")
                }
                self.sendDiagnosticsAfterNFCIfEnabled()
            }
        nfcSession = session
        session.start()
    }

    func reconnect() {
        precondition(Thread.isMainThread)
        operationGeneration &+= 1
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
        appendLog("Reconnect requested")
        bluetooth.reconnect()
    }

    func stop() {
        precondition(Thread.isMainThread)
        operationGeneration &+= 1
        nfcSession?.cancel()
        nfcSession = nil
        isScanningNFC = false
        isRunning = false
        bluetooth.stop()
        status = "Stopped"
        appendLog("Collection stopped deliberately")
    }

    func forgetSensor() {
        precondition(Thread.isMainThread)
        operationGeneration &+= 1
        nfcSession?.cancel()
        nfcSession = nil
        isScanningNFC = false
        isRunning = false
        bluetooth.forget()
        resetFrames()
        sensorSummary = ""
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
    }

    @objc private func appBecameActive() {
        bluetooth.appBecameActive()
        isNFCAvailable = LibreNFCSession(store: store).isAvailable
        appendLog("Application became active")
    }

    @objc private func appEnteredBackground() {
        bluetooth.appEnteredBackground()
        appendLog("Application entered background")
    }

    private func refreshStoredSession() {
        do {
            if let session = try store.load() {
                updateSensorSummary(session)
                let enabled = session.setupComplete && UserDefaults.standard.bool(forKey: "libre2.collectionEnabled")
                isRunning = enabled
                status = enabled ? "Restoring sensor connection" : "Sensor collection is stopped"
            } else {
                status = "Scan a Libre 2 sensor with NFC"
            }
        } catch {
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
            status = value
            appendLog(value)
        case .log(let message):
            appendLog(message)
        case .sessionChanged(let session):
            updateSensorSummary(session)
        case .rawFrame(let data, let date):
            frameCount += 1
            lastFrameAt = date
            lastFrameHex = data.hexString
            appendLog("Raw BLE frame #\(frameCount): \(data.hexString)")
        case .verifiedPayload(let payload, let date):
            verifiedFrameCount += 1
            lastVerifiedFrameAt = date
            lastPayloadHex = payload.hexString
            status = "Receiving CRC-valid frames"
            appendLog("Verified/decrypted payload (glucose decoding pending): \(payload.hexString)")
        case .error(let message):
            status = message
            appendLog("ERROR: \(message)")
        }
    }

    private func updateSensorSummary(_ session: LibreSensorSession) {
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
