import Foundation
import Security

enum LibreSessionStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Unable to access the saved Libre sensor session (Keychain status \(status))."
        }
    }
}

final class LibreSessionStore {
    // Different transport/coordinator instances share the same Keychain item.
    // Serialize in-process migration and identity-preserving counter saves.
    private static let lock = NSRecursiveLock()
    private let service = (Bundle.main.bundleIdentifier ?? "GlucoScope") + ".libre2"
    private let account = "active-sensor-session"

    init() {}

    func load() throws -> LibreSensorSession? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
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
        guard let session = try load() else { return nil }
        return try session.requiringPersistenceIdentity(save: save)
    }

    func save(_ session: LibreSensorSession) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let durable = try session.retainingDurableIdentity(from: load())
        let encoded = try JSONEncoder().encode(durable)
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
