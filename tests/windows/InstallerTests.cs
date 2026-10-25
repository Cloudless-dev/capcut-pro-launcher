using System;
using System.IO;
using System.Net;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class InstallerTests {
    static object Field(object instance,string name){return instance.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(instance);}
    [STAThread]static int Main(){
        Application.EnableVisualStyles();
        try{
            using(var form=(Form)Activator.CreateInstance(typeof(WindowsInstaller),true)){
                if(!((CheckBox)Field(form,"desktop")).Checked)throw new Exception("Desktop shortcut default missing.");
                if(!(Field(form,"install") is SetupButton)||!(Field(form,"browse") is SetupButton)||!(Field(form,"desktop") is SetupToggle))throw new Exception("Custom setup controls missing.");
                typeof(WindowsInstaller).GetMethod("Activity",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(form,new object[]{"Download","Fixture","download.png",62});
                if(((SetupProgress)Field(form,"progress")).Value!=62||((Label)Field(form,"percent")).Text!="62%")throw new Exception("Progress screen did not update.");
                if(((PictureBox)Field(form,"stateIcon")).Image==null)throw new Exception("Bundled icon missing.");
                foreach(string name in new[]{"install","cancel","heading","subtitle","message"}){
                    var control=(Control)Field(form,name);if(control.Right>form.ClientSize.Width||control.Bottom>form.ClientSize.Height||control.Left<0||control.Top<0)throw new Exception("Setup control outside viewport: "+name);
                }
            }
            Task.Run(async delegate{
                string file=Path.Combine(Path.GetTempPath(),"capcut-cancel-test-"+Guid.NewGuid().ToString("N")+".zip");
                try{using(var client=new WebClient()){
                    var task=(Task)typeof(WindowsInstaller).GetMethod("Download",BindingFlags.Static|BindingFlags.NonPublic).Invoke(null,new object[]{file,null,client});
                    await Task.Delay(75);client.CancelAsync();bool cancelled=false;try{await task;}catch(OperationCanceledException){cancelled=true;}catch(WebException ex){cancelled=ex.Status==WebExceptionStatus.RequestCanceled;}
                    if(!cancelled)throw new Exception("Download cancellation was not honored.");
                }}finally{if(File.Exists(file))File.Delete(file);}
            }).GetAwaiter().GetResult();
            Console.WriteLine("PASS setup controls, viewport bounds, embedded assets, progress updates and real download cancellation. No application installation was performed.");return 0;
        }catch(Exception error){Console.Error.WriteLine(error);return 1;}
    }
}
