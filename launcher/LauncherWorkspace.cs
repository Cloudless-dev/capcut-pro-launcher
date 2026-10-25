using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
internal sealed partial class Launcher {
    LauncherProfiles profiles;
    string languagePreference="system",theme="system",interfaceSize="medium",projectsRoot;
    bool autoStart=true,automaticUpdates;
    readonly Dictionary<string,string> profileStatuses=new Dictionary<string,string>();
    LauncherProfile SelectedProfile{get{return profiles==null?null:profiles.Document.Profiles.FirstOrDefault(p=>p.Id==profiles.Document.SelectedId);}}
    string ProfileState{get{return SelectedProfile==null?stateRoot:profiles.DirectoryFor(SelectedProfile);}}
    bool CapCutOpen(){return Process.GetProcessesByName("CapCut").Length>0||Process.GetProcessesByName("CapCutBrowserLogin").Length>0;}
    void PopulateProfiles(){if(SelectedProfile!=null)region.Text=SelectedProfile.Region;}
    void ApplyTheme(){
        string effective=theme;
        if(effective=="system"){bool light=true;try{using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))light=key==null||Convert.ToInt32(key.GetValue("AppsUseLightTheme",1))!=0;}catch{}effective=light?"light":"dark";}
        VeilColors.Set(effective);BackColor=VeilColors.Canvas;ForeColor=VeilColors.Ink;
        if(IsHandleCreated){int dark=effective=="light"?0:1;try{DwmSetWindowAttribute(Handle,20,ref dark,4);}catch{}}
    }
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")]static extern int DwmSetWindowAttribute(IntPtr window,int attribute,ref int value,int size);
    string DefaultProjectsRoot() {
        var dataRoots=new List<string>{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CapCut","User Data")};
        string folder = String.IsNullOrWhiteSpace(app.Text) ? null : Path.GetDirectoryName(app.Text);
        while (!String.IsNullOrEmpty(folder)) {
            if (Directory.Exists(Path.Combine(folder, "User Data"))) dataRoots.Add(Path.Combine(folder,"User Data"));
            folder = Path.GetDirectoryName(folder);
        }
        return ProjectLocations.Detect(dataRoots);
    }
    string ReadNativeName(){
        try{using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Bytedance\CapCut\Account")){
            string packed=key==null?null:key.GetValue("user_info") as string;if(String.IsNullOrEmpty(packed))return "";
            var profile=json.Deserialize<Dictionary<string,object>>(System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(packed)));
            string uid=ProjectLibrary.Text(profile,"uid");if(uid=="0"||uid.Length==0)return "";
            foreach(string field in new[]{"email","email_address","nick_name","screen_name"}){
                string name=ProjectLibrary.Text(profile,field);if(String.IsNullOrWhiteSpace(name))continue;
                int at=name.IndexOf('@');if(at>0&&!name.Substring(0,at).Contains("*"))name=name.Substring(0,Math.Min(2,at))+"***"+name.Substring(at);
                return name;
            }
        }}catch{}return "";
    }
    async Task VerifyProfile() {
        Busy(true);
        try {
            Prepare(false);
            string result = await Script("scripts/auth/verify_saved_login.ps1", ""); status.Text = UiText.Get("Вход подтверждён") + ": " + result;profileStatuses[SelectedProfile.Id]="Вход подтверждён";SaveVerification("verified");
        } catch (Exception ex) { status.Text = ex.Message;if(SelectedProfile!=null){bool expired=ex.Message.ToLowerInvariant().Contains("expired");profileStatuses[SelectedProfile.Id]=expired?"Сессия истекла":"Не удалось проверить вход";if(expired)SaveVerification("expired");} }
        finally { Busy(false);PublishWebState(); }
    }
}
