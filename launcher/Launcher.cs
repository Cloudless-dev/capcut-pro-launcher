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

internal sealed class Launcher : Form {
    readonly string root = AppDomain.CurrentDomain.BaseDirectory;
    readonly string stateRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CapCutLauncher");
    readonly TextBox app = new TextBox();
    readonly RegionPicker region = new RegionPicker();
    readonly Label status = new Label();
    readonly List<Button> actions = new List<Button>();
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly Color ink = Color.FromArgb(30, 31, 34);
    readonly Timer accountTimer = new Timer();
    readonly ToolTip accountTip = new ToolTip();
    Button accountButton;
    Button languageButton;
    string accountName="";
    bool working;

    Launcher() {
        Text = "CapCut Launcher · " + BuildVersion.Display; ClientSize = new Size(660, 530);
        AutoScaleMode = AutoScaleMode.Dpi; Font = new Font("Segoe UI", 10);
        BackColor = Color.FromArgb(249, 249, 247); ForeColor = ink;
        FormBorderStyle = FormBorderStyle.FixedSingle; MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Icon = new Icon(Path.Combine(root, "assets", "launcher.ico"));
        var logo = new PictureBox {Image=Image.FromFile(Path.Combine(root,"assets","launcher.png")),SizeMode=PictureBoxSizeMode.Zoom,Bounds=new Rectangle(30,29,56,56)};
        Controls.Add(logo);
        LabelAt("CapCut Launcher",104,28,420,35,20,FontStyle.Bold);
        var versionButton=ButtonAt("v"+BuildVersion.Display,536,28,94,32,async delegate{await UpdateLauncher();});versionButton.Tag=null;
        LabelAt(UiText.Get("Ваш аккаунт. Ваш регион."),106,65,370,28,10,FontStyle.Regular);
        languageButton=ButtonAt("English",506,72,124,34,delegate{UiText.English=!UiText.English;ApplyLanguage();SaveSettings();UiText.Notify();});languageButton.Tag=null;
        LabelAt(UiText.Get("Приложение"),30,116,550,24,10,FontStyle.Bold);
        var pathFrame=new Panel {Bounds=new Rectangle(30,145,370,34),BackColor=Color.FromArgb(238,238,235)};Controls.Add(pathFrame);
        app.SetBounds(40,152,350,24); app.Font=new Font("Segoe UI",9);app.BackColor=pathFrame.BackColor;app.ForeColor=ink;app.BorderStyle=BorderStyle.None;app.ReadOnly=true;
        Controls.Add(app);
        app.BringToFront();
        ButtonAt(UiText.Get("Найти CapCut"),410,145,112,32,delegate {
            string found=DetectApp();
            if(found.Length>0){app.Text=found;status.Text=UiText.Get("CapCut найден: ")+FileVersionInfo.GetVersionInfo(found).FileVersion+UiText.Get(". Выберите регион и действие.");}
            else status.Text=UiText.Get("CapCut не найден. Установите приложение или укажите CapCut.exe через «Обзор».");
        });
        ButtonAt(UiText.Get("Обзор…"),532,145,98,32,delegate {
            using(var dialog=new OpenFileDialog {Filter="CapCut.exe|CapCut.exe",Title=UiText.Get("Выберите установленный CapCut.exe")})
                if(dialog.ShowDialog(this)==DialogResult.OK)app.Text=dialog.FileName;
        });
        LabelAt(UiText.Get("Регион интерфейса"),30,195,550,24,10,FontStyle.Bold);
        region.SetBounds(30,225,600,38);
        region.BackColor=Color.White;region.ForeColor=ink;
        region.Items.AddRange(new[]{UiText.Get("US — США"), UiText.Get("NL — Нидерланды")});
        Controls.Add(region);region.SelectedIndex=0;
        LabelAt(UiText.Get("Регион сохранится для следующих запусков."),30,265,600,27,9,FontStyle.Regular);
        var launch=ButtonAt(UiText.Get("Запустить CapCut"),30,305,292,48,async delegate {await Run(false);});
        ((QuietButton)launch).IsPrimary=true;launch.BackColor=Color.FromArgb(30,31,34);launch.ForeColor=Color.White;launch.Font=new Font(Font,FontStyle.Bold);
        accountButton=ButtonAt(UiText.Get("Войти через email"),338,305,292,48,async delegate {await Run(true);});
        ButtonAt(UiText.Get("Проверить готовность"),30,369,190,34,async delegate {await Check();});
        ButtonAt(UiText.Get("Забыть вход"),235,369,190,34,async delegate {await Forget();});
        ButtonAt(UiText.Get("Инструкция"),440,369,190,34,delegate {new HelpWindow(root,Icon).Show(this);});
        status.SetBounds(30,422,600,72);status.Font=new Font("Segoe UI",9); status.ForeColor=Color.FromArgb(110,111,116);Controls.Add(status);
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(working)e.Cancel=true;else{
            try{SaveSettings();}catch{ }
        }};
        LoadSettings();ApplyLanguage();
        Shown+=delegate{ActiveControl=launch;};
        RefreshAccount();accountTimer.Interval=1500;accountTimer.Tick+=delegate{RefreshAccount();};accountTimer.Start();
        FormClosed+=delegate{accountTimer.Dispose();accountTip.Dispose();};
    }
    void LabelAt(string text,int x,int y,int width,int height,float size,FontStyle style) {
        Controls.Add(new Label {Text=text,Tag=UiText.Source(text),Bounds=new Rectangle(x,y,width,height),Font=new Font("Segoe UI",size,style),ForeColor=ink});
    }
    Button ButtonAt(string text,int x,int y,int width,int height,EventHandler handler) {
        var b=new QuietButton {Text=text,Tag=UiText.Source(text),Bounds=new Rectangle(x,y,width,height),FlatStyle=FlatStyle.Flat,BackColor=Color.White,ForeColor=ink,Cursor=Cursors.Hand};
        b.FlatAppearance.BorderSize=0;b.Click+=handler;Controls.Add(b);actions.Add(b);return b;
    }
    async Task UpdateLauncher(){
        Busy(true);
        try{
            status.Text=UiText.Get("Проверяем обновления…");
            var update=await Task.Run(()=>LauncherUpdate.Find());
            if(update==null){status.Text=UiText.Get("Установлена последняя версия.");return;}
            if(Process.GetProcessesByName("CapCut").Length>0||Process.GetProcessesByName("CapCutBrowserLogin").Length>0)
                throw new Exception(UiText.Get("Закройте CapCut и окно входа перед обновлением."));
            if(MessageBox.Show(this,UiText.Get("Доступна версия ")+update.Version+UiText.Get(". Скачать и установить?"),"CapCut Launcher",MessageBoxButtons.YesNo,MessageBoxIcon.Information)!=DialogResult.Yes)return;
            status.Text=UiText.Get("Скачиваем обновление…");
            string archive=await Task.Run(()=>LauncherUpdate.Download(update,stateRoot));
            LauncherUpdate.Install(root,archive,update.Hash);
            working=false;Application.Exit();
        }catch(Exception ex){status.Text=UiText.Get("Не удалось обновить: ")+ex.Message;}
        finally{Busy(false);}
    }
    string RegionCode() {
        string code=region.Text.Split(new[]{' ','—'},StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()??"";
        if(code!="US"&&code!="NL")throw new Exception(UiText.Get("Выберите регион из списка: US или NL."));
        return code.ToUpperInvariant();
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
                if(settings.ContainsKey("language"))UiText.English=settings["language"]=="en";
                if(settings.ContainsKey("appPath")&&File.Exists(settings["appPath"]))app.Text=settings["appPath"];
                if(settings.ContainsKey("region"))for(int i=0;i<region.Items.Count;i++)
                    if(region.Items[i].ToString().StartsWith(settings["region"]+" —"))region.SelectedIndex=i;
            }
        }catch { }
        if(app.Text.Length==0)app.Text=DetectApp();
    }
    void Prepare(bool requireClosed) {
        if(!Environment.Is64BitOperatingSystem)throw new Exception(UiText.Get("Требуется Windows x64."));
        if(!File.Exists(app.Text)||!String.Equals(Path.GetFileName(app.Text),"CapCut.exe",StringComparison.OrdinalIgnoreCase))
            throw new Exception(UiText.Get("Укажите установленный CapCut.exe через «Обзор»."));
        if(requireClosed&&Process.GetProcessesByName("CapCut").Length>0)throw new Exception(UiText.Get("Полностью закройте CapCut и повторите."));
        string code=RegionCode();SaveSettings();
        Environment.SetEnvironmentVariable("CAPCUT_APP_PATH",app.Text);
        Environment.SetEnvironmentVariable("CAPCUT_REGION",code);
        Environment.SetEnvironmentVariable("CAPCUT_STATE_ROOT",stateRoot);
        Environment.SetEnvironmentVariable("CAPCUT_LANGUAGE",UiText.English?"en":"ru");
    }
    void SaveSettings(){
        Directory.CreateDirectory(stateRoot);
        File.WriteAllText(Path.Combine(stateRoot,"settings.json"),json.Serialize(new {appPath=app.Text,region=RegionCode(),language=UiText.English?"en":"ru"}));
    }
    void ApplyLanguage(){
        foreach(Control control in Controls)if(control.Tag is string)control.Text=UiText.Get((string)control.Tag);
        int selected=region.SelectedIndex;region.Items.Clear();region.Items.AddRange(new[]{UiText.Get("US — США"),UiText.Get("NL — Нидерланды")});region.SelectedIndex=selected;
        region.AccessibleName=UiText.Get("Регион интерфейса");
        languageButton.Text=UiText.English?"Русский":"English";
        status.Text=UiText.Get("Закройте CapCut перед запуском. Для первого входа используйте «Войти через email».");RefreshAccount();
    }
    void Busy(bool value){working=value;foreach(var b in actions)b.Enabled=!value;app.Enabled=region.Enabled=!value;}
    void RefreshAccount(){
        accountName="";
        try{
            string file=Path.Combine(stateRoot,"auth-browser-sdk","desktop-session.bin");
            if(File.Exists(file)){
                byte[] raw=ProtectedData.Unprotect(File.ReadAllBytes(file),null,DataProtectionScope.CurrentUser);
                var saved=json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(raw));
                object value;
                if(saved.TryGetValue("displayName",out value))accountName=Convert.ToString(value);
                // Compatibility: older bundles have no display name.
                if(String.IsNullOrWhiteSpace(accountName))using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Bytedance\CapCut\Account")){
                    string packed=key==null?null:key.GetValue("user_info") as string;
                    if(!String.IsNullOrEmpty(packed)){
                        var native=json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(Convert.FromBase64String(packed)));
                        if(native.TryGetValue("uid",out value)&&Convert.ToString(value)!="0")
                            foreach(string field in new[]{"nick_name","screen_name"})if(native.TryGetValue(field,out value)&&!String.IsNullOrWhiteSpace(Convert.ToString(value))){accountName=Convert.ToString(value);break;}
                    }
                }
            }
        }catch{accountName="";}
        accountButton.Text=String.IsNullOrWhiteSpace(accountName)?UiText.Get("Войти через email"):accountName;
        accountTip.SetToolTip(accountButton,accountName.Length==0?UiText.Get("Войти в аккаунт CapCut через сайт"):UiText.Get("Сохранённый аккаунт: ")+accountName+UiText.Get(". Нажмите для повторного входа."));
        accountButton.Invalidate();
    }
    async Task<string> Script(string relative,string arguments) {
        var info=new ProcessStartInfo("powershell.exe","-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \""+Path.Combine(root,relative)+"\" "+arguments) {
            UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=root,RedirectStandardOutput=true,RedirectStandardError=true
        };
        using(var p=Process.Start(info)) {
            var output=p.StandardOutput.ReadToEndAsync();var errors=p.StandardError.ReadToEndAsync();
            await Task.Run(()=>p.WaitForExit());string text=await output;string error=await errors;
            if(p.ExitCode!=0)throw new Exception(error.Length>0?error:text);
            return text.Trim();
        }
    }
    async Task<bool> WebViewReady() {
        bool ready=true;
        try{await Script("scripts/auth/start_browser_login.ps1","-CheckOnly");}
        catch {ready=false;}
        if(ready)return true;
        if(MessageBox.Show(this,UiText.Get("Для входа нужен Microsoft WebView2 Runtime. Установить его официальным установщиком Microsoft из комплекта? Нужен интернет."),"WebView2",MessageBoxButtons.YesNo,MessageBoxIcon.Information)!=DialogResult.Yes)return false;
        var info=new ProcessStartInfo(Path.Combine(root,"runtime","MicrosoftEdgeWebview2Setup.exe"),"/install"){UseShellExecute=true};
        using(var p=Process.Start(info))await Task.Run(()=>p.WaitForExit());
        await Script("scripts/auth/start_browser_login.ps1","-CheckOnly");return true;
    }
    async Task Run(bool login) {
        Busy(true);
        try {
            Prepare(true);status.Text=login?UiText.Get("Проверяю браузерный компонент…"):UiText.Get("Запускаю CapCut с регионом ")+RegionCode()+"…";
            if(login){if(!await WebViewReady()){status.Text=UiText.Get("Установка отменена. CapCut не запускался.");return;}
                DateTime started=DateTime.UtcNow;
                status.Text=UiText.Get("Окно входа открыто. Войдите на сайте CapCut или закройте окно для отмены.");
                await Script("scripts/auth/start_browser_login.ps1","-WaitForExit");
                RefreshAccount();
                string sessionFile=Path.Combine(stateRoot,"auth-browser-sdk","desktop-session.bin");
                status.Text=accountName.Length>0&&File.Exists(sessionFile)&&File.GetLastWriteTimeUtc(sessionFile)>=started
                    ?UiText.Get("Вход выполнен: ")+accountName+".":UiText.Get("Окно входа закрыто. Новый вход не выполнен.");
            } else {
                string result=await Script("scripts/launch_capcut.ps1","-Region "+RegionCode()+" -ShowProUI -NoDiagnostics");
                status.Text=result.Contains("CapCut запущен")?UiText.Get("CapCut открыт. Регион — ")+RegionCode()+".":UiText.Get("CapCut запускается. Дождитесь окна приложения.");
            }
        }catch(Exception ex){status.Text=UiText.Get("Запуск не завершён. Проверьте сообщение.");MessageBox.Show(this,ex.Message,"CapCut Launcher",MessageBoxButtons.OK,MessageBoxIcon.Information);}
        finally{Busy(false);}
    }
    async Task Check() {
        Busy(true);
        try{Prepare(false);await Script("scripts/launch_capcut.ps1","-Region "+RegionCode()+" -ShowProUI -NoDiagnostics -CheckOnly");
            string version=FileVersionInfo.GetVersionInfo(app.Text).FileVersion;
            status.Text=UiText.Get("Готово к запуску. Найден CapCut ")+version+UiText.Get(".\nВсе необходимые библиотеки доступны. Браузер проверяется при входе.");
        }catch(Exception ex){MessageBox.Show(this,ex.Message,UiText.Get("Проверка"),MessageBoxButtons.OK,MessageBoxIcon.Information);status.Text=UiText.Get("Проверка не пройдена.");}
        finally{Busy(false);}
    }
    async Task Forget() {
        if(MessageBox.Show(this,UiText.Get("Удалить сохранённый вход, cookies браузера лаунчера и локальную запись аккаунта CapCut? Следующий вход можно будет выполнить в другой аккаунт. Проекты останутся."),UiText.Get("Забыть вход"),MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        Busy(true);
        try{Prepare(true);await Script("scripts/auth/forget_saved_login.ps1","");RefreshAccount();status.Text=UiText.Get("Вход и браузерный профиль удалены. Можно войти в другой аккаунт.");}
        catch(Exception ex){MessageBox.Show(this,ex.Message);}
        finally{Busy(false);}
    }
    [STAThread]static int Main(string[] args) {
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        try{UiText.Initialize(AppDomain.CurrentDomain.BaseDirectory);var form=new Launcher();if(args.Contains("--check-only")){form.Dispose();return 0;}Application.Run(form);return 0;}
        catch(Exception ex){MessageBox.Show(ex.Message,"CapCut Launcher");return 1;}
    }
}

internal sealed class QuietButton : Button {
    public bool IsPrimary {get;set;}
    public bool CheckMark {get;set;}
    bool hover;
    public QuietButton(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
    protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hover=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnGotFocus(EventArgs e){Invalidate();base.OnGotFocus(e);}
    protected override void OnLostFocus(EventArgs e){Invalidate();base.OnLostFocus(e);}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent.BackColor);
        var rect=new Rectangle(1,1,Width-3,Height-3);int diameter=14;
        using(var path=new GraphicsPath()){
            path.AddArc(rect.Left,rect.Top,diameter,diameter,180,90);
            path.AddArc(rect.Right-diameter,rect.Top,diameter,diameter,270,90);
            path.AddArc(rect.Right-diameter,rect.Bottom-diameter,diameter,diameter,0,90);
            path.AddArc(rect.Left,rect.Bottom-diameter,diameter,diameter,90,90);path.CloseFigure();
            Color fill=!Enabled?Color.FromArgb(235,235,232):hover?(IsPrimary?Color.FromArgb(58,59,63):Color.FromArgb(240,240,237)):BackColor;
            using(var brush=new SolidBrush(fill))e.Graphics.FillPath(brush,path);
            using(var pen=new Pen(IsPrimary?fill:Color.FromArgb(220,221,218),1))e.Graphics.DrawPath(pen,path);
            if(Focused)using(var pen=new Pen(Color.FromArgb(135,136,140),1.5f))e.Graphics.DrawPath(pen,path);
        }
        bool left=TextAlign==ContentAlignment.MiddleLeft;
        var textRect=left?new Rectangle(15,0,Width-45,Height):ClientRectangle;
        TextRenderer.DrawText(e.Graphics,Text,Font,textRect,Enabled?ForeColor:Color.Gray,(left?TextFormatFlags.Left:TextFormatFlags.HorizontalCenter)|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);
        if(CheckMark)TextRenderer.DrawText(e.Graphics,"✓",Font,new Rectangle(Width-32,0,20,Height),Color.FromArgb(115,73,195),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
    }
}

internal sealed class RegionPicker : Control {
    public readonly List<string> Items=new List<string>();
    int selected;
    bool expanded;
    public int SelectedIndex {get{return selected;}set{selected=value;Invalidate();}}
    public override string Text {get{return selected>=0&&selected<Items.Count?Items[selected]:"";}set{}}
    public RegionPicker(){Cursor=Cursors.Hand;TabStop=true;AccessibleName=UiText.Get("Регион интерфейса");AccessibleRole=AccessibleRole.ComboBox;
        SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
    protected override void OnClick(EventArgs e){base.OnClick(e);if(Enabled)Open();}
    protected override void OnKeyDown(KeyEventArgs e){if(e.KeyCode==Keys.Space||e.KeyCode==Keys.Enter||e.KeyCode==Keys.Down){Open();e.Handled=true;}base.OnKeyDown(e);}
    void Open(){
        if(expanded)return;
        expanded=true;Invalidate();
        var popup=new ToolStripDropDown {Padding=Padding.Empty,Margin=Padding.Empty,AutoClose=true,DropShadowEnabled=true,BackColor=Color.White,Renderer=new RegionRenderer()};
        var panel=new Panel {Width=Width,Height=Items.Count*46+12,BackColor=Color.White,Padding=new Padding(6)};
        for(int i=0;i<Items.Count;i++){
            int index=i;
            var row=new QuietButton {Text=Items[i],Font=Font,TextAlign=ContentAlignment.MiddleLeft,CheckMark=i==selected,
                Bounds=new Rectangle(6,6+i*46,Width-12,42),BackColor=i==selected?Color.FromArgb(243,239,251):Color.White,ForeColor=ForeColor,FlatStyle=FlatStyle.Flat,Cursor=Cursors.Hand};
            row.Click+=delegate{SelectedIndex=index;popup.Close();Focus();};panel.Controls.Add(row);
        }
        var host=new ToolStripControlHost(panel){Margin=Padding.Empty,Padding=Padding.Empty,AutoSize=false,Size=panel.Size};
        popup.Items.Add(host);popup.Closed+=delegate{
            expanded=false;Invalidate();
            // Native mouse-up processing still uses the menu during Closed.
            // Dispose after that callback has unwound, on the next UI message.
            BeginInvoke(new Action(delegate{popup.Dispose();}));
        };
        popup.Show(this,new Point(0,Height+5));
    }
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;e.Graphics.Clear(Parent.BackColor);
        var r=new Rectangle(1,1,Width-3,Height-3);int d=14;
        using(var path=new GraphicsPath()){
            path.AddArc(r.Left,r.Top,d,d,180,90);path.AddArc(r.Right-d,r.Top,d,d,270,90);
            path.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);path.AddArc(r.Left,r.Bottom-d,d,d,90,90);path.CloseFigure();
            using(var fill=new SolidBrush(BackColor))e.Graphics.FillPath(fill,path);
            using(var pen=new Pen(expanded?Color.FromArgb(151,124,197):Color.FromArgb(220,221,218)))e.Graphics.DrawPath(pen,path);
        }
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle(14,0,Width-48,Height),ForeColor,TextFormatFlags.Left|TextFormatFlags.VerticalCenter);
        int x=Width-24,y=Height/2;
        using(var pen=new Pen(Color.FromArgb(105,105,112),1.5f))e.Graphics.DrawLines(pen,new[]{new Point(x-4,y-2),new Point(x,y+2),new Point(x+4,y-2)});
    }
}
internal sealed class RegionRenderer : ToolStripProfessionalRenderer {
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e){using(var p=new Pen(Color.FromArgb(220,221,218)))e.Graphics.DrawRectangle(p,0,0,e.ToolStrip.Width-1,e.ToolStrip.Height-1);}
}

internal sealed class HelpWindow : Form {
    readonly string root;
    readonly Label heading,subtitle;
    readonly QuietButton close;
    readonly RichTextBox body;
    public HelpWindow(string root,Icon icon){
        this.root=root;
        Text=UiText.Get("Инструкция · CapCut Launcher ")+BuildVersion.Display;Icon=icon;ClientSize=new Size(720,720);MinimumSize=new Size(570,500);
        BackColor=Color.FromArgb(249,249,247);ForeColor=Color.FromArgb(30,31,34);Font=new Font("Segoe UI",10);
        StartPosition=FormStartPosition.CenterParent;
        heading=new Label{Text=UiText.Get("Как пользоваться"),Font=new Font("Segoe UI",22,FontStyle.Bold),Dock=DockStyle.Top,Height=76,Padding=new Padding(28,24,0,0)};
        subtitle=new Label{Text=UiText.Get("Версия ")+BuildVersion.Display+UiText.Get(" · запуск, аккаунт и настройки"),ForeColor=Color.FromArgb(110,111,116),Dock=DockStyle.Top,Height=40,Padding=new Padding(30,0,0,0)};
        var footer=new Panel{Dock=DockStyle.Bottom,Height=66,Padding=new Padding(24,12,24,12)};
        close=new QuietButton{Text=UiText.Get("Понятно"),IsPrimary=true,BackColor=Color.FromArgb(30,31,34),ForeColor=Color.White,Dock=DockStyle.Right,Width=130,Font=Font};close.Click+=delegate{Close();};footer.Controls.Add(close);
        var bodyPanel=new Panel{Dock=DockStyle.Fill,Padding=new Padding(30,8,26,8)};
        body=new RichTextBox{Dock=DockStyle.Fill,ReadOnly=true,BorderStyle=BorderStyle.None,BackColor=BackColor,ForeColor=ForeColor,Font=Font,DetectUrls=false,ScrollBars=RichTextBoxScrollBars.Vertical};
        bodyPanel.Controls.Add(body);Controls.Add(bodyPanel);Controls.Add(footer);Controls.Add(subtitle);Controls.Add(heading);
        RenderHelp();UiText.Changed+=RenderHelp;FormClosed+=delegate{UiText.Changed-=RenderHelp;};Shown+=delegate{ActiveControl=close;};
    }
    void RenderHelp(){
        Text=UiText.Get("Инструкция · CapCut Launcher ")+BuildVersion.Display;
        heading.Text=UiText.Get("Как пользоваться");subtitle.Text=UiText.Get("Версия ")+BuildVersion.Display+UiText.Get(" · запуск, аккаунт и настройки");close.Text=UiText.Get("Понятно");body.Clear();
        var titles=new HashSet<string>{UiText.Get("Быстрый старт"),UiText.Get("Что включено"),UiText.Get("Подписка"),UiText.Get("Сохранение входа"),UiText.Get("Поддерживаемая платформа"),UiText.Get("Если не запускается"),UiText.Get("PowerShell и права"),UiText.Get("Проверка ошибок"),UiText.Get("Структура")};
        bool warning=false;
        foreach(string line in File.ReadAllLines(Path.Combine(root,UiText.English?"Instructions.txt":"Инструкция.txt"),Encoding.UTF8)){
            if(line.StartsWith("CAPCUT LAUNCHER"))continue;
            bool title=titles.Contains(line)||line.StartsWith(UiText.Get("Проверенная конфигурация"))||line.StartsWith(UiText.Get("ВАЖНО:"));
            if(line.StartsWith(UiText.Get("ВАЖНО:")))warning=true;else if(title)warning=false;
            body.SelectionStart=body.TextLength;
            body.SelectionFont=new Font("Segoe UI",title?12:10,title?FontStyle.Bold:FontStyle.Regular);
            body.SelectionColor=warning?Color.FromArgb(125,78,39):title?ForeColor:Color.FromArgb(70,71,76);
            body.SelectionBackColor=warning?Color.FromArgb(251,242,229):BackColor;
            body.AppendText((title?"\n":"")+line+"\n");
        }
        body.Select(0,0);body.ScrollToCaret();
    }
}
