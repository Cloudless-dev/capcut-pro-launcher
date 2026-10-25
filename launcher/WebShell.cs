using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal sealed partial class Launcher {
    WebView2 webShell;
    bool webBusy;
    TaskCompletionSource<bool> webConfirmation;
    readonly Dictionary<string,CapCutProject> webProjects=new Dictionary<string,CapCutProject>();
    const string WebOrigin="https://launcher.local/";
    async Task InitializeWebShell(){
        foreach(Control control in Controls)control.Visible=false;
        var loading=new Label{Text=UiText.Get("Загрузка…"),Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleCenter,BackColor=VeilColors.Canvas,ForeColor=VeilColors.Ink};Controls.Add(loading);
        try{
            webShell=new WebView2{Dock=DockStyle.Fill,DefaultBackgroundColor=VeilColors.Canvas};Controls.Add(webShell);webShell.BringToFront();
            var env=await CoreWebView2Environment.CreateAsync(null,Path.Combine(stateRoot,"launcher-webview"));
            await webShell.EnsureCoreWebView2Async(env);
            var core=webShell.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled=false;core.Settings.AreDevToolsEnabled=false;core.Settings.IsStatusBarEnabled=false;core.Settings.AreHostObjectsAllowed=false;
            core.SetVirtualHostNameToFolderMapping("launcher.local",Path.Combine(root,"ui"),CoreWebView2HostResourceAccessKind.DenyCors);
            core.NavigationStarting+=delegate(object sender,CoreWebView2NavigationStartingEventArgs e){if(!e.Uri.StartsWith(WebOrigin,StringComparison.Ordinal))e.Cancel=true;};
            core.NewWindowRequested+=delegate(object sender,CoreWebView2NewWindowRequestedEventArgs e){e.Handled=true;};
            core.PermissionRequested+=delegate(object sender,CoreWebView2PermissionRequestedEventArgs e){e.State=CoreWebView2PermissionState.Deny;};
            core.DownloadStarting+=delegate(object sender,CoreWebView2DownloadStartingEventArgs e){e.Cancel=true;};
            core.WebMessageReceived+=WebMessage;
            VeilMessage.Notify=message=>WebReply(new{type="notice",message=message});
            status.TextChanged+=delegate{PublishWebState();};
            core.Navigate(WebOrigin+"index.html");loading.Dispose();
        }catch(Exception ex){
            if(webShell!=null){webShell.Dispose();webShell=null;}loading.Text=UiText.English?"Microsoft WebView2 Runtime is required to open the launcher.\n"+ex.Message:"Для открытия лаунчера нужен Microsoft WebView2 Runtime.\n"+ex.Message;loading.BringToFront();
            var install=new Button{Text=UiText.English?"Install Microsoft WebView2":"Установить Microsoft WebView2",Dock=DockStyle.Bottom,Height=52,BackColor=VeilColors.Button,ForeColor=VeilColors.OnButton};Controls.Add(install);install.BringToFront();
            install.Click+=async delegate{install.Enabled=false;try{string installer=Path.Combine(root,"runtime","MicrosoftEdgeWebview2Setup.exe");if(!File.Exists(installer))throw new IOException("MicrosoftEdgeWebview2Setup.exe is missing from the bundle.");using(var process=Process.Start(new ProcessStartInfo(installer,"/install"){UseShellExecute=true}))await Task.Run(()=>process.WaitForExit());install.Dispose();loading.Dispose();await InitializeWebShell();}catch(Exception failure){loading.Text=failure.Message;install.Enabled=true;}};
        }
    }
    object WebState(){
        return new {type="state",version=BuildVersion.Display,theme=theme,effectiveTheme=VeilColors.Canvas.GetBrightness()>.5?"light":theme=="gray"?"gray":"dark",language=languagePreference,english=UiText.English,density=interfaceSize,busy=working||webBusy,status=status.Text,appPath=app.Text,projectsRoot=projectsRoot,autoStart=autoStart,automaticUpdates=automaticUpdates,selectedId=profiles.Document.SelectedId,capcutRunning=CapCutOpen(),profiles=profiles.Document.Profiles.Select(p=>{
            string state;profileStatuses.TryGetValue(p.Id,out state);if(String.IsNullOrEmpty(state))try{var saved=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(profiles.DirectoryFor(p),"verification.json")));string code=ProjectLibrary.Text(saved,"status");if(code=="expired")state="Сессия истекла";}catch(IOException){}catch(ArgumentException){}string label=p.NativeAccount?ReadNativeName():ReadProfileLabel(p);
            if(p.NativeAccount&&label.Length==0)state="Вход не выполнен";
            if(String.IsNullOrEmpty(state))state=label.Length>0?"Вход сохранён":"Вход не выполнен";
            bool credentials=File.Exists(Path.Combine(profiles.DirectoryFor(p),"credentials.json"));
            return new {id=p.Id,name=p.Name,region=p.Region,native=p.NativeAccount,automatic=p.AutomaticLogin!=false,hasCredentials=credentials,account=label,status=state};
        }).ToArray()};
    }
    void SaveVerification(string statusCode){if(SelectedProfile!=null){Directory.CreateDirectory(profiles.DirectoryFor(SelectedProfile));ProjectLibrary.Save(Path.Combine(profiles.DirectoryFor(SelectedProfile),"verification.json"),new{status=statusCode,checkedUtc=DateTime.UtcNow.ToString("o")});}}
    string ReadProfileLabel(LauncherProfile profile){
        try{string file=Path.Combine(profiles.DirectoryFor(profile),"auth-browser-sdk","desktop-session.bin");if(!File.Exists(file))return "";byte[] plain=ProtectedData.Unprotect(File.ReadAllBytes(file),null,DataProtectionScope.CurrentUser);try{var data=json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(plain));return ProjectLibrary.Text(data,"displayName");}finally{Array.Clear(plain,0,plain.Length);}}catch{return "";}
    }
    void PublishWebState(){if(webShell==null||webShell.CoreWebView2==null)return;try{webShell.CoreWebView2.PostWebMessageAsJson(json.Serialize(WebState()));}catch(InvalidOperationException){}}
    void WebReply(object data){if(webShell!=null&&webShell.CoreWebView2!=null)webShell.CoreWebView2.PostWebMessageAsJson(json.Serialize(data));}
    static bool Flag(Dictionary<string,object> data,string key){object value;return data.TryGetValue(key,out value)&&value is bool&&(bool)value;}
    LauncherProfile WebProfile(Dictionary<string,object> data){string id=ProjectLibrary.Text(data,"id");var profile=profiles.Document.Profiles.FirstOrDefault(p=>p.Id==id);if(profile==null)throw new IOException("Profile not found.");return profile;}
    void SelectWebProfile(LauncherProfile profile){if(working||CapCutOpen())throw new IOException(UiText.Get("Сначала закройте CapCut и окно входа."));profiles.Document.SelectedId=profile.Id;profiles.Save();PopulateProfiles();RefreshAccount();}
    async void WebMessage(object sender,CoreWebView2WebMessageReceivedEventArgs e){
        if(!e.Source.StartsWith(WebOrigin,StringComparison.Ordinal))return;
        string request="";
        try{
            if(e.WebMessageAsJson.Length>200000)throw new IOException("Request is too large.");
            var data=json.Deserialize<Dictionary<string,object>>(e.WebMessageAsJson);request=ProjectLibrary.Text(data,"request");string action=ProjectLibrary.Text(data,"action");
            if(action=="ready"){PublishWebState();return;}
            if(action=="confirm"){if(webConfirmation!=null){webConfirmation.TrySetResult(Flag(data,"accepted"));webConfirmation=null;}return;}
            if(webBusy||working)throw new IOException(UiText.Get("Дождитесь завершения операции."));
            if(action=="select")SelectWebProfile(WebProfile(data));
            else if(action=="saveProfile")SaveWebProfile(data);
            else if(action=="deleteProfile"){var p=WebProfile(data);if(CapCutOpen())throw new IOException(UiText.Get("Сначала закройте CapCut и окно входа."));profiles.Delete(p);PopulateProfiles();RefreshAccount();}
            else if(action=="verify"){SelectWebProfile(WebProfile(data));await VerifyProfile();}
            else if(action=="login"){SelectWebProfile(WebProfile(data));await Run(true);}
            else if(action=="loginSelected")await Run(true);
            else if(action=="launch"){if(SelectedProfile!=null&&!SelectedProfile.NativeAccount&&!File.Exists(Path.Combine(ProfileState,"auth-browser-sdk","desktop-session.bin")))await Run(true,true);else await Run(false);}
            else if(action=="settings")ApplyWebSettings(data);
            else if(action=="detect"){app.Text=DetectApp();SaveSettings();}
            else if(action=="browseApp"){using(var dialog=new OpenFileDialog{Filter="CapCut.exe|CapCut.exe"})if(dialog.ShowDialog(this)==DialogResult.OK){app.Text=dialog.FileName;SaveSettings();}}
            else if(action=="browseProjects"){using(var dialog=new FolderBrowserDialog{SelectedPath=projectsRoot})if(dialog.ShowDialog(this)==DialogResult.OK){projectsRoot=dialog.SelectedPath;SaveSettings();}}
            else if(action=="openProjects"){if(Directory.Exists(projectsRoot))Process.Start(new ProcessStartInfo(projectsRoot){UseShellExecute=true});}
            else if(action=="check")await Check();
            else if(action=="update")await UpdateLauncher();
            else if(action=="forget"){SelectWebProfile(WebProfile(data));Prepare(true);if(SelectedProfile.NativeAccount)throw new IOException("Official CapCut account cannot be cleared here.");await Script("scripts/auth/forget_saved_login.ps1","");profileStatuses.Remove(SelectedProfile.Id);RefreshAccount();}
            else if(action=="projects")await LoadWebProjects(Flag(data,"trash"));
            else if(action=="projectAction")await WebProjectAction(data);
            else throw new IOException("Unknown action.");
            PublishWebState();WebReply(new{type="result",request=request,ok=true});
        }catch(Exception ex){WebReply(new{type="result",request=request,ok=false,error=ex.Message});PublishWebState();}
    }
    async Task<bool> ConfirmWeb(string title,string body){
        if(webShell==null)return VeilMessage.Show(this,body,title,MessageBoxButtons.YesNo)==DialogResult.Yes;
        if(webConfirmation!=null)return false;webConfirmation=new TaskCompletionSource<bool>();var task=webConfirmation.Task;WebReply(new{type="confirm",title=title,body=body});return await task;
    }
    void SaveWebProfile(Dictionary<string,object> data){
        if(CapCutOpen())throw new IOException(UiText.Get("Сначала закройте CapCut и окно входа."));
        string id=ProjectLibrary.Text(data,"id"),name=ProjectLibrary.Text(data,"name").Trim();if(name.Length==0||name.Length>100)throw new IOException(UiText.Get("Введите имя профиля."));
        var p=id.Length==0?new LauncherProfile{Id=Guid.NewGuid().ToString()}:WebProfile(data);
        string country=LauncherProfiles.Country(ProjectLibrary.Text(data,"region")),mail=ProjectLibrary.Text(data,"email").Trim(),password=ProjectLibrary.Text(data,"password");
        bool native=Flag(data,"native"),automatic=Flag(data,"automatic");
        if(!native&&automatic&&data.ContainsKey("email")&&!File.Exists(Path.Combine(profiles.DirectoryFor(p),"credentials.json"))&&(mail.Length==0||password.Length==0))throw new IOException(UiText.English?"Enter email and password for automatic sign-in, or turn it off to sign in through the browser.":"Введите почту и пароль для автоматического входа или выключите его для входа через браузер.");
        if(!native&&password.Length>0){if(mail.Length==0)throw new IOException(UiText.Get("Введите email."));string slot=profiles.DirectoryFor(p),browser=Path.Combine(slot,"auth-browser-profile"),session=Path.Combine(slot,"auth-browser-sdk","desktop-session.bin");if(Directory.Exists(browser)){foreach(var ignored in ProjectLibrary.Files(browser)){}Directory.Delete(browser,true);}if(File.Exists(session)){ProjectLibrary.NoLinks(session);File.Delete(session);}LauncherProfiles.SaveCredentials(slot,mail,password);profileStatuses.Remove(p.Id);}
        else if(!native&&mail.Length>0){var saved=LauncherProfiles.Credentials(profiles.DirectoryFor(p));if(saved==null||saved["email"]!=mail)throw new IOException(UiText.Get("При смене email введите пароль заново."));}
        p.Name=name;p.Region=country;p.NativeAccount=native;p.AutomaticLogin=automatic;if(id.Length==0)profiles.Document.Profiles.Add(p);profiles.Document.SelectedId=p.Id;profiles.Save();PopulateProfiles();RefreshAccount();
    }
    void ApplyWebSettings(Dictionary<string,object> data){
        string value=ProjectLibrary.Text(data,"theme");if(new[]{"system","light","gray","dark"}.Contains(value))theme=value;
        value=ProjectLibrary.Text(data,"language");if(new[]{"system","ru","en"}.Contains(value)){languagePreference=value;UiText.English=value=="en"||value=="system"&&System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName!="ru";}
        value=ProjectLibrary.Text(data,"density");if(new[]{"small","medium","large"}.Contains(value))interfaceSize=value;
        if(data.ContainsKey("autoStart"))autoStart=Flag(data,"autoStart");if(data.ContainsKey("automaticUpdates"))automaticUpdates=Flag(data,"automaticUpdates");SaveSettings();ApplyTheme();
    }
    async Task LoadWebProjects(bool trash){
        webBusy=true;PublishWebState();try{
            var library=new ProjectLibrary(projectsRoot,Path.Combine(stateRoot,"project-backups"));var items=await Task.Run(()=>trash?library.ScanTrash():library.Scan());webProjects.Clear();
            var result=new List<object>();foreach(var p in items){string key=Guid.NewGuid().ToString("N");webProjects[key]=p;string cover=null;if(p.Cover!=null&&File.Exists(p.Cover)&&new FileInfo(p.Cover).Length<20000000){try{using(var input=Image.FromFile(p.Cover))using(var image=new Bitmap(480,270))using(var stream=new MemoryStream()){using(var graphics=Graphics.FromImage(image)){graphics.Clear(Color.FromArgb(244,242,252));graphics.DrawImage(input,0,0,480,270);}image.Save(stream,System.Drawing.Imaging.ImageFormat.Jpeg);cover="data:image/jpeg;base64,"+Convert.ToBase64String(stream.ToArray());}}catch(ArgumentException){}catch(OutOfMemoryException){}catch(IOException){}}
                result.Add(new{id=key,name=p.Name,cover=cover,date=(trash?p.Deleted:p.Modified).ToLocalTime().ToString("dd.MM.yyyy"),bytes=p.Bytes,incomplete=p.Incomplete});}
            WebReply(new{type="projects",trash=trash,items=result});
        }finally{webBusy=false;PublishWebState();}
    }
    async Task WebProjectAction(Dictionary<string,object> data){
        bool trash=Flag(data,"trash");string operation=ProjectLibrary.Text(data,"operation");object raw;var chosen=new List<CapCutProject>();if(data.TryGetValue("ids",out raw)){var ids=raw as System.Collections.IEnumerable;if(ids!=null)foreach(var id in ids){CapCutProject p;if(!webProjects.TryGetValue(Convert.ToString(id),out p))throw new IOException("Refresh projects before retrying.");chosen.Add(p);}}
        if(operation=="open"){if(chosen.Count==1)Process.Start(new ProcessStartInfo(chosen[0].Folder){UseShellExecute=true});return;}
        string destination=null;if(operation=="import"||operation=="export"||operation=="move"){using(var dialog=new FolderBrowserDialog())if(dialog.ShowDialog(this)==DialogResult.OK)destination=dialog.SelectedPath;else return;}
        webBusy=true;PublishWebState();try{var library=new ProjectLibrary(projectsRoot,Path.Combine(stateRoot,"project-backups"));ProjectResult result=await Task.Run(()=>{
            if(operation=="import")return library.Import(destination);
            if(chosen.Count==0)throw new IOException(UiText.Get("Выберите проекты."));
            if(operation=="export"||operation=="move")return library.Export(chosen,destination,Flag(data,"media"),operation=="move");
            if(operation=="restore")return library.Restore(chosen);
            if(operation=="delete")return trash?library.PermanentlyDeleteTrash(chosen):library.Trash(chosen);
            throw new IOException("Unknown project action.");});status.Text=UiText.Get("Готово: ")+result.Completed+UiText.Get(". Пропущено: ")+result.Skipped;
        }finally{webBusy=false;}await LoadWebProjects(trash);
    }
}
