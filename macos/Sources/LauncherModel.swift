import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LauncherModel: ObservableObject {
    @Published var document: ProfilesDocument
    @Published var destination = "profiles"
    @Published var runningProfileID: String?
    @Published var launching = false
    @Published var browserProfileID: String?
    @Published var checkingProfiles = Set<String>()
    @Published var status = "Выберите профиль, регион и запустите CapCut."
    @Published var statusIsError = false
    @Published var observedRegion = ""
    @Published var nativeVerified = false
    @Published var editingProfileID: String?
    @Published var profileEditorVisible = false
    @Published var profileNameDraft = ""
    @Published var editorError = ""
    let state: URL
    let store: ProfileStore
    let updates = UpdateCenter()
    var helper: Process?
    var browser: BrowserLogin?
    var checks: [String:Process] = [:]
    private var helperBuffer = Data()
    private var checkBuffers: [String:Data] = [:]
    private var started = false
    private var lastError = false
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.2.0" }
    var selectedProfile: LauncherProfile? { document.profiles.first(where:{$0.id == document.selectedProfileID}) }
    var runningProfile: LauncherProfile? { document.profiles.first(where:{$0.id == runningProfileID}) }
    var busy: Bool { helper?.isRunning == true || browser != nil }
    init() throws {
        let state = URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/CapCut Launcher")
        self.state = state; store = ProfileStore(root:state)
        if let existing = try store.load() { document = existing }
        else {
            var initial = ProfilesDocument(); initial.settings = store.legacySettings()
            if let legacy = try SessionStore.load() {
                var profile = LauncherProfile(id:ProfileStore.legacyID,name:"Основной",region:store.legacyRegion())
                profile.accountLabel = legacy["displayName"] as? String ?? ""; profile.authState = .saved
                try SessionStore.save(legacy,profileID:profile.id)
                let old = state.appendingPathComponent("BrowserProfile")
                let newRoot = try store.directory(profile.id)
                let new = newRoot.appendingPathComponent("BrowserProfile")
                if FileManager.default.fileExists(atPath:old.path), !FileManager.default.fileExists(atPath:new.path) {
                    try FileManager.default.createDirectory(at:newRoot,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                    try FileManager.default.moveItem(at:old,to:new)
                }
                initial.profiles = [profile]; initial.selectedProfileID = profile.id
            }
            try store.save(initial); document = initial
            if !initial.profiles.isEmpty { try SessionStore.remove() }
        }
        updates.isCapCutRunning = { [weak self] in self?.helper?.isRunning == true }
        updates.configure(automatic:document.settings.automaticUpdates)
    }
    func persist() {
        do { try store.save(document) } catch { showError(error.localizedDescription) }
    }
    func changeProfile(_ id: String) {
        document.selectedProfileID = id; persist()
        if let profile = selectedProfile, profile.authState != .signedOut,
           profile.lastVerified == nil || Date().timeIntervalSince(profile.lastVerified!) > 300 { verifySession(id) }
    }
    func updateProfile(_ id: String, _ update: (inout LauncherProfile) -> Void) {
        guard let index = document.profiles.firstIndex(where:{$0.id == id}) else { return }
        update(&document.profiles[index]); persist()
    }
    func addProfile() { editingProfileID = nil; profileNameDraft = L("Профиль \(document.profiles.count+1)"); editorError = ""; profileEditorVisible = true }
    func renameProfile(_ profile: LauncherProfile) { editingProfileID = profile.id; profileNameDraft = profile.name; editorError = ""; profileEditorVisible = true }
    func saveProfileName() {
        let name = profileNameDraft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { editorError = "Введите название от 1 до 60 символов."; return }
        if let id = editingProfileID { updateProfile(id){$0.name = name} }
        else {
            let profile = LauncherProfile(name:name); document.profiles.append(profile); document.selectedProfileID = profile.id; persist()
        }
        profileEditorVisible = false
    }
    func deleteProfile(_ profile: LauncherProfile) {
        guard profile.id != runningProfileID, profile.id != browserProfileID else { showError("Сначала закройте CapCut и окно входа этого профиля."); return }
        let alert = NSAlert(); alert.messageText = L("Удалить профиль «\(profile.name)»?")
        alert.informativeText = L("Будут удалены вход в Keychain и браузерный профиль этого слота. Локальные проекты CapCut сохранятся.")
        alert.addButton(withTitle:L("Удалить профиль")); alert.addButton(withTitle:L("Отмена")); alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            checks[profile.id]?.terminate(); checks[profile.id] = nil; checkingProfiles.remove(profile.id)
            let directory = try store.directory(profile.id)
            if FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.removeItem(at:directory) }
            try SessionStore.remove(profileID:profile.id)
            document.profiles.removeAll(where:{$0.id == profile.id})
            if document.selectedProfileID == profile.id { document.selectedProfileID = document.profiles.first?.id }
            persist(); status = "Профиль удалён. Проекты CapCut сохранены."; statusIsError = false
        } catch { showError(error.localizedDescription) }
    }
    @discardableResult func setRegion(_ text: String, profileID: String) -> Bool {
        guard runningProfileID != profileID else { return false }
        do {
            let code = try ProfileStore.countryCode(text)
            if document.profiles.first(where:{$0.id == profileID})?.region != code {
                updateProfile(profileID){$0.region = code}
            }
            return true
        }
        catch { showError(error.localizedDescription); return false }
    }
    func setAutomaticUpdates(_ value: Bool) { document.settings.automaticUpdates = value; persist(); updates.configure(automatic:value) }
    func setAutoStart(_ value: Bool) { document.settings.autoStartAfterAuth = value; persist() }
    func appVersion() -> String { Bundle(path:document.settings.appPath)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "9.6.0" }
    func signIn(_ id: String) {
        guard helper?.isRunning != true else { showError("Сначала закройте CapCut, чтобы сменить или обновить вход."); return }
        if let browser {
            if browserProfileID != id { showError("Сначала завершите вход в открытом браузерном профиле.") }
            browser.activate(); return
        }
        guard document.profiles.contains(where:{$0.id == id}) else { return }
        do {
            let root = try store.directory(id)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let b = BrowserLogin(version:appVersion(),profileID:id,profileRoot:root); browser = b; browserProfileID = id
            b.onStatus = { [weak self] text in self?.status = text; self?.statusIsError = false }
            b.onSuccess = { [weak self] session in
                guard let self else { return }
                self.updateProfile(id){$0.accountLabel = session["displayName"] as? String ?? ""; $0.authState = .valid; $0.lastVerified = Date()}
                self.status = "Вход сохранён в выбранном профиле."; self.statusIsError = false
                if self.document.settings.autoStartAfterAuth && self.document.selectedProfileID == id { self.startCapCut(id) }
            }
            b.onClose = { [weak self] in self?.browser = nil; self?.browserProfileID = nil }
            b.show()
        } catch { showError(error.localizedDescription) }
    }
    func helperExecutable() -> URL { Bundle.main.resourceURL!.appendingPathComponent("Helper/launcher-helper") }
    func verifySession(_ id: String) {
        guard checks[id] == nil, browserProfileID != id, runningProfileID != id,
            let profile = document.profiles.first(where:{$0.id == id}), profile.authState != .signedOut else { return }
        do {
            guard let session = try SessionStore.load(profileID:id) else { updateProfile(id){$0.authState = .signedOut}; return }
            let process = Process(); process.executableURL = helperExecutable()
            let output = Pipe(), input = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            checks[id] = process; checkingProfiles.insert(id); checkBuffers[id] = Data()
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                if bytes.isEmpty { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.consumeCheck(bytes,id:id) }
            }
            process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.checkingProfiles.remove(id); self?.checks[id] = nil } }
            try process.run()
            var data = try JSONSerialization.data(withJSONObject:["action":"verify","session":session,"userAgent":"CapCut/\(appVersion()) (macOS)"])
            data.append(10); input.fileHandleForWriting.write(data); try input.fileHandleForWriting.close()
        } catch { checks[id] = nil; checkingProfiles.remove(id); showError(error.localizedDescription) }
    }
    func consumeCheck(_ bytes: Data, id: String) {
        checkBuffers[id,default:Data()].append(bytes)
        while let end = checkBuffers[id]?.firstIndex(of:10) {
            let line = checkBuffers[id]!.prefix(upTo:end); checkBuffers[id]!.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            if value["kind"] as? String == "session_valid" { markValid(id) }
            else if value["kind"] as? String == "error" { handleError(value,profileID:id) }
        }
    }
    func startCapCut(_ id: String) {
        if helper?.isRunning == true {
            if runningProfileID == id { NSWorkspace.shared.open(URL(fileURLWithPath:document.settings.appPath)) }
            else { showError("Сначала закройте CapCut, чтобы переключить профиль.") }; return
        }
        guard let profile = document.profiles.first(where:{$0.id == id}) else { return }
        do {
            guard let session = try SessionStore.load(profileID:id) else { signIn(id); return }
            if profile.authState == .expired || profile.authState == .needsLogin { signIn(id); return }
            _ = try ProfileStore.countryCode(profile.region)
            checks[id]?.terminate(); checks[id] = nil; checkingProfiles.remove(id)
            let process = Process(); process.executableURL = helperExecutable()
            let input = Pipe(), output = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            helperBuffer = Data(); started = false; lastError = false; launching = true; observedRegion = ""; nativeVerified = false
            helper = process; runningProfileID = id; statusIsError = false; status = "Проверяю вход и запускаю CapCut…"
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                if bytes.isEmpty { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.consumeHelper(bytes,profileID:id) }
            }
            process.terminationHandler = { [weak self] _ in Task { @MainActor in
                guard let self else { return }; self.helper = nil; self.runningProfileID = nil; self.launching = false
                if self.started && !self.lastError { self.status = "CapCut закрыт. Можно выбрать другой профиль или регион."; self.statusIsError = false }
            } }
            try process.run()
            let config: [String:Any] = ["region":profile.region,"appPath":document.settings.appPath,"dataRoot":document.settings.dataRoot,
                "stateRoot":state.path,"resources":Bundle.main.resourceURL!.appendingPathComponent("Runtime").path,
                "showProUI":true,"requireSession":true,"session":session]
            var data = try JSONSerialization.data(withJSONObject:config); data.append(10)
            input.fileHandleForWriting.write(data); try input.fileHandleForWriting.close()
        } catch { helper = nil; runningProfileID = nil; launching = false; showError(error.localizedDescription) }
    }
    func consumeHelper(_ bytes: Data, profileID: String) {
        helperBuffer.append(bytes)
        while let end = helperBuffer.firstIndex(of:10) {
            let line = helperBuffer.prefix(upTo:end); helperBuffer.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with:line) as? [String:Any], let kind = value["kind"] as? String else { continue }
            switch kind {
            case "started": started = true; launching = false; status = "CapCut \(value["version"] ?? "") запущен."; statusIsError = false
            case "session_checked": if value["present"] as? Bool == true { markValid(profileID) }
            case "catalog_request": if let r = value["region"] as? String { observedRegion = r }
            case "account_verified":
                nativeVerified = value["success"] as? Bool == true
                if nativeVerified { markValid(profileID) }
                else if value["expired"] as? Bool == true {
                    updateProfile(profileID){$0.authState = .expired}
                    status = "Сессия профиля истекла. Закройте CapCut и войдите заново."; statusIsError = true
                }
            case "error": lastError = true; handleError(value,profileID:profileID)
            default: break
            }
        }
    }
    func markValid(_ id: String) {
        guard let p = document.profiles.first(where:{$0.id == id}) else { return }
        if p.authState != .valid || Date().timeIntervalSince(p.lastVerified ?? .distantPast) > 60 {
            updateProfile(id){$0.authState = .valid; $0.lastVerified = Date()}
        }
    }
    func handleError(_ value: [String:Any], profileID: String) {
        let code = value["code"] as? String ?? ""
        if code == "session_expired" { updateProfile(profileID){$0.authState = .expired} }
        else if code == "auth_rejected" { updateProfile(profileID){$0.authState = .needsLogin} }
        else if code == "auth_missing" { updateProfile(profileID){$0.authState = .signedOut} }
        status = value["message"] as? String ?? "Не удалось выполнить действие."; statusIsError = true
    }
    func chooseApp() {
        guard !busy else { return }; let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { document.settings.appPath = url.path; persist() }
    }
    func chooseData() {
        guard !busy else { return }; let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = L("Выберите папку User Data приложения CapCut")
        if panel.runModal() == .OK, let url = panel.url { document.settings.dataRoot = url.path; persist() }
    }
    func openProjects() { NSWorkspace.shared.open(URL(fileURLWithPath:document.settings.dataRoot).appendingPathComponent("Projects/com.lveditor.draft")) }
    func showError(_ text: String) { status = text; statusIsError = true }
}
