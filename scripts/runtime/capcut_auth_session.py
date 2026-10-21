"""Load this user's CapCut session using Windows DPAPI; never print credentials."""
import ctypes
from ctypes import wintypes
import json
import os
import base64
from pathlib import Path
import urllib.request
import winreg

WORK = Path(__file__).resolve().parents[2]
STATE = Path(os.environ.get('CAPCUT_STATE_ROOT', str(WORK / 'local')))


def load_session():
    path = STATE / 'auth-browser-sdk/desktop-session.bin'
    if not path.exists():
        return None

    class Blob(ctypes.Structure):
        _fields_ = [('size', wintypes.DWORD), ('data', ctypes.POINTER(ctypes.c_ubyte))]

    raw = path.read_bytes()
    data = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
    source = Blob(len(raw), data)
    output = Blob()
    crypt = ctypes.WinDLL('crypt32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    crypt.CryptUnprotectData.argtypes = [ctypes.POINTER(Blob), ctypes.c_void_p,
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(Blob)]
    crypt.CryptUnprotectData.restype = wintypes.BOOL
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.LocalFree.restype = ctypes.c_void_p
    if not crypt.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)):
        raise RuntimeError('Saved CapCut session cannot be opened by this Windows user.')
    try:
        session = json.loads(ctypes.string_at(output.data, output.size).decode('utf-8'))
    finally:
        kernel.LocalFree(output.data)
    if session.get('version') != 1 or not isinstance(session.get('cookieHeader'), str):
        raise RuntimeError('Unsupported saved CapCut session format.')
    config = {name: session.get(name, '') for name in ('cookieHeader', 'xToken', 'csrfToken', 'sourceHost')}
    if any(not isinstance(value, str) or '\r' in value or '\n' in value for value in config.values()):
        raise RuntimeError('Invalid saved CapCut session fields.')
    if config['sourceHost'] not in ('passport-api-sg.capcutapi.com', 'passport16-normal-us-ttp.capcutapi.us'):
        raise RuntimeError('Unsupported saved CapCut session domain.')
    return config


def auth_source():
    config = load_session()
    if config is None:
        return ''
    return ('globalThis.CAPCUT_AUTH_SESSION=' + json.dumps(config) + ';\n'
            + (WORK / 'scripts/runtime/apply_capcut_session.js').read_text('utf-8'))


def restore_account():
    """Restore the local profile only after the saved session passes server validation."""
    session = load_session()
    if session is None:
        return False
    request = urllib.request.Request(
        'https://' + session['sourceHost'] + '/passport/account/info/v2/?aid=359289&device_platform=windows',
        headers={'Cookie': session['cookieHeader'], 'x-tt-token': session['xToken'],
                 'sdk-version': '2', 'User-Agent': 'CapCut/9.6.0.4097 (Windows)'})
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            result = json.load(response)
    except Exception:
        raise RuntimeError('Could not verify saved CapCut session. Check the connection and retry.') from None
    user = result.get('data') or {}
    if result.get('message') != 'success' and str(result.get('ret')) != '0':
        raise RuntimeError('Saved CapCut session is no longer accepted. Sign in with Email Login.cmd.')

    def field(*names):
        return next((str(user[name]) for name in names if user.get(name) is not None and user[name] != ''), '')

    uid = field('user_id_str', 'user_id', 'uid')
    if not uid or uid == '0':
        raise RuntimeError('CapCut server did not return a valid account identifier.')
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r'Software\Bytedance\CapCut\Account') as key:
        try:
            previous = json.loads(base64.b64decode(winreg.QueryValueEx(key, 'user_info')[0]))
        except (OSError, ValueError, TypeError):
            previous = {}
        previous_uid = str(previous.get('uid', '0'))
        if previous_uid not in ('', '0', uid):
            raise RuntimeError('Saved browser session belongs to another account. Use Email Login.cmd.')
        profile = {
            'uid': uid, 'xToken': session['xToken'], 'csrfToken': session['csrfToken'],
            'avatar_url': field('avatar_url', 'avatar'), 'nick_name': field('name', 'nick_name', 'nickname'),
            'screen_name': field('screen_name', 'name'), 'description': field('description'),
            'gender': user.get('gender') if isinstance(user.get('gender'), int) else 0,
            'is_looki_uid': user.get('is_looki_uid') is True,
            'sec_user_id': field('sec_user_id'), 'third_platform': field('third_platform')}
        encoded = base64.b64encode(json.dumps(profile, ensure_ascii=False, separators=(',', ':')).encode('utf-8')).decode('ascii')
        winreg.SetValueEx(key, 'user_info', 0, winreg.REG_SZ, encoded)
    return True
