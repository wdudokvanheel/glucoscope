import Foundation
import Combine

@MainActor
final class ServerUploadCoordinator: ObservableObject {
    @Published private(set) var snapshot = ServerUploadSnapshot(
        destinations: [], deliveries: [], attempts: []
    )
    @Published private(set) var connectionResults: [UUID: Result<Int, ServerUploadError>] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var isLoaded = false

    var pendingReadingCount: Int { snapshot.pendingCount }
    var hasPendingUploads: Bool { pendingReadingCount > 0 }

    private let readingStore: ReadingStore
    private let uploadStore: ServerUploadStore
    private let credentialStore: ServerUploadCredentialStore
    private let transport: ServerUploadTransport
    private var standaloneActive = false
    private var isLoading = false
    private var commitTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var retryWakeTask: Task<Void, Never>?

    init(
        readingStore: ReadingStore,
        storageURL: URL,
        credentialStore: ServerUploadCredentialStore = KeychainServerUploadCredentialStore(),
        transport: ServerUploadTransport = URLSessionServerUploadTransport()
    ) {
        self.readingStore = readingStore
        self.uploadStore = ServerUploadStore(fileURL: storageURL)
        self.credentialStore = credentialStore
        self.transport = transport
    }

    deinit {
        commitTask?.cancel()
        drainTask?.cancel()
        retryWakeTask?.cancel()
    }

    func load() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await uploadStore.load()
            // Subscribe before the snapshot reconciliation so a commit racing
            // with startup is either in that snapshot or delivered by this stream.
            let commits = await readingStore.commitStream()
            try await reconcileCommittedReadings()
            await publishSnapshot()
            isLoaded = true
            commitTask = Task { [weak self] in
                for await _ in commits {
                    guard !Task.isCancelled else { return }
                    await self?.committedReadingsChanged()
                }
            }
        } catch {
            lastError = display(error)
        }
    }

    /// Mode boundary: setting false does not cancel a running URL request. Its
    /// outcome is recorded, and the drain loop stops before claiming another row.
    func setStandaloneActive(_ active: Bool) async {
        standaloneActive = active
        if active {
            do { try await reconcileCommittedReadings() } catch { lastError = display(error) }
            await publishSnapshot()
            scheduleDrain()
        } else {
            retryWakeTask?.cancel()
            retryWakeTask = nil
        }
    }

    func refresh() async {
        if !isLoaded { await load() }
        guard isLoaded else { return }
        do {
            try await uploadStore.performMaintenance()
            try await reconcileCommittedReadings()
        } catch { lastError = display(error) }
        await publishSnapshot()
        if standaloneActive { scheduleDrain() }
    }

    func addDestination(
        name: String,
        backend: ServerUploadBackend,
        endpoint: String,
        secret: String
    ) async throws -> UUID {
        let secret = normalizedSecret(secret, backend: backend)
        guard !secret.isEmpty else { throw ServerUploadError.authentication }
        let reference = UUID().uuidString
        try await credentialStore.save(secret, reference: reference)
        do {
            let destination = try await uploadStore.addDestination(
                name: name,
                backend: backend,
                endpoint: endpoint,
                credentialReference: reference
            )
            try await reconcileCommittedReadings()
            await publishSnapshot()
            scheduleDrain()
            return destination.id
        } catch {
            try? await credentialStore.delete(reference: reference)
            throw error
        }
    }

    func updateDestination(
        id: UUID,
        name: String,
        backend: ServerUploadBackend,
        endpoint: String,
        secret: String,
        transferPending: Bool,
        backfill: ServerUploadHistorySelection?
    ) async throws {
        guard let old = snapshot.destinations.first(where: { $0.id == id }) else {
            throw ServerUploadError.destinationNotFound
        }
        let normalized = try ServerUploadEndpoint.normalize(endpoint)
        let cleanedSecret = normalizedSecret(secret, backend: backend)
        let replacesCredential = !cleanedSecret.isEmpty
        let replacementReference = replacesCredential ? UUID().uuidString : old.credentialReference
        if replacesCredential {
            try await credentialStore.save(cleanedSecret, reference: replacementReference)
        }
        do {
            if normalized == old.endpoint && backend == old.backend {
                try await uploadStore.updateCredentialReference(
                    destinationID: id,
                    reference: replacementReference,
                    name: name
                )
            } else {
                let readings = try await readingStore.snapshot().readings
                try await uploadStore.migrateDestination(
                    destinationID: id,
                    name: name,
                    backend: backend,
                    endpoint: normalized,
                    credentialReference: replacementReference,
                    transferPending: transferPending,
                    backfill: backfill,
                    readings: readings
                )
            }
            if replacesCredential {
                try? await credentialStore.delete(reference: old.credentialReference)
            }
            await publishSnapshot()
            scheduleDrain()
        } catch {
            if replacesCredential {
                try? await credentialStore.delete(reference: replacementReference)
            }
            throw error
        }
    }

    func removeDestination(_ id: UUID) async throws {
        let reference = snapshot.destinations.first(where: { $0.id == id })?.credentialReference
        try await uploadStore.removeDestination(id)
        if let reference { try? await credentialStore.delete(reference: reference) }
        connectionResults[id] = nil
        await publishSnapshot()
    }

    func setEnabled(_ enabled: Bool, destinationID: UUID, catchUpFrom: Date? = nil) async throws {
        let readings = try await readingStore.snapshot().readings
        try await uploadStore.setEnabled(
            enabled,
            destinationID: destinationID,
            catchUpFrom: catchUpFrom,
            readings: readings
        )
        await publishSnapshot()
        scheduleDrain()
    }

    func setPaused(_ paused: Bool, destinationID: UUID) async throws {
        try await uploadStore.setPaused(paused, destinationID: destinationID)
        await publishSnapshot()
        scheduleDrain()
    }

    func uploadHistory(_ selection: ServerUploadHistorySelection, destinationID: UUID) async throws {
        let readings = try await readingStore.snapshot().readings
        try await uploadStore.enqueueHistory(
            destinationID: destinationID,
            selection: selection,
            readings: readings
        )
        await publishSnapshot()
        scheduleDrain()
    }

    func retryNow(destinationID: UUID) async throws {
        try await uploadStore.retryFailures(destinationID: destinationID)
        await publishSnapshot()
        scheduleDrain()
    }

    func cancelRemainingUpload(destinationID: UUID) async throws {
        try await uploadStore.cancelRemainingBulk(destinationID: destinationID)
        await publishSnapshot()
    }

    func clearQueue(destinationID: UUID) async throws {
        try await uploadStore.clearQueue(destinationID: destinationID)
        await publishSnapshot()
    }

    func testConnection(destinationID: UUID) async {
        guard let destination = snapshot.destinations.first(where: { $0.id == destinationID }) else {
            connectionResults[destinationID] = .failure(.destinationNotFound)
            return
        }
        do {
            let secret = try await credentialStore.secret(reference: destination.credentialReference)
            connectionResults[destinationID] = await transport.test(destination: destination, secret: secret)
        } catch {
            connectionResults[destinationID] = .failure(.persistence("Credential unavailable"))
        }
    }

    private func committedReadingsChanged() async {
        do {
            try await reconcileCommittedReadings()
            await publishSnapshot()
            scheduleDrain()
        } catch {
            lastError = display(error)
        }
    }

    private func reconcileCommittedReadings() async throws {
        let readings = try await readingStore.snapshot().readings
        try await uploadStore.reconcileNewReadings(readings)
    }

    private func publishSnapshot() async {
        snapshot = await uploadStore.snapshot()
    }

    private func scheduleDrain() {
        guard standaloneActive, drainTask == nil else { return }
        retryWakeTask?.cancel()
        retryWakeTask = nil
        drainTask = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        defer {
            drainTask = nil
            scheduleRetryWakeIfNeeded()
        }
        while standaloneActive, !Task.isCancelled {
            let current = await uploadStore.snapshot()
            let destinations = current.destinations.filter { $0.enabled && !$0.paused }
            var claimed: (ServerUploadDestination, ServerUploadDelivery)?
            for destination in destinations {
                if let delivery = try? await uploadStore.nextDelivery(destinationID: destination.id) {
                    claimed = (destination, delivery)
                    break
                }
            }
            guard let (destination, delivery) = claimed else { return }
            // Publish the claimed row before awaiting the network so the queue UI
            // can show the sample currently in flight.
            await publishSnapshot()
            let secret: String?
            do {
                secret = try await credentialStore.secret(reference: destination.credentialReference)
            } catch {
                try? await uploadStore.complete(
                    deliveryID: delivery.id,
                    result: .failure(.persistence("Credential unavailable"))
                )
                await publishSnapshot()
                continue
            }
            let result = await transport.send(delivery, to: destination, secret: secret)
            try? await uploadStore.complete(
                deliveryID: delivery.id,
                result: result,
                secrets: secret.map { [$0] } ?? []
            )
            await publishSnapshot()
            // Re-read mode after recording the in-flight outcome. Viewer mode or
            // a pause/disable action prevents the next claim.
        }
    }

    private func scheduleRetryWakeIfNeeded() {
        guard standaloneActive, snapshot.pendingCount > 0 else { return }
        retryWakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.scheduleDrain()
        }
    }

    private func display(_ error: Error) -> String {
        ServerUploadRedactor.message(error.localizedDescription)
    }

    private func normalizedSecret(_ secret: String, backend: ServerUploadBackend) -> String {
        var value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if backend == .nightscout, value.lowercased().hasPrefix("token=") {
            value.removeFirst("token=".count)
        }
        return value
    }
}
