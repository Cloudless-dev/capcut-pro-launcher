"""Validate a saved session; no registry writes and no credentials on stdout."""
import base64
import json
import os
import urllib.error
import urllib.request
from capcut_auth_session import load_session
from capcut_native_account import NativeAccountJournal

HOSTS = ('passport-api-sg.capcutapi.com', 'passport16-normal-us-ttp.capcutapi.us')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def checked(session):
    if not session:
        raise ValueError('Sign in to this profile first.')
    if session.get('sourceHost') not in HOSTS:
        raise ValueError('Unsupported saved session domain.')
    headers = {'Cookie': session.get('cookieHeader', ''), 'x-tt-token': session.get('xToken', ''),
               'sdk-version': '2', 'User-Agent': 'CapCut/9.6.0.4097 (Windows)'}
    if any(not isinstance(value, str) or '\r' in value or '\n' in value for value in headers.values()):
        raise ValueError('Invalid saved session fields.')
    if not headers['x-tt-token']:
        raise ValueError('Sign in to this profile first.')
    request = urllib.request.Request('https://' + session['sourceHost'] +
        '/passport/account/info/v2/?aid=359289&device_platform=windows', headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code >= 500 or 300 <= error.code < 400:
            raise RuntimeError('Could not verify the session. Check the connection and retry.') from None
        try:
            result = json.loads(error.read(100000))
        except (ValueError, OSError):
            raise RuntimeError('Could not verify the session. Check the connection and retry.') from None
    except Exception:
        raise RuntimeError('Could not verify the session. Check the connection and retry.') from None
    user = result.get('data') or {}
    uid = next((str(user[k]) for k in ('user_id_str', 'user_id', 'uid') if user.get(k)), '')
    if (result.get('message') != 'success' and str(result.get('ret')) != '0') or not uid or uid == '0':
        raise ValueError('Session expired or rejected. Sign in again.')
    if session.get('uid') and str(session['uid']) != uid:
        raise ValueError('Saved session belongs to a different account.')
    return user


def native_session():
    packed = NativeAccountJournal().native_value()
    if not packed:
        raise ValueError('Sign in using the official CapCut application first.')
    value = json.loads(base64.b64decode(packed))
    uid = str(value.get('uid', '0'))
    if uid == '0' or not value.get('xToken'):
        raise ValueError('Sign in using the official CapCut application first.')
    failures = []
    for host in HOSTS:
        config = dict(value, cookieHeader='', sourceHost=host)
        try:
            checked(config)
            return config
        except (ValueError, RuntimeError) as error:
            failures.append(error)
    raise failures[-1]


if __name__ == '__main__':
    try:
        config = native_session() if os.environ.get('CAPCUT_USE_NATIVE_ACCOUNT') == '1' else load_session()
        user = checked(config)
        # Keep all session tokens and account identifiers out of process output.
        print('Session accepted by CapCut.')
    except ValueError:
        print('Session expired or rejected. Sign in again.', file=__import__('sys').stderr)
        raise SystemExit(2) from None
    except RuntimeError:
        print('Could not verify the session. Check the connection and retry.', file=__import__('sys').stderr)
        raise SystemExit(3) from None
