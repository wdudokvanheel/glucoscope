import SwiftUI
import UIKit

struct LibreDiagnosticsView: View {
    @StateObject private var coordinator = LibreDiagnosticsCoordinator.shared
    @ObservedObject private var diagnosticsUploader = LibreDiagnosticsCoordinator.shared.diagnosticsUploader
    @State private var didCopyDiagnostics = false
    @AppStorage(LibreDiagnosticsUploader.endpointDefaultsKey)
    private var diagnosticsEndpoint = LibreDiagnosticsUploader.defaultEndpoint
    @AppStorage(LibreDiagnosticsUploader.automaticUploadDefaultsKey)
    private var automaticDiagnosticsUpload = true

    var body: some View {
        NavigationStack {
            List {
                instructionsSection
                connectionSection
                storageSection
                savedReadingsSection
                sensorSection
                experimentalGlucoseSection
                controlsSection
                uploadSection
                frameSection
                logSection
                diagnosticsSection
                storageProbeSection
                lockedStorageProbeSection
            }
            .navigationTitle("Libre 2 Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Copy diagnostics") {
                            UIPasteboard.general.string = coordinator.exportText
                            didCopyDiagnostics = true
                        }
                        ShareLink(item: coordinator.exportText) {
                            Label("Share diagnostics", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("Export diagnostics", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var uploadSection: some View {
        Section {
            TextField("http://host:8765/diagnostics", text: $diagnosticsEndpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onChange(of: diagnosticsEndpoint) { _ in
                    diagnosticsUploader.endpointDidChange()
                }

            Toggle("Send after NFC scan", isOn: $automaticDiagnosticsUpload)

            Button {
                coordinator.sendDiagnostics(to: diagnosticsEndpoint)
            } label: {
                if diagnosticsUploader.isUploading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Sending diagnostics…")
                    }
                } else {
                    Label("Send diagnostics", systemImage: "arrow.up.circle")
                }
            }
            .disabled(diagnosticsUploader.isUploading)

            LabeledContent("Upload") {
                Text(diagnosticsUploader.resultMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let filename = diagnosticsUploader.savedFilename {
                LabeledContent("Saved as") {
                    Text(filename)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Diagnostics host")
        } footer: {
            Text("Automatic upload sends one diagnostics snapshot when an NFC scan finishes. Use Send diagnostics to capture later Bluetooth activity.")
        }
    }

    private var instructionsSection: some View {
        Section {
            Text("The collector uses the saved sensor connection. Incoming valid readings are saved on this device and loaded again after relaunch.")
            Text("Values are experimental development data. Saved readings appear below; diagnostic details and optional storage probes are further down.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Before you start")
        }
    }

    private var experimentalGlucoseSection: some View {
        Section {
            Text(coordinator.diagnosticGlucoseStatus)
                .foregroundStyle(.secondary)
            Text(coordinator.clockSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let frame = coordinator.diagnosticFrame {
                if let rejection = frame.rejection {
                    LabeledContent("Frame rejected") {
                        Text(rejection.description)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    ForEach(Array(frame.slots.enumerated()), id: \.offset) { _, slot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(slot.timestamp, format: .dateTime.month().day().hour().minute().second())
                                    .font(.body.monospacedDigit())
                                Spacer()
                                if let mgDL = slot.glucoseMgDL, slot.rejection == nil {
                                    Text(String(format: "%.1f mg/dL · %.2f mmol/L", mgDL, mgDL / 18.0182))
                                        .monospacedDigit()
                                } else {
                                    Text("Rejected")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("Offset \(slot.offsetMinutes) min · sensor minute \(slot.sensorMinute) · raw \(slot.rawGlucose)/\(slot.rawTemperature)/\(slot.temperatureAdjustment)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let rejection = slot.rejection {
                                Text(rejection.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            Text("Experimental glucose")
        } footer: {
            Text("This section shows the latest frame calculation. The Saved experimental readings section shows values actually committed to local storage after ingestion checks.")
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            statusRow("Collector", value: coordinator.status)
            statusRow("Bluetooth", value: coordinator.bluetoothState)
            statusRow("NFC", value: coordinator.isNFCAvailable ? "Available" : "Unavailable")
            statusRow("Collection requested", value: coordinator.isRunning ? "Enabled" : "Stopped")
            statusRow("Raw frames", value: coordinator.frameCount.formatted())
            statusRow("CRC-valid frames", value: coordinator.verifiedFrameCount.formatted())

            if coordinator.isScanningNFC {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("NFC scan in progress…")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var storageSection: some View {
        Section("Collection storage") {
            Text(coordinator.collectionStatus.summary)
                .foregroundStyle(.secondary)
            statusRow("Queued frames", value: "\(coordinator.collectionStatus.queuedFrames)/\(LibreOrderedIngestion.capacity)")
            statusRow("Committed frames", value: coordinator.collectionStatus.completedFrames.formatted())
            statusRow("Decode-rejected frames", value: coordinator.collectionStatus.rejectedFrames.formatted())
            statusRow("Discarded frames", value: coordinator.collectionStatus.discardedFrames.formatted())
            statusRow("Stale frames rejected", value: coordinator.collectionStatus.staleFrameCount.formatted())
            Text("Experimental readings are saved on this device with their sensor timestamps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var savedReadingsSection: some View {
        Section("Saved experimental readings") {
            Text(coordinator.collectionStatus.savedReadingsStatus)
                .foregroundStyle(.secondary)
            ForEach(coordinator.collectionStatus.recentReadings, id: \.id) { reading in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.sampleDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Text(reading.primaryOrigin == .bleLive ? "Sensor sample" : "Recovered sensor sample")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f mmol/L", Double(reading.glucoseMGDL) / 18.0182))
                        .monospacedDigit()
                    Text("\(reading.glucoseMGDL) mg/dL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Read from local storage and restored after relaunch. Experimental values; no glucose uploads are running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var storageProbeSection: some View {
        Section {
            Text(coordinator.storageProbeStatus.detail)
                .foregroundStyle(.secondary)
            statusRow("Phase", value: coordinator.storageProbeStatus.phase)
            statusRow("Reopen", value: coordinator.storageProbeStatus.reopenVerified ? "Verified" : "Pending")
            statusRow("Relaunch", value: coordinator.storageProbeStatus.relaunchVerified ? "Verified" : "Pending")

            ForEach(Array(coordinator.storageProbeStatus.fileObservations.enumerated()), id: \.offset) { _, observation in
                statusRow("\(observation.fileName) · \(observation.phase)", value: observation.result)
            }

            Button {
                coordinator.startStorageProbe()
            } label: {
                if coordinator.storageProbeStatus.isRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Running isolated probe…")
                    }
                } else {
                    Label("Run isolated storage probe", systemImage: "externaldrive.badge.checkmark")
                }
            }
            .disabled(coordinator.storageProbeStatus.isRunning || coordinator.storageProbeStatus.lockedVerificationArmed)

            Button {
                coordinator.verifyStorageProbeAfterRelaunch()
            } label: {
                Label("Verify saved probe after relaunch", systemImage: "arrow.clockwise")
            }
            .disabled(coordinator.storageProbeStatus.isRunning || coordinator.storageProbeStatus.lockedVerificationArmed)
        } header: {
            Text("Isolated storage probe")
        } footer: {
            Text("Runs only when tapped and writes synthetic session/clock metadata to a separate test store. It never writes glucose readings or delivery records. Reopen is checked during the run; relaunch stays pending until a later app process verifies the saved probe. Stop the collector before the device check.")
        }
    }

    private var lockedStorageProbeSection: some View {
        Section {
            Text(coordinator.storageProbeStatus.detail)
                .foregroundStyle(.secondary)
            statusRow("Armed", value: coordinator.storageProbeStatus.lockedVerificationArmed ? "Lock iPhone now" : "No")
            statusRow("Unavailable while backgrounded", value: coordinator.storageProbeStatus.lockedVerificationAttempted ? "Observed" : "Not observed")
            statusRow("Locked storage", value: coordinator.storageProbeStatus.lockedVerified ? "Verified" : "Not verified")

            ForEach(Array(coordinator.storageProbeStatus.lockedObservations.enumerated()), id: \.offset) { _, observation in
                Text(observation)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button {
                coordinator.armLockedStorageProbe()
            } label: {
                if coordinator.storageProbeStatus.lockedVerificationArmed {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Armed — lock iPhone now")
                    }
                } else {
                    Label("Arm locked-device probe", systemImage: "lock.shield")
                }
            }
            .disabled(
                coordinator.storageProbeStatus.isRunning ||
                coordinator.storageProbeStatus.lockedVerificationArmed ||
                coordinator.isRunning ||
                coordinator.isScanningNFC
            )

            if coordinator.storageProbeStatus.lockedVerificationArmed {
                Button("Cancel locked-device probe", role: .cancel) {
                    coordinator.cancelLockedStorageProbe()
                }
            }
        } header: {
            Text("Locked-device storage probe")
        } footer: {
            Text("This explicit, bounded check uses a second isolated synthetic-metadata store and a temporary iOS background task. It writes no glucose or delivery records and does not use NFC or Bluetooth. Success requires directly observing protected data unavailable while the app is backgrounded; a notification, cancellation, expiration or missing callback is inconclusive. The verdict is kept in memory, so export it before terminating or relaunching.")
        }
    }

    private var sensorSection: some View {
        Section("Paired sensor") {
            Text(coordinator.calibrationSummary)
                .foregroundStyle(.secondary)
            statusRow("Calibration action", value: coordinator.calibrationStatus)

            if coordinator.sensorSummary.isEmpty {
                Text("No sensor identity saved. Run NFC setup to read the sensor identity and enable Bluetooth streaming.")
                    .foregroundStyle(.secondary)
            } else {
                Text(coordinator.sensorSummary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var controlsSection: some View {
        Section("Actions") {
            Button {
                coordinator.startNFCCalibration()
            } label: {
                Label("Read calibration with NFC", systemImage: "wave.3.right")
            }
            .disabled(coordinator.isScanningNFC || !coordinator.isNFCAvailable || !coordinator.canCaptureCalibration || coordinator.storageProbeStatus.lockedVerificationArmed)

            Button {
                coordinator.startNFCSetup()
            } label: {
                Label(coordinator.isScanningNFC ? "Scanning sensor…" : "Set up with NFC", systemImage: "wave.3.right.circle")
            }
            .disabled(coordinator.isScanningNFC || coordinator.storageProbeStatus.lockedVerificationArmed)

            Button {
                coordinator.reconnect()
            } label: {
                Label("Reconnect Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(coordinator.isScanningNFC || coordinator.sensorSummary.isEmpty || coordinator.storageProbeStatus.lockedVerificationArmed)

            Button {
                coordinator.stop()
            } label: {
                Label("Stop connection", systemImage: "stop.circle")
            }
            .disabled((!coordinator.isRunning && !coordinator.isScanningNFC) || coordinator.storageProbeStatus.lockedVerificationArmed)

            Button(role: .destructive) {
                coordinator.forgetSensor()
            } label: {
                Label("Forget sensor", systemImage: "trash")
            }
            .disabled(coordinator.sensorSummary.isEmpty || coordinator.isScanningNFC || coordinator.storageProbeStatus.lockedVerificationArmed)
        }
    }

    private var frameSection: some View {
        Section("Latest raw BLE frame") {
            if coordinator.lastFrameHex.isEmpty {
                Text("No complete BLE frame received yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(coordinator.lastFrameHex)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                if let lastFrameAt = coordinator.lastFrameAt {
                    LabeledContent("Received") {
                        Text(lastFrameAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
            }

            if let verifiedAt = coordinator.lastVerifiedFrameAt {
                LabeledContent("Last CRC-valid frame") {
                    Text(verifiedAt, format: .dateTime.hour().minute().second())
                }
                Text(coordinator.lastPayloadHex)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Text("A connection or raw frame alone is not proof that sensor data is valid. Experimental values appear only after frame integrity and per-sample checks pass.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var logSection: some View {
        Section {
            if coordinator.logs.isEmpty {
                Text("No events yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(coordinator.logs.reversed())) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            HStack {
                Text("Event log")
                Spacer()
                Button("Clear") {
                    coordinator.clearLog()
                }
                .font(.caption)
                .disabled(coordinator.logs.isEmpty)
            }
        } footer: {
            Text("The collector keeps this log bounded so extended testing does not consume unlimited memory.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Complete diagnostics") {
            Button {
                UIPasteboard.general.string = coordinator.exportText
                didCopyDiagnostics = true
            } label: {
                Label(didCopyDiagnostics ? "Copied" : "Copy diagnostics", systemImage: didCopyDiagnostics ? "checkmark" : "doc.on.doc")
            }

            ShareLink(item: coordinator.exportText) {
                Label("Share diagnostics", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func statusRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value.isEmpty ? "Unknown" : value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
