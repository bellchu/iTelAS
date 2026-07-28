import Foundation
import Security

enum KeychainStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain returned status \(status)."
        }
    }
}

struct KeychainStore {
    private let aiService = "io.situ.iTelAS.ai"
    private let aiAccount = "provider-api-key"
    private let db2Service = "io.situ.iTelAS.db2"

    func readAPIKey() throws -> String? {
        try read(service: aiService, account: aiAccount)
    }

    func writeAPIKey(_ key: String) throws {
        try write(
            key,
            service: aiService,
            account: aiAccount,
            accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    func deleteAPIKey() throws {
        try delete(service: aiService, account: aiAccount)
    }

    func readDb2Password(profileID: UUID) throws -> String? {
        try read(service: db2Service, account: profileID.uuidString.lowercased())
    }

    func writeDb2Password(_ password: String, profileID: UUID) throws {
        try write(
            password,
            service: db2Service,
            account: profileID.uuidString.lowercased(),
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
    }

    func deleteDb2Password(profileID: UUID) throws {
        try delete(service: db2Service, account: profileID.uuidString.lowercased())
    }

    private func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    private func write(
        _ value: String,
        service: String,
        account: String,
        accessibility: CFString
    ) throws {
        if value.isEmpty {
            try delete(service: service, account: account)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = accessibility
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    private func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
