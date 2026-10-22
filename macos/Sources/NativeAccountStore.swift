import Foundation
import Security

/// CapCut owns the official login flow. Only the preference changed by managed
/// launcher profiles is journalled, in Keychain, so a normal launch keeps its login.
struct NativeAccountStore {
    struct Snapshot: Codable, Equatable {
        var kind: String
        var bytes: Data?
        var preference: Any? {
            if kind == "string", let bytes { return String(data:bytes,encoding:.utf8) }
            if kind == "data" { return bytes }
            return nil
        }
    }
    struct Summary: Equatable {
        var present: Bool
        var label: String
    }
    let domain: String
    let journalAccount: String
    static let service = "app.capcutlauncher.macos.native-account"
    let key = "Account.user_info"
    init(domain:String = "com.capcut.CapCut", journalAccount:String = "managed-launch") {
        self.domain = domain; self.journalAccount = journalAccount
    }
    var query: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Self.service,kSecAttrAccount as String:journalAccount]
    }
    func snapshot() throws -> Snapshot {
        // CapCut changes this domain in another process. A long-lived launcher
        // must not validate a cached token from before an official sign-in.
        let reader = Process(); reader.executableURL = URL(fileURLWithPath:"/usr/bin/defaults")
        reader.arguments = ["export",domain,"-"]
        let output = Pipe(); reader.standardOutput = output; reader.standardError = FileHandle.nullDevice
        try reader.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); reader.waitUntilExit()
        if reader.terminationStatus != 0 {
            if data.isEmpty { return Snapshot(kind:"missing",bytes:nil) }
            throw LauncherError.message("Формат входа CapCut не поддерживается. Сохранённые данные не изменены.")
        }
        guard let preferences = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else {
            throw LauncherError.message("Формат входа CapCut не поддерживается. Сохранённые данные не изменены.")
        }
        guard let value = preferences[key] else { return Snapshot(kind:"missing",bytes:nil) }
        if let value = value as? String { return Snapshot(kind:"string",bytes:Data(value.utf8)) }
        if let value = value as? Data { return Snapshot(kind:"data",bytes:value) }
        throw LauncherError.message("Формат входа CapCut не поддерживается. Сохранённые данные не изменены.")
    }
    static func summary(_ snapshot: Snapshot) -> Summary {
        guard let bytes = snapshot.bytes,
              let decoded = Data(base64Encoded:bytes),
              let value = try? JSONSerialization.jsonObject(with:decoded) as? [String:Any],
              let uid = value["uid"] as? String, !uid.isEmpty, uid != "0",
              let token = value["xToken"] as? String, !token.isEmpty else { return Summary(present:false,label:"") }
        return Summary(present:true,label:displayLabel(value))
    }
    static func displayLabel(_ value:[String:Any]) -> String {
        let candidates = ["email","email_address","name","nick_name","screen_name"].compactMap { value[$0] as? String }
            .map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let label = candidates.first ?? "user" + (value["uid"] as? String ?? value["user_id_str"] as? String ?? "")
        guard let at = label.firstIndex(of:"@") else { return String(label.prefix(120)) }
        let local = String(label[..<at]), domain = String(label[at...])
        if local.contains("*") { return String(label.prefix(120)) }
        return String((String(local.prefix(2)) + "***" + domain).prefix(120))
    }
    func journal() throws -> Snapshot? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(q as CFDictionary,&value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let bytes = value as? Data else {
            throw LauncherError.message("Не удалось прочитать сохранённый вход CapCut из Связки ключей.")
        }
        return try JSONDecoder().decode(Snapshot.self,from:bytes)
    }
    func currentSummary() throws -> Summary { try Self.summary(journal() ?? snapshot()) }
    func verificationSession() throws -> [String:Any]? {
        let saved = try journal() ?? snapshot()
        guard Self.summary(saved).present, let bytes = saved.bytes, let decoded = Data(base64Encoded:bytes),
              let value = try JSONSerialization.jsonObject(with:decoded) as? [String:Any] else { return nil }
        return ["uid":value["uid"] as? String ?? "", "xToken":value["xToken"] as? String ?? "",
                "csrfToken":value["csrfToken"] as? String ?? "", "cookieHeader":"",
                "profileBase64":String(decoding:bytes,as:UTF8.self)]
    }
    func beginManagedLaunch() throws {
        guard try journal() == nil else { throw LauncherError.message("Сначала восстановите исходный вход CapCut после предыдущего запуска.") }
        let bytes = try JSONEncoder().encode(snapshot())
        var q = query; q[kSecValueData as String] = bytes; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else {
            throw LauncherError.message("Не удалось сохранить исходный вход CapCut в Связке ключей.")
        }
    }
    func restoreManagedLaunch() throws {
        guard let saved = try journal() else { return }
        guard ["missing","string","data"].contains(saved.kind), saved.kind == "missing" || saved.preference != nil else {
            throw LauncherError.message("Не удалось восстановить исходный вход CapCut.")
        }
        CFPreferencesSetAppValue(key as CFString,saved.preference as CFPropertyList?,domain as CFString)
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            throw LauncherError.message("Не удалось восстановить исходный вход CapCut.")
        }
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw LauncherError.message("Не удалось завершить восстановление входа CapCut.")
        }
    }
    static func isCapCutRunning() -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath:"/bin/ps"); p.arguments = ["-axo","comm="]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(decoding:data,as:UTF8.self).split(separator:"\n").contains { $0.hasSuffix("/Contents/MacOS/CapCut") }
        } catch { return true } // Never restore preferences while a process may own them.
    }
}
