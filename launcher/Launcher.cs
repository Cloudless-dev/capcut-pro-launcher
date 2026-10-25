using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

internal sealed partial class Launcher : Form {
    readonly string root=AppDomain.CurrentDomain.BaseDirectory;
    readonly string stateRoot=Environment.GetEnvironmentVariable("CAPCUT_LAUNCHER_STATE_ROOT")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CapCutLauncher");
    readonly TextBox app=new TextBox(),region=new TextBox{Text="US"};
    readonly Label status=new Label();
    readonly JavaScriptSerializer json=new JavaScriptSerializer();
    readonly Timer accountTimer=new Timer();
    string accountName="";
    bool working;
    Launcher(){
        Text="CapCut Launcher · "+BuildVersion.Display;ClientSize=new Size(1200,820);MinimumSize=new Size(980,700);StartPosition=FormStartPosition.CenterScreen;
        string icon=Path.Combine(root,"assets","launcher.ico");if(File.Exists(icon))Icon=new Icon(icon);
        LoadSettings();profiles=new LauncherProfiles(stateRoot,RegionCode());PopulateProfiles();if(String.IsNullOrWhiteSpace(projectsRoot))projectsRoot=DefaultProjectsRoot();ApplyTheme();
        Shown+=async delegate{await InitializeWebShell();if(automaticUpdates)await UpdateLauncher();};
        accountTimer.Interval=1500;accountTimer.Tick+=delegate{RefreshAccount();PublishWebState();};accountTimer.Start();
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(working||webBusy)e.Cancel=true;else SaveSettings();};
        Disposed+=delegate{accountTimer.Dispose();VeilMessage.Notify=null;};RefreshAccount();
    }
    void Busy(bool value){working=value;PublishWebState();}
    void RefreshAccount(){accountName=SelectedProfile==null?"":SelectedProfile.NativeAccount?ReadNativeName():ReadProfileLabel(SelectedProfile);}
    async Task UpdateLauncher(){
        Busy(true);
        try{
            status.Text=UiText.Get("Проверяем обновления…");
            var update=await Task.Run(()=>LauncherUpdate.Find());
            if(update==null){status.Text=UiText.Get("Установлена последняя версия.");return;}
            if(Process.GetProcessesByName("CapCut").Length>0||Process.GetProcessesByName("CapCutBrowserLogin").Length>0)
                throw new Exception(UiText.Get("Закройте CapCut и окно входа перед обновлением."));
            if(!await ConfirmWeb("CapCut Launcher",UiText.Get("Доступна версия ")+update.Version+UiText.Get(". Скачать и установить?")))return;
            status.Text=UiText.Get("Скачиваем обновление…");
            string archive=await Task.Run(()=>LauncherUpdate.Download(update,stateRoot));
            LauncherUpdate.Install(root,archive,update.Hash);
            working=false;Application.Exit();
        }catch(Exception ex){status.Text=UiText.Get("Не удалось обновить: ")+ex.Message;}
        finally{Busy(false);}
    }
    string RegionCode() {
        string code=region.Text.Split(new[]{' ','—'},StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()??"";
        return LauncherProfiles.Country(code);
    }
    string DetectApp() {
        var roots=new List<string>{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CapCut"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"CapCut"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"CapCut")};
        foreach(var hive in new[]{Registry.CurrentUser,Registry.LocalMachine}) {
            try{using(var key=hive.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\CapCut.exe")){
                string executable=key==null?null:key.GetValue(null) as string;
                if(!String.IsNullOrEmpty(executable))roots.Add(Path.GetDirectoryName(executable.Trim('"')));
            }}catch{ }
            try{using(var uninstall=hive.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall")){
                if(uninstall!=null)foreach(string name in uninstall.GetSubKeyNames())using(var key=uninstall.OpenSubKey(name)){
                    string title=key==null?null:key.GetValue("DisplayName") as string;
                    if(title!=null&&title.StartsWith("CapCut",StringComparison.OrdinalIgnoreCase)){
                        string location=key.GetValue("InstallLocation") as string;
                        if(!String.IsNullOrEmpty(location))roots.Add(location);
                    }
                }
            }}catch{ }
        }
        var candidates=new List<string>();
        foreach(string folder in roots.Where(p=>!String.IsNullOrEmpty(p)).Distinct(StringComparer.OrdinalIgnoreCase))Collect(folder,2,candidates);
        return candidates.Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(p=>ParseVersion(FileVersionInfo.GetVersionInfo(p).FileVersion)).FirstOrDefault()??"";
    }
    static void Collect(string folder,int depth,List<string> found) {
        try{if(!Directory.Exists(folder))return;string exe=Path.Combine(folder,"CapCut.exe");if(File.Exists(exe))found.Add(exe);
            if(depth>0)foreach(string child in Directory.GetDirectories(folder))Collect(child,depth-1,found);
        }catch(UnauthorizedAccessException){}catch(IOException){}
    }
    static Version ParseVersion(string text){Version v;return Version.TryParse(text,out v)?v:new Version(0,0);}
    void LoadSettings() {
        try {
            string file=Path.Combine(stateRoot,"settings.json");
            if(File.Exists(file)){
                var settings=json.Deserialize<Dictionary<string,string>>(File.ReadAllText(file));
                if(settings.ContainsKey("projectsRoot"))projectsRoot=settings["projectsRoot"];
                if(settings.ContainsKey("theme"))theme=settings["theme"];
                if(settings.ContainsKey("interfaceSize"))interfaceSize=settings["interfaceSize"];
                if(settings.ContainsKey("autoStart"))autoStart=settings["autoStart"]=="true";
                if(settings.ContainsKey("automaticUpdates"))automaticUpdates=settings["automaticUpdates"]=="true";
                if(settings.ContainsKey("language")){languagePreference=settings["language"];UiText.English=languagePreference=="system"?System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName!="ru":languagePreference=="en";}
                if(settings.ContainsKey("appPath")&&File.Exists(settings["appPath"]))app.Text=settings["appPath"];
                if(settings.ContainsKey("region"))region.Text=LauncherProfiles.Country(settings["region"]);
            }
        }catch { }
        if(app.Text.Length==0)app.Text=DetectApp();
    }
    void Prepare(bool requireClosed) {
        if(SelectedProfile==null)throw new IOException(UiText.Get("Добавьте профиль перед запуском."));
        if(!Environment.Is64BitOperatingSystem)throw new Exception(UiText.Get("Требуется Windows x64."));
        if(!File.Exists(app.Text)||!String.Equals(Path.GetFileName(app.Text),"CapCut.exe",StringComparison.OrdinalIgnoreCase))
            throw new Exception(UiText.Get("Укажите установленный CapCut.exe через «Обзор»."));
        if(requireClosed&&Process.GetProcessesByName("CapCut").Length>0)throw new Exception(UiText.Get("Полностью закройте CapCut и повторите."));
        if(requireClosed&&Process.GetProcessesByName("CapCutBrowserLogin").Length>0)throw new Exception(UiText.Get("Сначала закройте CapCut и окно входа."));
        string code=RegionCode();SaveSettings();
        Environment.SetEnvironmentVariable("CAPCUT_APP_PATH",app.Text);
        Environment.SetEnvironmentVariable("CAPCUT_REGION",code);
        Environment.SetEnvironmentVariable("CAPCUT_STATE_ROOT",ProfileState);
        Environment.SetEnvironmentVariable("CAPCUT_AUTO_START",autoStart?"1":"0");
        Environment.SetEnvironmentVariable("CAPCUT_USE_NATIVE_ACCOUNT",SelectedProfile!=null&&SelectedProfile.NativeAccount?"1":"0");
        Environment.SetEnvironmentVariable("CAPCUT_MANAGED_PROFILE",SelectedProfile!=null&&!SelectedProfile.NativeAccount?"1":"0");
        Environment.SetEnvironmentVariable("CAPCUT_ACCOUNT_JOURNAL_ROOT",stateRoot);
        Environment.SetEnvironmentVariable("CAPCUT_LANGUAGE",UiText.English?"en":"ru");
        Environment.SetEnvironmentVariable("CAPCUT_AUTOMATIC_LOGIN",SelectedProfile.AutomaticLogin==false?"0":"1");
    }
    void SaveSettings(){
        string code;
        try{code=RegionCode();}catch(IOException){code=SelectedProfile==null?"US":SelectedProfile.Region;}
        if(SelectedProfile!=null){SelectedProfile.Region=code;profiles.Save();}
        Directory.CreateDirectory(stateRoot);
        ProjectLibrary.Save(Path.Combine(stateRoot,"settings.json"),new {appPath=app.Text,region=code,language=languagePreference,projectsRoot=projectsRoot,theme=theme,interfaceSize=interfaceSize,autoStart=autoStart?"true":"false",automaticUpdates=automaticUpdates?"true":"false"});
    }
    async Task<string> Script(string relative,string arguments) {
        var info=new ProcessStartInfo("powershell.exe","-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \""+Path.Combine(root,relative)+"\" "+arguments) {
            UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=root,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8
        };
        using(var p=Process.Start(info)) {
            var ready=new TaskCompletionSource<bool>();
            bool launching=relative=="scripts/launch_capcut.ps1"&&!arguments.Contains("-CheckOnly");
            var output=ReadScriptOutput(p,launching?ready:null);var errors=p.StandardError.ReadToEndAsync();
            if(launching){var finished=Task.Run(()=>p.WaitForExit());if(await Task.WhenAny(ready.Task,finished)==ready.Task)return "CAPCUT_LAUNCH_READY";}
            await Task.Run(()=>p.WaitForExit());string text=await output;string error=await errors;
            if(p.ExitCode!=0){string details=error.Length>0?error:text;var clean=Regex.Match(details,@"CAPCUT_ERROR ([^\r\n]+)");if(clean.Success)details=clean.Groups[1].Value;if(details.Contains("Session expired or rejected."))details=UiText.English?"Session expired or rejected. Sign in again.":"Сессия истекла или отклонена. Войдите в профиль заново. (Session expired or rejected.)";throw new Exception(details);}
            return text.Trim();
        }
    }
    static async Task<string> ReadScriptOutput(Process process,TaskCompletionSource<bool> ready){
        var text=new StringBuilder();try{string line;while((line=await process.StandardOutput.ReadLineAsync())!=null){if(text.Length<65536)text.AppendLine(line);if(ready!=null&&line.Trim()=="CAPCUT_LAUNCH_READY")ready.TrySetResult(true);}}catch(ObjectDisposedException){}catch(IOException){}return text.ToString();
    }
    async Task<bool> WebViewReady() {
        bool ready=true;
        try{await Script("scripts/auth/start_browser_login.ps1","-CheckOnly");}
        catch {ready=false;}
        if(ready)return true;
        if(!await ConfirmWeb("WebView2",UiText.Get("Для входа нужен Microsoft WebView2 Runtime. Установить его официальным установщиком Microsoft из комплекта? Нужен интернет.")))return false;
        var info=new ProcessStartInfo(Path.Combine(root,"runtime","MicrosoftEdgeWebview2Setup.exe"),"/install"){UseShellExecute=true};
        using(var p=Process.Start(info))await Task.Run(()=>p.WaitForExit());
        await Script("scripts/auth/start_browser_login.ps1","-CheckOnly");return true;
    }
    async Task Run(bool login, bool forceLaunch=false) {
        bool recover=false;
        Busy(true);
        try {
            Prepare(true);status.Text=login?UiText.Get("Проверяю браузерный компонент…"):UiText.Get("Запускаю CapCut с регионом ")+RegionCode()+"…";
            if(login && SelectedProfile!=null && SelectedProfile.NativeAccount){status.Text=UiText.Get("Войдите через официальное приложение CapCut, затем закройте его и запустите через лаунчер.");return;}
            if(login){if(!await WebViewReady()){status.Text=UiText.Get("Установка отменена. CapCut не запускался.");return;}
                DateTime started=DateTime.UtcNow;
                status.Text=UiText.Get("Окно входа открыто. Войдите на сайте CapCut или закройте окно для отмены.");
                await Script("scripts/auth/start_browser_login.ps1","-WaitForExit");
                RefreshAccount();
                string sessionFile=Path.Combine(ProfileState,"auth-browser-sdk","desktop-session.bin");
                status.Text=accountName.Length>0&&File.Exists(sessionFile)&&File.GetLastWriteTimeUtc(sessionFile)>=started
                    ?UiText.Get("Вход выполнен: ")+accountName+".":UiText.Get("Окно входа закрыто. Новый вход не выполнен.");
                if(File.Exists(sessionFile)&&File.GetLastWriteTimeUtc(sessionFile)>=started){profileStatuses[SelectedProfile.Id]="Вход подтверждён";SaveVerification("verified");}
                if((autoStart||forceLaunch) && File.Exists(sessionFile) && File.GetLastWriteTimeUtc(sessionFile)>=started){await Script("scripts/launch_capcut.ps1","-Region "+RegionCode()+" -ShowProUI -NoDiagnostics");status.Text=UiText.Get("Сеанс сохранён, CapCut открыт.");}
            } else {
                string result=await Script("scripts/launch_capcut.ps1","-Region "+RegionCode()+" -ShowProUI -NoDiagnostics");
                status.Text=result.Contains("CAPCUT_LAUNCH_READY")||result.Contains("CapCut запущен")?UiText.Get("CapCut запущен")+" · "+RegionCode():UiText.Get("CapCut запускается. Дождитесь окна приложения.");
            }
        }catch(Exception ex){
            recover=!login && SelectedProfile!=null && !SelectedProfile.NativeAccount && File.Exists(Path.Combine(ProfileState,"credentials.json")) && ex.Message.Contains("Session expired or rejected.");
            if(recover)status.Text=UiText.Get("Сессия истекла. Повторяю вход…");
            else {status.Text=UiText.Get("Запуск не завершён. Проверьте сообщение.");VeilMessage.Show(this,ex.Message,"CapCut Launcher",MessageBoxButtons.OK,MessageBoxIcon.Information);}
        }
        finally{Busy(false);}
        if(recover)await Run(true,true);
    }
    async Task Check() {
        Busy(true);
        try{Prepare(false);await Script("scripts/launch_capcut.ps1","-Region "+RegionCode()+" -ShowProUI -NoDiagnostics -CheckOnly");
            string version=FileVersionInfo.GetVersionInfo(app.Text).FileVersion;
            status.Text=UiText.Get("Готово к запуску. Найден CapCut ")+version+UiText.Get(".\nВсе необходимые библиотеки доступны. Браузер проверяется при входе.");
        }catch(Exception ex){VeilMessage.Show(this,ex.Message,UiText.Get("Проверка"),MessageBoxButtons.OK,MessageBoxIcon.Information);status.Text=UiText.Get("Проверка не пройдена.");}
        finally{Busy(false);}
    }
    [STAThread]static int Main(string[] args) {
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        string fixture=null,previous=Environment.GetEnvironmentVariable("CAPCUT_LAUNCHER_STATE_ROOT");
        try{
            if(args.Contains("--check-only")){fixture=Path.Combine(Path.GetTempPath(),"capcut-launcher-check-"+Guid.NewGuid().ToString("N"));Environment.SetEnvironmentVariable("CAPCUT_LAUNCHER_STATE_ROOT",fixture);}
            UiText.Initialize(AppDomain.CurrentDomain.BaseDirectory);
            using(var form=new Launcher()){if(args.Contains("--check-only"))return 0;Application.Run(form);}return 0;
        }
        catch(Exception ex){VeilMessage.Show(ex.Message,"CapCut Launcher");return 1;}
        finally{if(fixture!=null){Environment.SetEnvironmentVariable("CAPCUT_LAUNCHER_STATE_ROOT",previous);if(Directory.Exists(fixture))Directory.Delete(fixture,true);}}
    }
}
