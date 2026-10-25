"""Session tests use fixture registry values; never a user's CapCut account."""
import base64
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/runtime'))
if sys.platform != 'win32':
    sys.modules.setdefault('winreg', types.ModuleType('winreg'))
import capcut_native_account as native
import verify_capcut_session as verify


class FakeRegistry:
    HKEY_CURRENT_USER = 1
    REG_SZ = 1

    def __init__(self):
        self.value = None

    def OpenKey(self, *args):
        if self.value is None:
            raise FileNotFoundError
        return self

    def CreateKey(self, *args):
        return self

    def QueryValueEx(self, *args):
        return self.value, self.REG_SZ

    def SetValueEx(self, key, name, reserved, kind, value):
        self.value = value

    def DeleteValue(self, *args):
        if self.value is None:
            raise FileNotFoundError
        self.value = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass


class Sessions(unittest.TestCase):
    def test_native_launch_does_not_require_a_saved_login(self):
        import capcut_auth_session as auth
        with patch.dict(os.environ, CAPCUT_USE_NATIVE_ACCOUNT='1'), patch.object(verify, 'native_session') as validation, patch.object(auth, 'load_session') as saved:
            self.assertFalse(auth.restore_account())
            validation.assert_not_called()
            saved.assert_not_called()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.registry = FakeRegistry()
        for target in (patch.object(native, 'winreg', self.registry),
                       patch.dict(os.environ, LOCALAPPDATA=self.tmp.name,
                                  CAPCUT_ACCOUNT_JOURNAL_ROOT=self.tmp.name),
                       patch.object(native, 'protect', lambda value, **kwargs: value)):
            target.start()
            self.addCleanup(target.stop)
        self.journal = native.NativeAccountJournal()

    def test_restore_original_account_after_switch(self):
        self.registry.value = 'official account fixture'
        self.journal.begin()
        self.registry.value = 'managed slot fixture'
        self.assertEqual(self.journal.native_value(), 'official account fixture')
        self.journal.restore()
        self.assertEqual(self.registry.value, 'official account fixture')
        self.assertFalse(self.journal.path.exists())

    def test_restore_original_missing_value(self):
        self.journal.begin()
        self.registry.value = 'managed slot fixture'
        self.journal.restore()
        self.assertIsNone(self.registry.value)

    def test_existing_journal_cannot_be_overwritten(self):
        self.registry.value = 'original'
        self.journal.begin()
        with self.assertRaises(RuntimeError):
            self.journal.begin()
        self.assertEqual(self.journal.native_value(), 'original')

    def test_corrupt_journal_is_preserved(self):
        self.journal.path.write_bytes(b'{}')
        with self.assertRaises(RuntimeError):
            self.journal.restore()
        self.assertTrue(self.journal.path.exists())

    def test_registry_failure_retains_recovery_copy(self):
        self.registry.value = 'original'
        self.journal.begin()
        with patch.object(self.registry, 'SetValueEx', side_effect=OSError('fixture failure')):
            with self.assertRaises(OSError):
                self.journal.restore()
        self.assertTrue(self.journal.path.exists())

    def test_recover_interrupted_launch_in_another_helper(self):
        self.registry.value = 'original'
        self.journal.begin()
        self.registry.value = 'managed'
        native.NativeAccountJournal().restore()
        self.assertEqual(self.registry.value, 'original')

    @staticmethod
    def config(**kwargs):
        return dict(sourceHost=verify.HOSTS[0], xToken='fixture-token', cookieHeader='', uid='fixture-user', **kwargs)

    def test_reject_untrusted_domain_before_network(self):
        config = self.config()
        config['sourceHost'] = 'example.invalid'
        with patch.object(verify.urllib.request, 'build_opener') as opener:
            with self.assertRaises(ValueError):
                verify.checked(config)
            opener.assert_not_called()

    def test_reject_header_injection(self):
        config = self.config()
        config['xToken'] = 'fixture\r\ninvalid'
        with self.assertRaises(ValueError):
            verify.checked(config)

    def test_successful_validation_and_identity_match(self):
        response = io.BytesIO(json.dumps({'message': 'success', 'data': {'uid': 'fixture-user'}}).encode())
        with patch.object(verify.urllib.request, 'build_opener') as opener:
            opener.return_value.open.return_value = response
            self.assertEqual(verify.checked(self.config())['uid'], 'fixture-user')
            self.assertIs(opener.call_args.args[0], verify.NoRedirect)

    def test_different_account_rejected(self):
        response = io.BytesIO(json.dumps({'message': 'success', 'data': {'uid': 'other-user'}}).encode())
        with patch.object(verify.urllib.request, 'build_opener') as opener:
            opener.return_value.open.return_value = response
            with self.assertRaises(ValueError):
                verify.checked(self.config())

    def test_expired_session_rejected(self):
        response = io.BytesIO(b'{"message":"error","ret":13}')
        with patch.object(verify.urllib.request, 'build_opener') as opener:
            opener.return_value.open.return_value = response
            with self.assertRaisesRegex(ValueError, 'Session expired or rejected'):
                verify.checked(self.config())

    def test_network_failure_not_treated_as_expired(self):
        with patch.object(verify.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = OSError('fixture network failure')
            with self.assertRaisesRegex(RuntimeError, 'connection'):
                verify.checked(self.config())

    def test_redirects_never_receive_session_headers(self):
        self.assertIsNone(verify.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.invalid'))


class WindowsDPAPI(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'win32', 'requires Windows DPAPI')
    def test_actual_encryption_round_trip(self):
        raw = b'local fixture, no account information'
        encrypted = native.protect(raw)
        self.assertNotIn(raw, encrypted)
        self.assertEqual(native.protect(encrypted, decrypt=True), raw)


if __name__ == '__main__':
    unittest.main()
