# Windows

C# backend and WebView2 host. Interface: [launcher-web](../launcher-web/).

- `Launcher.cs` — startup and settings.
- `WebShell.cs` — interface commands.
- `LauncherProfiles.cs` — profiles and saved sign-ins.
- `ProjectLibrary.cs`, `ProjectAssets.cs` — projects and trash.
- `LauncherUpdate.cs` — updates.

## Build

Windows x64, .NET Framework 4.8, Node.js, pnpm and Python 3.11+.

```powershell
pnpm --dir launcher-web install --frozen-lockfile
pnpm --dir launcher-web build
python packaging/fetch_windows_dependencies.py
python packaging/build_portable.py
```

Output: setup EXE, portable ZIP and checksums in `releases/`.
Tests: `powershell -ExecutionPolicy Bypass -File scripts/test_windows.ps1`.
