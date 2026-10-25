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
    readonly ProgressBar progress=new ProgressBar();
    readonly CheckBox desktop=new CheckBox();
    readonly Button install=new Button();
    readonly Button browse=new Button();
    bool busy,complete;
    readonly bool english=System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName!="ru";
    string T(string ru,string en){return english?en:ru;}
    WindowsInstaller(){
        Text="CapCut Launcher · "+Version;ClientSize=new Size(580,340);FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;Font=new Font("Segoe UI",10);BackColor=Color.FromArgb(244,242,252);ForeColor=Color.FromArgb(41,39,56);
        Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        Controls.Add(new Label{Text="CapCut Launcher",Bounds=new Rectangle(28,24,520,42),Font=new Font("Segoe UI",22,FontStyle.Bold)});
        Controls.Add(new Label{Text=T("Установка для Windows","Windows setup"),Bounds=new Rectangle(30,75,520,25),ForeColor=Color.FromArgb(110,103,124)});
        Controls.Add(new Label{Text=T("Папка установки","Installation folder"),Bounds=new Rectangle(30,117,500,24)});
        folder.SetBounds(30,146,405,28);folder.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","CapCutLauncher");Controls.Add(folder);
        browse.Text=T("Выбрать…","Browse…");browse.SetBounds(445,143,105,34);browse.FlatStyle=FlatStyle.Flat;browse.Click+=delegate{using(var dialog=new FolderBrowserDialog{SelectedPath=folder.Text})if(dialog.ShowDialog(this)==DialogResult.OK)folder.Text=dialog.SelectedPath;};Controls.Add(browse);
        desktop.Text=T("Создать ярлык на рабочем столе","Create a desktop shortcut");desktop.Checked=true;desktop.SetBounds(30,190,520,30);Controls.Add(desktop);
        message.SetBounds(30,230,520,34);message.Text=T("Нужен интернет для загрузки файлов лаунчера.","An internet connection is required to download the launcher.");Controls.Add(message);
        progress.SetBounds(30,270,330,12);Controls.Add(progress);
        install.Text=T("Установить","Install");install.SetBounds(390,270,160,44);install.FlatStyle=FlatStyle.Flat;install.FlatAppearance.BorderSize=0;install.BackColor=Color.FromArgb(41,38,63);install.ForeColor=Color.White;install.Click+=async delegate{if(complete){Process.Start(new ProcessStartInfo(Path.Combine(folder.Text,"CapCut Launcher.exe")){UseShellExecute=true,WorkingDirectory=folder.Text});Close();}else await Install();};Controls.Add(install);
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy)e.Cancel=true;};
    }
    static void VerifyArchive(string file){using(var input=File.OpenRead(file))using(var sha=SHA256.Create())if(BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant()!=ArchiveHash)throw new IOException("Downloaded file failed verification. Please try again.");}
    static async Task Download(string file,Action<int> changed){
        ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
        using(var client=new WebClient()){client.Headers["User-Agent"]="CapCutLauncher-Setup/"+Version;if(changed!=null)client.DownloadProgressChanged+=delegate(object sender,DownloadProgressChangedEventArgs e){changed(e.ProgressPercentage);};await client.DownloadFileTaskAsync(new Uri(ArchiveUrl),file);}VerifyArchive(file);
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
        string temp=null,stage=null,backup=null,target=null;bool committed=false;busy=true;install.Enabled=browse.Enabled=folder.Enabled=desktop.Enabled=false;
        try{
            target=Path.GetFullPath(folder.Text.Trim()).TrimEnd(Path.DirectorySeparatorChar);CheckPath(target);
            if(Directory.Exists(target)&&Directory.GetFileSystemEntries(target).Length>0&&(!File.Exists(Path.Combine(target,"manifest-sha256.json"))||!File.Exists(Path.Combine(target,"CapCut Launcher.exe"))))throw new IOException(T("Выберите пустую папку или папку установленного CapCut Launcher.","Choose an empty folder or an existing CapCut Launcher installation."));
            foreach(var process in Process.GetProcessesByName("CapCut Launcher")){try{if(String.Equals(process.MainModule.FileName,Path.Combine(target,"CapCut Launcher.exe"),StringComparison.OrdinalIgnoreCase))throw new IOException(T("Закройте установленный лаунчер перед обновлением.","Close the installed launcher before updating."));}finally{process.Dispose();}}
            temp=Path.Combine(Path.GetTempPath(),"CapCutLauncher-download-"+Guid.NewGuid().ToString("N")+".zip");message.Text=T("Загрузка лаунчера…","Downloading launcher…");await Download(temp,value=>progress.Value=Math.Max(0,Math.Min(100,value)));
            message.Text=T("Установка…","Installing…");stage=target+".installing-"+Guid.NewGuid().ToString("N");await Task.Run(()=>Extract(temp,stage));
            if(Directory.Exists(target)){backup=target+".previous-"+Guid.NewGuid().ToString("N");Directory.Move(target,backup);}Directory.Move(stage,target);stage=null;committed=true;
            string executable=Path.Combine(target,"CapCut Launcher.exe");
            Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"CapCut Launcher","CapCut Launcher.lnk"),executable);
            if(desktop.Checked)Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"CapCut Launcher.lnk"),executable);
            message.Text=T("Установлено. Можно открыть лаунчер.","Installed. You can now open the launcher.");install.Text=T("Открыть лаунчер","Open launcher");complete=true;
        }catch(Exception error){message.Text=T("Не удалось завершить установку.","Setup could not be completed.");MessageBox.Show(this,error.Message,"CapCut Launcher",MessageBoxButtons.OK,MessageBoxIcon.Error);if(!committed&&backup!=null&&!Directory.Exists(target))Directory.Move(backup,target);}
        finally{if(temp!=null&&File.Exists(temp))File.Delete(temp);busy=false;install.Enabled=true;if(!complete)browse.Enabled=folder.Enabled=desktop.Enabled=true;}
        // A previous installation or failed staging folder is retained rather than
        // recursively deleting files from a user-selected installation location.
    }
    [STAThread]static int Main(string[] args){
        if(args.Length==2&&args[0]=="--download-only"){try{Download(Path.GetFullPath(args[1]),null).GetAwaiter().GetResult();return 0;}catch{return 1;}}
        if(args.Length==3&&args[0]=="--extract-only"){try{VerifyArchive(args[1]);Extract(args[1],args[2]);return 0;}catch{return 1;}}
        if(args.Length==1&&args[0]=="--check-only")return Uri.IsWellFormedUriString(ArchiveUrl,UriKind.Absolute)&&ArchiveHash.Length==64?0:1;
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new WindowsInstaller());return 0;
    }
}
