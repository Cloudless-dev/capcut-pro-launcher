"""Build a self-contained macOS launcher. No user state enters the bundle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
VERSION=(ROOT/'VERSION').read_text().strip()
BUILD=(ROOT/'BUILD_NUMBER').read_text().strip()
OUTPUT=ROOT.parent/'releases'
APP=OUTPUT/'CapCut Launcher.app'

def run(args,**kwargs):subprocess.run([str(x) for x in args],check=True,**kwargs)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--skip-helper',action='store_true');parser.add_argument('--dmg',action='store_true');args=parser.parse_args()
    identity=os.environ.get('CODE_SIGN_IDENTITY','-')
    sparkle=ROOT/'vendor/Sparkle/Sparkle.framework'
    if not args.skip_helper:
        run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--name','launcher-helper',
             '--distpath',ROOT/'build/helper','--workpath',ROOT/'build/pyinstaller','--specpath',ROOT/'build',ROOT/'Runtime/launcher_helper.py'])
    if APP.exists():shutil.rmtree(APP)
    contents=APP/'Contents';macos=contents/'MacOS';resources=contents/'Resources';frameworks=contents/'Frameworks'
    for p in [macos,resources,frameworks]:p.mkdir(parents=True,exist_ok=True)
    shutil.copytree(sparkle,frameworks/'Sparkle.framework',symlinks=True)
    run(['swiftc','-O','-swift-version','5','-target','arm64-apple-macosx14.0','-F',sparkle.parent,
        '-framework','AppKit','-framework','SwiftUI','-framework','Security','-framework','Sparkle',
        *sorted((ROOT/'Sources').glob('*.swift')),'-o',macos/'CapCutLauncher',
        '-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks'])
    shutil.copytree(ROOT/'build/helper/launcher-helper',resources/'Helper',symlinks=True)
    for localization in (ROOT/'Resources').glob('*.lproj'):
        shutil.copytree(localization,resources/localization.name)
    runtime=resources/'Runtime';runtime.mkdir()
    shutil.copy2(ROOT/'Runtime/agent.js',runtime/'agent.js')
    shutil.copy2(ROOT/'vendor/frida-gadget.dylib',runtime/'LauncherBridge.dylib')
    icons=ROOT/'build/AppIcon.iconset';icons.mkdir(parents=True,exist_ok=True)
    for size in [16,32,128,256,512]:
        for scale in [1,2]:
            name=f'icon_{size}x{size}'+('@2x' if scale==2 else '')+'.png'
            run(['sips','-z',str(size*scale),str(size*scale),ROOT/'packaging/assets/launcher.png','--out',icons/name],stdout=subprocess.DEVNULL)
    run(['iconutil','-c','icns',icons,'-o',resources/'AppIcon.icns'])
    info={'CFBundleIdentifier':'app.capcutlauncher.macos','CFBundleName':'CapCut Launcher','CFBundleDisplayName':'CapCut Launcher',
        'CFBundleExecutable':'CapCutLauncher','CFBundlePackageType':'APPL','CFBundleShortVersionString':VERSION,'CFBundleVersion':BUILD,
        'CFBundleDevelopmentRegion':'ru','CFBundleLocalizations':['ru','en'],'LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'CFBundleIconFile':'AppIcon',
        'NSPrincipalClass':'NSApplication','NSHumanReadableCopyright':'Independent launcher. Not affiliated with ByteDance.',
        'SUEnableAutomaticChecks':False,'SUEnableInstallerLauncherService':True}
    feed=os.environ.get('UPDATE_FEED_URL','');public_key=os.environ.get('SPARKLE_PUBLIC_KEY',(ROOT/'packaging/sparkle-public-key.txt').read_text().strip() if (ROOT/'packaging/sparkle-public-key.txt').exists() else '')
    if feed:info['SUFeedURL']=feed
    if public_key:info['SUPublicEDKey']=public_key
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    browser = resources/'Browser/CapCut Login.app'
    shutil.copytree(ROOT/'vendor/electron-arm64/Electron.app',browser,symlinks=True)
    electron_info=browser/'Contents/Info.plist'
    browser_info=plistlib.loads(electron_info.read_bytes())
    browser_info.update({'CFBundleIdentifier':'app.capcutlauncher.macos.login','CFBundleName':'CapCut Login',
        'CFBundleDisplayName':'CapCut Login','CFBundleExecutable':'CapCutLogin'})
    (browser/'Contents/MacOS/Electron').rename(browser/'Contents/MacOS/CapCutLogin')
    electron_info.write_bytes(plistlib.dumps(browser_info))
    shutil.copytree(ROOT/'Browser',browser/'Contents/Resources/app')
    shutil.copy2(ROOT/'vendor/electron-arm64/LICENSE',resources/'Electron-LICENSE.txt')
    shutil.copy2(ROOT/'vendor/electron-arm64/LICENSES.chromium.html',resources/'Chromium-LICENSES.html')
    licenses=resources/'Licenses';shutil.copytree(ROOT/'packaging/licenses',licenses)
    shutil.copy2(ROOT/'vendor/Sparkle/LICENSE',licenses/'Sparkle-LICENSE.txt')
    # Keep installer artwork inside the signed bundle so Finder's Show Hidden
    # Files preference cannot expose loose background images in the DMG window.
    artwork=ROOT/'build/dmg-assets';artwork.mkdir(parents=True,exist_ok=True)
    run(['swiftc',ROOT/'packaging/render_dmg.swift','-o',artwork/'render-dmg'])
    run([artwork/'render-dmg',artwork])
    installer=resources/'Installer';installer.mkdir()
    shutil.copy2(ROOT/'packaging/assets/Installation.pdf',installer/'Installation.pdf')
    run(['tiffutil','-cathidpicheck',artwork/'dmg-background.png',artwork/'dmg-background@2x.png','-out',installer/'background.tiff'])
    # Unique artwork paths prevent Finder resolving a background on an older
    # mounted release with the same volume name and bundle-relative path.
    backdrop=installer/'background.tiff'
    backdrop.rename(installer/f'background-{hashlib.sha256(backdrop.read_bytes()).hexdigest()[:12]}.tiff')
    # PyInstaller carries its Python framework and Frida client module.
    for p in sorted((resources/'Helper').rglob('*'),key=lambda p:len(p.parts),reverse=True):
        if p.is_file() and not p.is_symlink():
            with p.open('rb') as f:magic=f.read(4)
            if magic in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xfe\xed\xfa\xcf']:
                run(['codesign','--force','--sign',identity,p],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    # Sign Sparkle's nested services first, then its framework and the outer app.
    sf=frameworks/'Sparkle.framework/Versions/B'
    for rel in ['XPCServices/Downloader.xpc','XPCServices/Installer.xpc','Autoupdate','Updater.app']:
        p=sf/rel
        if p.exists():run(['codesign','--force','--options','runtime','--sign',identity,p])
    run(['codesign','--force','--options','runtime','--sign',identity,frameworks/'Sparkle.framework'])
    run(['codesign','--force','--deep','--options','runtime','--entitlements',ROOT/'packaging/browser-entitlements.plist','--sign',identity,browser])
    # Ad-hoc signatures have no Team ID, so hardened library validation cannot
    # match the embedded Sparkle framework. Keep this exception scoped to the
    # anonymous build; certificate-signed builds retain normal validation.
    app_entitlements=['--entitlements',ROOT/'packaging/launcher-adhoc-entitlements.plist'] if identity == '-' else []
    run(['codesign','--force','--options','runtime',*app_entitlements,'--sign',identity,APP])
    run(['codesign','--verify','--deep','--strict',APP])
    run([macos/'CapCutLauncher','--check'])
    run([resources/'Helper/launcher-helper','--check'])
    print('APP',APP)
    if args.dmg:
        dmg=OUTPUT/f'CapCut-Launcher-{VERSION}-macOS-arm64.dmg'
        run([sys.executable,ROOT/'packaging/create_dmg.py','--app',APP,'--output',dmg])
        print('DMG',dmg)

if __name__=='__main__':main()
