"""Build a small installer that downloads the matching portable ZIP."""
from pathlib import Path
import hashlib
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
version = re.search(r'public const string Display = "([^"]+)"', (ROOT/'launcher/Version.cs').read_text('utf-8-sig')).group(1)
release = ROOT/'releases'
archive = release/('CapCut-Launcher-'+version+'-Windows-x64.zip')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
source = ROOT/'local/windows-installer-generated.cs'
source.parent.mkdir(parents=True, exist_ok=True)
source.write_text((ROOT/'packaging/WindowsInstaller.cs').read_text('utf-8').replace('__VERSION__',version).replace('__ARCHIVE_SHA256__',digest),encoding='utf-8-sig')
output = release/('CapCut-Launcher-'+version+'-Windows-x64-Setup.exe')
compiler = Path(os.environ['WINDIR'])/'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
subprocess.run([str(compiler),'/nologo','/codepage:65001','/langversion:5','/target:winexe','/platform:x64','/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll','/reference:Microsoft.CSharp.dll','/win32icon:'+str(ROOT/'assets/launcher.ico'),'/out:'+str(output),str(source)],check=True)
subprocess.run([str(output),'--check-only'],check=True)
(release/'SHA256SUMS.txt').write_text(digest+'  '+archive.name+'\n'+hashlib.sha256(output.read_bytes()).hexdigest()+'  '+output.name+'\n',encoding='ascii')
print('INSTALLER',output)
print('INSTALLER_KIB',round(output.stat().st_size/1024,1))
