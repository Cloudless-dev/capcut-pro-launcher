# Windows 0.054

The interface is React + TypeScript + CSS in `launcher-web/`. WebView2 hosts the
local files. `launcher/` contains the C# backend and a minimal native host.
No legacy WinForms launcher interface is included.

## Build

Use Windows x64, .NET Framework 4.8, Node.js with pnpm, and Python 3.11+ with pip.

```powershell
pnpm --dir launcher-web install --frozen-lockfile
pnpm --dir launcher-web build
python packaging/fetch_windows_dependencies.py
python packaging/build_portable.py
```

The dependency lock file pins download hashes. The builder runs project,
profile, session, native WebView2 and browser-mode checks, then creates a ZIP,
a self-extracting EXE, and SHA256SUMS.txt under `releases/`.

The EXE contains the exact ZIP and extracts it into a versioned local cache.
Account data stays under `%LOCALAPPDATA%/CapCutLauncher` and is not included.

## Source map

- `Launcher.cs`: startup, settings, CapCut process and browser helper.
- `WebShell.cs`: local WebView2 bridge and project commands.
- `LauncherProfiles.cs`: isolated profiles and Windows DPAPI credentials.
- `ProjectLibrary.cs`, `ProjectAssets.cs`: verified project operations and trash.
- `LauncherUpdate.cs`: Windows release selection and checksums.
- `scripts/auth/`: official browser sign-in and session transfer.
- `scripts/runtime/`: region, interface and session integration.

The profile automatic-sign-in switch controls browser visibility. The global
launch-after-sign-in setting is independent and defaults to enabled.

The unified trash deduplicates IDs from launcher and CapCut trash. Clearing it
permanently deletes selected project payloads, without the Windows Recycle Bin.
Project tests use disposable fixtures, not real project files.

Font category modification is disabled on Windows. Other CapCut versions and
fresh Windows installations have not been verified. Full real-account hidden
sign-in still depends on the site's current sign-in and verification flow.
