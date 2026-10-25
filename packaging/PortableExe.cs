using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using System.Windows.Forms;

// The downloadable EXE contains the exact published portable ZIP.
internal static class PortableExe {
    const string Version="__VERSION__",Digest="__ARCHIVE_SHA256__";
    static bool Verify(string root){
        string manifest=Path.Combine(root,"manifest-sha256.json");if(!File.Exists(manifest))return false;
        var records=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,string>>(File.ReadAllText(manifest));
        foreach(var item in records){string file=Path.GetFullPath(Path.Combine(root,item.Key));if(!file.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)||!File.Exists(file))return false;using(var input=File.OpenRead(file))using(var sha=SHA256.Create())if(BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant()!=item.Value)return false;}return true;
    }
    [STAThread]static int Main(string[] args){
        Application.EnableVisualStyles();string pending=null;
        try{
            using(var source=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))using(var zip=new MemoryStream()){
                source.CopyTo(zip);zip.Position=0;using(var sha=SHA256.Create())if(BitConverter.ToString(sha.ComputeHash(zip)).Replace("-","").ToLowerInvariant()!=Digest)throw new IOException("The downloaded file is damaged. Download it again.");
                zip.Position=0;
                if(args.Contains("--check-only")){using(var check=new ZipArchive(zip,ZipArchiveMode.Read,true))if(!check.Entries.Any(e=>e.FullName.EndsWith("/CapCut Launcher.exe")))throw new IOException("Launcher missing from bundle.");return 0;}
                bool extract=args.Length==2&&args[0]=="--extract-only";
                string target=extract?Path.GetFullPath(args[1]):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CapCutLauncher","Portable",Version+"-"+Digest.Substring(0,12));
                if(!Directory.Exists(target)||!Verify(target)){
                    if(extract&&Directory.Exists(target))throw new IOException("Choose a new, empty output path.");
                    if(Directory.Exists(target))target+="-"+Guid.NewGuid().ToString("N").Substring(0,8);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));pending=target+".extracting-"+Guid.NewGuid().ToString("N");Directory.CreateDirectory(pending);
                    using(var archive=new ZipArchive(zip,ZipArchiveMode.Read,true))foreach(var entry in archive.Entries){
                        int slash=entry.FullName.IndexOf('/');if(slash<0)throw new IOException("Invalid archive layout.");string relative=entry.FullName.Substring(slash+1);if(relative.Length==0)continue;
                        string destination=Path.GetFullPath(Path.Combine(pending,relative));if(!destination.StartsWith(pending+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Unsafe archive path.");
                        if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(destination);continue;}Directory.CreateDirectory(Path.GetDirectoryName(destination));using(var input=entry.Open())using(var output=File.Create(destination))input.CopyTo(output);
                    }
                    if(!Verify(pending))throw new IOException("The extracted files did not pass verification.");Directory.Move(pending,target);pending=null;
                }
                if(!extract)Process.Start(new ProcessStartInfo(Path.Combine(target,"CapCut Launcher.exe")){UseShellExecute=true,WorkingDirectory=target});return 0;
            }
        }catch(Exception error){if(!args.Contains("--check-only"))MessageBox.Show(error.Message,"CapCut Launcher",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
        // Keep failed extraction data for inspection; never delete user-selected paths.
    }
}
