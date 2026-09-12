import Foundation
import Security

protocol ServerUploadCredentialStore: Sendable {
    func save(_ secret: String, reference: String) async throws
    func secret(reference: String) async throws -> String?
    func delete(reference: String) async throws
}

actor KeychainServerUploadCredentialStore: ServerUploadCredentialStore {
    private let service = "com.bitechular.glucoscope.server-uploads"

    func save(_ secret: String, reference: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        SecItemDelete(query as CFDictionary)
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ServerUploadError.persistence("Credential could not be stored")
        }
    }

    func secret(reference: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw ServerUploadError.persistence("Credential could not be read")
        }
        return secret
    }

    func delete(reference: String) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ServerUploadError.persistence("Credential could not be removed")
        }
    }
}

actor MemoryServerUploadCredentialStore: ServerUploadCredentialStore {
    private var values: [String: String] = [:]

    func save(_ secret: String, reference: String) { values[reference] = secret }
    func secret(reference: String) -> String? { values[reference] }
    func delete(reference: String) { values.removeValue(forKey: reference) }
}
