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
                sensorSection
                controlsSection
                uploadSection
                frameSection
                logSection
                diagnosticsSection
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

            Toggle("Send after NFC setup", isOn: $automaticDiagnosticsUpload)

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
            Text("Automatic upload sends one diagnostics snapshot when NFC setup finishes. Use Send diagnostics to capture later Bluetooth activity.")
        }
    }

    private var instructionsSection: some View {
        Section {
            Text("This screen is for Libre 2 hardware testing. It reports connection events and diagnostic frames; it does not calculate or display glucose yet.")
            Text("Use NFC setup with an already activated EU Libre 2 sensor. Hold the top of the iPhone close to the sensor until the scan finishes. Keep this screen open for the first Bluetooth connection.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Before you start")
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

    private var sensorSection: some View {
        Section("Paired sensor") {
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
                coordinator.startNFCSetup()
            } label: {
                Label(coordinator.isScanningNFC ? "Scanning sensor…" : "Set up with NFC", systemImage: "wave.3.right.circle")
            }
            .disabled(coordinator.isScanningNFC)

            Button {
                coordinator.reconnect()
            } label: {
                Label("Reconnect Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(coordinator.isScanningNFC || coordinator.sensorSummary.isEmpty)

            Button {
                coordinator.stop()
            } label: {
                Label("Stop connection", systemImage: "stop.circle")
            }
            .disabled(!coordinator.isRunning && !coordinator.isScanningNFC)

            Button(role: .destructive) {
                coordinator.forgetSensor()
            } label: {
                Label("Forget sensor", systemImage: "trash")
            }
            .disabled(coordinator.sensorSummary.isEmpty || coordinator.isScanningNFC)
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

            Text("A connection or raw frame alone is not proof that sensor data is valid. Successful verification appears in the collector status and event log; glucose decoding is not implemented yet.")
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
