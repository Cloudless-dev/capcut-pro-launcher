using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

internal sealed class LauncherProfile {
    public string Id { get; set; }
    public string Name { get; set; }
    public string Region { get; set; }
    public bool NativeAccount { get; set; }
    public bool? AutomaticLogin { get; set; }
    public override string ToString() { return Name + (NativeAccount ? " · CapCut" : ""); }
}
internal sealed class ProfilesDocument {
    public int SchemaVersion { get; set; }
    public string SelectedId { get; set; }
    public List<LauncherProfile> Profiles { get; set; }
}
internal sealed class LauncherProfiles {
    readonly string root;
    public ProfilesDocument Document;
    public LauncherProfiles(string stateRoot, string region) {
        root = stateRoot; string file = Path.Combine(root, "profiles.json");
        if (File.Exists(file)) {
            ProjectLibrary.NoLinks(file);
            Document = ProjectLibrary.Serializer().Deserialize<ProfilesDocument>(File.ReadAllText(file));
            Validate();
        } else {
            Document = new ProfilesDocument { SchemaVersion = 1, Profiles = new List<LauncherProfile>() };
            string old = Path.Combine(root, "auth-browser-sdk", "desktop-session.bin");
            var profile = new LauncherProfile { Id = "00000000-0000-4000-8000-000000000001", Name = UiText.Get("Основной"), Region = region, NativeAccount = !File.Exists(old) };
            Document.Profiles.Add(profile); Document.SelectedId = profile.Id;
            // Preserve the old session and browser profile. Migration is repeatable
            // if interrupted before profiles.json has been committed.
            if (File.Exists(old)) {
                ProjectLibrary.NoLinks(old); string target = Path.Combine(DirectoryFor(profile), "auth-browser-sdk"); Directory.CreateDirectory(target);
                string migrated=Path.Combine(target, "desktop-session.bin");
                if(!File.Exists(migrated))File.Copy(old, migrated, false);
                else if(ProjectLibrary.Hash(old)!=ProjectLibrary.Hash(migrated))throw new IOException("Legacy session migration needs review; both copies were retained.");
            }
            string browser = Path.Combine(root, "auth-browser-profile");
            if (Directory.Exists(browser)) {
                if(Process.GetProcessesByName("CapCutBrowserLogin").Length>0)throw new IOException(UiText.Get("Сначала закройте CapCut и окно входа."));
                ProjectLibrary.NoLinks(browser);
                foreach (string ignored in ProjectLibrary.Files(browser)) { }
                Directory.CreateDirectory(DirectoryFor(profile));
                string migratedBrowser=Path.Combine(DirectoryFor(profile), "auth-browser-profile");
                if(!Directory.Exists(migratedBrowser))Directory.Move(browser,migratedBrowser);
            }
            Save();
        }
    }
    public static string Country(string value) {
        string code = (value ?? "").Trim().Split(new[] {' ', '—', '-'}, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        code = code.ToUpperInvariant();
        if (!Regex.IsMatch(code, "^[A-Z]{2}$")) throw new IOException(UiText.Get("Введите двухбуквенный код страны, например US, TR или NL."));
        return code;
    }
    void Validate() {
        if (Document == null || Document.SchemaVersion != 1 || Document.Profiles == null ||
            Document.Profiles.Any(p => p == null || !ValidId(p.Id) || String.IsNullOrWhiteSpace(p.Name) || Country(p.Region) != p.Region) ||
            Document.Profiles.Select(p => p.Id).Distinct().Count() != Document.Profiles.Count ||
            (Document.SelectedId != null && !Document.Profiles.Any(p => p.Id == Document.SelectedId)))
            throw new IOException(UiText.Get("Не удалось прочитать список профилей. Сохранённые данные не изменены."));
    }
    static bool ValidId(string value) { Guid id; return Guid.TryParseExact(value, "D", out id); }
    public string DirectoryFor(LauncherProfile profile) {
        if (!ValidId(profile.Id)) throw new IOException("Invalid profile identifier.");
        string folder = Path.Combine(root, "Profiles", profile.Id); ProjectLibrary.NoLinks(folder); return folder;
    }
    public void Save() { Validate(); ProjectLibrary.NoLinks(root); Directory.CreateDirectory(root); ProjectLibrary.Save(Path.Combine(root, "profiles.json"), Document); }
    public void Delete(LauncherProfile profile) {
        string directory = DirectoryFor(profile);
        if (Directory.Exists(directory)) { foreach (var ignored in ProjectLibrary.Files(directory)) { } Directory.Delete(directory, true); }
        Document.Profiles.Remove(profile); Document.SelectedId = Document.Profiles.Select(p => p.Id).FirstOrDefault(); Save();
    }
    public static void SaveCredentials(string folder, string email, string password) {
        ProjectLibrary.NoLinks(folder); Directory.CreateDirectory(folder);
        byte[] bytes = Encoding.UTF8.GetBytes(ProjectLibrary.Serializer().Serialize(new { email = email, password = password }));
        try { ProjectLibrary.Save(Path.Combine(folder, "credentials.json"), Convert.ToBase64String(ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser))); }
        finally { Array.Clear(bytes, 0, bytes.Length); }
    }
    public static Dictionary<string, string> Credentials(string folder) {
        string file = Path.Combine(folder, "credentials.json"); ProjectLibrary.NoLinks(file);
        if (!File.Exists(file)) return null;
        var packed = ProjectLibrary.Serializer().Deserialize<string>(File.ReadAllText(file));
        byte[] raw = ProtectedData.Unprotect(Convert.FromBase64String(packed), null, DataProtectionScope.CurrentUser);
        try { return ProjectLibrary.Serializer().Deserialize<Dictionary<string, string>>(Encoding.UTF8.GetString(raw)); }
        finally { Array.Clear(raw, 0, raw.Length); }
    }
}
