"""Fetch pinned build inputs. End users only need the published ZIP or EXE."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
lock = json.loads((ROOT / 'packaging/windows-dependencies.json').read_text('utf-8'))
downloads = ROOT / 'local/package-downloads'
downloads.mkdir(parents=True, exist_ok=True)
for item in lock['files']:
    target = downloads / item['name']
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != item['sha256']:
        pending = target.with_suffix(target.suffix + '.download')
        urllib.request.urlretrieve(item['url'], pending)
        if hashlib.sha256(pending.read_bytes()).hexdigest() != item['sha256']:
            raise SystemExit('Checksum mismatch: ' + item['name'])
        pending.replace(target)
    print('Verified', item['name'])
sdk = ROOT / 'local/auth-browser-sdk'
sdk.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(downloads / 'webview2-sdk.nupkg') as bundle:
    for name in ('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll'):
        (sdk / name).write_bytes(bundle.read('lib/net462/' + name))
    (sdk / 'WebView2Loader.dll').write_bytes(bundle.read('build/native/x64/WebView2Loader.dll'))
(sdk / 'sdk-version.txt').write_text(lock['webview2'], encoding='ascii')
subprocess.run([sys.executable, '-m', 'pip', 'install', '--only-binary=:all:', '--target',
                str(ROOT / 'local/runtime-dependencies'), 'frida==' + lock['frida']], check=True)
print('Windows build dependencies ready.')
