"""Build the drag-to-install window without controlling Finder or user settings."""
import argparse
import ctypes
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import dmgbuild
from ds_store import DSStore
from mac_alias import Alias

ROOT = Path(__file__).resolve().parents[1]


class AttrList(ctypes.Structure):
    _fields_ = [('bitmapcount', ctypes.c_uint16), ('reserved', ctypes.c_uint16),
                ('commonattr', ctypes.c_uint32), ('volattr', ctypes.c_uint32),
                ('dirattr', ctypes.c_uint32), ('fileattr', ctypes.c_uint32), ('forkattr', ctypes.c_uint32)]


def auto_open_root(mount_point, _options):
    """Set only the HFS+ Finder auto-open folder, preserving all other volume data.

    ATTR_CMN_FNDRINFO + ATTR_VOL_INFO select the volume's 32-byte Finder info.
    Word 2 is the folder to open on mounting; this is not boot configuration.
    """
    mount = Path(mount_point)
    if mount.parent != Path('/Volumes') or not os.path.ismount(mount) or mount.stat().st_ino != 2:
        raise RuntimeError('Expected the temporary HFS+ installer volume')
    libc = ctypes.CDLL(None, use_errno=True)
    attrs = AttrList(5, 0, 0x4000, 0x80000000, 0, 0, 0)
    result = ctypes.create_string_buffer(36)
    libc.getattrlist.argtypes = [ctypes.c_char_p, ctypes.POINTER(AttrList), ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong]
    libc.setattrlist.argtypes = libc.getattrlist.argtypes
    path = os.fsencode(mount)
    if libc.getattrlist(path, ctypes.byref(attrs), result, len(result), 0):
        raise OSError(ctypes.get_errno(), 'Cannot read installer Finder info')
    info = bytearray(result.raw[4:36])
    struct.pack_into('>I', info, 8, 2)
    data = ctypes.create_string_buffer(bytes(info))
    if libc.setattrlist(path, ctypes.byref(attrs), data, 32, 0):
        raise OSError(ctypes.get_errno(), 'Cannot set installer auto-open folder')
    if libc.getattrlist(path, ctypes.byref(attrs), result, len(result), 0) or struct.unpack_from('>I', result.raw, 12)[0] != 2:
        raise RuntimeError('Installer auto-open flag was not saved')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    info = plistlib.loads((args.app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'app.capcutlauncher.macos':
        raise ValueError('Expected CapCut Launcher.app')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
    backgrounds = list((args.app/'Contents/Resources/Installer').glob('background-*.tiff'))
    if len(backgrounds) != 1:
        raise ValueError('Rebuild the app to include installer artwork')
    backdrop = backgrounds[0].relative_to(args.app)
    guide = args.app/'Contents/Resources/Installer/Installation.pdf'
    if not guide.is_file():
        raise ValueError('Rebuild the app to include the installation guide')
    mounted = None
    def configure_volume(mount_point, options):
        nonlocal mounted
        mounted = Path(mount_point)
        auto_open_root(mount_point, options)
    def finish_layout(event):
        if event.get('type') == 'operation::finished' and event.get('operation') == 'dsstore::create':
            with DSStore.open(str(mounted/'.DS_Store'), 'r+') as store:
                view = store['.']['icvp']
                view['backgroundType'] = 2
                view['backgroundImageAlias'] = Alias.for_file(str(mounted/args.app.name/backdrop)).to_bytes()
                store['.']['icvp'] = view
            # Verify the copied app after all Finder metadata has been applied.
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mounted/args.app.name)], check=True)
    settings = {
        'format':'UDZO', 'filesystem':'HFS+', 'compression_level':9,
        'files':[str(args.app.resolve()), str(guide.resolve())], 'symlinks':{'Applications':'/Applications'},
        'background':None,
        'window_rect':((180,160),(760,322)), 'default_view':'icon-view',
        'icon_locations':{args.app.name:(150,171), 'Applications':(400,171), 'Installation.pdf':(635,171)},
        'icon_size':96, 'text_size':12, 'grid_spacing':80,
        'show_status_bar':False, 'show_toolbar':False, 'show_pathbar':False,
        'show_sidebar':False, 'show_tab_view':False, 'show_icon_preview':False,
        # Do not set FinderInfo on the signed app to hide its extension:
        # modifying bundle metadata after signing breaks strict verification.
        'show_item_info':False,
        'create_hook':configure_volume,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Keep the previous distributable until a complete replacement is available.
    temporary = args.output.with_name(args.output.stem+'.building.dmg')
    if temporary.exists(): temporary.unlink()
    dmgbuild.build_dmg(str(temporary), 'CapCut Launcher '+info['CFBundleShortVersionString'], settings=settings, callback=finish_layout)
    subprocess.run(['hdiutil', 'verify', str(temporary)], check=True)
    temporary.replace(args.output)
    print('DMG', args.output)


if __name__ == '__main__':
    main()
