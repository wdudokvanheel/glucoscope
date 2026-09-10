import Foundation
import Security

enum LibreSessionStoreError: LocalizedError {
    case keychain(OSStatus)
    case missingSession
    case replacedSession
    case clockRepairNotAllowed

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Unable to access the saved Libre sensor session (Keychain status \(status))."
        case .missingSession: return "The saved Libre sensor session is unavailable."
        case .replacedSession: return "The saved Libre sensor pairing changed before persistence completed."
        case .clockRepairNotAllowed: return "The saved Libre clock is already valid and cannot be replaced automatically."
        }
    }
}

final class LibreSessionStore: @unchecked Sendable {
    // Different transport/coordinator instances share the same Keychain item.
    // Serialize in-process migration and identity-preserving counter saves.
    private static let lock = NSRecursiveLock()
    private let service = (Bundle.main.bundleIdentifier ?? "GlucoScope") + ".libre2"
    private let account = "active-sensor-session"

    init() {}

    func load() throws -> LibreSensorSession? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try loadUnlocked()
    }

    private func loadUnlocked() throws -> LibreSensorSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw LibreSessionStoreError.keychain(status) }
        return try JSONDecoder().decode(LibreSensorSession.self, from: data)
    }

    /// Ingestion must use this entry point, not an unsaved decoded legacy record.
    /// Diagnostics keep using load() even when the optional wear identity is damaged.
    func loadForIngestion() throws -> LibreSensorSession? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let session = try loadUnlocked() else { return nil }
        return try session.requiringPersistenceIdentity(save: saveUnlocked)
    }

    /// Migrates only the Keychain record for the exact pairing which authenticated
    /// the frame. Counter, peripheral and newer calibration differences are allowed.
    func loadForIngestion(matching expected: LibreSensorSession) throws -> LibreSensorSession {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let latest = try loadUnlocked() else { throw LibreSessionStoreError.missingSession }
        guard latest.hasSameDurablePairing(as: expected) else {
            throw LibreSessionStoreError.replacedSession
        }
        return try latest.requiringPersistenceIdentity(save: saveUnlocked)
    }

    func save(_ session: LibreSensorSession) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let durable = try session.retainingDurableIdentity(from: loadUnlocked())
        try saveUnlocked(durable)
    }

    /// Deliberate repair only. Re-read the newest pairing under the shared lock and
    /// change its unavailable clock field, preserving all operational state.
    func restoreMissingClockAnchor(
        _ anchor: LibreSensorClockAnchor,
        matching expected: LibreSensorSession
    ) throws -> LibreSensorSession {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let latest = try loadUnlocked() else { throw LibreSessionStoreError.missingSession }
        guard latest.needsClockAnchor else { throw LibreSessionStoreError.clockRepairNotAllowed }
        let repaired: LibreSensorSession
        do {
            repaired = try latest.restoringMissingClockAnchor(anchor, expectedSession: expected)
        } catch LibrePersistenceIdentityError.repairRequired {
            throw LibreSessionStoreError.replacedSession
        }
        try saveUnlocked(repaired)
        return repaired
    }

    private func saveUnlocked(_ session: LibreSensorSession) throws {
        let encoded = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: encoded,
                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary
        var status = SecItemUpdate(baseQuery as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = encoded
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LibreSessionStoreError.keychain(status) }
    }

    func clear() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LibreSessionStoreError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
