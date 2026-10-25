"""Journal only CapCut's account value, encrypted for the current Windows user."""
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import winreg

KEY = r'Software\Bytedance\CapCut\Account'


def protect(data, *, decrypt=False):
    class Blob(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]
    raw = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
    source = Blob(len(data), raw)
    output = Blob()
    crypt = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if decrypt:
        ok = crypt.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output))
    else:
        ok = crypt.CryptProtectData(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output))
    if not ok:
        raise RuntimeError('Windows could not protect or restore the account journal.')
    try:
        return ctypes.string_at(output.data, output.size)
    finally:
        kernel.LocalFree(output.data)


class NativeAccountJournal:
    def __init__(self):
        root = Path(os.environ.get('CAPCUT_ACCOUNT_JOURNAL_ROOT',
                                  str(Path(os.environ['LOCALAPPDATA']) / 'CapCutLauncher')))
        self.path = root / 'native-account.bin'

    def saved(self):
        if not self.path.exists():
            return None
        value = json.loads(protect(self.path.read_bytes(), decrypt=True))
        if value.get('version') != 1 or not isinstance(value.get('present'), bool) or (value['present'] and not isinstance(value.get('value'), str)):
            raise RuntimeError('Unsupported native account journal. Saved data was retained.')
        return value

    def snapshot(self):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, KEY) as key:
                value, kind = winreg.QueryValueEx(key, 'user_info')
            if kind != winreg.REG_SZ or not isinstance(value, str):
                raise RuntimeError('Unsupported CapCut account format.')
            return {'version': 1, 'present': True, 'value': value}
        except FileNotFoundError:
            return {'version': 1, 'present': False}

    def begin(self):
        if self.path.exists():
            raise RuntimeError('Restore the previous native account journal before launching.')
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = protect(json.dumps(self.snapshot()).encode())
        with self.path.open('xb') as output:
            output.write(data)

    def restore(self):
        value = self.saved()
        if value is None:
            return
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, KEY) as key:
            if value['present']:
                winreg.SetValueEx(key, 'user_info', 0, winreg.REG_SZ, value['value'])
            else:
                try:
                    winreg.DeleteValue(key, 'user_info')
                except FileNotFoundError:
                    pass
        self.path.unlink()

    def native_value(self):
        snapshot = self.saved() or self.snapshot()
        return snapshot.get('value') if snapshot['present'] else None
