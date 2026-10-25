using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

internal static class ProjectAssets {
    public static bool IsDocument(string path) {
        return Path.GetExtension(path).Equals(".json",StringComparison.OrdinalIgnoreCase) ||
            new[]{"draft_content.json.bak","draft_info.json.bak","template.tmp","template-2.tmp"}.Contains(Path.GetFileName(path));
    }
    public static string Normalize(string path) {
        path=path.Replace('\\','/');string prefix="";
        if(path.StartsWith("//")){prefix="//";path=path.Substring(2);}
        else if(path.StartsWith("/")){prefix="/";path=path.Substring(1);}
        else if(Regex.IsMatch(path,@"^[A-Za-z]:/")){prefix=path.Substring(0,3);path=path.Substring(3);}
        var parts=new List<string>();
        foreach(string part in path.Split('/')) {
            if(part.Length==0||part==".")continue;
            if(part==".." && parts.Count>0 && parts[parts.Count-1]!="..")parts.RemoveAt(parts.Count-1);
            else if(part!=".."||prefix.Length==0)parts.Add(part);
        }
        return parts.Count==0 && prefix.Length>0 ? prefix : (prefix+String.Join("/",parts)).TrimEnd('/');
    }
    static string LocalPath(string text) {
        Uri uri;
        if (text.StartsWith("file:", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(text, UriKind.Absolute, out uri) && uri.IsFile) return Normalize(uri.LocalPath);
        if (text.StartsWith("/") || Regex.IsMatch(text, @"^[A-Za-z]:[\\/]")) return Normalize(text);
        return null;
    }
    static bool Contains(string parent, string path) { return path.Equals(parent, ProjectLibrary.PathComparison) || path.StartsWith(parent.TrimEnd('/') + "/", ProjectLibrary.PathComparison); }
    static object Embedded(string text) {
        string trimmed = text.TrimStart();
        if (!trimmed.StartsWith("{") && !trimmed.StartsWith("[")) return null;
        object value;return ProjectLibrary.TryJSON(text,out value)?value:null;
    }
    public static object Replace(object value, IEnumerable<KeyValuePair<string, string>> mapping) {
        var text = value as string;
        if (text != null) {
            var path = LocalPath(text);
            if (path != null) foreach (var pair in mapping) {
                string from = Normalize(pair.Key);
                if (from.Length > 0 && Contains(from, path)) {
                    string replacement = Normalize(pair.Value) + path.Substring(from.Length);
                    return text.StartsWith("file:", StringComparison.OrdinalIgnoreCase) ? new Uri(replacement).AbsoluteUri : replacement;
                }
            }
            var inner = Embedded(text);
            return inner == null ? text : ProjectLibrary.Serializer().Serialize(Replace(inner, mapping));
        }
        var dict = value as Dictionary<string, object>;
        if (dict != null) return dict.ToDictionary(p => p.Key, p => Replace(p.Value, mapping));
        var list = value as IEnumerable;
        if (list != null) return list.Cast<object>().Select(x => Replace(x, mapping)).ToArray();
        return value;
    }
    static IEnumerable<string> References(object value, bool scope = false, string key = "") {
        var dict = value as Dictionary<string, object>;
        if (dict != null) {
            foreach (var pair in dict) foreach (var path in References(pair.Value, scope || new[] {"materials", "draft_materials", "mini_draft_data"}.Contains(pair.Key), pair.Key)) yield return path;
            yield break;
        }
        var text = value as string;
        if (text != null) {
            string name = key.Replace("_", "").ToLowerInvariant(); var local = LocalPath(text);
            if (scope && (name.EndsWith("path") || name.EndsWith("pathlist")) && local != null) yield return local;
            var inner = Embedded(text);
            if (inner != null) foreach (var path in References(inner, scope)) yield return path;
            yield break;
        }
        var list = value as IEnumerable;
        if (list != null) foreach (var item in list) foreach (var path in References(item, scope, key)) yield return path;
    }
    static Dictionary<string, object> Documents(string folder) {
        var result = new Dictionary<string, object>();
        foreach (string file in ProjectLibrary.Files(folder).Where(IsDocument)) {
            bool main = new[] {"draft_info.json", "draft_content.json", "template.json", "mini_draft.json"}.Contains(Path.GetFileName(file));
            if (new FileInfo(file).Length >= 32000000) {
                if (main) throw new IOException(UiText.Get("Не удалось прочитать связи материалов. Выберите «Только проект»."));
                continue;
            }
            object value;
            if(ProjectLibrary.TryJSON(File.ReadAllText(file),out value))result.Add(file,value);
            else if(main)throw new IOException(UiText.Get("Не удалось прочитать связи материалов. Выберите «Только проект»."));
        }
        return result;
    }
    public static void Collect(string copy, string original) {
        var docs = Documents(copy);
        string stored = ProjectLibrary.Text(ProjectLibrary.Read(Path.Combine(copy, "draft_meta_info.json")), "draft_fold_path");
        var paths = docs.Values.SelectMany(x => References(x)).Distinct(ProjectLibrary.PathComparer).ToList();
        var external = new List<string>();
        foreach (var path in paths) {
            string prefix = new[] {Normalize(original), Normalize(stored)}.FirstOrDefault(p => p.Length > 0 && Contains(p, path));
            string source = prefix == null ? path : copy + path.Substring(prefix.Length);
            if (prefix != null && !ProjectLibrary.Within(source, copy)) throw new IOException(UiText.Get("Копия с материалами повреждена: обнаружены внешние ссылки."));
            if (!File.Exists(source) && !Directory.Exists(source)) throw new IOException(UiText.Get("Не найден материал: ") + Path.GetFileName(path) + UiText.Get(". Восстановите исходник или выберите «Только проект»."));
            ProjectLibrary.NoLinks(source);
            if (prefix == null) external.Add(path);
        }
        var sources = new List<string>();
        foreach (string path in external.OrderBy(p => p.Length)) if (!sources.Any(s => Contains(s, path))) sources.Add(path);
        var mapping = new List<KeyValuePair<string, string>>();
        string assets = Path.Combine(copy, "Resources", "LauncherMedia-" + Guid.NewGuid().ToString("N"));
        for (int i = 0; i < sources.Count; i++) {
            string source = sources[i], destination = Path.Combine(assets, i.ToString("D4") + "-" + Path.GetFileName(source));
            if (Directory.Exists(source)) {
                // Never gather a drive, home, project ancestor or export ancestor.
                if (ProjectLibrary.Within(copy, source) || ProjectLibrary.Within(original, source) || Path.GetPathRoot(source) == Path.GetFullPath(source) ||
                    Path.GetFullPath(source) == Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)) throw new IOException(UiText.Get("Материал указывает на слишком широкую папку. Выберите «Только проект»."));
                Directory.CreateDirectory(assets); ProjectLibrary.CopyVerified(source, destination);
            } else {
                Directory.CreateDirectory(assets); string before = ProjectLibrary.Hash(source); File.Copy(source, destination);
                if (before != ProjectLibrary.Hash(destination) || before != ProjectLibrary.Hash(source)) throw new IOException(UiText.Get("Не удалось проверить копию материала."));
            }
            mapping.Add(new KeyValuePair<string, string>(source, destination));
        }
        foreach (var doc in docs) ProjectLibrary.Save(doc.Key, Replace(doc.Value, mapping));
        ProjectLibrary.Save(Path.Combine(copy, "capcut-launcher-media.json"), new { version = 1, includes_media = true });
    }
    public static void ValidatePortable(string copy) {
        if (!File.Exists(Path.Combine(copy, "capcut-launcher-media.json"))) return;
        var docs = Documents(copy);
        string stored = ProjectLibrary.Text(ProjectLibrary.Read(Path.Combine(copy, "draft_meta_info.json")), "draft_fold_path");
        foreach (string path in docs.Values.SelectMany(x => References(x)).Distinct(ProjectLibrary.PathComparer)) {
            string prefix = new[] {Normalize(copy), Normalize(stored)}.FirstOrDefault(p => p.Length > 0 && Contains(p, path));
            if (prefix == null) throw new IOException(UiText.Get("Копия с материалами повреждена: обнаружены внешние ссылки."));
            string file = Path.GetFullPath(copy + path.Substring(prefix.Length));
            if (!ProjectLibrary.Within(file, copy) || (!File.Exists(file) && !Directory.Exists(file))) throw new IOException(UiText.Get("В копии отсутствует материал: ") + Path.GetFileName(path));
            ProjectLibrary.NoLinks(file);
        }
    }
}
