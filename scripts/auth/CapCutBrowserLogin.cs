// Local, user-operated browser sign-in. No password collection or secret logging.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

internal sealed class LoginWindow : Form {
    readonly string root;
    readonly string stateRoot;
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly WebView2 browser = new WebView2();
    readonly Label status = new Label();
    readonly Label address = new Label();
    readonly Button transfer = new Button();
    readonly Timer timer = new Timer();
    readonly string nonce = Guid.NewGuid().ToString("N");
    string state;
    readonly Timer automaticTimer = new Timer();
    Dictionary<string,string> credentials;
    string loginStage = "initial";
    bool automaticBusy;
    bool busy;
    bool attempted;
    bool backgroundLogin, interactionRequired;
    readonly DateTime automaticStarted=DateTime.UtcNow;

    internal LoginWindow(string workspace) {
        root = workspace;
        UiText.Initialize(workspace);
        stateRoot = Environment.GetEnvironmentVariable("CAPCUT_STATE_ROOT") ?? Path.Combine(root, "local");
        LoadCredentials();backgroundLogin=credentials!=null;
        if(backgroundLogin){Opacity=0;ShowInTaskbar=false;}
        string iconPath = Path.Combine(root, "assets", "launcher.ico");
        if (File.Exists(iconPath)) Icon = new Icon(iconPath);
        Text = UiText.Get("CapCut — вход через email");
        BackColor = Color.FromArgb(249, 249, 247);
        ForeColor = Color.FromArgb(30, 31, 34);
        Font = new Font("Segoe UI", 10);
        Size = new Size(1100, 850); MinimumSize = new Size(800, 650);
        StartPosition = FormStartPosition.CenterScreen;
        if(backgroundLogin){StartPosition=FormStartPosition.Manual;Location=new Point(-20000,-20000);}
        address.Dock = DockStyle.Top; address.Height = 28;
        address.Text = "https://www.capcut.com/login";
        address.Padding = new Padding(8, 5, 0, 0);
        status.Dock = DockStyle.Bottom; status.Height = 58;
        status.Padding = new Padding(8);
        status.Text = UiText.Get("Войдите на сайте CapCut через email и пароль. После входа начнётся обмен сеанса для ПК.");
        transfer.Dock = DockStyle.Bottom; transfer.Height = 36;
        transfer.Text = UiText.Get("Передать вход в CapCut на ПК"); transfer.Enabled = false;
        transfer.FlatStyle = FlatStyle.Flat; transfer.FlatAppearance.BorderSize = 0;
        transfer.BackColor = Color.FromArgb(30, 31, 34); transfer.ForeColor = Color.White;
        transfer.Click += async delegate { await RequestGrant(); };
        browser.Dock = DockStyle.Fill;
        Controls.Add(browser); Controls.Add(address); Controls.Add(transfer); Controls.Add(status);
        timer.Interval = 1500;
        timer.Tick += async delegate {
            timer.Stop();
            if (!attempted && IsReadyPage()) await RequestGrant();
        };
        Shown += async delegate { await InitializeBrowser(); };
        FormClosed += delegate { timer.Dispose(); automaticTimer.Dispose(); if(credentials!=null)credentials.Clear(); browser.Dispose(); };
        automaticTimer.Interval=1500; automaticTimer.Tick+=async delegate { await AutomaticLogin(); };
    }

    bool IsReadyPage() {
        Uri uri;
        return Uri.TryCreate(browser.Source == null ? "" : browser.Source.ToString(), UriKind.Absolute, out uri)
            && uri.Scheme == "https" && uri.Host == "www.capcut.com"
            && (uri.AbsolutePath.StartsWith("/my-edit") || uri.AbsolutePath.StartsWith("/editor"));
    }

    async Task InitializeBrowser() {
        try {
            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(stateRoot, "auth-browser-profile"));
            await browser.EnsureCoreWebView2Async(env);
            browser.CoreWebView2.Settings.IsPasswordAutosaveEnabled = false;
            browser.CoreWebView2.WebMessageReceived += OnMessage;
            browser.CoreWebView2.SourceChanged += delegate {
                Uri uri;
                if (Uri.TryCreate(browser.CoreWebView2.Source, UriKind.Absolute, out uri))
                    address.Text = uri.Scheme + "://" + uri.Host + uri.AbsolutePath;
                transfer.Enabled = IsReadyPage() && !busy;
                if (IsReadyPage() && !attempted) timer.Start();
            };
            browser.CoreWebView2.NavigationStarting += delegate(object sender, CoreWebView2NavigationStartingEventArgs e) {
                Uri uri;
                if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out uri) || uri.Scheme != "https") e.Cancel = true;
            };
            browser.CoreWebView2.NewWindowRequested += delegate(object sender, CoreWebView2NewWindowRequestedEventArgs e) {
                Uri uri;
                e.Handled = true;
                if (Uri.TryCreate(e.Uri, UriKind.Absolute, out uri) && uri.Scheme == "https") browser.CoreWebView2.Navigate(e.Uri);
            };
            browser.CoreWebView2.Navigate("https://www.capcut.com/login");
            if(credentials!=null)automaticTimer.Start();
            WriteStatus(backgroundLogin?"automatic_login":"waiting_for_manual_login", "");
        } catch (Exception ex) { Fail("browser_init", ex.GetType().Name); }
    }

    void LoadCredentials() {
        if(Environment.GetEnvironmentVariable("CAPCUT_AUTOMATIC_LOGIN")=="0")return;
        string file=Path.Combine(stateRoot,"credentials.json");
        if(!File.Exists(file))return;
        try {
            string packed=json.Deserialize<string>(File.ReadAllText(file));
            byte[] bytes=ProtectedData.Unprotect(Convert.FromBase64String(packed),null,DataProtectionScope.CurrentUser);
            try { credentials=json.Deserialize<Dictionary<string,string>>(Encoding.UTF8.GetString(bytes)); }
            finally {Array.Clear(bytes,0,bytes.Length);}
        } catch { credentials=null; }
    }
    async Task AutomaticLogin() {
        if(automaticBusy||busy||interactionRequired||browser.CoreWebView2==null)return;
        if(DateTime.UtcNow-automaticStarted>TimeSpan.FromMinutes(3)){Fail("automatic_login_timeout","");return;}
        if(credentials==null){if(loginStage=="password_submitted")try{await ObserveLoginResult();}catch{Fail("automatic_login_error","");}return;}
        Uri uri;
        if(!Uri.TryCreate(browser.CoreWebView2.Source,UriKind.Absolute,out uri)||uri.Scheme!="https"||uri.Host!="www.capcut.com")return;
        automaticBusy=true;
        try {
            string script=File.ReadAllText(Path.Combine(root,"scripts/auth/auto_login.js"));
            string result=await browser.CoreWebView2.ExecuteScriptAsync("("+script+")("+json.Serialize(credentials)+","+json.Serialize(loginStage)+")");
            var reply=json.Deserialize<Dictionary<string,object>>(result);object action;
            if(reply!=null&&reply.TryGetValue("action",out action)) {
                string next=Convert.ToString(action);
                if(next=="interaction"){RevealForInteraction();return;}
                if(next=="error"){Fail("automatic_login_rejected","");return;}
                if(next=="password_submitted"){loginStage=next;credentials.Clear();credentials=null;}
                else if(next!="waiting")loginStage=next;
                if(DateTime.UtcNow-automaticStarted>TimeSpan.FromSeconds(60)&&loginStage!="email_submitted"&&loginStage!="password_submitted")RevealForInteraction();
            }
        } catch {Fail("automatic_login_error","");}
        finally {automaticBusy=false;}
    }
    async Task ObserveLoginResult(){
        if(IsReadyPage())return;
        string result=await browser.CoreWebView2.ExecuteScriptAsync("(()=>{const visible=e=>e&&e.getBoundingClientRect().height>0;const nodes=[...document.querySelectorAll('[role=alert],[class*=error]')].filter(visible);if(nodes.some(e=>/incorrect|invalid|wrong|too many|неверн|слишком много/i.test(e.textContent)))return 'error';return [...document.querySelectorAll('input[autocomplete=one-time-code],iframe[title*=captcha i]')].some(visible)?'interaction':'waiting'})()");
        if(result=="\"error\"")Fail("automatic_login_rejected","");else if(result=="\"interaction\"")RevealForInteraction();
    }
    void RevealForInteraction(){
        if(credentials!=null){credentials.Clear();credentials=null;}automaticTimer.Stop();interactionRequired=true;Opacity=1;ShowInTaskbar=true;
        var area=Screen.PrimaryScreen.WorkingArea;Location=new Point(area.Left+Math.Max(0,(area.Width-Width)/2),area.Top+Math.Max(0,(area.Height-Height)/2));
        status.Text=UiText.Get("Сайт CapCut требует подтверждения. Завершите его вручную.");WriteStatus("interaction_required","");Show();Activate();
    }

    async Task RequestGrant() {
        if (busy || !IsReadyPage()) return;
        if (Process.GetProcessesByName("CapCut").Length > 0) { Fail("client_running", UiText.Get("Закройте CapCut штатно и повторите.")); return; }
        busy = true; attempted = true; transfer.Enabled = false;
        state = Guid.NewGuid().ToString("N");
        status.Text = UiText.Get("Получение одноразового разрешения на вход…");
        WriteStatus("requesting_transfer_grant", "");
        try {
            string script = File.ReadAllText(Path.Combine(root, "scripts", "auth", "browser_transfer.js"), Encoding.UTF8)
                .Replace("__CAPCUT_NONCE__", json.Serialize(nonce)).Replace("__CAPCUT_STATE__", json.Serialize(state));
            await browser.CoreWebView2.ExecuteScriptAsync(script);
        } catch (Exception ex) { Fail("grant_script", ex.GetType().Name); }
    }

    async void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e) {
        try {
            Uri source;
            if (!Uri.TryCreate(e.Source, UriKind.Absolute, out source) || source.Scheme != "https" || source.Host != "www.capcut.com") return;
            string text = e.TryGetWebMessageAsString();
            if (text.Length > 500000) return;
            var message = Obj(json.DeserializeObject(text));
            if (!busy || Str(message, "nonce") != nonce) return;
            if (Str(message, "type") == "error") { Fail("grant", Str(message, "code")); return; }
            if (Str(message, "type") != "grant") return;
            var result = Obj(Value(message, "result"));
            var data = Obj(Value(result, "data"));
            if (Str(data, "token").Length == 0 && Str(result, "token").Length > 0) data = result;
            if (Str(data, "domain").Length == 0 && Str(result, "domain").Length > 0) data["domain"] = Str(result, "domain");
            string token = Str(data, "token");
            if (token.Length == 0) { Fail("grant_rejected", "HTTP " + Str(message, "httpStatus") + " " + Code(result)
                + " root_fields=" + String.Join(",", result.Keys) + " data_fields=" + String.Join(",", data.Keys)); return; }
            string returnedState = Str(data, "state");
            if (returnedState.Length > 0 && returnedState != state) { Fail("grant_state_mismatch", ""); return; }
            await ExchangeAndSave(data, token);
        } catch (Exception ex) { Fail("transfer", ex.GetType().Name); }
    }

    async Task ExchangeAndSave(Dictionary<string, object> grant, string token) {
        string grantDomain = Str(grant, "domain");
        string host = grantDomain.IndexOf("capcutapi.us", StringComparison.OrdinalIgnoreCase) >= 0
            || grantDomain == "https://login.us.capcut.com"
            ? "passport16-normal-us-ttp.capcutapi.us" : "passport-api-sg.capcutapi.com";
        string country = Str(grant, "country_code");
        if (country.Length > 8) country = "";
        status.Text = UiText.Get("Обмен разрешения на токен ПК-клиента…");
        WriteStatus("exchanging_transfer_grant", "");
        using (var handler = new HttpClientHandler()) {
            handler.AllowAutoRedirect = false;
            handler.CookieContainer = new CookieContainer();
            using (var client = new HttpClient(handler)) {
                client.Timeout = TimeSpan.FromSeconds(25);
                client.DefaultRequestHeaders.TryAddWithoutValidation("sdk-version", "2");
                client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "CapCut/9.6.0.4097 (Windows)");
                var form = new Dictionary<string, string> { {"aid", "359289"}, {"token", token}, {"state", state} };
                if (country.Length > 0) form["country_code"] = country;
                var response = await client.PostAsync("https://" + host + "/passport/transfer/token_auth/?aid=359289", new FormUrlEncodedContent(form));
                var reply = Obj(json.DeserializeObject(await response.Content.ReadAsStringAsync()));
                var payload = Obj(Value(reply, "data"));
                string xToken = Header(response, "x-tt-token");
                if (!response.IsSuccessStatusCode || xToken.Length == 0) {
                    Fail("token_exchange_rejected", "HTTP " + (int)response.StatusCode + " " + Code(reply)
                        + " fields=" + String.Join(",", payload.Keys)); return;
                }
                status.Text = UiText.Get("Проверка выданного сервером сеанса…");
                WriteStatus("validating_desktop_session", "");
                client.DefaultRequestHeaders.TryAddWithoutValidation("x-tt-token", xToken);
                var checkedResponse = await client.GetAsync("https://" + host + "/passport/account/info/v2/?aid=359289&device_platform=windows");
                var checkedReply = Obj(json.DeserializeObject(await checkedResponse.Content.ReadAsStringAsync()));
                var user = Obj(Value(checkedReply, "data"));
                string uid = First(user, "user_id_str", "user_id", "uid");
                if (!checkedResponse.IsSuccessStatusCode || uid.Length == 0 || uid == "0" || !Success(checkedReply)) {
                    Fail("desktop_session_invalid", "HTTP " + (int)checkedResponse.StatusCode + " " + Code(checkedReply)); return;
                }
                string refreshedToken = Header(checkedResponse, "x-tt-token");
                if (refreshedToken.Length > 0) xToken = refreshedToken;
                string csrfToken = "";
                foreach (Cookie cookie in handler.CookieContainer.GetCookies(new Uri("https://" + host + "/"))) {
                    if (cookie.Name == "passport_csrf_token" || (csrfToken.Length == 0 && cookie.Name == "passport_csrf_token_default")) csrfToken = cookie.Value;
                }
                if (Process.GetProcessesByName("CapCut").Length > 0) { Fail("client_running", UiText.Get("Закройте CapCut и повторите.")); return; }
                var profile = new Dictionary<string, object> {
                    {"uid", uid}, {"xToken", xToken}, {"csrfToken", csrfToken},
                    {"avatar_url", First(user, "avatar_url", "avatar")},
                    {"nick_name", First(user, "name", "nick_name", "nickname")},
                    {"screen_name", First(user, "screen_name", "name")},
                    {"description", Str(user, "description")}, {"gender", 0},
                    {"is_looki_uid", Value(user, "is_looki_uid") is bool && (bool)Value(user, "is_looki_uid")}, {"sec_user_id", Str(user, "sec_user_id")},
                    {"third_platform", Str(user, "third_platform")}
                };
                string packed = Convert.ToBase64String(Encoding.UTF8.GetBytes(json.Serialize(profile)));
                string sessionPath = Path.Combine(stateRoot, "auth-browser-sdk", "desktop-session.bin");
                Directory.CreateDirectory(Path.GetDirectoryName(sessionPath));
                string cookieHeader = handler.CookieContainer.GetCookieHeader(new Uri("https://" + host + "/"));
                if (cookieHeader.Length == 0) { Fail("desktop_cookies_missing", ""); return; }
                if (Environment.GetEnvironmentVariable("CAPCUT_AUTH_DIAGNOSTIC") == "1") {
                    var probes = new List<object>();
                    foreach (string probeHost in new [] {host, "passport-api.capcutapi.com"}) {
                        foreach (bool withCookie in new [] {false, true}) {
                            using (var probeHandler = new HttpClientHandler {UseCookies=false, AllowAutoRedirect=false})
                            using (var probeClient = new HttpClient(probeHandler)) {
                                probeClient.Timeout = TimeSpan.FromSeconds(12);
                                probeClient.DefaultRequestHeaders.TryAddWithoutValidation("x-tt-token", xToken);
                                if (withCookie) probeClient.DefaultRequestHeaders.TryAddWithoutValidation("Cookie", cookieHeader);
                                var probeResponse = await probeClient.GetAsync("https://" + probeHost + "/passport/account/info/v2/?aid=359289&device_platform=windows");
                                var probeReply = Obj(json.DeserializeObject(await probeResponse.Content.ReadAsStringAsync()));
                                probes.Add(new {host=probeHost,cookies=withCookie,http=(int)probeResponse.StatusCode,
                                    success=Success(probeReply),code=Code(probeReply)});
                            }
                        }
                    }
                    File.WriteAllText(Path.Combine(stateRoot,"auth-analysis","browser-login-probes.json"),json.Serialize(probes),Encoding.UTF8);
                }
                var session = new {version=1, xToken=xToken, csrfToken=csrfToken, uid=uid,
                    displayName=First(user,"email","name","nick_name","nickname","screen_name"),
                    cookieHeader=cookieHeader, sourceHost=host, createdUtc=DateTime.UtcNow.ToString("o")};
                string pendingSession = sessionPath + ".tmp";
                File.WriteAllBytes(pendingSession, ProtectedData.Protect(Encoding.UTF8.GetBytes(json.Serialize(session)), null, DataProtectionScope.CurrentUser));
                if (File.Exists(sessionPath)) File.Replace(pendingSession, sessionPath, null);
                else File.Move(pendingSession, sessionPath);
                // Managed slots let the launcher perform the launch and journal
                // the official account; browser sign-in only saves this slot.
                if(Environment.GetEnvironmentVariable("CAPCUT_MANAGED_PROFILE")=="1" || Environment.GetEnvironmentVariable("CAPCUT_AUTO_START")=="0") {
                    WriteStatus("verified","");
                    status.Text=UiText.Get("Вход подтверждён");await Task.Delay(500);Close();return;
                }
                string previous;
                using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Bytedance\CapCut\Account")) {
                    previous = key.GetValue("user_info") as string;
                    key.SetValue("user_info", packed, RegistryValueKind.String);
                }
                try {
                    string launcher = Path.Combine(root, "scripts", "launch_capcut.ps1");
                    Process.Start(new ProcessStartInfo("powershell.exe",
                        "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + launcher + "\" -Region " + SelectedRegion() + " -ShowProUI"
                        + (Environment.GetEnvironmentVariable("CAPCUT_AUTH_DIAGNOSTIC") == "1" ? "" : " -NoDiagnostics")) {
                        UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = root
                    });
                } catch {
                    using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Bytedance\CapCut\Account")) {
                        if (previous == null) key.DeleteValue("user_info", false); else key.SetValue("user_info", previous);
                    }
                    throw;
                }
                WriteStatus("desktop_session_saved_client_start_requested", "server_session_verified");
                status.Text = UiText.Get("Сервер подтвердил сеанс; ожидаю окно CapCut…");
                bool windowOpened = false;
                for (int attempt = 0; attempt < 60; attempt++) {
                    foreach (var process in Process.GetProcessesByName("CapCut")) {
                        try { if (process.MainWindowHandle != IntPtr.Zero) windowOpened = true; }
                        catch (InvalidOperationException) { }
                        finally { process.Dispose(); }
                    }
                    if (windowOpened) break;
                    await Task.Delay(500);
                }
                if (!windowOpened) { Fail("client_window_not_opened", UiText.Get("Сеанс сохранён; повторите запуск через US Pro.cmd.")); return; }
                WriteStatus("client_window_opened_session_saved", "server_session_verified");
                status.Text = UiText.Get("Сеанс сохранён, CapCut открыт.");
                await Task.Delay(1500);
                Close();
            }
        }
    }

    static Dictionary<string, object> Obj(object value) { return value as Dictionary<string, object> ?? new Dictionary<string, object>(); }
    static string SelectedRegion() {
        string value = Environment.GetEnvironmentVariable("CAPCUT_REGION") ?? "US";
        return System.Text.RegularExpressions.Regex.IsMatch(value, "^[A-Za-z]{2}$") ? value.ToUpperInvariant() : "US";
    }
    static object Value(Dictionary<string, object> value, string key) { object x; return value.TryGetValue(key, out x) ? x : null; }
    static string Str(Dictionary<string, object> value, string key) { return Convert.ToString(Value(value, key), CultureInfo.InvariantCulture) ?? ""; }
    static string First(Dictionary<string, object> value, params string[] keys) { foreach (string key in keys) { string x = Str(value, key); if (x.Length > 0) return x; } return ""; }
    static string Code(Dictionary<string, object> value) { var data = Obj(Value(value, "data")); return "ret=" + First(value, "ret", "code") + " error_code=" + First(data, "error_code", "code"); }
    static bool Success(Dictionary<string, object> value) { return Str(value, "ret") == "0" || Str(value, "message") == "success"; }
    static string Header(HttpResponseMessage value, string name) { IEnumerable<string> list; return value.Headers.TryGetValues(name, out list) ? String.Join("", list) : ""; }
    void Fail(string stage, string code) {
        busy = false; transfer.Enabled = IsReadyPage();
        status.Text = UiText.Get("Вход пока не завершён: ") + stage + " — " + code;
        WriteStatus(stage, code);
        if(backgroundLogin&&!interactionRequired){automaticTimer.Stop();Environment.ExitCode=4;Close();}
    }
    void WriteStatus(string phase, string code) {
        // Allowlisted status metadata only: no tokens, identifiers, responses or cookies.
        string folder = Path.Combine(stateRoot, "auth-analysis");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "browser-login-status.json"),
            json.Serialize(new {phase=phase, code=code, timeUtc=DateTime.UtcNow.ToString("o")}), Encoding.UTF8);
    }
    [STAThread] static int Main(string[] args) {
        if (args.Length < 1) return 2;
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        if (args.Length > 1 && args[1] == "--check-only") {
            string version = CoreWebView2Environment.GetAvailableBrowserVersionString();
            return String.IsNullOrEmpty(version) ? 3 : 0;
        }
        Application.Run(new LoginWindow(Path.GetFullPath(args[0])));
        return Environment.ExitCode;
    }
}
