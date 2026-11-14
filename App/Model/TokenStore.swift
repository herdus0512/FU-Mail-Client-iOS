import Foundation
import Security

/// The device token, in the Keychain: readable only while this device is unlocked, never synced to
/// iCloud Keychain and never in a backup ("ThisDeviceOnly"). It's never logged or shown again.
enum TokenStore {
    private static let service = "com.h3rdus.fumail"
    private static let account = "device-token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        var status: OSStatus
        var errorDescription: String? {
            "Couldn't keep the token in the Keychain (\(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"))."
        }
    }
}
