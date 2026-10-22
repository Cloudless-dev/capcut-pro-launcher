import Foundation
import Security

struct LoginCredentials: Codable {
    let email: String
    let password: String
    static func validated(email: String, password: String) throws -> LoginCredentials {
        let address = email.trimmingCharacters(in:.whitespacesAndNewlines)
        guard address.range(of:"^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$",options:.regularExpression) != nil else {
            throw LauncherError.message("Введите корректную почту CapCut.")
        }
        guard !password.isEmpty, password.utf8.count <= 4096 else {
            throw LauncherError.message("Введите пароль CapCut.")
        }
        return LoginCredentials(email:address,password:password)
    }
}

enum CredentialStore {
    static let service = "app.capcutlauncher.macos.credentials"
    static func query(_ profileID: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"profile-"+profileID]
    }
    static func load(_ profileID: String) throws -> LoginCredentials? {
        var q = query(profileID); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw LauncherError.message("Не удалось прочитать пароль из Связки ключей.")
        }
        return try JSONDecoder().decode(LoginCredentials.self,from:data)
    }
    static func save(_ value: LoginCredentials, profileID: String) throws {
        let data = try JSONEncoder().encode(value)
        var status = SecItemUpdate(query(profileID) as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(profileID); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(q as CFDictionary,nil)
        }
        guard status == errSecSuccess else { throw LauncherError.message("Не удалось сохранить пароль в Связке ключей.") }
    }
    static func remove(_ profileID: String) throws {
        let status = SecItemDelete(query(profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LauncherError.message("Не удалось удалить пароль из Связки ключей.")
        }
    }
}
