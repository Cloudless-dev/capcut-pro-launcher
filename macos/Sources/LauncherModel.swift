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
    @Published var profileEmailDraft = ""
    @Published var profilePasswordDraft = ""
    @Published var profileAutomaticDraft = true
    @Published var profileHasPassword = false
    @Published var profileMethodDraft: ProfileSignInMethod = .launcher
    @Published var profileRegionDraft = "US"
    @Published var editorError = ""
    let state: URL
    let store: ProfileStore
    let nativeAccounts: NativeAccountStore
    var capcutIsRunning: () -> Bool = NativeAccountStore.isCapCutRunning
    let updates = UpdateCenter()
    let projects = ProjectManager()
    var helper: Process?
    var browser: BrowserLogin?
    var checks: [String:Process] = [:]
    private var helperBuffer = Data()
    private var checkBuffers: [String:Data] = [:]
    private var started = false
    private var lastError = false
    private var verificationTimer: Timer?
    private var pendingRecovery = Set<String>()
    private var recoveryBlocked = Set<String>()
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.2.0" }
    var selectedProfile: LauncherProfile? { document.profiles.first(where:{$0.id == document.selectedProfileID}) }
    var editorNeedsSignIn: Bool {
        profileMethodDraft != .capcut && profileAutomaticDraft && (editingProfileID == nil || !profilePasswordDraft.isEmpty || document.profiles.first(where:{$0.id == editingProfileID})?.authState != .valid)
    }
    var runningProfile: LauncherProfile? { document.profiles.first(where:{$0.id == runningProfileID}) }
    var busy: Bool { helper?.isRunning == true || browser != nil }
    init(stateRoot: URL? = nil, nativeAccounts: NativeAccountStore = NativeAccountStore()) throws {
        let state = stateRoot ?? URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/CapCut Launcher")
        self.state = state; store = ProfileStore(root:state); self.nativeAccounts = nativeAccounts
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
        if !capcutIsRunning() { try nativeAccounts.restoreManagedLaunch() }
        updates.isCapCutRunning = { [weak self] in self?.helper?.isRunning == true || self?.capcutIsRunning() == true }
        updates.configure(automatic:document.settings.automaticUpdates)
        verificationTimer = Timer.scheduledTimer(withTimeInterval:300,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.busy, let p = self.selectedProfile, p.authState == .valid || p.authState == .saved else { return }
                self.verifySession(p.id)
            }
        }
    }
    func persist() {
        do { try store.save(document) } catch { showError(error.localizedDescription) }
    }
    func changeProfile(_ id: String) {
        document.selectedProfileID = id; persist()
        if selectedProfile?.usesCapCutAccount == true { verifySession(id); return }
        if let profile = selectedProfile, profile.authState == .signedOut { recoverSession(profile.id); return }
        if let profile = selectedProfile, profile.authState != .signedOut,
           profile.lastVerified == nil || Date().timeIntervalSince(profile.lastVerified!) > 300 { verifySession(id) }
    }
    func checkSelectedSession() {
        guard let profile = selectedProfile else { return }
        if profile.usesCapCutAccount { verifySession(profile.id); return }
        if profile.authState == .signedOut { recoverSession(profile.id) }
        else { verifySession(profile.id) }
    }
    func checkSelectedProfile(_ id: String) {
        guard let p = document.profiles.first(where:{$0.id == id}) else { return }
        if p.usesCapCutAccount || p.authState != .signedOut { verifySession(id) }
        else { recoverSession(id) }
    }
    func updateProfile(_ id: String, _ update: (inout LauncherProfile) -> Void) {
        guard let index = document.profiles.firstIndex(where:{$0.id == id}) else { return }
        update(&document.profiles[index]); persist()
    }
    func addProfile() {
        editingProfileID = nil; profileNameDraft = L("Профиль \(document.profiles.count+1)")
        profileEmailDraft = ""; profilePasswordDraft = ""; profileHasPassword = false; profileAutomaticDraft = true
        profileMethodDraft = .launcher; profileRegionDraft = "US"
        editorError = ""; profileEditorVisible = true
    }
    func renameProfile(_ profile: LauncherProfile) {
        guard !busy else { return }
        do {
            let credentials = profile.automaticSignIn == true ? try CredentialStore.load(profile.id) : nil
            editingProfileID = profile.id; profileNameDraft = profile.name; profileEmailDraft = credentials?.email ?? ""
            profilePasswordDraft = ""; profileHasPassword = credentials != nil; profileAutomaticDraft = profile.automaticSignIn == true
            profileMethodDraft = profile.usesCapCutAccount ? .capcut : .launcher; profileRegionDraft = profile.region
            editorError = ""; profileEditorVisible = true
        } catch { showError(error.localizedDescription) }
    }
    func dismissProfileEditor() { profilePasswordDraft = ""; profileEmailDraft = ""; profileEditorVisible = false }
    func saveProfileName() {
        let name = profileNameDraft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { editorError = "Введите название от 1 до 60 символов."; return }
        do {
            let region = try ProfileStore.countryCode(profileRegionDraft)
            let id = editingProfileID ?? UUID().uuidString
            let priorCredentials = try CredentialStore.load(id)
            var next = document
            let existing = next.profiles.firstIndex(where:{$0.id == id})
            var profile = existing.map { next.profiles[$0] } ?? LauncherProfile(id:id,name:name)
            let changedMethod = profile.usesCapCutAccount != (profileMethodDraft == .capcut)
            var changedCredentials = false
            if profileMethodDraft != .capcut && profileAutomaticDraft {
                let previous = profileHasPassword ? priorCredentials : nil
                if profilePasswordDraft.isEmpty, let previous {
                    guard profileEmailDraft.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == previous.email.lowercased() else {
                        editorError = "При смене почты введите пароль заново."; return
                    }
                } else {
                    let credentials = try LoginCredentials.validated(email:profileEmailDraft,password:profilePasswordDraft)
                    try CredentialStore.save(credentials,profileID:id); changedCredentials = true
                }
            }
            profile.name = name; profile.region = region; profile.signInMethod = profileMethodDraft
            profile.automaticSignIn = profileMethodDraft != .capcut && profileAutomaticDraft
            if changedCredentials || changedMethod { profile.authState = .signedOut; profile.lastVerified = nil; profile.accountLabel = "" }
            if profile.usesCapCutAccount {
                let current = try nativeAccounts.currentSummary()
                profile.accountLabel = current.label; profile.authState = current.present ? .saved : .signedOut; profile.lastVerified = nil
            }
            if let existing { next.profiles[existing] = profile } else { next.profiles.append(profile); next.selectedProfileID = id }
            do { try store.save(next) } catch {
                if changedCredentials {
                    if let priorCredentials { try? CredentialStore.save(priorCredentials,profileID:id) }
                    else { try? CredentialStore.remove(id) }
                }
                throw error
            }
            document = next
            if profile.automaticSignIn != true { try CredentialStore.remove(id) }
            if changedMethod { try SessionStore.remove(profileID:id) }
            if changedCredentials { recoveryBlocked.remove(id) }
            dismissProfileEditor()
            if profile.automaticSignIn == true && (changedCredentials || profile.authState != .valid) { signIn(id,launchAfter:false) }
            else if profile.usesCapCutAccount { status = "Профиль использует текущий вход приложения CapCut."; statusIsError = false; verifySession(id) }
        } catch { editorError = error.localizedDescription }
    }
    func deleteProfile(_ profile: LauncherProfile) {
        guard profile.id != runningProfileID, profile.id != browserProfileID else { showError("Сначала закройте CapCut и окно входа этого профиля."); return }
        Task {
            let response = await AppDialogs.shared.choose(title:"Удалить профиль «\(profile.name)»?",
                message:profile.usesCapCutAccount ? "Будет удалён только профиль лаунчера. Вход в приложении CapCut и локальные проекты сохранятся." : "Будут удалены вход в Keychain и браузерный профиль этого слота. Локальные проекты CapCut сохранятся.",
                symbol:"person.crop.circle.badge.minus",actions:[AppDialogAction(title:"Отмена",cancel:true),AppDialogAction(title:"Удалить профиль",destructive:true)])
            guard response == 1, document.profiles.contains(where:{$0.id == profile.id}) else { return }
            guard profile.id != runningProfileID, profile.id != browserProfileID else { showError("Сначала закройте CapCut и окно входа этого профиля."); return }
        do {
            checks[profile.id]?.terminate(); checks[profile.id] = nil; checkingProfiles.remove(profile.id)
            let directory = try store.directory(profile.id)
            if FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.removeItem(at:directory) }
            try SessionStore.remove(profileID:profile.id)
            try CredentialStore.remove(profile.id)
            pendingRecovery.remove(profile.id); recoveryBlocked.remove(profile.id)
            document.profiles.removeAll(where:{$0.id == profile.id})
            if document.selectedProfileID == profile.id { document.selectedProfileID = document.profiles.first?.id }
            persist(); status = "Профиль удалён. Проекты CapCut сохранены."; statusIsError = false
        } catch { showError(error.localizedDescription) }
        }
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
    func signIn(_ id: String, manualBrowser: Bool = false, launchAfter: Bool? = nil, recovery: Bool = false) {
        if document.profiles.first(where:{$0.id == id})?.usesCapCutAccount == true { startCapCut(id); return }
        guard helper?.isRunning != true else { showError("Сначала закройте CapCut, чтобы сменить или обновить вход."); return }
        if let browser {
            if browserProfileID != id { showError("Сначала завершите вход в открытом браузерном профиле.") }
            browser.activate(); return
        }
        guard document.profiles.contains(where:{$0.id == id}) else { return }
        do {
            let automatic = !manualBrowser && document.profiles.first(where:{$0.id == id})?.automaticSignIn == true
            let credentials = automatic ? try CredentialStore.load(id) : nil
            if automatic && credentials == nil { showError("Откройте настройки профиля и сохраните почту и пароль."); return }
            if !recovery { recoveryBlocked.remove(id) }
            recoveryBlocked.insert(id)
            let root = try store.directory(id)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let b = BrowserLogin(version:appVersion(),profileID:id,profileRoot:root,credentials:credentials); browser = b; browserProfileID = id
            b.onStatus = { [weak self] text in self?.status = text; self?.statusIsError = false }
            b.onSuccess = { [weak self] session in
                guard let self else { return }
                self.updateProfile(id){$0.accountLabel = session["displayName"] as? String ?? ""; $0.authState = .valid; $0.lastVerified = Date()}
                self.recoveryBlocked.remove(id); self.pendingRecovery.remove(id)
                self.status = "Вход сохранён в выбранном профиле."; self.statusIsError = false
                if (launchAfter ?? self.document.settings.autoStartAfterAuth) && self.document.selectedProfileID == id { self.startCapCut(id) }
            }
            b.onNeedsInteraction = { [weak self] in self?.updateProfile(id){$0.authState = .needsLogin} }
            b.onFailure = { [weak self] in self?.updateProfile(id){$0.authState = .needsLogin}; self?.statusIsError = true }
            b.onClose = { [weak self] in self?.browser = nil; self?.browserProfileID = nil; self?.resumeRecovery() }
            b.show()
        } catch { showError(error.localizedDescription) }
    }
    func cancelSignIn(_ id: String) {
        guard browserProfileID == id else { return }
        browser?.cancel(); status = "Вход отменён."; statusIsError = false
    }
    func recoverSession(_ id: String) {
        guard document.profiles.first(where:{$0.id == id})?.automaticSignIn == true, !recoveryBlocked.contains(id) else { return }
        pendingRecovery.insert(id)
        resumeRecovery()
    }
    func resumeRecovery() {
        guard !busy, let id = pendingRecovery.sorted().first else { return }
        pendingRecovery.remove(id)
        guard !recoveryBlocked.contains(id) else { resumeRecovery(); return }
        signIn(id,launchAfter:false,recovery:true)
    }
    func helperExecutable() -> URL { Bundle.main.resourceURL!.appendingPathComponent("Helper/launcher-helper") }
    func verifySession(_ id: String) {
        guard checks[id] == nil, browserProfileID != id, runningProfileID != id,
            let profile = document.profiles.first(where:{$0.id == id}), profile.usesCapCutAccount || profile.authState != .signedOut else { return }
        do {
            if profile.usesCapCutAccount { refreshNativeAccount(id) }
            guard let session = profile.usesCapCutAccount ? try nativeAccounts.verificationSession() : try SessionStore.load(profileID:id) else {
                updateProfile(id){$0.authState = .signedOut}
                if profile.usesCapCutAccount { status = "Войдите в аккаунт в приложении CapCut."; statusIsError = false }
                else { recoverSession(id) }
                return
            }
            let process = Process(); process.executableURL = helperExecutable()
            let output = Pipe(), input = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            checks[id] = process; checkingProfiles.insert(id); checkBuffers[id] = Data()
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                if bytes.isEmpty { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.consumeCheck(bytes,id:id) }
            }
            process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.checkingProfiles.remove(id); self?.checks[id] = nil; self?.resumeRecovery() } }
            try process.run()
            var data = try JSONSerialization.data(withJSONObject:["action":profile.usesCapCutAccount ? "verify_native" : "verify","session":session,"userAgent":"CapCut/\(appVersion()) (macOS)"])
            data.append(10); input.fileHandleForWriting.write(data); try input.fileHandleForWriting.close()
        } catch { checks[id] = nil; checkingProfiles.remove(id); showError(error.localizedDescription) }
    }
    func consumeCheck(_ bytes: Data, id: String) {
        checkBuffers[id,default:Data()].append(bytes)
        while let end = checkBuffers[id]?.firstIndex(of:10) {
            let line = checkBuffers[id]!.prefix(upTo:end); checkBuffers[id]!.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            if value["kind"] as? String == "session_valid" {
                markValid(id)
                if document.profiles.first(where:{$0.id == id})?.usesCapCutAccount == true,
                   let label = value["displayName"] as? String, !label.isEmpty { updateProfile(id){$0.accountLabel = label} }
            }
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
            guard !capcutIsRunning() else { showError("Сначала полностью закройте CapCut, затем запустите его из лаунчера."); return }
            try nativeAccounts.restoreManagedLaunch()
            let session = profile.usesCapCutAccount ? nil : try SessionStore.load(profileID:id)
            if !profile.usesCapCutAccount {
                guard session != nil else { signIn(id); return }
                if profile.authState == .expired || profile.authState == .needsLogin { signIn(id); return }
                try nativeAccounts.beginManagedLaunch()
            }
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
                do { if !self.capcutIsRunning() { try self.nativeAccounts.restoreManagedLaunch() } }
                catch { self.lastError = true; self.showError(error.localizedDescription) }
                if self.document.profiles.first(where:{$0.id == id})?.usesCapCutAccount == true { self.refreshNativeAccount(id) }
                if self.started && !self.lastError { self.status = "CapCut закрыт. Можно выбрать другой профиль или регион."; self.statusIsError = false }
                self.resumeRecovery()
            } }
            try process.run()
            var config: [String:Any] = ["region":profile.region,"appPath":document.settings.appPath,"dataRoot":document.settings.dataRoot,
                "stateRoot":state.path,"resources":Bundle.main.resourceURL!.appendingPathComponent("Runtime").path,
                "showProUI":true,"requireSession":!profile.usesCapCutAccount]
            if let session { config["session"] = session }
            if profile.usesCapCutAccount, let current = try nativeAccounts.verificationSession() { config["nativeSession"] = current }
            var data = try JSONSerialization.data(withJSONObject:config); data.append(10)
            input.fileHandleForWriting.write(data); try input.fileHandleForWriting.close()
        } catch {
            helper = nil; runningProfileID = nil; launching = false
            do { if !capcutIsRunning() { try nativeAccounts.restoreManagedLaunch() } }
            catch { showError(error.localizedDescription); return }
            showError(error.localizedDescription)
        }
    }
    func refreshNativeAccount(_ id: String) {
        guard document.profiles.first(where:{$0.id == id})?.usesCapCutAccount == true else { return }
        do {
            let current = try nativeAccounts.currentSummary()
            updateProfile(id) {
                $0.accountLabel = current.label
                if !current.present { $0.authState = .signedOut; $0.lastVerified = nil }
                else if runningProfileID != id || !nativeVerified { $0.authState = .saved; $0.lastVerified = nil }
            }
        } catch { showError(error.localizedDescription) }
    }
    func consumeHelper(_ bytes: Data, profileID: String) {
        helperBuffer.append(bytes)
        while let end = helperBuffer.firstIndex(of:10) {
            let line = helperBuffer.prefix(upTo:end); helperBuffer.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with:line) as? [String:Any], let kind = value["kind"] as? String else { continue }
            switch kind {
            case "started":
                started = true; launching = false
                status = document.profiles.first(where:{$0.id == profileID})?.usesCapCutAccount == true && document.profiles.first(where:{$0.id == profileID})?.authState != .valid ? "CapCut открыт. При необходимости войдите в аккаунт в приложении." : "CapCut \(value["version"] ?? "") запущен."
                statusIsError = false
            case "session_checked": if value["present"] as? Bool == true { markValid(profileID) }
            case "catalog_request": if let r = value["region"] as? String { observedRegion = r }
            case "account_verified":
                nativeVerified = value["success"] as? Bool == true
                if nativeVerified { markValid(profileID) }
                else if value["accountMatches"] as? Bool == false {
                    updateProfile(profileID){$0.authState = .needsLogin; $0.lastVerified = nil}
                    status = "Сохранённый сеанс относится к другому аккаунту."; statusIsError = true
                }
                else if value["expired"] as? Bool == true {
                    updateProfile(profileID){$0.authState = .expired}
                    status = document.profiles.first(where:{$0.id == profileID})?.usesCapCutAccount == true ? "Сессия CapCut истекла. Войдите заново в приложении CapCut." : "Сессия профиля истекла. Закройте CapCut и войдите заново."; statusIsError = true
                    recoverSession(profileID)
                }
                if nativeVerified, document.profiles.first(where:{$0.id == profileID})?.usesCapCutAccount == true,
                   let label = value["displayName"] as? String { updateProfile(profileID){$0.accountLabel = label} }
            case "session_logout":
                if document.profiles.first(where:{$0.id == profileID})?.usesCapCutAccount == true {
                    nativeVerified = false; updateProfile(profileID){$0.authState = .signedOut; $0.accountLabel = ""; $0.lastVerified = nil}
                    status = "Войдите в аккаунт в приложении CapCut."; statusIsError = false
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
        if ["session_expired","auth_rejected","auth_missing"].contains(code) { recoverSession(profileID) }
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
