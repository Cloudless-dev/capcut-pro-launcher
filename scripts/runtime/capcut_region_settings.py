"""Prepare the three local region sources; optional private backup."""
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import winreg

WORK = Path(__file__).resolve().parents[2]
APP_ROOT = Path(os.environ['LOCALAPPDATA']) / 'CapCut'
APP = Path(os.environ.get('CAPCUT_APP_PATH', str(APP_ROOT / 'Apps/9.6.0.4097/CapCut.exe')))
if os.environ.get('CAPCUT_APP_PATH'):
    APP_ROOT = next((parent for parent in APP.parents if (parent / 'User Data').is_dir()), APP_ROOT)


def prepare_region(region, *, backup=True):
    if not re.fullmatch('[a-z]{2}', region):
        raise ValueError('Unsupported region')
    native = APP_ROOT / 'User Data/TTNet/tt_net_config.config'
    registration = APP_ROOT / 'User Data/Config/DeviceRegister'
    original_native = native.read_bytes()
    original_registration = registration.read_bytes()
    changed_native, count = re.subn(
        rb'(?<![A-Za-z_])store_region&#\*[^@]*@\$\*',
        b'store_region&#*' + region.encode('ascii') + b'@$*', original_native)
    changed_registration, device_count = re.subn(
        rb'(?m)^(real_region=)[A-Za-z]{2}',
        lambda match: match.group(1) + region.upper().encode('ascii'),
        original_registration)
    if count != 1 or device_count != 1:
        raise RuntimeError('Unexpected region-cache format; no changes applied.')
    registry = r'Software\Bytedance\CapCut\Common\basevalue'
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, registry, 0,
                        winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE) as key:
        names = ('store_region_of_uid', 'store_region_of_did')
        saved = {name: winreg.QueryValueEx(key, name) for name in names}
        folder = None
        if backup:
            folder = WORK / 'local/backups' / (
                'startup-guard-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
            folder.mkdir(parents=True)
            shutil.copy2(native, folder / 'tt_net_config.config')
            shutil.copy2(registration, folder / 'DeviceRegister')
            (folder / 'regions.json').write_text(json.dumps(
                {name: value[0] for name, value in saved.items()}, indent=2), encoding='utf-8')
            (folder / 'test-settings.json').write_text(json.dumps({
                'local_region': region, 'device_region': region.upper(),
                'server_account_region_modified': False}, indent=2), encoding='utf-8')
        try:
            native.write_bytes(changed_native)
            registration.write_bytes(changed_registration)
            for name in names:
                winreg.SetValueEx(key, name, 0, winreg.REG_SZ, region)
        except Exception:
            # In-memory rollback even when persistent backups are disabled.
            native.write_bytes(original_native)
            registration.write_bytes(original_registration)
            for name, (value, kind) in saved.items():
                winreg.SetValueEx(key, name, 0, kind, value)
            raise
    return folder
