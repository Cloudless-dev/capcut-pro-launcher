using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;

internal static class LauncherStateTests {
    static int count;
    static void Check(bool value, string name) { if (!value) throw new Exception(name); count++; Console.WriteLine("PASS " + name); }
    static Dictionary<string, object> Release(string tag, string version, bool windows) {
        return new Dictionary<string,object> { {"tag_name",tag}, {"draft",false}, {"prerelease",false}, {"assets",new ArrayList {
            new Dictionary<string,object> { {"name",windows ? "CapCut-Launcher-"+version+"-Windows-x64.zip" : "CapCut-Launcher-"+version+"-macOS-arm64.dmg"}, {"browser_download_url","https://github.com/Cloudless-dev/capcut-pro-launcher/releases/download/"+tag+"/app.zip"} },
            new Dictionary<string,object> { {"name","SHA256SUMS.txt"}, {"browser_download_url","https://github.com/Cloudless-dev/capcut-pro-launcher/releases/download/"+tag+"/SHA256SUMS.txt"} }
        }} };
    }
    public static int Main() {
        string root = Path.Combine(Path.GetTempPath(),"capcut-state-tests-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try {
            string old = Path.Combine(root,"auth-browser-sdk"); Directory.CreateDirectory(old); File.WriteAllText(Path.Combine(old,"desktop-session.bin"),"encrypted fixture");
            string browser=Path.Combine(root,"auth-browser-profile");Directory.CreateDirectory(browser);File.WriteAllText(Path.Combine(browser,"fixture"),"browser fixture");
            var store=new LauncherProfiles(root,"TR");var first=store.Document.Profiles.Single();string directory=store.DirectoryFor(first);
            var fresh=new LauncherProfiles(Path.Combine(root,"fresh"),"US");Check(fresh.Document.Profiles.Single().NativeAccount,"new installation defaults to official CapCut account");
            Check(first.Region=="TR" && File.ReadAllText(Path.Combine(directory,"auth-browser-sdk","desktop-session.bin"))=="encrypted fixture", "migrate legacy session to a slot");
            Check(File.Exists(Path.Combine(directory,"auth-browser-profile","fixture")) && File.Exists(Path.Combine(old,"desktop-session.bin")), "move browser while preserving legacy session backup");
            var second=new LauncherProfile { Id=Guid.NewGuid().ToString(),Name="Second",Region="NL",NativeAccount=true };
            store.Document.Profiles.Add(second);store.Document.SelectedId=second.Id;store.Save();
            var reloaded=new LauncherProfiles(root,"US");Check(reloaded.Document.Profiles.Count==2 && reloaded.Document.SelectedId==second.Id, "profile selection persists");
            Check(store.DirectoryFor(first)!=store.DirectoryFor(second), "slots have separate storage");
            Check(LauncherProfiles.Country(" tr ")=="TR" && LauncherProfiles.Country("NL — Netherlands")=="NL", "custom region normalization");
            bool invalid=false;try {LauncherProfiles.Country("USA");}catch(IOException){invalid=true;}Check(invalid,"reject malformed country");
            if(Environment.OSVersion.Platform==PlatformID.Win32NT){
                LauncherProfiles.SaveCredentials(directory,"test@example.invalid","fixture password");var credentials=LauncherProfiles.Credentials(directory);
                Check(credentials["email"]=="test@example.invalid"&&credentials["password"]=="fixture password", "Windows DPAPI credential round trip");
                Check(!File.ReadAllText(Path.Combine(directory,"credentials.json")).Contains("fixture password"), "credentials not stored as plaintext");
            } else Console.WriteLine("UNRUN Windows DPAPI checks require Windows");
            reloaded.Delete(reloaded.Document.Profiles.First(p=>p.Id==second.Id));Check(reloaded.Document.Profiles.Count==1&&Directory.Exists(directory),"deleting one slot preserves another");
            string contents=File.ReadAllText(Path.Combine(root,"profiles.json"));File.WriteAllText(Path.Combine(root,"profiles.json"),contents.Replace(first.Id,"../../escape"));
            invalid=false;try {new LauncherProfiles(root,"US");}catch(IOException){invalid=true;}Check(invalid,"reject path traversal in profile identifiers");
            var releases=new ArrayList { Release("macos-v9.9","9.9",false),Release("v0.055","0.055",true),Release("v0.02","0.02",true) };
            Check(LauncherUpdate.SelectWindowsRelease(releases).Version=="0.055", "Windows updater ignores newer Mac releases");
            var parsed=ProjectLibrary.Serializer().Deserialize<ArrayList>(ProjectLibrary.Serializer().Serialize(releases));
            Check(LauncherUpdate.SelectWindowsRelease(parsed).Version=="0.055","release API JSON deserializes with asset lists");
            releases.Add(Release("windows-v0.056","0.056",true));Check(LauncherUpdate.SelectWindowsRelease(releases).Version=="0.056","Windows tag prefix supported");
            var prerelease=Release("v0.057","0.057",true);prerelease["prerelease"]=true;releases.Add(prerelease);
            Check(LauncherUpdate.SelectWindowsRelease(releases).Version=="0.056","prereleases excluded");
            Check(LauncherUpdate.SelectWindowsRelease(new ArrayList{Release("v0.054","0.054",true)})==null,"current release does not trigger update");
            Console.WriteLine("RESULT "+count+" checks passed");return 0;
        } catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
        finally {Directory.Delete(root,true);}
    }
}
