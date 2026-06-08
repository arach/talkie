//
//  BridgePrivateKeyStore.swift
//  Talkie iOS
//
//  Stores per-paired-Mac bridge ECDH private keys in the system keychain.
//  Keyed by PairedMac.id. Not shared with app extensions (no access group),
//  and not synced/backed up (`...ThisDeviceOnly`). Replaces the previous
//  plaintext storage in the App-Group config.json / UserDefaults.
//

import Foundation
import Security

struct BridgePrivateKeyStore {
    private let service = "jdi.talkie-os.bridge"

    /// Load the base64-encoded private key for a paired Mac.
    func load(id: String) -> String? {
        guard !id.isEmpty else { return nil }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard
            status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    /// Store (or update) the base64-encoded private key for a paired Mac.
    func save(id: String, privateKeyBase64: String) {
        guard !id.isEmpty else { return }

        let normalized = privateKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            delete(id: id)
            return
        }

        let data = Data(normalized.utf8)
        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id
        ]
        let updateAttributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        SecItemDelete(updateQuery as CFDictionary)
        let addAttributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]
        SecItemAdd(addAttributes as CFDictionary, nil)
    }

    /// Remove the stored private key for a paired Mac.
    func delete(id: String) {
        guard !id.isEmpty else { return }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id
        ]

        SecItemDelete(query as CFDictionary)
    }
}
