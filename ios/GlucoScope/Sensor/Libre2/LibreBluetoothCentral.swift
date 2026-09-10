import CoreBluetooth
import Foundation
import UIKit

/// The Core Bluetooth lifecycle for one NFC-provisioned Libre 2 sensor.
/// All mutable state and all Core Bluetooth calls are confined to `queue`.
final class LibreBluetoothCentral: NSObject {
    enum Event {
        case bluetoothState(String)
        case status(String)
        case log(String)
        case sessionChanged(LibreSensorSession)
        case rawFrame(Data, Date)
        case verifiedPayload(Data, Date)
        case error(String)
    }

    private static let serviceID = CBUUID(string: "FDE3")
    private static let writeID = CBUUID(string: "F001")
    private static let notifyID = CBUUID(string: "F002")
    private static let frameLength = 46
    private static let fragmentTimeout: TimeInterval = 3

    private let queue = DispatchQueue(label: "nl.glucoscope.libre2.bluetooth", qos: .userInitiated)
    private let store: LibreSessionStore
    private let onEvent: (Event) -> Void
    private var central: CBCentralManager!
    private var session: LibreSensorSession?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var frameAssembler = LibreFrameAssembler(frameLength: frameLength)
    private var fragmentTimeoutWork: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?
    private var generation: UInt64 = 0
    private var shouldRun = false
    private var pendingConnection = false
    private var didUnlockThisConnection = false
    private var discoveryInProgress = false
    private var connectionFailureCount = 0
    private var unlockedAt: Date?
    private var lastVerifiedFrameAt: Date?
    private var isForeground = UIApplication.shared.applicationState != .background
    private var loggedCandidateNames = Set<String>()
    private static let enabledDefaultsKey = "libre2.collectionEnabled"

    init(store: LibreSessionStore, onEvent: @escaping (Event) -> Void) {
        self.store = store
        self.onEvent = onEvent
        super.init()
        queue.sync {
            do {
                session = try store.load()
                shouldRun = session?.setupComplete == true && UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
            } catch { emit(.error("Could not load saved sensor: \(error.localizedDescription)")) }
            central = CBCentralManager(delegate: self, queue: queue, options: [
                CBCentralManagerOptionRestoreIdentifierKey: "nl.glucoscope.libre2.central"
            ])
        }
    }

    func use(_ newSession: LibreSensorSession, connect: Bool = true) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopCurrentConnection(forgetPeripheral: true)
            self.session = newSession
            self.shouldRun = connect && newSession.setupComplete
            UserDefaults.standard.set(self.shouldRun, forKey: Self.enabledDefaultsKey)
            self.emit(.sessionChanged(newSession))
            if self.shouldRun { self.connectOrDiscover() }
        }
    }

    /// Serialize calibration persistence with counter reservations and peripheral updates.
    /// Never reconnect, reset assembly, or publish a capture before its save succeeds.
    func applyCalibration(_ calibration: LibreCalibration, expectedSession: LibreSensorSession,
                          completion: @escaping (Result<LibreSensorSession, Error>) -> Void) {
        queue.async {
            let result: Result<LibreSensorSession, Error>
            do {
                guard let current = self.session, let latest = try self.store.load() else {
                    throw LibreNFCError.differentSensor
                }
                _ = try current.mergingCalibration(calibration, expectedSession: expectedSession)
                let merged = try latest.mergingCalibration(calibration, expectedSession: expectedSession)
                try self.store.save(merged)
                self.session = merged
                result = .success(merged)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func reconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            do { self.session = try self.store.load() }
            catch { self.emit(.error("Could not reload saved sensor: \(error.localizedDescription)")); return }
            guard self.session?.setupComplete == true else {
                self.shouldRun = false
                UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
                self.emit(.error("Scan a sensor with NFC before connecting."))
                return
            }
            self.shouldRun = true
            UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
            self.connectionFailureCount = 0
            self.retryWork?.cancel()
            self.retryWork = nil
            let activityAt = self.lastVerifiedFrameAt ?? self.unlockedAt
            if let peripheral = self.peripheral, peripheral.state == .connected,
               let activityAt, Date().timeIntervalSince(activityAt) > 6 * 60 {
                self.emit(.log("Reconnecting a stalled sensor stream"))
                self.central.cancelPeripheralConnection(peripheral)
            } else {
                self.connectOrDiscover()
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
            self.stopCurrentConnection(forgetPeripheral: false)
            self.emit(.status("Stopped"))
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func forget() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
            self.stopCurrentConnection(forgetPeripheral: true)
            self.session = nil
            do {
                try self.store.clear()
                self.emit(.status("No sensor configured"))
            } catch {
                self.emit(.error("Could not clear saved sensor: \(error.localizedDescription)"))
            }
        }
    }

    func appBecameActive() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isForeground = true
            guard self.shouldRun else { return }
            let activityAt = self.lastVerifiedFrameAt ?? self.unlockedAt
            if let activityAt, self.didUnlockThisConnection,
               Date().timeIntervalSince(activityAt) > 6 * 60,
               let peripheral = self.peripheral, peripheral.state == .connected {
                self.emit(.error("Sensor stream is stale; reconnecting"))
                self.central.cancelPeripheralConnection(peripheral)
            } else { self.connectOrDiscover() }
        }
    }

    func appEnteredBackground() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isForeground = false
            // An unfiltered scan is ineffective in the background. Existing connections and
            // exact-peripheral connection requests remain active for Core Bluetooth restoration.
            if self.peripheral == nil { self.central.stopScan() }
        }
    }

    private func connectOrDiscover() {
        guard shouldRun, let session else { return }
        guard central.state == .poweredOn else {
            emit(.status("Waiting for Bluetooth"))
            return
        }
        if let current = peripheral, current.identifier == session.peripheralID {
            requestConnection(to: current)
            return
        }
        if let identifier = session.peripheralID,
           let known = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            adopt(known)
            requestConnection(to: known)
            return
        }
        // Libre 2 does not reliably advertise its service. Initial discovery is deliberately
        // unfiltered and must match the exact name obtained during NFC setup.
        guard isForeground else {
            emit(.status("Open GlucoScope to discover the configured sensor"))
            return
        }
        emit(.status("Discovering \(session.advertisedName)"))
        emit(.log("Started foreground, unfiltered scan for exact sensor name"))
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func requestConnection(to peripheral: CBPeripheral) {
        guard shouldRun, central.state == .poweredOn else { return }
        central.stopScan()
        if peripheral.state == .connected {
            pendingConnection = false
            if didUnlockThisConnection, notifyCharacteristic?.isNotifying == true {
                emit(.status(lastVerifiedFrameAt == nil ? "Connected; waiting for sensor frames" : "Receiving CRC-valid frames"))
                return
            }
            if discoveryInProgress { return }
            discover(on: peripheral)
            return
        }
        if peripheral.state == .disconnecting { return }
        if peripheral.state == .connecting { pendingConnection = true; return }
        guard !pendingConnection else { return }
        pendingConnection = true
        emit(.status("Connecting"))
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    private func adopt(_ peripheral: CBPeripheral) {
        self.peripheral?.delegate = nil
        self.peripheral = peripheral
        peripheral.delegate = self
    }

    private func discover(on peripheral: CBPeripheral) {
        guard shouldRun, peripheral === self.peripheral else { return }
        generation &+= 1
        resetFrameBuffer()
        discoveryInProgress = true
        didUnlockThisConnection = false
        unlockedAt = nil
        lastVerifiedFrameAt = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        emit(.status("Connected; discovering service"))
        if let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) {
            discoverCharacteristicsOrReuse(on: peripheral, service: service)
        } else {
            peripheral.discoverServices([Self.serviceID])
        }
    }

    private func discoverCharacteristicsOrReuse(on peripheral: CBPeripheral, service: CBService) {
        guard shouldRun, peripheral === self.peripheral else { return }
        let existing = service.characteristics ?? []
        if let write = existing.first(where: { $0.uuid == Self.writeID }),
           let notify = existing.first(where: { $0.uuid == Self.notifyID }) {
            guard write.properties.contains(.write),
                  notify.properties.contains(.notify) || notify.properties.contains(.indicate) else {
                emit(.error("Libre characteristics do not support required write/notify operations"))
                return
            }
            writeCharacteristic = write
            notifyCharacteristic = notify
            if notify.isNotifying { reserveAndSendUnlock() }
            else { emit(.status("Subscribing")); peripheral.setNotifyValue(true, for: notify) }
        } else {
            peripheral.discoverCharacteristics([Self.writeID, Self.notifyID], for: service)
        }
    }

    private func stopCurrentConnection(forgetPeripheral: Bool) {
        generation &+= 1
        retryWork?.cancel()
        retryWork = nil
        central?.stopScan()
        resetFrameBuffer()
        if let notifyCharacteristic, notifyCharacteristic.isNotifying {
            peripheral?.setNotifyValue(false, for: notifyCharacteristic)
        }
        if let peripheral, peripheral.state != .disconnected {
            central?.cancelPeripheralConnection(peripheral)
        }
        pendingConnection = false
        discoveryInProgress = false
        didUnlockThisConnection = false
        connectionFailureCount = 0
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if forgetPeripheral {
            peripheral?.delegate = nil
            peripheral = nil
        }
    }

    private func scheduleBoundedRetry(for peripheral: CBPeripheral) {
        guard shouldRun, peripheral === self.peripheral else { return }
        connectionFailureCount += 1
        guard connectionFailureCount <= 5 else {
            emit(.error("Repeated Bluetooth connection failures; use Reconnect to try again"))
            return
        }
        let delay = min(pow(2, Double(connectionFailureCount - 1)), 16)
        let currentGeneration = generation
        emit(.log("Retrying connection in \(Int(delay)) seconds (\(connectionFailureCount)/5)"))
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral, self.shouldRun,
                  self.generation == currentGeneration, peripheral === self.peripheral else { return }
            self.requestConnection(to: peripheral)
        }
        retryWork?.cancel()
        retryWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resetFrameBuffer() {
        fragmentTimeoutWork?.cancel()
        fragmentTimeoutWork = nil
        frameAssembler.reset()
    }

    private func appendNotification(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        switch frameAssembler.append(bytes) {
        case .overflow(let count):
            emit(.error("BLE frame overflow (\(count) bytes); buffer reset"))
            resetFrameBuffer()
        case .frame(let frame):
            resetFrameBuffer()
            let receivedAt = Date()
            emit(.rawFrame(frame, receivedAt))
            guard let uid = session?.uid else {
                emit(.error("Received a frame without a configured sensor identity"))
                return
            }
            do {
                let payload = try Libre2Protocol.decryptFrame(frame, uid: uid)
                lastVerifiedFrameAt = receivedAt
                emit(.verifiedPayload(payload, receivedAt))
            } catch {
                emit(.error("Frame verification failed: \(error.localizedDescription)"))
            }
        case .incomplete: break
        }
        guard !frameAssembler.buffer.isEmpty else { return }
        let currentGeneration = generation
        fragmentTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration, !self.frameAssembler.buffer.isEmpty else { return }
            self.emit(.error("BLE frame timed out at \(self.frameAssembler.buffer.count)/\(Self.frameLength) bytes; buffer reset"))
            self.resetFrameBuffer()
        }
        fragmentTimeoutWork = work
        queue.asyncAfter(deadline: .now() + Self.fragmentTimeout, execute: work)
    }

    private func reserveAndSendUnlock() {
        guard !didUnlockThisConnection, var session, let peripheral, let writeCharacteristic else { return }
        guard (1...UInt32(UInt16.max)).contains(session.nextUnlockCount) else {
            emit(.error("Unlock counter is exhausted; scan the sensor with NFC to repair setup"))
            return
        }
        let reserved = UInt16(session.nextUnlockCount)
        do {
            let payload = try Libre2Protocol.unlockPayload(session: session, counter: reserved)
            session.nextUnlockCount += 1
            // Saving first prevents reuse after termination between reservation and write.
            try store.save(session)
            self.session = session
            emit(.sessionChanged(session))
            discoveryInProgress = false
            didUnlockThisConnection = true
            unlockedAt = Date()
            emit(.status("Unlocking stream"))
            peripheral.writeValue(payload, for: writeCharacteristic, type: .withResponse)
            emit(.log("Reserved unlock counter \(reserved) and wrote \(payload.count)-byte command"))
        } catch {
            emit(.error("Could not reserve/send unlock command: \(error.localizedDescription)"))
        }
    }

    private func emit(_ event: Event) {
        if case .error = event { discoveryInProgress = false }
        DispatchQueue.main.async { [onEvent] in onEvent(event) }
    }
}

extension LibreBluetoothCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let label: String
        switch central.state {
        case .poweredOn: label = "Powered on"
        case .poweredOff: label = "Powered off"
        case .unauthorized: label = "Unauthorized"
        case .unsupported: label = "Unsupported"
        case .resetting: label = "Resetting"
        case .unknown: label = "Unknown"
        @unknown default: label = "Unknown (\(central.state.rawValue))"
        }
        emit(.bluetoothState(label))
        if central.state != .poweredOn {
            generation &+= 1
            resetFrameBuffer()
            discoveryInProgress = false
            didUnlockThisConnection = false
            writeCharacteristic = nil
            notifyCharacteristic = nil
            if shouldRun { emit(.status("Waiting for Bluetooth (\(label))")) }
            pendingConnection = false
            retryWork?.cancel()
            retryWork = nil
        }
        if central.state == .poweredOn, shouldRun { connectOrDiscover() }
        if central.state == .unauthorized { emit(.error("Bluetooth permission is not granted.")) }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard shouldRun, let session else {
            for candidate in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
                central.cancelPeripheralConnection(candidate)
            }
            emit(.log("Cancelled Bluetooth restoration because collection is disabled"))
            return
        }
        let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for candidate in restoredPeripherals where candidate.identifier != session.peripheralID {
            central.cancelPeripheralConnection(candidate)
        }
        let restored = restoredPeripherals.first(where: { $0.identifier == session.peripheralID })
        guard let restored else {
            emit(.log("No matching paired sensor in restored Bluetooth state"))
            return
        }
        adopt(restored)
        emit(.log("Restored paired peripheral \(restored.identifier.uuidString)"))
        if central.state == .poweredOn { requestConnection(to: restored) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard shouldRun, central.isScanning, var session else { return }
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard advertised == session.advertisedName || peripheral.name == session.advertisedName else {
            if let candidate = advertised ?? peripheral.name,
               (candidate.uppercased().hasPrefix("ABBOTT") || (candidate.count == 12 && candidate.allSatisfy { $0.isHexDigit })),
               loggedCandidateNames.count < 12, loggedCandidateNames.insert(candidate).inserted {
                emit(.log("Ignored possible Libre candidate named \(candidate); expected exact name \(session.advertisedName)"))
            }
            return
        }
        central.stopScan()
        session.peripheralID = peripheral.identifier
        do {
            try store.save(session)
            self.session = session
            emit(.sessionChanged(session))
        } catch {
            emit(.error("Found sensor but could not save its Bluetooth identifier: \(error.localizedDescription)"))
            return
        }
        emit(.log("Matched sensor \(session.advertisedName), RSSI \(RSSI)"))
        adopt(peripheral)
        requestConnection(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard shouldRun, peripheral === self.peripheral else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        pendingConnection = false
        connectionFailureCount = 0
        emit(.log("Connected to paired peripheral"))
        discover(on: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard shouldRun, peripheral === self.peripheral else { return }
        pendingConnection = false
        emit(.error("Connection failed: \(error?.localizedDescription ?? "unknown error")"))
        scheduleBoundedRetry(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard shouldRun, peripheral === self.peripheral else { return }
        pendingConnection = false
        discoveryInProgress = false
        didUnlockThisConnection = false
        generation &+= 1
        resetFrameBuffer()
        writeCharacteristic = nil
        notifyCharacteristic = nil
        emit(.status(shouldRun ? "Disconnected; waiting for sensor" : "Stopped"))
        if let error { emit(.log("Disconnected: \(error.localizedDescription)")) }
        requestConnection(to: peripheral)
    }
}

extension LibreBluetoothCentral: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard shouldRun, peripheral === self.peripheral else { return }
        if let error { emit(.error("Service discovery failed: \(error.localizedDescription)")); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else {
            emit(.error("Libre service FDE3 was not found")); return
        }
        discoverCharacteristicsOrReuse(on: peripheral, service: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard shouldRun, peripheral === self.peripheral, service.uuid == Self.serviceID else { return }
        if let error { emit(.error("Characteristic discovery failed: \(error.localizedDescription)")); return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.writeID { writeCharacteristic = characteristic }
            if characteristic.uuid == Self.notifyID { notifyCharacteristic = characteristic }
        }
        guard writeCharacteristic != nil, let notifyCharacteristic else {
            emit(.error("Libre F001/F002 characteristics were not found")); return
        }
        guard writeCharacteristic?.properties.contains(.write) == true,
              notifyCharacteristic.properties.contains(.notify) || notifyCharacteristic.properties.contains(.indicate) else {
            emit(.error("Libre characteristics do not support required write/notify operations")); return
        }
        emit(.status("Subscribing"))
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard shouldRun, peripheral === self.peripheral, characteristic === notifyCharacteristic else { return }
        if let error { emit(.error("Notification subscription failed: \(error.localizedDescription)")); return }
        guard characteristic.isNotifying else { emit(.error("Sensor notifications are disabled")); return }
        reserveAndSendUnlock()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard shouldRun, peripheral === self.peripheral, characteristic === writeCharacteristic else { return }
        if let error { emit(.error("Unlock write failed: \(error.localizedDescription)")); return }
        emit(.status("Connected; waiting for sensor frames"))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard shouldRun, peripheral === self.peripheral, characteristic === notifyCharacteristic else { return }
        if let error { emit(.error("Notification failed: \(error.localizedDescription)")); return }
        guard let value = characteristic.value else { emit(.error("Sensor sent an empty notification")); return }
        emit(.log("F002 notification (\(value.count) bytes): " + value.map { String(format: "%02X", $0) }.joined()))
        appendNotification(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard shouldRun, peripheral === self.peripheral,
              invalidatedServices.contains(where: { $0.uuid == Self.serviceID }) else { return }
        generation &+= 1
        resetFrameBuffer()
        writeCharacteristic = nil
        notifyCharacteristic = nil
        didUnlockThisConnection = false
        unlockedAt = nil
        emit(.log("Libre service was invalidated; rediscovering"))
        peripheral.discoverServices([Self.serviceID])
    }
}
