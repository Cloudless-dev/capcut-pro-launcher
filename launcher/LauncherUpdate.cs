using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

internal sealed class LauncherUpdate {
    public string Version,Url,Hash;
    static WebClient Client(){
        ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
        var client=new WebClient();client.Encoding=Encoding.UTF8;
        client.Headers["User-Agent"]="CapCutLauncher/"+BuildVersion.Display;
        return client;
    }
    public static LauncherUpdate Find(){
        using(var client=Client()){
            Dictionary<string,object> release;
            try{release=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(client.DownloadString("https://api.github.com/repositories/1428167761/releases/latest"));}
            catch(WebException ex){var response=ex.Response as HttpWebResponse;if(response!=null&&response.StatusCode==HttpStatusCode.NotFound)return null;throw;}
            string tag=Convert.ToString(release["tag_name"]).TrimStart('v');
            Version latest,current;
            if(!System.Version.TryParse(tag,out latest)||!System.Version.TryParse(BuildVersion.Display,out current))throw new IOException("Invalid release version.");
            if(latest<=current)return null;
            string url=null,sums=null;
            foreach(Dictionary<string,object> asset in (ArrayList)release["assets"]){
                string name=Convert.ToString(asset["name"]);
                if(name=="CapCut-Launcher-"+tag+"-Windows-x64.zip")url=Convert.ToString(asset["browser_download_url"]);
                if(name=="SHA256SUMS.txt")sums=Convert.ToString(asset["browser_download_url"]);
            }
            ValidateUrl(url);ValidateUrl(sums);
            string expected="CapCut-Launcher-"+tag+"-Windows-x64.zip",hash=null;
            foreach(string line in client.DownloadString(sums).Split('\n')){
                var match=Regex.Match(line.Trim(),@"^([a-fA-F0-9]{64})\s+\*?(.+)$");
                if(match.Success&&match.Groups[2].Value==expected)hash=match.Groups[1].Value.ToLowerInvariant();
            }
            if(hash==null)throw new IOException("Release checksum is missing.");
            return new LauncherUpdate{Version=tag,Url=url,Hash=hash};
        }
    }
    static void ValidateUrl(string value){Uri uri;if(!Uri.TryCreate(value,UriKind.Absolute,out uri)||uri.Scheme!="https"||uri.Host!="github.com"||!uri.AbsolutePath.Contains("/releases/download/"))throw new IOException("Invalid release download URL.");}
    public static string Download(LauncherUpdate update,string stateRoot){
        string folder=Path.Combine(stateRoot,"updates",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        string archive=Path.Combine(folder,"update.zip");
        using(var client=Client())client.DownloadFile(update.Url,archive);
        using(var input=File.OpenRead(archive))using(var sha=SHA256.Create()){
            string actual=BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant();
            if(actual!=update.Hash)throw new IOException("Update checksum mismatch.");
        }
        return archive;
    }
    public static void Install(string root,string archive,string hash){
        string worker=Path.Combine(Path.GetDirectoryName(archive),"install-update.ps1");
        File.Copy(Path.Combine(root,"scripts","install_update.ps1"),worker,true);
        string args="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+worker+"\" -Target \""+root.TrimEnd('\\')+"\" -Archive \""+archive+"\" -ExpectedHash "+hash+" -LauncherPid "+Process.GetCurrentProcess().Id;
        Process.Start(new ProcessStartInfo("powershell.exe",args){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(worker)});
    }
}
