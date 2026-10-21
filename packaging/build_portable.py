"""Allowlist-only release: never copy this PC's account, cache, logs or projects."""
import datetime
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.search(r'public const string Display = "([^"]+)"', (ROOT / 'launcher/Version.cs').read_text('utf-8')).group(1)
OUT = ROOT / 'Лаунчер' / ('CapCut Launcher-' + VERSION)
ARCHIVE = Path(str(OUT) + '.zip')
if OUT.exists() or ARCHIVE.exists():
    raise SystemExit('Release already exists; preserve it and choose a new version.')
OUT.mkdir(parents=True)

def copy(relative):
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / relative, target)

files = [
    'scripts/launch_capcut.ps1',
    'scripts/install_update.ps1',
    'scripts/runtime/launch_capcut_minimal.py',
    'scripts/runtime/capcut_region_settings.py',
    'scripts/runtime/capcut_auth_session.py',
    'scripts/runtime/apply_capcut_session.js',
    'scripts/runtime/guard_capcut_region.js',
    'scripts/runtime/show_capcut_pro_ui.js',
    'scripts/auth/CapCutBrowserLogin.cs',
    'scripts/auth/browser_transfer.js',
    'scripts/auth/start_browser_login.ps1',
    'scripts/auth/forget_saved_login.ps1',
    'launcher/UiText.cs',
    'assets/launcher.ico', 'assets/launcher.png',
]
for name in files:
    copy(name)
    if name.endswith('.ps1'):
        target = OUT / name
        target.write_text(target.read_text('utf-8-sig'), encoding='utf-8-sig', newline='\r\n')

# The distributed entry point uses only its included runtime.
entry = OUT / 'scripts/launch_capcut.ps1'
entry_text = entry.read_text('utf-8-sig')
entry_text = re.sub(r"\$pythonPath = Join-Path \$env:USERPROFILE [^\n]+\n", "", entry_text)
entry_text = entry_text.replace('if (Test-Path -LiteralPath $portablePython) { $pythonPath = $portablePython }', '$pythonPath = $portablePython')
entry.write_text(entry_text, encoding='utf-8-sig', newline='\r\n')

python_zip = ROOT / 'local/package-downloads/python-3.13.16-embed-amd64.zip'
python_root = OUT / 'runtime/python'
with zipfile.ZipFile(python_zip) as bundle:
    bundle.extractall(python_root)
(python_root / 'python313._pth').write_text(
    'python313.zip\n.\n..\\..\\scripts\\runtime\n..\\..\\local\\runtime-dependencies\n', encoding='ascii')
for name in ('__init__.py', '_frida.pyd', '_frida.pyi', 'aio.py', 'py.typed'):
    copy('local/runtime-dependencies/frida/' + name)
for name in ('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll', 'WebView2Loader.dll', 'sdk-version.txt'):
    copy('local/auth-browser-sdk/' + name)
shutil.copy2(ROOT / 'local/package-downloads/MicrosoftEdgeWebview2Setup.exe', OUT / 'runtime/MicrosoftEdgeWebview2Setup.exe')
shutil.copy2(ROOT / 'packaging/Инструкция.txt', OUT / 'Инструкция.txt')
shutil.copy2(ROOT / 'packaging/Instructions.txt', OUT / 'Instructions.txt')
(OUT/'locales').mkdir()
shutil.copy2(ROOT/'launcher/English.json',OUT/'locales/en.json')
licenses = OUT / 'licenses'
licenses.mkdir()
shutil.copy2(python_root / 'LICENSE.txt', licenses / 'Python-LICENSE.txt')
shutil.copy2(ROOT / 'local/runtime-dependencies/frida-17.24.3.dist-info/licenses/COPYING', licenses / 'Frida-COPYING.txt')
with zipfile.ZipFile(ROOT / 'local/package-downloads/webview2-sdk.nupkg') as sdk:
    for name in ('LICENSE.txt', 'NOTICE.txt'):
        (licenses / ('WebView2-' + name)).write_bytes(sdk.read(name))

compiler = Path(r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe')
common = [str(compiler), '/nologo', '/target:winexe', '/platform:x64',
          '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
          '/reference:System.Web.Extensions.dll', '/reference:System.Security.dll', '/win32icon:' + str(OUT / 'assets/launcher.ico')]
subprocess.run(common + ['/out:' + str(OUT / 'CapCut Launcher.exe'), str(ROOT / 'launcher/Launcher.cs'), str(ROOT / 'launcher/Version.cs'),str(ROOT/'launcher/UiText.cs'),str(ROOT/'launcher/LauncherUpdate.cs')], check=True)
sdk = OUT / 'local/auth-browser-sdk'
subprocess.run(common + ['/out:' + str(sdk / 'CapCutBrowserLogin.exe'),
    '/reference:System.Net.Http.dll', '/reference:System.Security.dll',
    '/reference:' + str(sdk / 'Microsoft.Web.WebView2.Core.dll'),
    '/reference:' + str(sdk / 'Microsoft.Web.WebView2.WinForms.dll'),
    str(OUT / 'scripts/auth/CapCutBrowserLogin.cs'), str(ROOT / 'launcher/Version.cs'),str(ROOT/'launcher/UiText.cs')], check=True)
subprocess.run([str(python_root / 'python.exe'), '-B', '-c',
    'import frida,ssl,ctypes,winreg,capcut_auth_session; print("Portable imports OK: Frida",frida.__version__); '
    'assert frida.__version__=="17.24.3"'], check=True)
subprocess.run([str(OUT / 'CapCut Launcher.exe'), '--check-only'], check=True)
subprocess.run([str(sdk / 'CapCutBrowserLogin.exe'), str(OUT), '--check-only'], check=True)
info = {
    'version': VERSION, 'built_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'platform': 'Windows x64', 'python': '3.13.16 embeddable', 'frida': '17.24.3',
    'tested_os': 'Windows 11 Pro 25H2 26200.9711 AMD64',
    'tested_capcut_file_version': '9.6.0.4097', 'tested_capcut_product_version': '9.6.0.89fd5606',
    'account_data_included': False, 'state_location': '%LOCALAPPDATA%/CapCutLauncher',
    'portable_imports_checked': True, 'launcher_constructs': True, 'webview_runtime_available_on_build_pc': True,
    'clean_windows_vm_tested': False, 'other_capcut_versions_tested': False,
    'custom_region_menu_live_checked': True,
    'standalone_runtime_checked': True,
    'icon_transparent_exterior': True,
    'account_label_live_checked': True,
    'help_window_live_checked': True,
    'forget_profile_fixture_checked': True,
    'browser_exit_wait_checked_with_stub_process': True,
    'download_sources': {
        'python': 'https://www.python.org/ftp/python/3.13.16/python-3.13.16-embed-amd64.zip',
        'webview2_installer': 'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
        'webview2_sdk': 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4258.31/microsoft.web.webview2.1.0.4258.31.nupkg'},
    'download_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (python_zip, ROOT/'local/package-downloads/MicrosoftEdgeWebview2Setup.exe',ROOT/'local/package-downloads/webview2-sdk.nupkg')},
}
(OUT / 'build-info.json').write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding='utf-8')
manifest = {str(p.relative_to(OUT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(OUT.rglob('*')) if p.is_file()}
assert not any('desktop-session' in name or 'auth-browser-profile' in name or name.endswith('.jsonl') for name in manifest)
(OUT / 'manifest-sha256.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
with zipfile.ZipFile(ARCHIVE, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for p in sorted(OUT.rglob('*')):
        if p.is_file():bundle.write(p, p.relative_to(OUT.parent))
print('RELEASE_FOLDER', OUT)
print('RELEASE_ZIP', ARCHIVE)
print('ZIP_MIB', round(ARCHIVE.stat().st_size / 1024**2, 1))
