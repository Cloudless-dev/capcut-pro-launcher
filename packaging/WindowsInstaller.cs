using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows.Forms;

internal sealed class WindowsInstaller:Form {
    const string Version="__VERSION__",ArchiveHash="__ARCHIVE_SHA256__";
    const string ArchiveUrl="https://github.com/Cloudless-dev/capcut-pro-launcher/releases/download/windows-v__VERSION__/CapCut-Launcher-__VERSION__-Windows-x64.zip";
    readonly TextBox folder=new TextBox();
    readonly Label message=new Label();
    readonly SetupProgress progress=new SetupProgress();
    readonly SetupToggle desktop=new SetupToggle();
    readonly SetupButton install=new SetupButton{Primary=true};
    readonly SetupButton browse=new SetupButton();
    readonly SetupButton cancel=new SetupButton();
    readonly Label heading=new Label(),subtitle=new Label(),percent=new Label(),stageTitle=new Label(),details=new Label();
    readonly Panel options=new Panel(),activity=new Panel();
    readonly PictureBox stateIcon=new PictureBox();
    WebClient activeDownload;
    bool busy,complete,cancelRequested;
    readonly bool english=System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName!="ru";
    string T(string ru,string en){return english?en:ru;}
    WindowsInstaller(){
        Text="CapCut Launcher · "+Version;ClientSize=new Size(660,500);AutoScaleMode=AutoScaleMode.Dpi;FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;Font=new Font("Segoe UI",10);BackColor=SetupStyle.Canvas;ForeColor=SetupStyle.Ink;
        Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var logo=new PictureBox{Bounds=new Rectangle(32,30,56,56),SizeMode=PictureBoxSizeMode.Zoom,Image=Asset("launcher.png")};Controls.Add(logo);
        Controls.Add(new Label{Text="CapCut Launcher",Bounds=new Rectangle(102,29,390,32),Font=new Font("Segoe UI",18,FontStyle.Bold)});
        Controls.Add(new Label{Text="WINDOWS  ·  "+Version,Bounds=new Rectangle(104,65,380,20),ForeColor=SetupStyle.Muted,Font=new Font("Segoe UI",9)});
        heading.SetBounds(32,113,595,38);heading.Font=new Font("Segoe UI",23,FontStyle.Bold);heading.Text=T("Установка лаунчера","Install launcher");Controls.Add(heading);
        subtitle.SetBounds(35,160,588,30);subtitle.ForeColor=SetupStyle.Muted;subtitle.Text=T("Выберите папку. Остальное установщик сделает сам.","Choose a folder. Setup will take care of the rest.");Controls.Add(subtitle);
        var card=new SetupCard{Bounds=new Rectangle(32,205,596,190)};Controls.Add(card);
        options.Bounds=new Rectangle(2,12,592,166);options.BackColor=Color.Transparent;card.Controls.Add(options);
        options.Controls.Add(new Label{Text=T("Папка установки","Installation folder"),Bounds=new Rectangle(22,20,548,25),Font=new Font("Segoe UI",10,FontStyle.Bold)});
        var field=new SetupCard{Bounds=new Rectangle(20,54,422,44),Padding=new Padding(12,12,12,8)};folder.BorderStyle=BorderStyle.None;folder.Dock=DockStyle.Fill;folder.BackColor=SetupStyle.Card;folder.ForeColor=SetupStyle.Ink;folder.Font=new Font("Segoe UI",9);folder.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","CapCutLauncher");field.Controls.Add(folder);options.Controls.Add(field);
        browse.Text=T("Выбрать…","Browse…");browse.SetBounds(452,54,122,44);browse.Click+=delegate{using(var dialog=new FolderBrowserDialog{SelectedPath=folder.Text})if(dialog.ShowDialog(this)==DialogResult.OK)folder.Text=dialog.SelectedPath;};options.Controls.Add(browse);
        desktop.Text=T("Ярлык на рабочем столе","Desktop shortcut");desktop.Checked=true;desktop.SetBounds(22,120,550,40);desktop.BackColor=SetupStyle.Card;options.Controls.Add(desktop);
        activity.Bounds=new Rectangle(2,12,592,166);activity.BackColor=Color.Transparent;activity.Visible=false;card.Controls.Add(activity);
        stateIcon.SetBounds(22,24,44,44);stateIcon.SizeMode=PictureBoxSizeMode.Zoom;activity.Controls.Add(stateIcon);
        stageTitle.SetBounds(80,24,488,30);stageTitle.Font=new Font("Segoe UI",13,FontStyle.Bold);activity.Controls.Add(stageTitle);
        details.SetBounds(81,58,488,38);details.ForeColor=SetupStyle.Muted;details.Font=new Font("Segoe UI",9);activity.Controls.Add(details);
        progress.SetBounds(24,127,475,8);progress.BackColor=SetupStyle.Card;activity.Controls.Add(progress);
        percent.SetBounds(512,115,60,28);percent.TextAlign=ContentAlignment.MiddleRight;percent.ForeColor=SetupStyle.Accent;activity.Controls.Add(percent);
        message.SetBounds(35,406,590,26);message.Font=new Font("Segoe UI",9);message.ForeColor=SetupStyle.Muted;message.Text=T("Для загрузки нужен интернет.","Internet is required for the download.");Controls.Add(message);
        cancel.Text=T("Отмена","Cancel");cancel.SetBounds(302,442,122,42);cancel.Click+=delegate{if(busy){cancelRequested=true;if(activeDownload!=null)activeDownload.CancelAsync();cancel.Enabled=false;message.Text=T("Отмена…","Cancelling…");}else Close();};Controls.Add(cancel);
        install.Text=T("Установить","Install");install.SetBounds(438,442,190,42);install.Click+=async delegate{if(complete){Process.Start(new ProcessStartInfo(Path.Combine(folder.Text,"CapCut Launcher.exe")){UseShellExecute=true,WorkingDirectory=folder.Text});Close();}else await Install();};Controls.Add(install);
        AcceptButton=install;CancelButton=cancel;
        Shown+=delegate{ActiveControl=install;};
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy){e.Cancel=true;cancel.PerformClick();}};
        Disposed+=delegate{if(logo.Image!=null)logo.Image.Dispose();if(stateIcon.Image!=null)stateIcon.Image.Dispose();};
    }
    static Image Asset(string name){using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)){if(stream==null)return null;using(var image=Image.FromStream(stream))return new Bitmap(image);}}
    void Activity(string title,string detail,string icon,int value){options.Visible=false;activity.Visible=true;activity.BringToFront();stageTitle.Text=title;details.Text=detail;if(stateIcon.Image!=null)stateIcon.Image.Dispose();stateIcon.Image=Asset(icon);progress.Value=value;percent.Text=value+"%";}
    static void VerifyArchive(string file){using(var input=File.OpenRead(file))using(var sha=SHA256.Create())if(BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant()!=ArchiveHash)throw new IOException("Downloaded file failed verification. Please try again.");}
    static async Task Download(string file,Action<int> changed,WebClient supplied=null){
        ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
        using(var client=supplied??new WebClient()){client.Headers["User-Agent"]="CapCutLauncher-Setup/"+Version;if(changed!=null)client.DownloadProgressChanged+=delegate(object sender,DownloadProgressChangedEventArgs e){changed(e.ProgressPercentage);};await client.DownloadFileTaskAsync(new Uri(ArchiveUrl),file);}VerifyArchive(file);
    }
    static void CheckPath(string target){
        if(String.Equals(target,Path.GetPathRoot(target),StringComparison.OrdinalIgnoreCase))throw new IOException("Choose an application folder, not a drive root.");
        for(var directory=new DirectoryInfo(target);directory!=null;directory=directory.Parent)if(directory.Exists&&(directory.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked installation folders are not supported.");
    }
    static void Extract(string archive,string target){
        target=Path.GetFullPath(target);CheckPath(target);if(Directory.Exists(target))throw new IOException("The extraction folder already exists.");Directory.CreateDirectory(target);
        using(var zip=ZipFile.OpenRead(archive))foreach(var entry in zip.Entries){
            int split=entry.FullName.IndexOf('/');if(split<0)throw new IOException("Invalid package layout.");string relative=entry.FullName.Substring(split+1);if(relative.Length==0)continue;
            string file=Path.GetFullPath(Path.Combine(target,relative));if(!file.StartsWith(target+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid package path.");
            if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(file);continue;}Directory.CreateDirectory(Path.GetDirectoryName(file));entry.ExtractToFile(file);
        }
        if(!File.Exists(Path.Combine(target,"CapCut Launcher.exe"))||!File.Exists(Path.Combine(target,"manifest-sha256.json")))throw new IOException("The launcher package is incomplete.");
    }
    static void Shortcut(string link,string executable){
        Directory.CreateDirectory(Path.GetDirectoryName(link));dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));dynamic shortcut=shell.CreateShortcut(link);shortcut.TargetPath=executable;shortcut.WorkingDirectory=Path.GetDirectoryName(executable);shortcut.IconLocation=executable+",0";shortcut.Save();
    }
    async Task Install(){
        string temp=null,stage=null,backup=null,target=null;bool committed=false;busy=true;cancelRequested=false;install.Enabled=browse.Enabled=folder.Enabled=desktop.Enabled=false;progress.Visible=percent.Visible=true;
        try{
            target=Path.GetFullPath(folder.Text.Trim()).TrimEnd(Path.DirectorySeparatorChar);CheckPath(target);
            if(Directory.Exists(target)&&Directory.GetFileSystemEntries(target).Length>0&&(!File.Exists(Path.Combine(target,"manifest-sha256.json"))||!File.Exists(Path.Combine(target,"CapCut Launcher.exe"))))throw new IOException(T("Выберите пустую папку или папку установленного CapCut Launcher.","Choose an empty folder or an existing CapCut Launcher installation."));
            foreach(var process in Process.GetProcessesByName("CapCut Launcher")){try{if(String.Equals(process.MainModule.FileName,Path.Combine(target,"CapCut Launcher.exe"),StringComparison.OrdinalIgnoreCase))throw new IOException(T("Закройте установленный лаунчер перед обновлением.","Close the installed launcher before updating."));}finally{process.Dispose();}}
            temp=Path.Combine(Path.GetTempPath(),"CapCutLauncher-download-"+Guid.NewGuid().ToString("N")+".zip");heading.Text=T("Устанавливаем лаунчер","Installing launcher");subtitle.Text=T("Скоро всё будет готово.","Everything will be ready shortly.");message.Text="";
            Activity(T("Загрузка файлов","Downloading files"),T("Скачиваем последнюю сборку лаунчера.","Downloading the launcher package."),"download.png",0);
            activeDownload=new WebClient();await Download(temp,value=>{progress.Value=value;percent.Text=value+"%";},activeDownload);activeDownload=null;
            if(cancelRequested)throw new OperationCanceledException();
            Activity(T("Установка файлов","Installing files"),T("Подготавливаем приложение и ярлыки.","Preparing the application and shortcuts."),"folder-open.png",100);
            stage=target+".installing-"+Guid.NewGuid().ToString("N");await Task.Run(()=>Extract(temp,stage));if(cancelRequested)throw new OperationCanceledException();cancel.Enabled=false;
            if(Directory.Exists(target)){backup=target+".previous-"+Guid.NewGuid().ToString("N");Directory.Move(target,backup);}Directory.Move(stage,target);stage=null;committed=true;
            string executable=Path.Combine(target,"CapCut Launcher.exe");
            Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"CapCut Launcher","CapCut Launcher.lnk"),executable);
            if(desktop.Checked)Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"CapCut Launcher.lnk"),executable);
            heading.Text=T("Всё готово","You're all set");subtitle.Text=T("CapCut Launcher установлен.","CapCut Launcher is installed.");Activity(T("Установка завершена","Installation complete"),target,"circle-check.png",100);progress.Visible=percent.Visible=false;
            message.Text="";install.Text=T("Открыть лаунчер","Open launcher");cancel.Text=T("Закрыть","Close");complete=true;
        }catch(Exception error){
            bool cancelled=cancelRequested||error is OperationCanceledException;
            heading.Text=cancelled?T("Установка отменена","Setup cancelled"):T("Не удалось установить","Setup couldn't finish");subtitle.Text=cancelled?T("Можно начать заново, когда будет удобно.","You can start again whenever you're ready."):T("Проверьте подключение и попробуйте ещё раз.","Check your connection and try again.");
            if(cancelled){options.Visible=true;activity.Visible=false;message.Text="";}else{Activity(T("Требуется внимание","Something needs attention"),error.Message,"circle-alert.png",0);details.Height=84;progress.Visible=percent.Visible=false;message.Text="";}
            install.Text=T("Повторить","Try again");if(!committed&&backup!=null&&!Directory.Exists(target))Directory.Move(backup,target);
        }
        finally{
            activeDownload=null;if(temp!=null&&File.Exists(temp))File.Delete(temp);busy=false;install.Enabled=cancel.Enabled=true;if(!complete)browse.Enabled=folder.Enabled=desktop.Enabled=true;
            if(stage!=null&&target!=null&&stage.StartsWith(target+".installing-",StringComparison.OrdinalIgnoreCase)&&Directory.Exists(stage)){
                // Only the newly generated staging directory is eligible for cleanup.
                bool safe=true;var queue=new System.Collections.Generic.Stack<string>();queue.Push(stage);while(queue.Count>0){string current=queue.Pop();if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0){safe=false;break;}foreach(string child in Directory.GetDirectories(current))queue.Push(child);}if(safe)Directory.Delete(stage,true);
            }
        }
        // A previous installation or failed staging folder is retained rather than
        // recursively deleting files from a user-selected installation location.
    }
    [STAThread]static int Main(string[] args){
        if(args.Length==2&&args[0]=="--download-only"){try{Download(Path.GetFullPath(args[1]),null).GetAwaiter().GetResult();return 0;}catch{return 1;}}
        if(args.Length==3&&args[0]=="--extract-only"){try{VerifyArchive(args[1]);Extract(args[1],args[2]);return 0;}catch{return 1;}}
        if(args.Length==1&&args[0]=="--check-only")return Uri.IsWellFormedUriString(ArchiveUrl,UriKind.Absolute)&&ArchiveHash.Length==64?0:1;
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);var window=new WindowsInstaller();
        if(args.Length==1&&args[0]=="--preview-progress"){window.heading.Text=window.T("Устанавливаем лаунчер","Installing launcher");window.subtitle.Text=window.T("Скоро всё будет готово.","Everything will be ready shortly.");window.Activity(window.T("Загрузка файлов","Downloading files"),window.T("Скачиваем сборку лаунчера.","Downloading the launcher package."),"download.png",62);window.install.Enabled=false;window.message.Text="";}
        if(args.Length==1&&args[0]=="--preview-complete"){window.heading.Text=window.T("Всё готово","You're all set");window.subtitle.Text=window.T("CapCut Launcher установлен.","CapCut Launcher is installed.");window.Activity(window.T("Установка завершена","Installation complete"),window.folder.Text,"circle-check.png",100);window.progress.Visible=window.percent.Visible=false;window.message.Text="";window.cancel.Text=window.T("Закрыть","Close");window.install.Text=window.T("Открыть лаунчер","Open launcher");window.install.Enabled=false;}
        Application.Run(window);return 0;
    }
}
