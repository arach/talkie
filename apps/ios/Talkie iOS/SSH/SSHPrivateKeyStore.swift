//
//  SSHPrivateKeyStore.swift
//  Talkie iOS
//
//  Stores the SSH terminal private key in the system keychain.
//

import Foundation
import Security

struct SSHPrivateKeyStore {
    private let service = "jdi.talkie-os.ssh"
    private let account = "default-private-key"

    func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard
            status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    func save(_ privateKeyPEM: String) {
        let normalized = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            delete()
            return
        }

        let data = Data(normalized.utf8)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]

        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        SecItemDelete(updateQuery as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
