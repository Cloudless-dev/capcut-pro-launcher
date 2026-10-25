using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

internal static class ProjectLibraryTests {
    static int passed;
    static string temporary;
    static void Check(bool value, string name) { if (!value) throw new Exception(name); passed++; Console.WriteLine("PASS " + name); }
    static void Reject(Action action, string name) { try { action(); } catch (IOException) { passed++; Console.WriteLine("PASS " + name); return; } throw new Exception("Expected rejection: " + name); }
    static string Folder(string name) { string result = Path.Combine(temporary, name); Directory.CreateDirectory(result); return result; }
    static void Fixture(string root, string name, string id, string media = null) {
        string folder = Path.Combine(root, name); Directory.CreateDirectory(folder);
        ProjectLibrary.Save(Path.Combine(folder, "draft_meta_info.json"), new { draft_id = id, draft_name = "Project " + name, draft_fold_path = folder, draft_root_path = root, tm_draft_modified = 1700000000000000L });
        ProjectLibrary.Save(Path.Combine(folder, "draft_content.json"), new { materials = new { videos = new[] {new { path = media ?? Path.Combine(folder, "clip.mp4") }} }, embedded = ProjectLibrary.Serializer().Serialize(new { materials = new { videos = new[] {new { path = media ?? Path.Combine(folder, "clip.mp4") }} } }) });
        File.WriteAllText(Path.Combine(folder, "clip.mp4"), "fixture media"); Directory.CreateDirectory(Path.Combine(folder, "empty"));
    }
    static void Index(string root, params string[] names) {
        ProjectLibrary.Save(Path.Combine(root, "root_meta_info.json"), new { all_draft_store = names.Select(n => ProjectLibrary.Read(Path.Combine(root, n, "draft_meta_info.json"))).ToArray(), draft_ids = names.Length, custom_field = "keep" });
    }
    static bool Same(Dictionary<string,string> left, Dictionary<string,string> right) { return left.Count == right.Count && left.All(p => right.ContainsKey(p.Key) && right[p.Key] == p.Value); }
    public static int Main() {
        temporary = Path.Combine(Path.GetTempPath(), "capcut-project-tests-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temporary);
        try {
            string root = Folder("library"), backups = Folder("backups"), output = Folder("exports"), imported = Folder("imported");
            Fixture(root, "one", "id-one"); Fixture(root, "two", "id-two"); Index(root, "one", "two");
            File.WriteAllText(Path.Combine(root, "unrelated.txt"), "do not touch");
            var library = new ProjectLibrary(root, backups, () => false); var projects = library.Scan();
            Check(projects.Count == 2 && projects.All(p => !p.Incomplete), "scan recognized projects");
            Check(projects[0].Modified.Year == 2023, "microsecond timestamps");
            var before = ProjectLibrary.Manifest(root);
            var report = library.Export(projects, output, false);
            Check(report.Completed == 2 && Same(before, ProjectLibrary.Manifest(root)), "export preserves originals including empty folders");
            var target = new ProjectLibrary(imported, backups, () => false); var result = target.Import(report.Destination);
            Check(result.Completed == 2 && target.Scan().Count == 2, "import both projects");
            string content = File.ReadAllText(Path.Combine(imported, "one", "draft_content.json"));
            Check(content.Contains(ProjectAssets.Normalize(imported)) && !content.Contains(ProjectAssets.Normalize(root)), "rebase normal and embedded JSON references");
            Check(target.Import(report.Destination).Skipped == 2, "duplicate IDs skipped");
            var targetIndex = ProjectLibrary.Read(Path.Combine(imported, "root_meta_info.json"));
            Check(targetIndex.ContainsKey("all_draft_store"), "import writes CapCut index");
            Reject(() => library.Export(projects, root, false), "export into library rejected");
            var active = new ProjectLibrary(root, backups, () => true);
            Reject(() => active.Export(projects, output, false), "export while CapCut running rejected");
            Reject(() => active.Trash(projects), "trash while CapCut running rejected");
            Reject(() => active.Import(report.Destination), "import while CapCut running rejected");
            library.Trash(new[] {projects[0]});
            Check(library.Scan().Count == 1 && library.ScanTrash().Count == 1, "trash removes project and index entry");
            Check(ProjectLibrary.Text(ProjectLibrary.Read(Path.Combine(root, "root_meta_info.json")), "custom_field") == "keep", "unknown index fields preserved");
            Check(Directory.GetFiles(backups, "root_meta_info.json", SearchOption.AllDirectories).Length > 0, "index backup exists");
            var trash = library.ScanTrash(); var restored = library.Restore(trash);
            Check(restored.Completed == 1 && library.Scan().Count == 2 && library.ScanTrash().Count == 0, "restore reinstates folder and index");
            Check(!File.ReadAllText(Path.Combine(projects[0].Folder, "draft_content.json")).Contains(".launcher-trash") && File.Exists(Path.Combine(projects[0].Folder,"clip.mp4")), "restore rebases paths out of trash");
            library.Trash(library.Scan());
            library.Import(report.Destination);
            Check(library.Restore(library.ScanTrash()).Skipped == 2 && library.ScanTrash().Count == 2, "restore skips duplicate IDs without deleting trash");
            int recycled = 0;
            library.EmptyTrash(library.ScanTrash(), folder => { Directory.Move(folder, Path.Combine(Folder("recycled"), Guid.NewGuid().ToString("N"))); recycled++; });
            Check(recycled == 2 && library.ScanTrash().Count == 0, "empty trash invokes recycler for payloads");
            Check(File.ReadAllText(Path.Combine(root, "unrelated.txt")) == "do not touch", "unrelated files untouched");
            string broken = Folder("broken"); Fixture(broken, "one", "broken"); File.WriteAllText(Path.Combine(broken, "root_meta_info.json"), "not json");
            var invalid = new ProjectLibrary(broken, backups, () => false);
            Reject(() => invalid.Import(report.Destination), "malformed index prevents import");
            Check(File.ReadAllText(Path.Combine(broken, "root_meta_info.json")) == "not json" && Directory.GetDirectories(broken).Length == 1, "malformed index remains unchanged");
            string mediaLibrary = Folder("media-library"), material = Path.Combine(Folder("external"), "clip.mp4"); File.WriteAllText(material, "external media");
            Fixture(mediaLibrary, "movie", "movie-id", material); Index(mediaLibrary, "movie");
            var media = new ProjectLibrary(mediaLibrary, backups, () => false); var mediaBefore = ProjectLibrary.Manifest(mediaLibrary);
            var portable = media.Export(media.Scan(), output, true);
            Check(Same(mediaBefore, ProjectLibrary.Manifest(mediaLibrary)) && File.ReadAllText(material) == "external media", "media export leaves original references and material untouched");
            File.Delete(material); var portableTarget = new ProjectLibrary(Folder("portable-import"), backups, () => false);
            Check(portableTarget.Import(portable.Destination).Completed == 1, "portable import works without original material");
            string portableContent = File.ReadAllText(Path.Combine(portableTarget.Root, "movie", "draft_content.json"));
            Check(!portableContent.Contains(ProjectAssets.Normalize(material)) && portableContent.Contains("LauncherMedia-"), "portable media paths rewritten");
            Reject(() => media.Export(media.Scan(), output, true), "missing media aborts complete export");
            Check(Directory.GetDirectories(output).All(p => !Path.GetFileName(p).StartsWith(".capcut")), "failed export cleans staging only");
            var portableFiles = Directory.GetFiles(Path.Combine(portable.Destination, "movie", "Resources"), "*", SearchOption.AllDirectories);
            File.Delete(portableFiles[0]);
            Reject(() => new ProjectLibrary(Folder("bad-portable-import"), backups, () => false).Import(portable.Destination), "broken portable copy rejected");
            string moveRoot = Folder("move-library"); Fixture(moveRoot, "move", "move-id"); Index(moveRoot, "move"); var mover = new ProjectLibrary(moveRoot, backups, () => false);
            var moved = mover.Export(mover.Scan(), output, false, true);
            Check(Directory.Exists(moved.Destination) && mover.Scan().Count == 0 && mover.ScanTrash().Count == 1, "move exports verified copy then trashes originals");
            string incompleteRoot = Folder("incomplete"); Directory.CreateDirectory(Path.Combine(incompleteRoot, "partial")); ProjectLibrary.Save(Path.Combine(incompleteRoot, "partial", "draft_meta_info.json"), new { draft_id = "partial" });
            Check(target.Import(incompleteRoot).Skipped == 1, "incomplete import skipped");
            bool becameRunning = false; var guarded = new ProjectLibrary(Folder("race-import"), backups, () => { bool was = becameRunning; becameRunning = true; return was; });
            Reject(() => guarded.Import(report.Destination), "CapCut starting during import aborts");
            Check(!Directory.Exists(Path.Combine(guarded.Root, "one")), "interrupted import leaves no project behind");
            string rollbackRoot=Folder("rollback-import");
            var rollback=new ProjectLibrary(rollbackRoot,backups,()=>Directory.Exists(Path.Combine(rollbackRoot,"one")));
            Reject(()=>rollback.Import(report.Destination),"CapCut starting after first copy triggers rollback");
            Check(Directory.GetDirectories(rollbackRoot).Length==0 && !File.Exists(Path.Combine(rollbackRoot,"root_meta_info.json")),"multi-project rollback removes only new copies");
            string changedRoot=Folder("changed-index");bool changed=false;
            var changedLibrary=new ProjectLibrary(changedRoot,backups,()=>{
                if(!changed && Directory.Exists(Path.Combine(changedRoot,"one"))){
                    changed=true;ProjectLibrary.Save(Path.Combine(changedRoot,"root_meta_info.json"),new {all_draft_store=new object[0],fixture="concurrent update"});
                }
                return false;
            });
            Reject(()=>changedLibrary.Import(report.Destination),"concurrent index change aborts import");
            Check(Directory.GetDirectories(changedRoot).Length==0 && ProjectLibrary.Text(ProjectLibrary.Read(Path.Combine(changedRoot,"root_meta_info.json")),"fixture")=="concurrent update","concurrent index update preserved during rollback");
            string linkRoot=Folder("linked-library"),link=Path.Combine(linkRoot,"outside"),outside=Folder("outside");Fixture(outside,"protected","protected-id");
            var linkInfo=Environment.OSVersion.Platform==PlatformID.Win32NT
                ? new System.Diagnostics.ProcessStartInfo("cmd.exe","/c mklink /J \""+link+"\" \""+outside+"\"")
                : new System.Diagnostics.ProcessStartInfo("ln","-s \""+outside+"\" \""+link+"\"");
            linkInfo.UseShellExecute=false;linkInfo.CreateNoWindow=true;
            using(var process=System.Diagnostics.Process.Start(linkInfo)){process.WaitForExit();Check(process.ExitCode==0,"create junction/symlink fixture");}
            var linked=new ProjectLibrary(linkRoot,backups,()=>false);
            Reject(()=>linked.Scan(),"project junction/symlink is rejected");
            Check(File.Exists(Path.Combine(outside,"protected","clip.mp4")),"linked external files untouched");
            if(Environment.OSVersion.Platform==PlatformID.Win32NT)Directory.Delete(link);else File.Delete(link);
            string windowsRoot=Folder("windows-path-fixture");Fixture(windowsRoot,"draft","windows-path-id");Index(windowsRoot,"draft");
            string windowsFolder=Path.Combine(windowsRoot,"draft"),stored="C:/Users/Fixture/AppData/Local/CapCut/User Data/Projects/com.lveditor.draft/draft";
            var windowsMeta=ProjectLibrary.Read(Path.Combine(windowsFolder,"draft_meta_info.json"));windowsMeta["draft_fold_path"]=stored;ProjectLibrary.Save(Path.Combine(windowsFolder,"draft_meta_info.json"),windowsMeta);
            var windowsDraft=new {materials=new {videos=new[]{new {path=stored+"/clip.mp4"}}}};
            ProjectLibrary.Save(Path.Combine(windowsFolder,"draft_content.json"),windowsDraft);ProjectLibrary.Save(Path.Combine(windowsFolder,"template.tmp"),windowsDraft);ProjectLibrary.Save(Path.Combine(windowsFolder,"draft_content.json.bak"),windowsDraft);
            var windowsLibrary=new ProjectLibrary(windowsRoot,backups,()=>false);var windowsExport=windowsLibrary.Export(windowsLibrary.Scan(),output,true);
            string winCopy=Path.Combine(windowsExport.Destination,"draft");
            Check(!File.ReadAllText(Path.Combine(winCopy,"template.tmp")).Contains("C:/Users/Fixture")&&!File.ReadAllText(Path.Combine(winCopy,"draft_content.json.bak")).Contains("C:/Users/Fixture"),"Windows template and backup JSON paths updated");
            string fileURI=Convert.ToString(ProjectAssets.Replace("file:///C:/Users/Fixture/draft/clip.mp4",new[]{new KeyValuePair<string,string>("C:/Users/Fixture/draft",windowsFolder)}));
            Check(fileURI.Contains("windows-path-fixture")&&!fileURI.Contains("Users/Fixture"),"Windows file URI references rebased across hosts");
            string outsideReference="C:/Users/Fixture/draft/../outside.mp4";
            Check(Convert.ToString(ProjectAssets.Replace(outsideReference,new[]{new KeyValuePair<string,string>("C:/Users/Fixture/draft",windowsFolder)}))==outsideReference,"parent-traversing external path is not rebased into project");
            File.WriteAllBytes(Path.Combine(windowsFolder,"draft_content.json"),new byte[]{0,1,2,3});
            var opaque=windowsLibrary.Export(windowsLibrary.Scan(),output,false);
            Check(File.ReadAllBytes(Path.Combine(opaque.Destination,"draft","draft_content.json")).SequenceEqual(new byte[]{0,1,2,3}),"opaque project content copied byte for byte");
            Reject(()=>windowsLibrary.Export(windowsLibrary.Scan(),output,true),"opaque content cannot be labelled a complete media export");
            string lockedRoot=Folder("locked-library");bool attempted=false,blocked=false;
            var secondLauncher=new ProjectLibrary(lockedRoot,backups,()=>false);
            var firstLauncher=new ProjectLibrary(lockedRoot,backups,()=>{
                if(!attempted){attempted=true;try{secondLauncher.Import(report.Destination);}catch(IOException){blocked=true;}}
                return false;
            });
            var lockedResult=firstLauncher.Import(report.Destination);
            Check(blocked&&lockedResult.Completed==2,"concurrent launcher operation is blocked while first commits");
            string nativeRoot=Folder("native-trash-library"),nativeBin=Path.Combine(nativeRoot,".recycle_bin");Directory.CreateDirectory(nativeBin);
            Fixture(nativeBin,"native-one","native-one-id");Fixture(nativeBin,"native-two","native-two-id");Index(nativeBin,"native-one","native-two");
            var combined=new ProjectLibrary(nativeRoot,backups,()=>false);
            Check(combined.ScanTrash().Count==2,"projects deleted in CapCut appear in unified trash");
            Fixture(nativeRoot,"launcher-one","native-one-id");Index(nativeRoot,"launcher-one");combined.Trash(combined.Scan());
            Check(combined.ScanTrash().Count==2&&combined.ScanTrash().Count(p=>p.Id=="native-one-id")==1,"matching projects from both trash folders appear once");
            int nativeRecycleCount=0;
            var nativeDeleted=combined.EmptyTrash(combined.ScanTrash().Where(p=>p.Id=="native-one-id").ToArray(),folder=>{Directory.Move(folder,Path.Combine(Folder("native-recycled"),Guid.NewGuid().ToString("N")));nativeRecycleCount++;});
            Check(nativeDeleted.Completed==1&&combined.ScanTrash().Count==1&&nativeRecycleCount==2,"empty launcher trash recycles both copies of matching project");
            var nativeIndex=ProjectLibrary.Serializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(nativeBin,"root_meta_info.json")));
            Check(((System.Collections.IEnumerable)nativeIndex["all_draft_store"]).Cast<object>().Count()==1&&!Directory.Exists(Path.Combine(nativeBin,"native-one")),"matching CapCut trash file and index entry removed");
            Check(Directory.Exists(Path.Combine(nativeBin,"native-two")),"unrelated CapCut trash projects remain untouched");
            var restoredNative=combined.Restore(combined.ScanTrash());
            Check(restoredNative.Completed==1&&combined.ScanTrash().Count==0&&combined.Scan().Count==1,"restore from unified native trash updates both libraries");
            Fixture(nativeBin,"native-final","native-final-id");Index(nativeBin,"native-final");
            var clearedNative=combined.EmptyTrash(combined.ScanTrash(),folder=>Directory.Move(folder,Path.Combine(Folder("native-final-recycled"),Guid.NewGuid().ToString("N"))));
            Check(clearedNative.Completed==1&&combined.ScanTrash().Count==0,"native-only entries can be cleared through unified trash");
            Fixture(nativeRoot,"permanent","permanent-id");Index(nativeRoot,"permanent");
            var permanentProject=combined.Scan().First(p=>p.Id=="permanent-id");combined.Trash(new[]{permanentProject});
            Fixture(nativeBin,"permanent-native","permanent-id");Index(nativeBin,"permanent-native");
            var permanentItems=combined.ScanTrash();string permanentFolder=permanentItems.Single().Folder;
            Check(combined.PermanentlyDeleteTrash(permanentItems).Completed==1&&!Directory.Exists(permanentFolder)&&!Directory.Exists(Path.Combine(nativeBin,"permanent-native")),"permanent trash deletion removes both copies without a recycler");
            Check(combined.ScanTrash().Count==0&&Directory.Exists(combined.Scan().First().Folder),"permanent deletion preserves active projects");
            Console.WriteLine("RESULT " + passed + " checks passed"); return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { Directory.Delete(temporary, true); }
    }
}
