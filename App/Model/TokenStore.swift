import FUMailKit
import Foundation
import Security

/// The device token and the Cloudflare Worker Google OAuth session, in the Keychain: readable once
/// this device has been unlocked after starting up, so "Rest of Today" works from Siri on a locked
/// phone; never synced to iCloud Keychain and never in a backup ("ThisDeviceOnly"). They're never
/// logged, and the secrets are never shown again.
enum TokenStore {
    private static let service = "com.h3rdus.fumail"
    private static let deviceToken = "device-token"
    private static let workerSession = "worker-session"
    private static let legacyAccessKeys = ["cf-access-client-id", "cf-access-client-secret"]

    static func load() -> String? { read(deviceToken) }
    static func save(_ token: String) throws { try write(token, deviceToken) }
    static func delete() { remove(deviceToken) }

    /// Removes any leftover Cloudflare Access Service Token entries from older versions.
    static func removeLegacyAccess() {
        legacyAccessKeys.forEach(remove)
    }

    static func loadWorkerSession() -> WorkerSession? {
        guard let raw = read(workerSession), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkerSession.self, from: data)
    }

    static func saveWorkerSession(_ session: WorkerSession?) throws {
        guard let session else {
            remove(workerSession)
            return
        }
        let data = try JSONEncoder().encode(session)
        try write(String(decoding: data, as: UTF8.self), workerSession)
    }

    private static var accessible: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    /// Items saved before 4.1 were readable only while unlocked: moves them over, once, in place.
    static func upgradeAccessibility() {
        for account in [deviceToken, workerSession] {
            SecItemUpdate(query(account) as CFDictionary, [kSecAttrAccessible as String: accessible] as CFDictionary)
        }
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
        item[kSecAttrAccessible as String] = accessible
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
