import SwiftUI

struct ServerUploadsView: View {
    @ObservedObject var coordinator: ServerUploadCoordinator
    @State private var showingAdd = false
    @State private var presentedError: String?

    var body: some View {
        List {
            Section {
                if coordinator.snapshot.destinations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No upload destinations").font(.headline)
                        Text("Add Nightscout or a GlucoScope Server. New destinations upload new sensor readings only.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(coordinator.snapshot.destinations) { destination in
                        NavigationLink {
                            ServerUploadDestinationView(
                                coordinator: coordinator,
                                destinationID: destination.id
                            )
                        } label: {
                            ServerUploadDestinationRow(
                                destination: destination,
                                progress: coordinator.snapshot.progress(for: destination.id)
                            )
                        }
                    }
                }
            } header: {
                Text("Destinations")
            } footer: {
                Text("Each destination has its own durable queue and delivery history. Viewer mode pauses all uploads without clearing them.")
            }

            if let lastError = coordinator.lastError {
                Section("Needs attention") {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Server uploads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add destination", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                ServerUploadEditorView(coordinator: coordinator, destination: nil)
            }
        }
        .task { await coordinator.refresh() }
        .alert("Upload error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presentedError ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }
}

private struct ServerUploadDestinationRow: View {
    let destination: ServerUploadDestination
    let progress: ServerUploadProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: destination.backend == .nightscout ? "cloud.fill" : "server.rack")
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.name)
                    .font(.body.weight(.medium))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if progress.pendingCount > 0 {
                Text("\(progress.pendingCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var statusText: String {
        if !destination.enabled { return "Disabled" }
        if destination.paused { return "Paused · \(progress.pendingCount) pending" }
        if progress.failedCount > 0 { return "\(progress.failedCount) failed · \(progress.pendingCount) pending" }
        if progress.pendingCount > 0 { return "Uploading · \(progress.pendingCount) pending" }
        return "Up to date"
    }

    private var statusColor: Color {
        if !destination.enabled || destination.paused { return .secondary }
        if progress.failedCount > 0 { return .orange }
        return .accentColor
    }
}

private struct ServerUploadDestinationView: View {
    @ObservedObject var coordinator: ServerUploadCoordinator
    let destinationID: UUID
    @State private var showingEdit = false
    @State private var showingHistory = false
    @State private var showingCatchUp = false
    @State private var confirmingCancel = false
    @State private var confirmingClear = false
    @State private var confirmingRemove = false
    @State private var presentedError: String?
    @Environment(\.dismiss) private var dismiss

    private var destination: ServerUploadDestination? {
        coordinator.snapshot.destinations.first { $0.id == destinationID }
    }

    var body: some View {
        Group {
            if let destination {
                Form {
                    statusSection(destination)
                    controlsSection(destination)
                    progressSection(destination)
                    Section("Tools") {
                        Button { showingHistory = true } label: {
                            Label("Upload existing history", systemImage: "clock.arrow.circlepath")
                        }
                        Button { Task { await retry() } } label: {
                            Label("Retry failed readings now", systemImage: "arrow.clockwise")
                        }
                        .disabled(coordinator.snapshot.progress(for: destinationID).failedCount == 0 || !destination.enabled)
                        NavigationLink {
                            ServerUploadDebugView(coordinator: coordinator, destinationID: destinationID)
                        } label: {
                            Label("Debug", systemImage: "ladybug")
                        }
                    }
                    Section {
                        Button("Cancel remaining history upload", role: .destructive) {
                            confirmingCancel = true
                        }
                        Button("Clear upload queue", role: .destructive) {
                            confirmingClear = true
                        }
                    } footer: {
                        Text("Cancel removes unfinished history and catch-up work but keeps new-reading deliveries. Clear removes every pending item. A request already being sent may finish and its outcome will be recorded.")
                    }
                    Section {
                        Button("Remove destination", role: .destructive) { confirmingRemove = true }
                    }
                }
                .navigationTitle(destination.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showingEdit = true }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.xmark").font(.largeTitle)
                    Text("Destination removed").font(.headline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let destination {
                NavigationStack {
                    ServerUploadEditorView(coordinator: coordinator, destination: destination)
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                ServerUploadHistoryView(coordinator: coordinator, destinationID: destinationID)
            }
        }
        .sheet(isPresented: $showingCatchUp) {
            if let destination, let disabledAt = destination.disabledAt {
                NavigationStack {
                    ServerUploadCatchUpView(
                        coordinator: coordinator,
                        destinationID: destinationID,
                        disabledAt: disabledAt
                    )
                }
            }
        }
        .confirmationDialog("Cancel remaining history upload?", isPresented: $confirmingCancel) {
            Button("Cancel remaining history", role: .destructive) { Task { await cancelBulk() } }
        } message: {
            Text("Already uploaded readings remain on the server. New-reading deliveries stay queued.")
        }
        .confirmationDialog("Clear every pending upload?", isPresented: $confirmingClear) {
            Button("Clear queue", role: .destructive) { Task { await clear() } }
        } message: {
            Text("Local history is preserved. Remote uploads already completed cannot be undone.")
        }
        .confirmationDialog("Remove this destination?", isPresented: $confirmingRemove) {
            Button("Remove destination", role: .destructive) { Task { await remove() } }
        }
        .alert("Upload error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(presentedError ?? "Unknown error") }
    }

    @ViewBuilder
    private func statusSection(_ destination: ServerUploadDestination) -> some View {
        Section("Connection") {
            LabeledContent("Type", value: destination.backend.title)
            LabeledContent("Server", value: destination.endpoint)
            if let result = coordinator.connectionResults[destinationID] {
                switch result {
                case .success:
                    Label("Connection successful", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Button("Test connection") { Task { await coordinator.testConnection(destinationID: destinationID) } }
        }
    }

    @ViewBuilder
    private func controlsSection(_ destination: ServerUploadDestination) -> some View {
        Section("Delivery") {
            Button {
                if destination.enabled {
                    Task { await disable() }
                } else {
                    showingCatchUp = true
                }
            } label: {
                LabeledContent("Destination", value: destination.enabled ? "Enabled" : "Disabled")
            }
            if destination.enabled {
                Button(destination.paused ? "Resume uploads" : "Pause uploads") {
                    Task { await pause(!destination.paused) }
                }
            }
        }
    }

    @ViewBuilder
    private func progressSection(_ destination: ServerUploadDestination) -> some View {
        let progress = coordinator.snapshot.progress(for: destination.id)
        Section("Queue") {
            LabeledContent("Pending", value: "\(progress.pendingCount)")
            LabeledContent("Failed", value: "\(progress.failedCount)")
            if let current = progress.currentSampleDate {
                LabeledContent("Sending", value: current.formatted(date: .abbreviated, time: .shortened))
            }
            if let target = progress.targetStartDate, progress.pendingCount > 0 {
                LabeledContent("Working back to", value: target.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func pause(_ paused: Bool) async { await perform { try await coordinator.setPaused(paused, destinationID: destinationID) } }
    private func disable() async { await perform { try await coordinator.setEnabled(false, destinationID: destinationID) } }
    private func retry() async { await perform { try await coordinator.retryNow(destinationID: destinationID) } }
    private func cancelBulk() async { await perform { try await coordinator.cancelRemainingUpload(destinationID: destinationID) } }
    private func clear() async { await perform { try await coordinator.clearQueue(destinationID: destinationID) } }
    private func remove() async {
        await perform { try await coordinator.removeDestination(destinationID) }
        if presentedError == nil { dismiss() }
    }
    private func perform(_ work: () async throws -> Void) async {
        do { try await work() } catch { presentedError = error.localizedDescription }
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }
}

private struct ServerUploadEditorView: View {
    @ObservedObject var coordinator: ServerUploadCoordinator
    let destination: ServerUploadDestination?
    @State private var name: String
    @State private var backend: ServerUploadBackend
    @State private var endpoint: String
    @State private var secret = ""
    @State private var transferPending = false
    @State private var includeBackfill = false
    @State private var backfillDate = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
    @State private var allHistory = false
    @State private var saving = false
    @State private var presentedError: String?
    @Environment(\.dismiss) private var dismiss

    init(coordinator: ServerUploadCoordinator, destination: ServerUploadDestination?) {
        self.coordinator = coordinator
        self.destination = destination
        _name = State(initialValue: destination?.name ?? "")
        _backend = State(initialValue: destination?.backend ?? .nightscout)
        _endpoint = State(initialValue: destination?.endpoint ?? "")
    }

    private var addressChanged: Bool {
        guard let destination else { return false }
        let normalized = try? ServerUploadEndpoint.normalize(endpoint)
        return normalized != destination.endpoint || backend != destination.backend
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Server type", selection: $backend) {
                    ForEach(ServerUploadBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Server address", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(destination == nil ? "Access token" : "New token (leave blank to keep current)", text: $secret)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Destination")
            } footer: {
                Text(backend == .nightscout
                    ? "Use a Nightscout access token with permission to create entries. It is kept in the iOS Keychain."
                    : "Use the API token configured on your GlucoScope Server. It is kept in the iOS Keychain.")
            }
            if destination == nil {
                Section {
                    Text("Only readings committed after this destination is added are queued automatically. You can choose existing history afterward.")
                        .foregroundStyle(.secondary)
                }
            } else if addressChanged {
                Section {
                    Toggle("Send pending readings to new address", isOn: $transferPending)
                    Toggle("Also upload history", isOn: $includeBackfill)
                    if includeBackfill {
                        Toggle("All available history", isOn: $allHistory)
                        if !allHistory { DatePicker("Starting", selection: $backfillDate, in: ...Date()) }
                    }
                } header: {
                    Text("Address migration")
                } footer: {
                    Text("Acknowledgements from the previous address stay linked to it. Pending transfer and selected history are deduplicated before sending.")
                }
            }
        }
        .navigationTitle(destination == nil ? "Add destination" : "Edit destination")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(
                        saving ||
                        name.trimmingCharacters(in: .whitespaces).isEmpty ||
                        endpoint.isEmpty ||
                        (destination == nil && secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
            }
        }
        .alert("Couldn’t save destination", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(presentedError ?? "Unknown error") }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if let destination {
                let history: ServerUploadHistorySelection? = includeBackfill
                    ? (allHistory ? .allAvailable : .since(backfillDate))
                    : nil
                try await coordinator.updateDestination(
                    id: destination.id,
                    name: name,
                    backend: backend,
                    endpoint: endpoint,
                    secret: secret,
                    transferPending: transferPending,
                    backfill: history
                )
            } else {
                _ = try await coordinator.addDestination(
                    name: name, backend: backend, endpoint: endpoint, secret: secret
                )
            }
            dismiss()
        } catch { presentedError = error.localizedDescription }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })
    }
}

private struct ServerUploadHistoryView: View {
    @ObservedObject var coordinator: ServerUploadCoordinator
    let destinationID: UUID
    @State private var allHistory = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Toggle("From the beginning", isOn: $allHistory)
                if !allHistory { DatePicker("Starting", selection: $startDate, in: ...Date()) }
            } footer: {
                Text("Readings send newest first. You can leave this screen, pause, or cancel the remaining history later.")
            }
        }
        .navigationTitle("Upload history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { Task { await start() } }
            }
        }
        .alert("Couldn’t queue history", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "Unknown error") }
    }

    private func start() async {
        do {
            try await coordinator.uploadHistory(allHistory ? .allAvailable : .since(startDate), destinationID: destinationID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ServerUploadCatchUpView: View {
    @ObservedObject var coordinator: ServerUploadCoordinator
    let destinationID: UUID
    let disabledAt: Date
    @State private var includeMissed = true
    @State private var startDate: Date
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(coordinator: ServerUploadCoordinator, destinationID: UUID, disabledAt: Date) {
        self.coordinator = coordinator
        self.destinationID = destinationID
        self.disabledAt = disabledAt
        _startDate = State(initialValue: disabledAt)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Upload readings missed while disabled", isOn: $includeMissed)
                if includeMissed {
                    DatePicker("Starting", selection: $startDate, in: disabledAt...Date())
                }
            } footer: {
                Text("Previously pending readings are preserved either way. New readings resume automatically after enabling.")
            }
        }
        .navigationTitle("Resume destination")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Enable") { Task { await enable() } } }
        }
        .alert("Couldn’t enable destination", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "Unknown error") }
    }

    private func enable() async {
        do {
            try await coordinator.setEnabled(
                true,
                destinationID: destinationID,
                catchUpFrom: includeMissed ? startDate : nil
            )
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ServerUploadDebugView: View {
    @ObservedObject var coordinator: ServerUploadCoordinator
    let destinationID: UUID

    private var pending: [ServerUploadDelivery] {
        coordinator.snapshot.deliveries.filter {
            $0.destinationID == destinationID && $0.state != .acknowledged
        }
    }
    private var attempts: [ServerUploadAttempt] {
        coordinator.snapshot.attempts.filter { $0.destinationID == destinationID }
    }

    var body: some View {
        List {
            Section {
                if pending.isEmpty {
                    Text("No queued readings").foregroundStyle(.secondary)
                } else {
                    ForEach(pending) { delivery in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(delivery.sampleDate.formatted(date: .abbreviated, time: .standard))
                                Spacer()
                                Text(delivery.state.rawValue.capitalized)
                                    .foregroundStyle(delivery.state == .failed ? .orange : .secondary)
                            }
                            Text("\(delivery.glucoseMGDL) mg/dL · attempt \(delivery.attemptCount) · endpoint revision \(delivery.endpointRevision)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let error = delivery.lastError {
                                Text(error).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: { Text("Queued readings (\(pending.count))") }
              footer: { Text("Every pending reading is shown regardless of age.") }

            Section {
                if attempts.isEmpty {
                    Text("No attempts in the last 30 days").foregroundStyle(.secondary)
                } else {
                    ForEach(attempts) { attempt in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(attempt.outcome.rawValue.capitalized, systemImage: icon(attempt.outcome))
                                Spacer()
                                Text(attempt.occurredAt.formatted(date: .numeric, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                            Text(attempt.message).font(.caption).foregroundStyle(.secondary)
                            Text("Endpoint revision \(attempt.endpointRevision)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: { Text("Send attempts") }
              footer: { Text("Success and failure logs are retained for 30 days. Tokens and query credentials are redacted.") }
        }
        .navigationTitle("Upload debug")
    }

    private func icon(_ outcome: ServerUploadAttemptOutcome) -> String {
        switch outcome {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        case .interrupted: return "arrow.clockwise.circle"
        }
    }
}
