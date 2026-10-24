import AppKit
import Foundation

final class NoRedirectSession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class BrowserLogin: NSObject {
    let capcutVersion: String
    let profileID: String
    let profileRoot: URL
    let nonce = UUID().uuidString
    let state = UUID().uuidString
    var process: Process?
    var input: Pipe?
    var buffer = Data()
    var busy = false
    var onSuccess: (([String: Any]) -> Void)?
    var onClose: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var onNeedsInteraction: (() -> Void)?
    var onFailure: (() -> Void)?
    private var credentials: LoginCredentials?
    private let automatic: Bool
    private var cancelled = false
    private var exchangeTask: Task<Void,Never>?
    init(version: String, profileID: String, profileRoot: URL, credentials: LoginCredentials? = nil) {
        self.credentials = credentials; automatic = credentials != nil
        capcutVersion = version; self.profileID = profileID; self.profileRoot = profileRoot; super.init()
    }
    func show() {
        do {
            let executable = Bundle.main.resourceURL!.appendingPathComponent("Browser/CapCut Login.app/Contents/MacOS/CapCutLogin")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw LauncherError.message("Комплектный браузер отсутствует. Переустановите лаунчер.")
            }
            let p = Process(); p.executableURL = executable; process = p
            let output = Pipe(), channel = Pipe(); input = channel
            p.standardInput = channel; p.standardOutput = output; p.standardError = FileHandle.nullDevice
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                Task { @MainActor in self?.consume(data) }
            }
            p.terminationHandler = { [weak self] _ in Task { @MainActor in
                self?.cancelled = true; self?.exchangeTask?.cancel(); self?.onClose?()
            } }
            try p.run()
            var config: [String:Any] = ["nonce":nonce,"state":state,"stateRoot":profileRoot.path,"language":InterfacePreferences.shared.effectiveLanguage,"theme":InterfacePreferences.shared.theme == "gray" ? "dark" : InterfacePreferences.shared.theme]
            if let credentials { config["credentials"] = ["email":credentials.email,"password":credentials.password] }
            send(config); credentials = nil
            onStatus?(automatic ? "Выполняю автоматический вход…" : "Окно входа открыто. Войдите на сайте CapCut.")
        } catch { fail(error.localizedDescription); onClose?() }
    }
    func send(_ value: [String: Any]) {
        guard process?.isRunning == true, let input else { return }
        guard var data = try? JSONSerialization.data(withJSONObject: value) else { return }; data.append(10)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }
    func activate() {
        send(["command":"show"])
        NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "app.capcutlauncher.macos.login" })?.activate(options: [.activateAllWindows])
    }
    func cancel() { cancelled = true; credentials = nil; exchangeTask?.cancel(); send(["command":"close"]) }
    func consume(_ bytes: Data) {
        guard !cancelled else { return }
        buffer.append(bytes)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let kind = value["kind"] as? String else { continue }
            if kind == "grant_requested" { onStatus?("Получаю одноразовое разрешение на вход…") }
            if kind == "grant_error" { onStatus?("Сайт не передал разрешение. Повторите передачу в окне входа.") }
            if kind == "interaction_required" { onNeedsInteraction?(); onStatus?("Подтвердите вход в открывшемся окне CapCut.") }
            if kind == "login_error" { fail("Не удалось войти автоматически. Проверьте почту и пароль в настройках профиля."); return }
            guard kind == "grant", !busy, value["nonce"] as? String == nonce,
                  let grant = value["grant"] as? [String: Any], let token = grant["token"] as? String, !token.isEmpty else { continue }
            if let returned = grant["state"] as? String, !returned.isEmpty, returned != state { fail("Проверка состояния входа не пройдена."); return }
            busy = true
            exchangeTask = Task {
                do {
                    let session = try await exchange(grant: grant, token: token)
                    try Task.checkCancellation()
                    guard !cancelled else { return }
                    try SessionStore.save(session, profileID: profileID)
                    send(["command":"close"])
                    onSuccess?(session)
                } catch { if !Task.isCancelled && !cancelled { fail(error.localizedDescription) } }
            }
        }
    }
    func fail(_ text: String) {
        guard !cancelled else { return }
        cancelled = true
        onStatus?(text); send(["command":"close"])
        onFailure?()
        if automatic { return }
        NSApp.activate(ignoringOtherApps: true)
        AppDialogs.shared.notice("Вход в CapCut",text)
    }
    func form(_ values: [String: String]) -> Data {
        var components = URLComponents(); components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery!.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)!
    }
    func exchange(grant: [String: Any], token: String) async throws -> [String: Any] {
        let domain = grant["domain"] as? String ?? ""
        let host = (URL(string: domain)?.host?.hasSuffix(".capcutapi.us") == true || domain == "https://login.us.capcut.com")
            ? "passport16-normal-us-ttp.capcutapi.us" : "passport-api-sg.capcutapi.com"
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 60
        let network = URLSession(configuration: configuration, delegate: NoRedirectSession(), delegateQueue: nil)
        defer { network.invalidateAndCancel() }
        let agent = "CapCut/\(capcutVersion) (macOS)"
        var request = URLRequest(url: URL(string: "https://\(host)/passport/transfer/token_auth/?aid=359289")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "sdk-version"); request.setValue(agent, forHTTPHeaderField: "User-Agent")
        var values = ["aid":"359289", "token":token, "state":state]
        if let country = grant["country_code"] as? String, country.count <= 8 { values["country_code"] = country }
        request.httpBody = form(values); onStatus?("Обмениваю разрешение на сеанс Mac-клиента…")
        let (_, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let xToken = http.value(forHTTPHeaderField: "x-tt-token"), !xToken.isEmpty else {
            throw LauncherError.message("Сервер отклонил передачу входа в Mac-клиент.")
        }
        var check = URLRequest(url: URL(string: "https://\(host)/passport/account/info/v2/?aid=359289&device_platform=macos")!)
        check.setValue(xToken, forHTTPHeaderField: "x-tt-token"); check.setValue("2", forHTTPHeaderField: "sdk-version")
        check.setValue(agent, forHTTPHeaderField: "User-Agent"); onStatus?("Проверяю вход на сервере CapCut…")
        let (data, checkedResponse) = try await network.data(for: check)
        guard let checkedHTTP = checkedResponse as? HTTPURLResponse, (200..<300).contains(checkedHTTP.statusCode),
            let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            reply["message"] as? String == "success" || String(describing: reply["ret"] ?? "") == "0",
            let user = reply["data"] as? [String: Any] else { throw LauncherError.message("Сервер не подтвердил новый сеанс.") }
        func field(_ names: String...) -> String { names.compactMap { user[$0].map { String(describing: $0) } }.first(where: { !$0.isEmpty }) ?? "" }
        let uid = field("user_id_str", "user_id", "uid")
        guard !uid.isEmpty, uid != "0" else { throw LauncherError.message("Сервер не вернул профиль аккаунта.") }
        let cookies = network.configuration.httpCookieStorage?.cookies(for: URL(string: "https://\(host)/")!) ?? []
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
        guard !cookieHeader.isEmpty else { throw LauncherError.message("Сервер не выдал cookies сеанса.") }
        let csrf = cookies.first(where: { $0.name == "passport_csrf_token" })?.value
            ?? cookies.first(where: { $0.name == "passport_csrf_token_default" })?.value ?? ""
        return ["version":1,"sourceHost":host,"cookieHeader":cookieHeader,
            "xToken":checkedHTTP.value(forHTTPHeaderField: "x-tt-token") ?? xToken,"csrfToken":csrf,
            "uid":uid,"displayName":field("email","name","nick_name","nickname","screen_name"),
            "createdUtc":ISO8601DateFormatter().string(from: Date())]
    }
}
