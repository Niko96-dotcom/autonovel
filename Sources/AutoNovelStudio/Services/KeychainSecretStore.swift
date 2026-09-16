import Foundation
import Security

protocol CredentialSecretStore {
    func read() throws -> String?
    func write(_ secret: String) throws
    func delete() throws
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

struct KeychainSecretStore: CredentialSecretStore, Equatable, Sendable {
    static let sentinel = "keychain:org.nousresearch.autonovelstudio"

    let service: String
    let account: String

    static func managedAPIKey(projectURL: URL) -> KeychainSecretStore {
        KeychainSecretStore(
            service: "org.nousresearch.autonovelstudio.api-key",
            account: projectURL.standardizedFileURL.path
        )
    }

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ secret: String) throws {
        let data = Data(secret.utf8)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                ] as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ] as CFDictionary
        )
        if status == errSecItemNotFound || status == errSecSuccess { return }
        throw KeychainError(status: status)
    }
}

final class MemorySecretStore: CredentialSecretStore {
    private var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func read() throws -> String? { value }

    func write(_ secret: String) throws {
        value = secret
    }

    func delete() throws {
        value = nil
    }
}
