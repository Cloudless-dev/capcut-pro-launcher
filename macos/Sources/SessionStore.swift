import Foundation
import Security

enum LauncherError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum SessionStore {
    static let service = "app.capcutlauncher.macos.session"
    static let legacyAccount = "desktop-session-v1"
    static func query(_ profileID: String?) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: profileID.map { "profile-"+$0 } ?? legacyAccount] }
    static func load(profileID: String? = nil) throws -> [String: Any]? {
        var q = query(profileID); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LauncherError.message("Не удалось прочитать сохранённый вход из Keychain (\(status)).")
        }
        return result
    }
    static func save(_ value: [String: Any], profileID: String) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        let attrs: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query(profileID) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(profileID); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LauncherError.message("Не удалось сохранить вход в Keychain (\(status)).") }
    }
    static func remove(profileID: String? = nil) throws {
        let status = SecItemDelete(query(profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LauncherError.message("Не удалось удалить вход из Keychain (\(status)).")
        }
    }
}
