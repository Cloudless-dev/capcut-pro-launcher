import Foundation

enum ProfileAuthState: String, Codable {
    case signedOut, saved, valid, expired, needsLogin
    var title: String {
        switch self {
        case .signedOut: return "Нужен вход"
        case .saved: return "Вход сохранён"
        case .valid: return "Вход подтверждён"
        case .expired: return "Сессия истекла"
        case .needsLogin: return "Войдите заново"
        }
    }
}
struct LauncherProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var region: String
    var accountLabel: String = ""
    var authState: ProfileAuthState = .signedOut
    var lastVerified: Date?
    // Optional for compatibility with profiles created before automatic sign-in.
    var automaticSignIn: Bool?
    init(id: String = UUID().uuidString, name: String, region: String = "US") {
        self.id = id; self.name = name; self.region = region
    }
}
struct LauncherSettings: Codable, Equatable {
    var appPath = "/Applications/CapCut.app"
    var dataRoot = NSHomeDirectory()+"/Movies/CapCut/User Data"
    var automaticUpdates = false
    var autoStartAfterAuth = true
}
struct ProfilesDocument: Codable, Equatable {
    var schemaVersion = 1
    var selectedProfileID: String?
    var profiles: [LauncherProfile] = []
    var settings = LauncherSettings()
}
struct ProfileStore {
    let root: URL
    var url: URL { root.appendingPathComponent("profiles.json") }
    static let legacyID = "00000000-0000-4000-8000-000000000001"
    func load() throws -> ProfilesDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let document = try JSONDecoder().decode(ProfilesDocument.self, from: Data(contentsOf: url))
        try validate(document); return document
    }
    func save(_ document: ProfilesDocument) throws {
        try validate(document)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: url.path)
    }
    func validate(_ document: ProfilesDocument) throws {
        guard document.schemaVersion == 1 else { throw LauncherError.message("Формат профилей этой версии не поддерживается.") }
        let ids = document.profiles.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ UUID(uuidString:$0) != nil }),
              document.selectedProfileID == nil || ids.contains(document.selectedProfileID!) else {
            throw LauncherError.message("Не удалось прочитать список профилей. Сохранённые данные не изменены.")
        }
    }
    func directory(_ id: String) throws -> URL {
        guard UUID(uuidString:id) != nil else { throw LauncherError.message("Недопустимый идентификатор профиля.") }
        return root.appendingPathComponent("Profiles").appendingPathComponent(id)
    }
    func legacySettings() -> LauncherSettings {
        var result = LauncherSettings()
        if let data = try? Data(contentsOf:root.appendingPathComponent("settings.json")),
           let old = try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
            result.appPath = old["appPath"] as? String ?? result.appPath
            result.dataRoot = old["dataRoot"] as? String ?? result.dataRoot
        }
        return result
    }
    func legacyRegion() -> String {
        guard let data = try? Data(contentsOf:root.appendingPathComponent("settings.json")),
            let old = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let value = old["region"] as? String else { return "US" }
        return (try? Self.countryCode(value)) ?? "US"
    }
    static func countryCode(_ value: String) throws -> String {
        let code = value.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
            .components(separatedBy:CharacterSet.whitespaces.union(CharacterSet(charactersIn:"—-"))).first ?? ""
        guard code.range(of:"^[A-Z]{2}$",options:.regularExpression) != nil,
            Locale.Region.isoRegions.contains(where:{$0.identifier == code}) else {
            throw LauncherError.message("Введите двухбуквенный код страны, например US, TR или NL.")
        }
        return code
    }
}
