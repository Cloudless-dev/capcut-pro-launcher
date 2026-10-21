"""Fetch pinned upstream build dependencies, checking published SHA-256 digests."""
import hashlib
import json
import lzma
from pathlib import Path
import tarfile
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
VENDOR=ROOT/'vendor';VENDOR.mkdir(exist_ok=True)

def fetch(url,path,expected):
    if not path.exists():
        request=urllib.request.Request(url,headers={'User-Agent':'CapCutLauncherBuild'})
        with urllib.request.urlopen(request,timeout=120) as response,path.open('wb') as output:
            while data:=response.read(1024*1024):output.write(data)
    actual=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual!=expected:raise RuntimeError('SHA-256 mismatch: '+path.name)
    print('Verified',path.name)

def release_asset(repo,tag,name):
    req=urllib.request.Request(f'https://api.github.com/repos/{repo}/releases/tags/{tag}',headers={'User-Agent':'CapCutLauncherBuild'})
    release=json.load(urllib.request.urlopen(req,timeout=30))
    asset=next(a for a in release['assets'] if a['name']==name)
    digest=asset.get('digest','')
    if not digest.startswith('sha256:'):raise RuntimeError('Upstream did not publish a digest.')
    return asset['browser_download_url'],digest[7:]

frida=VENDOR/'frida-gadget.dylib.xz'
fetch('https://github.com/frida/frida/releases/download/17.24.3/frida-gadget-17.24.3-macos-universal.dylib.xz',frida,'ee41fd09297f4c4c2b1cd58761ec2f61540a0d917760f453e947376058a87eae')
with lzma.open(frida) as source:(VENDOR/'frida-gadget.dylib').write_bytes(source.read())
u='https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz'
d='c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
fetch(u,VENDOR/'Sparkle.tar.xz',d)
with tarfile.open(VENDOR/'Sparkle.tar.xz') as bundle:bundle.extractall(VENDOR/'Sparkle',filter='tar')

electron=VENDOR/'electron-arm64.zip'
fetch('https://github.com/electron/electron/releases/download/v45.0.0/electron-v45.0.0-darwin-arm64.zip',electron,'896c3a50b148e89a158dca08a6996a022ddf39b23aac871e107f5b4087f8caa9')
import subprocess
subprocess.run(['ditto','-x','-k',str(electron),str(VENDOR/'electron-arm64')],check=True)
