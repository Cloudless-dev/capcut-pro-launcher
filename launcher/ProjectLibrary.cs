using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

internal sealed class CapCutProject {
    public string Folder, Id, Name, Cover;
    public DateTime Modified, Deleted;
    public long Bytes;
    public bool Incomplete;
    public string TrashId;
    public bool NativeTrash;
}

internal sealed class ProjectResult {
    public int Completed, Skipped;
    public string Destination;
}

// File operations are independent of WinForms so the same fixtures can run on
// Windows and Linux. All writes require a closed CapCut and a valid index.
internal sealed class ProjectLibrary {
    public readonly string Root, Backups;
    readonly Func<bool> running;
    public static readonly StringComparison PathComparison = Path.DirectorySeparatorChar == '\\' ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
    public static readonly StringComparer PathComparer = Path.DirectorySeparatorChar == '\\' ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    public ProjectLibrary(string root, string backups, Func<bool> isRunning = null) {
        string full = Path.GetFullPath(root);
        Root = full == Path.GetPathRoot(full) ? full : full.TrimEnd(Path.DirectorySeparatorChar);
        Backups = Path.GetFullPath(backups);
        running = isRunning ?? (() => Process.GetProcessesByName("CapCut").Any());
    }
    string Index { get { return Path.Combine(Root, "root_meta_info.json"); } }
    string Bin { get { return Path.Combine(Root, ".launcher-trash"); } }
    public static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 32000000, RecursionLimit = 128 }; }
    public static bool TryJSON(string text,out object value) {
        try {value=Serializer().DeserializeObject(text);return true;}
        catch(ArgumentException){value=null;return false;}
        catch(InvalidOperationException){value=null;return false;}
    }
    public static string Text(Dictionary<string, object> value, string key, string fallback = "") {
        object item; return value != null && value.TryGetValue(key, out item) && item != null ? Convert.ToString(item) : fallback;
    }
    public static bool Within(string child, string parent) {
        child = Path.GetFullPath(child); parent = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar);
        return child.Equals(parent, PathComparison) || child.StartsWith(parent + Path.DirectorySeparatorChar, PathComparison);
    }
    public static void NoLinks(string path) {
        var current = Path.GetFullPath(path);
        while (!String.IsNullOrEmpty(current)) {
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new IOException(UiText.Get("Ссылки и точки соединения в путях проектов не поддерживаются."));
            current = Path.GetDirectoryName(current);
        }
    }
    public static IEnumerable<string> Files(string root) {
        NoLinks(root);
        foreach (string item in Directory.GetFileSystemEntries(root)) {
            NoLinks(item);
            if (Directory.Exists(item)) { foreach (var file in Files(item)) yield return file; }
            else yield return item;
        }
    }
    public static Dictionary<string, object> Read(string file) {
        NoLinks(file);
        if (!File.Exists(file)) return null;
        if (new FileInfo(file).Length >= 32000000) throw new IOException(UiText.Get("Файл проекта слишком большой для безопасной обработки."));
        object value;
        if(!TryJSON(File.ReadAllText(file,Encoding.UTF8),out value))throw new IOException(UiText.Get("Не удалось прочитать JSON проекта."));
        return value as Dictionary<string, object>;
    }
    static Dictionary<string,object> Metadata(string file) {
        NoLinks(file);
        if(!File.Exists(file)||new FileInfo(file).Length>=32000000)return null;
        object value;return TryJSON(File.ReadAllText(file,Encoding.UTF8),out value)?value as Dictionary<string,object>:null;
    }
    public static string ContentFile(string folder) {
        foreach(string name in new[] {"draft_info.json","draft_content.json"})if(File.Exists(Path.Combine(folder,name)))return name;
        string timelines=Path.Combine(folder,"Timelines");
        if(!Directory.Exists(timelines))return null;
        var project=Metadata(Path.Combine(timelines,"project.json"));string main=Text(project,"main_timeline_id");
        if(main.Length>0 && main.IndexOfAny(new[]{'/','\\',':'})<0 && main!="." && main!="..") {
            foreach(string name in new[] {"draft_info.json","draft_content.json"}) {
                string relative=Path.Combine("Timelines",main,name);
                if(File.Exists(Path.Combine(folder,relative))){NoLinks(Path.Combine(folder,relative));return relative;}
            }
        }
        return Files(timelines).Where(f=>new[]{"draft_info.json","draft_content.json"}.Contains(Path.GetFileName(f))).OrderBy(f=>f,StringComparer.Ordinal).Select(f=>f.Substring(folder.Length+1)).FirstOrDefault();
    }
    public static void Save(string file, object value) {
        NoLinks(file);
        string pending = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            File.WriteAllText(pending, Serializer().Serialize(value), new UTF8Encoding(false));
            if (File.Exists(file)) File.Replace(pending, file, null); else File.Move(pending, file);
        } finally { if (File.Exists(pending)) File.Delete(pending); }
    }
    void Closed() { if (running()) throw new IOException(UiText.Get("Сначала полностью закройте CapCut для работы с файлами проектов.")); }
    IDisposable Acquire() {
        string identity=Path.DirectorySeparatorChar=='\\'?Root.ToUpperInvariant():Root;
        string key;
        using(var sha=SHA256.Create())key=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(identity))).Replace("-","");
        string locks=Path.Combine(Backups,".operation-locks");NoLinks(locks);Directory.CreateDirectory(locks);
        string file=Path.Combine(locks,key+".lock");NoLinks(file);
        try{return new FileStream(file,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
        catch(IOException ex){throw new IOException(UiText.Get("Другая операция с этой библиотекой ещё выполняется. Повторите позже."),ex);}
    }
    static List<Dictionary<string, object>> Records(Dictionary<string, object> index) {
        object raw;
        if (index == null) throw new IOException(UiText.Get("Индекс проектов повреждён. Файлы не изменены."));
        if (!index.TryGetValue("all_draft_store", out raw) || !(raw is IEnumerable) || raw is string || raw is IDictionary)
            throw new IOException(UiText.Get("Индекс проектов повреждён. Файлы не изменены."));
        var result = new List<Dictionary<string, object>>();
        foreach (var item in (IEnumerable)raw) {
            var record = item as Dictionary<string, object>;
            if (record == null) throw new IOException(UiText.Get("Индекс проектов повреждён. Файлы не изменены."));
            result.Add(record);
        }
        return result;
    }
    Dictionary<string, object> SafeIndex(out byte[] original) {
        NoLinks(Root); NoLinks(Index);
        original = File.Exists(Index) ? File.ReadAllBytes(Index) : null;
        if (original == null) return new Dictionary<string, object> { {"all_draft_store", new object[0]}, {"draft_ids", 0}, {"root_path", Root} };
        try { var index = Read(Index); Records(index); return index; }
        catch (ArgumentException ex) {
            throw new IOException(UiText.Get("Индекс проектов повреждён. Файлы не изменены."), ex);
        }
    }
    void Unchanged(byte[] original) {
        Closed(); NoLinks(Index);
        byte[] now = File.Exists(Index) ? File.ReadAllBytes(Index) : null;
        if ((original == null) != (now == null) || (original != null && !original.SequenceEqual(now)))
            throw new IOException(UiText.Get("Список проектов изменился. Обновите его и повторите действие."));
    }
    void Backup(byte[] original) {
        if (original == null) return;
        NoLinks(Backups);
        string directory = Path.Combine(Backups, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory); File.WriteAllBytes(Path.Combine(directory, "root_meta_info.json"), original);
    }
    public List<CapCutProject> Scan() {
        NoLinks(Root);
        if (!Directory.Exists(Root)) return new List<CapCutProject>();
        List<Dictionary<string, object>> entries = new List<Dictionary<string, object>>();
        if (File.Exists(Index)) { byte[] ignored; entries = Records(SafeIndex(out ignored)); }
        var result = new List<CapCutProject>();
        foreach (string folder in Directory.GetDirectories(Root)) {
            if (Path.GetFileName(folder).StartsWith(".")) continue;
            NoLinks(folder);
            var entry = entries.FirstOrDefault(x => ProjectAssets.Normalize(Text(x, "draft_fold_path")).TrimEnd('/').Split('/').Last() == Path.GetFileName(folder));
            var project = Describe(folder, entry);
            if (project != null) result.Add(project);
        }
        return result.OrderByDescending(x => x.Modified).ToList();
    }
    static CapCutProject Describe(string folder, Dictionary<string, object> entry) {
        var meta = Metadata(Path.Combine(folder, "draft_meta_info.json"));
        bool hasDraft = ContentFile(folder)!=null;
        if (meta == null && entry == null && !hasDraft) return null;
        var info = meta ?? entry ?? new Dictionary<string, object>();
        string cover = Path.GetFullPath(Path.Combine(folder, Text(info, "draft_cover", "draft_cover.jpg")));
        if (!Within(cover, folder)) cover = null;
        else NoLinks(cover);
        DateTime modified = Directory.GetLastWriteTimeUtc(folder);
        double stamp;
        if (Double.TryParse(Text(info, "tm_draft_modified"), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out stamp)) {
            stamp = stamp > 1e14 ? stamp / 1e6 : stamp > 1e11 ? stamp / 1e3 : stamp;
            try { modified = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(stamp); } catch (ArgumentOutOfRangeException) { }
        }
        return new CapCutProject { Folder = folder, Id = Text(info, "draft_id"), Name = Text(info, "draft_name", Path.GetFileName(folder)),
            Modified = modified, Cover = cover, Incomplete = meta == null || !hasDraft, Bytes = Files(folder).Sum(f => new FileInfo(f).Length) };
    }
    void Validate(IList<CapCutProject> projects) {
        Closed(); NoLinks(Root);
        if (projects.Count == 0 || projects.Select(p => p.Folder).Distinct(PathComparer).Count() != projects.Count) throw new IOException(UiText.Get("Выберите проекты."));
        foreach (var project in projects) {
            NoLinks(project.Folder);
            var current = Describe(project.Folder, SourceRecord(project));
            if (!String.Equals(Path.GetDirectoryName(project.Folder), Root, PathComparison) || current == null || current.Id != project.Id)
                throw new IOException(UiText.Get("Список проектов изменился. Обновите его и повторите действие."));
        }
    }
    public static string Hash(string file) {
        using (var input = File.OpenRead(file)) using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "").ToLowerInvariant();
    }
    public static Dictionary<string, string> Manifest(string folder) {
        var result = new Dictionary<string, string>(PathComparer);
        WalkManifest(folder, folder, result); return result;
    }
    static void WalkManifest(string root, string directory, Dictionary<string, string> result) {
        NoLinks(directory);
        foreach (string path in Directory.GetFileSystemEntries(directory)) {
            NoLinks(path); string relative = path.Substring(root.Length);
            if (Directory.Exists(path)) { result.Add(relative, "directory"); WalkManifest(root, path, result); }
            else result.Add(relative, Hash(path));
        }
    }
    static bool Equal(Dictionary<string, string> a, Dictionary<string, string> b) { return a.Count == b.Count && a.All(x => b.ContainsKey(x.Key) && b[x.Key] == x.Value); }
    static void CopyTree(string source, string target) {
        NoLinks(source); NoLinks(target); Directory.CreateDirectory(target);
        foreach (var entry in Directory.GetFileSystemEntries(source)) {
            NoLinks(entry); string dest = Path.Combine(target, Path.GetFileName(entry));
            if (Directory.Exists(entry)) CopyTree(entry, dest); else File.Copy(entry, dest, false);
        }
    }
    public static Dictionary<string, string> CopyVerified(string source, string target) {
        var before = Manifest(source); CopyTree(source, target);
        if (!Equal(before, Manifest(target)) || !Equal(before, Manifest(source))) throw new IOException(UiText.Get("Не удалось проверить копию проекта. Исходные файлы сохранены."));
        return before;
    }
    static void Rewrite(string copy, string source, string final, string library) {
        var meta = Metadata(Path.Combine(copy, "draft_meta_info.json"));
        var mapping = new List<KeyValuePair<string, string>> { new KeyValuePair<string, string>(copy, final), new KeyValuePair<string, string>(source, final) };
        string stored = Text(meta, "draft_fold_path");
        if (stored.Length > 0) mapping.Add(new KeyValuePair<string, string>(stored, final));
        foreach (var file in Files(copy).Where(ProjectAssets.IsDocument).ToList()) {
            if (new FileInfo(file).Length >= 32000000) continue;
            object value;
            if(!TryJSON(File.ReadAllText(file),out value))continue;
            object updated = ProjectAssets.Replace(value, mapping);
            if (Path.GetFileName(file) == "draft_meta_info.json") {
                var record = updated as Dictionary<string, object>;
                if (record != null) { record["draft_fold_path"] = final; record["draft_root_path"] = library; }
            }
            if (Serializer().Serialize(value) != Serializer().Serialize(updated)) Save(file, updated);
        }
    }
    static Dictionary<string, object> Record(CapCutProject project, string copy, string final, string library, Dictionary<string, object> fallback = null) {
        var meta = Metadata(Path.Combine(copy, "draft_meta_info.json")) ?? fallback ?? new Dictionary<string, object>();
        var record = new Dictionary<string, object>(fallback ?? meta);
        record = (Dictionary<string, object>)ProjectAssets.Replace(record, new[] { new KeyValuePair<string, string>(Text(record, "draft_fold_path", project.Folder), final) });
        record["draft_fold_path"] = final; record["draft_root_path"] = library; record["draft_id"] = project.Id; record["draft_name"] = project.Name;
        record["draft_json_file"] = Path.Combine(final, ContentFile(copy) ?? "draft_content.json");
        if (!record.ContainsKey("draft_timeline_materials_size")) { object size; record["draft_timeline_materials_size"] = meta.TryGetValue("draft_timeline_materials_size_", out size) ? size : 0; }
        if (!record.ContainsKey("streaming_edit_draft_ready")) record["streaming_edit_draft_ready"] = true;
        return record;
    }
    Dictionary<string, object> SourceRecord(CapCutProject project) {
        var file = Path.Combine(Path.GetDirectoryName(project.Folder), "root_meta_info.json");
        var index = Read(file);
        return index == null ? null : Records(index).FirstOrDefault(x => project.Id.Length > 0 && Text(x, "draft_id") == project.Id);
    }
    public ProjectResult Export(IList<CapCutProject> projects, string parent, bool media, bool move = false) {
        using(var held=Acquire())return ExportCore(projects,parent,media,move);
    }
    ProjectResult ExportCore(IList<CapCutProject> projects, string parent, bool media, bool move) {
        Validate(projects); parent = Path.GetFullPath(parent); NoLinks(parent);
        if (Within(parent, Root)) throw new IOException(UiText.Get("Выберите папку вне текущей библиотеки проектов."));
        string name = "CapCut Projects " + DateTime.UtcNow.ToString("yyyy-MM-dd HH-mm-ss") + " " + Guid.NewGuid().ToString("N").Substring(0, 6);
        string final = Path.Combine(parent, name), stage = Path.Combine(parent, ".capcut-export-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        var fingerprints = new Dictionary<string, Dictionary<string, string>>();
        try {
            var entries = new List<Dictionary<string, object>>();
            foreach (var project in projects) {
                Closed(); string copy = Path.Combine(stage, Path.GetFileName(project.Folder)), target = Path.Combine(final, Path.GetFileName(project.Folder));
                fingerprints[project.Folder] = CopyVerified(project.Folder, copy);
                if (media) ProjectAssets.Collect(copy, project.Folder);
                Rewrite(copy, project.Folder, target, final);
                entries.Add(Record(project, copy, target, final, SourceRecord(project)));
            }
            Save(Path.Combine(stage, "root_meta_info.json"), new { all_draft_store = entries, draft_ids = entries.Count, root_path = final });
            Save(Path.Combine(stage, "capcut-launcher-projects.json"), new { format = "capcut-launcher-projects", version = 2, includes_media = media, projects = projects.Select(p => Path.GetFileName(p.Folder)).ToArray() });
            Closed(); Directory.Move(stage, final);
        } finally { if (Directory.Exists(stage)) Directory.Delete(stage, true); }
        if (move) {
            try {
                Validate(projects);
                foreach (var project in projects) if (!Equal(fingerprints[project.Folder], Manifest(project.Folder))) throw new IOException(UiText.Get("Исходный проект изменился."));
                TrashCore(projects);
            } catch (Exception ex) { throw new IOException(UiText.Get("Копия сохранена. Оригиналы не перенесены: ") + final + "\n" + ex.Message, ex); }
        }
        return new ProjectResult { Completed = projects.Count, Destination = final };
    }
    public ProjectResult Trash(IList<CapCutProject> projects) {
        using(var held=Acquire())return TrashCore(projects);
    }
    ProjectResult TrashCore(IList<CapCutProject> projects) {
        Validate(projects); byte[] original; var index = SafeIndex(out original); Backup(original); NoLinks(Bin); Directory.CreateDirectory(Bin);
        var moved = new List<KeyValuePair<string, string>>();
        try {
            foreach (var project in projects) {
                Unchanged(original);
                string entry = Path.Combine(Bin, Guid.NewGuid().ToString()), payload = Path.Combine(entry, Path.GetFileName(project.Folder));
                Directory.CreateDirectory(entry); moved.Add(new KeyValuePair<string, string>(project.Folder, payload));
                Save(Path.Combine(entry, "receipt.json"), new { version = 1, folder_name = Path.GetFileName(project.Folder), draft_id = project.Id, name = project.Name,
                    modified = project.Modified.ToString("o"), deleted = DateTime.UtcNow.ToString("o"), original_path = project.Folder, index_record = SourceRecord(project) });
                Directory.Move(project.Folder, payload);
            }
            Unchanged(original);
            var ids = new HashSet<string>(projects.Where(p => p.Id.Length > 0).Select(p => p.Id));
            index["all_draft_store"] = Records(index).Where(r => !ids.Contains(Text(r, "draft_id")) && !projects.Any(p => ProjectAssets.Normalize(p.Folder).Equals(ProjectAssets.Normalize(Text(r, "draft_fold_path")), PathComparison))).ToArray();
            Save(Index, index);
        } catch {
            foreach (var pair in moved.AsEnumerable().Reverse()) {
                // If rollback cannot complete, retain the receipt and payload.
                if (Directory.Exists(pair.Value) && !Directory.Exists(pair.Key)) Directory.Move(pair.Value, pair.Key);
                if (!Directory.Exists(pair.Value)) Directory.Delete(Path.GetDirectoryName(pair.Value), true);
            }
            throw;
        }
        return new ProjectResult { Completed = projects.Count };
    }
    public List<CapCutProject> ScanTrash() {
        NoLinks(Bin); var result = ScanNativeTrash();
        if (!Directory.Exists(Bin)) return result;
        foreach (var directory in Directory.GetDirectories(Bin)) {
            NoLinks(directory); Guid id;
            if (!Guid.TryParse(Path.GetFileName(directory), out id)) continue;
            var receipt = Read(Path.Combine(directory, "receipt.json"));
            if (receipt == null || Text(receipt, "version") != "1") continue;
            string name = Text(receipt, "folder_name");
            if (name.Length == 0 || name.StartsWith(".") || name.IndexOfAny(new[] {'/', '\\', ':'}) >= 0) continue;
            string payload = Path.Combine(directory, name);
            if (!Directory.Exists(payload)) continue;
            var project = Describe(payload, new Dictionary<string, object> { {"draft_id", Text(receipt, "draft_id")}, {"draft_name", Text(receipt, "name")} });
            if (project.Id != Text(receipt, "draft_id")) throw new IOException(UiText.Get("Список проектов изменился. Обновите его и повторите действие."));
            project.TrashId = Path.GetFileName(directory); DateTime deleted;
            if (DateTime.TryParse(Text(receipt, "deleted"), out deleted)) project.Deleted = deleted;
            result.Add(project);
        }
        return result.GroupBy(p=>p.Id.Length>0?p.Id:p.Folder).Select(group=>group.FirstOrDefault(p=>!p.NativeTrash)??group.First()).OrderByDescending(x => x.Deleted).ToList();
    }
    string NativeBin {get{return Path.Combine(Root,".recycle_bin");}}
    List<CapCutProject> ScanNativeTrash(){
        NoLinks(NativeBin);if(!Directory.Exists(NativeBin))return new List<CapCutProject>();
        var native=new ProjectLibrary(NativeBin,Backups,running);var result=native.Scan();
        Dictionary<string,object> index=File.Exists(native.Index)?Read(native.Index):null;
        var records=index==null?new List<Dictionary<string,object>>():Records(index);
        foreach(var project in result){
            project.NativeTrash=true;project.TrashId="capcut:"+Path.GetFileName(project.Folder);
            var record=records.FirstOrDefault(r=>Text(r,"draft_id")==project.Id);double stamp;
            if(record!=null&&Double.TryParse(Text(record,"tm_draft_removed"),out stamp)&&stamp>0){try{project.Deleted=new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc).AddSeconds(stamp>1e14?stamp/1e6:stamp>1e11?stamp/1e3:stamp);}catch(ArgumentOutOfRangeException){project.Deleted=project.Modified;}}
            else project.Deleted=project.Modified;
        }
        return result;
    }
    void RemoveNativeTrashRecord(CapCutProject project){
        if(!project.NativeTrash||!Within(project.Folder,NativeBin)||Path.GetDirectoryName(project.Folder)!=NativeBin)throw new IOException("Invalid CapCut trash entry.");
        var native=new ProjectLibrary(NativeBin,Backups,running);byte[] original;var index=native.SafeIndex(out original);native.Backup(original);
        var remaining=Records(index).Where(r=>!ProjectAssets.Normalize(Text(r,"draft_fold_path")).Equals(ProjectAssets.Normalize(project.Folder),PathComparison)).ToArray();
        native.Unchanged(original);index["all_draft_store"]=remaining;index["draft_ids"]=remaining.Length;Save(native.Index,index);
    }
    List<CapCutProject> CheckedTrash(IList<CapCutProject> items) {
        Closed(); var current = ScanTrash();
        if (items.Count == 0 || items.Select(i => i.TrashId).Distinct().Count() != items.Count) throw new IOException(UiText.Get("Выберите проекты."));
        var result = new List<CapCutProject>();
        foreach(var item in items) {
            var stored=current.FirstOrDefault(c => c.TrashId == item.TrashId && c.Id == item.Id && c.Folder == item.Folder);
            if(stored==null)throw new IOException(UiText.Get("Список проектов изменился. Обновите его и повторите действие."));
            result.Add(stored);
        }
        return result;
    }
    public ProjectResult Restore(IList<CapCutProject> requested) {
        using(var held=Acquire())return ImportCore(CheckedTrash(requested),true);
    }
    public ProjectResult Import(string source) {
        using(var held=Acquire()) {
            source=Path.GetFullPath(source);NoLinks(source);Closed();
            if(Within(source,Root)||Within(Root,source))throw new IOException(UiText.Get("Выберите папку вне текущей библиотеки проектов."));
            var single=Describe(source,null);
            var items=single!=null ? new List<CapCutProject>{single} : new ProjectLibrary(source,Backups,()=>false).Scan();
            return ImportCore(items,false);
        }
    }
    ProjectResult ImportCore(IList<CapCutProject> projects,bool restore) {
        Closed();NoLinks(Root);Directory.CreateDirectory(Root);
        byte[] original;var index=SafeIndex(out original);Backup(original);
        var entries=Records(index);
        var ids=new HashSet<string>(Scan().Where(p=>p.Id.Length>0).Select(p=>p.Id));
        string stage=Path.Combine(Root,".capcut-import-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        var added=new List<string>();var restored=new List<CapCutProject>();
        var result=new ProjectResult();
        try {
            foreach(var project in projects) {
                Unchanged(original);
                if(project.Incomplete||project.Id.Length==0||ids.Contains(project.Id)){result.Skipped++;continue;}
                string name=Path.GetFileName(project.Folder),baseName=name;int suffix=2;
                while(Directory.Exists(Path.Combine(Root,name))||File.Exists(Path.Combine(Root,name)))name=baseName+" ("+(suffix++)+")";
                string copy=Path.Combine(stage,name),target=Path.Combine(Root,name);
                CopyVerified(project.Folder,copy);ProjectAssets.ValidatePortable(copy);
                Dictionary<string,object> fallback=SourceRecord(project);
                if(restore){
                    var receipt=Read(Path.Combine(Path.GetDirectoryName(project.Folder),"receipt.json"));object record;
                    if(receipt!=null&&receipt.TryGetValue("index_record",out record))fallback=record as Dictionary<string,object>;
                    string former=Text(receipt,"original_path");
                    if(former.Length>0)Rewrite(copy,former,target,Root);
                }
                Rewrite(copy,project.Folder,target,Root);
                var entry=Record(project,copy,target,Root,fallback);
                if(project.NativeTrash){entry["tm_draft_removed"]=0;string metaFile=Path.Combine(copy,"draft_meta_info.json");var meta=Metadata(metaFile);if(meta!=null){meta["tm_draft_removed"]=0;Save(metaFile,meta);}}
                Unchanged(original);Directory.Move(copy,target);added.Add(target);
                entries.RemoveAll(e=>Text(e,"draft_id")==project.Id||Text(e,"draft_fold_path")==target);
                entries.Add(entry);ids.Add(project.Id);restored.Add(project);result.Completed++;
            }
            if(added.Count>0){
                Unchanged(original);index["all_draft_store"]=entries.ToArray();index["root_path"]=Root;
                int count;Int32.TryParse(Text(index,"draft_ids"),out count);index["draft_ids"]=Math.Max(count+added.Count,entries.Count);
                Save(Index,index);
            }
        }catch{
            foreach(string folder in added.AsEnumerable().Reverse()){NoLinks(folder);if(Within(folder,Root)&&Directory.Exists(folder))Directory.Delete(folder,true);}
            throw;
        }finally{if(Directory.Exists(stage)){NoLinks(stage);Directory.Delete(stage,true);}}
        if(restore)foreach(var project in restored){
            if(project.NativeTrash){RemoveNativeTrashRecord(project);NoLinks(project.Folder);if(Within(project.Folder,NativeBin)&&Directory.Exists(project.Folder))Directory.Delete(project.Folder,true);continue;}
            if(project.Id.Length>0)foreach(var matching in ScanNativeTrash().Where(p=>p.Id==project.Id).ToArray()){
                RemoveNativeTrashRecord(matching);NoLinks(matching.Folder);if(Within(matching.Folder,NativeBin)&&Directory.Exists(matching.Folder))Directory.Delete(matching.Folder,true);
            }
            string receipt=Path.GetDirectoryName(project.Folder);
            try{NoLinks(receipt);if(Within(receipt,Bin))Directory.Delete(receipt,true);}catch(IOException){}
        }
        return result;
    }
    public ProjectResult PermanentlyDeleteTrash(IList<CapCutProject> requested){
        return EmptyTrash(requested,folder=>{
            string target=Path.GetFullPath(folder);
            if(target.Equals(Bin,PathComparison)||target.Equals(NativeBin,PathComparison)||(!Within(target,Bin)&&!Within(target,NativeBin)))throw new IOException("Deletion target is outside the project trash.");
            NoLinks(target);foreach(string file in Files(target)){}
            Directory.Delete(target,true);
        });
    }
    public ProjectResult EmptyTrash(IList<CapCutProject> requested,Action<string> recycle) {
        using(var held=Acquire()){
            var items=CheckedTrash(requested);int done=0;
            foreach(var project in items){
                if(!project.NativeTrash&&project.Id.Length>0)foreach(var matching in ScanNativeTrash().Where(p=>p.Id==project.Id).ToArray()){
                    Closed();recycle(matching.Folder);if(!Directory.Exists(matching.Folder))RemoveNativeTrashRecord(matching);
                    else throw new IOException(UiText.Get("Не удалось переместить проект в системную Корзину Windows."));
                }
                Closed();recycle(project.Folder);done++;
                if(project.NativeTrash){if(!Directory.Exists(project.Folder))RemoveNativeTrashRecord(project);continue;}
                string receipt=Path.GetDirectoryName(project.Folder);
                if(!Directory.Exists(project.Folder)&&Within(receipt,Bin)){NoLinks(receipt);Directory.Delete(receipt,true);}
            }
            return new ProjectResult{Completed=done};
        }
    }
}
