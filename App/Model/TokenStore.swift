import FUMailKit
import Foundation
import Security

/// The device token and the Cloudflare Access service token, in the Keychain: readable only while
/// this device is unlocked, never synced to iCloud Keychain and never in a backup ("ThisDeviceOnly").
/// They're never logged, and the secrets are never shown again.
enum TokenStore {
    private static let service = "com.h3rdus.fumail"
    private static let deviceToken = "device-token"
    private static let accessClientID = "cf-access-client-id"
    private static let accessClientSecret = "cf-access-client-secret"

    static func load() -> String? { read(deviceToken) }
    static func save(_ token: String) throws { try write(token, deviceToken) }
    static func delete() { remove(deviceToken) }

    /// The service token, when both halves are saved.
    static func loadAccess() -> ServiceToken? {
        guard let id = read(accessClientID), let secret = read(accessClientSecret) else { return nil }
        return ServiceToken(clientID: id, clientSecret: secret)
    }

    /// Saves both halves, or removes both (nil).
    static func saveAccess(_ access: ServiceToken?) throws {
        guard let access else {
            remove(accessClientID)
            remove(accessClientSecret)
            return
        }
        try write(access.clientID, accessClientID)
        try write(access.clientSecret, accessClientSecret)
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> String? {
        var search = query(account)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, _ account: String) throws {
        remove(account)
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        var status: OSStatus
        var errorDescription: String? {
            "Couldn't keep the token in the Keychain (\(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"))."
        }
    }
}
