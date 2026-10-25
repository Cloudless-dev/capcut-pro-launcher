using System;
using System.IO;

internal static class ProjectLocationTests {
    static int count;
    static void Check(bool value,string label){if(!value)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
    public static int Main(){
        string root=Path.Combine(Path.GetTempPath(),"capcut-location-tests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
        try{
            string data=Path.Combine(root,"CapCut","User Data"),standard=Path.Combine(data,"Projects","com.lveditor.draft");Directory.CreateDirectory(standard);
            string config=Path.Combine(data,"Config");Directory.CreateDirectory(config);
            Check(ProjectLocations.Detect(new[]{data})==standard,"standard Windows project-library layout");
            string custom=Path.Combine(root,"custom","com.lveditor.draft");Directory.CreateDirectory(custom);
            ProjectLibrary.Save(Path.Combine(custom,"root_meta_info.json"),new {all_draft_store=new object[0]});
            ProjectLibrary.Save(Path.Combine(config,"globalSetting"),new {draft_storage_path=Path.GetDirectoryName(custom)});
            Check(ProjectLocations.Detect(new[]{data})==custom,"validated custom location from JSON settings");
            File.WriteAllText(Path.Combine(config,"globalSetting"),"[General]\ndraft_path="+custom+"\n");
            Check(ProjectLocations.Detect(new[]{data})==custom,"validated custom location from INI settings");
            File.WriteAllText(Path.Combine(config,"globalSetting"),"[General]\ndraft_path="+root+"\n");
            Check(ProjectLocations.Detect(new[]{data})==standard,"unrecognized directory hint ignored");
            File.WriteAllText(Path.Combine(config,"globalSetting"),"{broken");
            Check(ProjectLocations.Detect(new[]{data})==standard,"malformed settings do not block default discovery");
            string project=Path.Combine(standard,"timeline-project"),timeline=Path.Combine(project,"Timelines","timeline-id");Directory.CreateDirectory(timeline);
            ProjectLibrary.Save(Path.Combine(project,"draft_meta_info.json"),new {draft_id="timeline-project",draft_name="Timeline fixture",draft_fold_path=project});
            ProjectLibrary.Save(Path.Combine(project,"Timelines","project.json"),new {main_timeline_id="timeline-id"});
            ProjectLibrary.Save(Path.Combine(timeline,"draft_content.json"),new {materials=new object[0]});
            var library=new ProjectLibrary(standard,Path.Combine(root,"backups"),()=>false);
            Check(library.Scan().Count==1&&!library.Scan()[0].Incomplete,"nested Windows timeline counts as complete project");
            string destination=Path.Combine(root,"imported");var importer=new ProjectLibrary(destination,Path.Combine(root,"backups"),()=>false);
            Check(importer.Import(project).Completed==1,"nested-timeline project imports");
            string index=File.ReadAllText(Path.Combine(destination,"root_meta_info.json"));
            Check(index.Contains("Timelines")&&index.Contains("timeline-id"),"index points to actual nested content file");
            Console.WriteLine("RESULT "+count+" checks passed");return 0;
        }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
        finally{Directory.Delete(root,true);}
    }
}
