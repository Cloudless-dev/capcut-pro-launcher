using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.WinForms;

internal static class WebShellTests {
    static int result=1;
    static async Task Wait(Func<Task<bool>> condition){var limit=DateTime.UtcNow.AddSeconds(20);while(DateTime.UtcNow<limit){if(await condition())return;await Task.Delay(100);}throw new Exception("Web UI timed out.");}
    static async Task<bool> JS(WebView2 web,string expression){return await web.CoreWebView2.ExecuteScriptAsync("Boolean("+expression+")")=="true";}
    [STAThread]static int Main(){
        string state=Path.Combine(Path.GetTempPath(),"capcut-web-tests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(state);string library=Path.Combine(state,"projects");Directory.CreateDirectory(library);
        for(int i=0;i<3;i++){string folder=Path.Combine(library,"fixture-"+i);Directory.CreateDirectory(folder);File.WriteAllText(Path.Combine(folder,"draft_meta_info.json"),"{\"draft_id\":\""+i+"\",\"draft_name\":\"Project "+i+"\"}");File.WriteAllText(Path.Combine(folder,"draft_content.json"),"{}");}
        ProjectLibrary.Save(Path.Combine(state,"settings.json"),new System.Collections.Generic.Dictionary<string,string>{{"projectsRoot",library},{"theme","dark"},{"language","en"}});
        Environment.SetEnvironmentVariable("CAPCUT_LAUNCHER_STATE_ROOT",state);Environment.SetEnvironmentVariable("CAPCUT_LEGACY_UI",null);Application.EnableVisualStyles();UiText.Initialize(AppDomain.CurrentDomain.BaseDirectory);
        using(var form=(Form)Activator.CreateInstance(typeof(Launcher),true)){
            form.Shown+=async delegate{
                try{
                    Console.WriteLine("CHECK WebView startup");WebView2 web=null;await Wait(async()=>{web=(WebView2)typeof(Launcher).GetField("webShell",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form);return web!=null&&web.CoreWebView2!=null&&await JS(web,"document.querySelectorAll('.profile-card').length===1");});
                    Console.WriteLine("CHECK initial theme");if(!await JS(web,"document.documentElement.dataset.theme==='dark'"))throw new Exception("Initial dark theme missing");
                    if(!(bool)typeof(Launcher).GetField("autoStart",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form))throw new Exception("Launch after sign-in must default to enabled.");
                    if(!await JS(web,"getComputedStyle(document.querySelector('.profile-name')).color==='rgb(242, 238, 248)'"))throw new Exception("Dark text contrast regression");
                    await web.CoreWebView2.ExecuteScriptAsync("document.querySelector('.profile-meta .picker-trigger').click()");await Wait(()=>JS(web,"document.querySelectorAll('[role=option]').length>=249"));
                    if(!await JS(web,"[...document.querySelectorAll('[role=option] img')].some(i=>i.getAttribute('src')==='flags/us.svg')"))throw new Exception("Country flags missing");
                    await web.CoreWebView2.ExecuteScriptAsync("document.querySelector('.profile-name').click()");
                    Console.WriteLine("CHECK projects");await web.CoreWebView2.ExecuteScriptAsync("document.querySelectorAll('.nav-item')[1].click()");await Wait(()=>JS(web,"document.querySelectorAll('.project-card').length===3"));
                    if(!await JS(web,"(()=>{const b=[...document.querySelectorAll('.delete-button')];return b.length===2&&b[0].offsetWidth===b[1].offsetWidth&&b[0].offsetHeight===b[1].offsetHeight})()"))throw new Exception("Delete button dimensions differ");
                    if(!await JS(web,"document.querySelector('[title=\"Refresh projects\"]').textContent.trim()===''"))throw new Exception("Refresh text overlaps icon");
                    Console.WriteLine("CHECK settings");await web.CoreWebView2.ExecuteScriptAsync("document.querySelectorAll('.nav-item')[3].click()");await Wait(()=>JS(web,"document.querySelectorAll('.setting').length>=7"));
                    foreach(string theme in new[]{"light","gray","dark"}){await web.CoreWebView2.ExecuteScriptAsync("chrome.webview.postMessage({action:'settings',theme:'"+theme+"'})");await Wait(()=>JS(web,"document.documentElement.dataset.theme==='"+theme+"'"));}
                    Console.WriteLine("CHECK modal");await web.CoreWebView2.ExecuteScriptAsync("document.querySelectorAll('.nav-item')[0].click()");await Wait(()=>JS(web,"document.querySelector('header button')!==null"));await web.CoreWebView2.ExecuteScriptAsync("document.querySelector('header button').click()");await Wait(()=>JS(web,"document.querySelector('[role=dialog]')!==null"));
                    if(!await JS(web,"document.querySelector('input[type=password]')!==null&&document.querySelector('.toggle')!==null"))throw new Exception("Profile modal incomplete");
                    if(!await JS(web,"(()=>{const r=document.querySelector('.modal').getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight})()"))throw new Exception("Modal outside viewport");
                    await web.CoreWebView2.ExecuteScriptAsync("document.querySelector('.modal-actions button').click()");
                    Console.WriteLine("PASS native WebView2: profiles, project fixtures, equal delete buttons, icon-only refresh, three themes, profile modal and viewport bounds");result=0;
                }catch(Exception ex){Console.Error.WriteLine(ex);}finally{form.Close();}
            };
            Application.Run(form);
        }
        for(int i=0;i<20;i++){try{Directory.Delete(state,true);break;}catch(IOException){System.Threading.Thread.Sleep(100);}catch(UnauthorizedAccessException){System.Threading.Thread.Sleep(100);}}
        return result;
    }
}
