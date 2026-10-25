using System;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class BrowserModeTests {
    [STAThread]static int Main(){
        string state=Path.Combine(Path.GetTempPath(),"capcut-browser-mode-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(state);Environment.SetEnvironmentVariable("CAPCUT_STATE_ROOT",state);
        try{
            var serializer=new JavaScriptSerializer();byte[] plain=Encoding.UTF8.GetBytes("{\"email\":\"fixture@example.invalid\",\"password\":\"test fixture only\"}");File.WriteAllText(Path.Combine(state,"credentials.json"),serializer.Serialize(Convert.ToBase64String(ProtectedData.Protect(plain,null,DataProtectionScope.CurrentUser))));Array.Clear(plain,0,plain.Length);
            Environment.SetEnvironmentVariable("CAPCUT_AUTOMATIC_LOGIN","1");
            using(var form=new LoginWindow(AppDomain.CurrentDomain.BaseDirectory)){
                if(form.Opacity!=0||form.ShowInTaskbar||form.Location.X>-10000)throw new Exception("Automatic login would expose the website window.");
                if(!(bool)typeof(LoginWindow).GetField("backgroundLogin",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form))throw new Exception("Automatic mode not enabled.");
            }
            Environment.SetEnvironmentVariable("CAPCUT_AUTOMATIC_LOGIN","0");
            using(var form=new LoginWindow(AppDomain.CurrentDomain.BaseDirectory)){if(form.Opacity!=1||!form.ShowInTaskbar)throw new Exception("Manual browser would be hidden.");if((bool)typeof(LoginWindow).GetField("backgroundLogin",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form))throw new Exception("Manual mode loaded saved credentials.");}
            Console.WriteLine("PASS automatic sign-in hidden off-screen, manual sign-in visible, toggle respected even with saved credentials. No authentication requests were made.");return 0;
        }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
        finally{Directory.Delete(state,true);}
    }
}
