using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;

internal static class UiText {
    static Dictionary<string,string> translations=new Dictionary<string,string>();
    public static bool English;
    public static event Action Changed;
    public static void Initialize(string root){
        string file=Path.Combine(root,"locales","en.json");
        if(!File.Exists(file))file=Path.Combine(root,"launcher","English.json");
        if(File.Exists(file))translations=new JavaScriptSerializer().Deserialize<Dictionary<string,string>>(File.ReadAllText(file));
        string language=Environment.GetEnvironmentVariable("CAPCUT_LANGUAGE");
        English=language==null?System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName!="ru":language=="en";
    }
    public static void Notify(){if(Changed!=null)Changed();}
    public static string Source(string text){
        if(translations.ContainsKey(text))return text;
        foreach(var pair in translations)if(pair.Value==text)return pair.Key;
        return text;
    }
    public static string Get(string text){
        string source=Source(text),value;
        return English&&translations.TryGetValue(source,out value)?value:source;
    }
}
