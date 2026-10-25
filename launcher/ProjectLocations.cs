using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;

// Settings are hints, never authority to mutate a directory. A configured hint
// is used only if it points to an existing, recognizable CapCut library.
internal static class ProjectLocations {
    const string Drafts = "com.lveditor.draft";
    static IEnumerable<string> Strings(object value) {
        var text = value as string;
        if (text != null) { yield return text; yield break; }
        var dict = value as Dictionary<string,object>;
        if (dict != null) { foreach (var child in dict.Values) foreach (var item in Strings(child)) yield return item; yield break; }
        var list = value as IEnumerable;
        if (list != null) foreach (var child in list) foreach (var item in Strings(child)) yield return item;
    }
    static IEnumerable<string> Hints(string file) {
        ProjectLibrary.NoLinks(file);
        if (!File.Exists(file) || new FileInfo(file).Length >= 2000000) return new string[0];
        string raw = File.ReadAllText(file);
        object value;
        if(ProjectLibrary.TryJSON(raw,out value))return Strings(value).ToArray();
        // Qt/INI variants are read as data. Only whole path values count.
        return raw.Split(new[] {'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Where(line=>line.Contains("="))
            .Select(line=>line.Substring(line.IndexOf('=')+1).Trim().Trim('"')).ToArray();
    }
    static bool Recognized(string path) {
        ProjectLibrary.NoLinks(path);
        string index=Path.Combine(path,"root_meta_info.json");
        if(File.Exists(index)) {
            var value=ProjectLibrary.Read(index);object entries;
            if(value!=null&&value.TryGetValue("all_draft_store",out entries)&&entries is object[])return true;
        }
        if(!Directory.Exists(path))return false;
        return Directory.GetDirectories(path).Where(p=>!Path.GetFileName(p).StartsWith(".")).Any(p=>{
            ProjectLibrary.NoLinks(p);
            return File.Exists(Path.Combine(p,"draft_meta_info.json")) && ProjectLibrary.ContentFile(p)!=null;
        });
    }
    public static string Detect(IEnumerable<string> dataRoots) {
        var roots=dataRoots.Where(p=>!String.IsNullOrWhiteSpace(p)).Select(Path.GetFullPath).Distinct(ProjectLibrary.PathComparer).ToArray();
        if(roots.Length==0)throw new ArgumentException("A CapCut user-data root is required.");
        var defaults=roots.Select(r=>Path.Combine(r,"Projects",Drafts)).ToList();
        foreach(string data in roots) {
            var files=new[] {Path.Combine(data,"Config","globalSetting"),Path.Combine(data,"Config","globalSetting.ini"),Path.Combine(data,"Config","settings.json"),Path.Combine(data,"Config","config.json"),Path.Combine(data,"Projects",Drafts,"root_meta_info.json")};
            foreach(string file in files) {
                try {
                    foreach(string hint in Hints(file)) {
                        if(!Path.IsPathRooted(hint)||hint.StartsWith("\\\\")||hint.StartsWith("//"))continue;
                        foreach(string candidate in new[] {hint,Path.Combine(hint,Drafts),Path.Combine(hint,"Projects",Drafts)})
                            if(Recognized(candidate))return Path.GetFullPath(candidate);
                    }
                }catch(IOException){}catch(UnauthorizedAccessException){}catch(ArgumentException){}catch(NotSupportedException){}
            }
        }
        return defaults.FirstOrDefault(Directory.Exists) ?? defaults[0];
    }
}
