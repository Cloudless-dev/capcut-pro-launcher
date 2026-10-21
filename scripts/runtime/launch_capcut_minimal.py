"""Region + Pro UI only. No diagnostic collection or backup files."""
import argparse
import json
import re
from pathlib import Path
import sys
import time

from capcut_region_settings import APP, WORK, prepare_region
from capcut_auth_session import auth_source, restore_account

sys.path.insert(0, str(WORK / 'local/runtime-dependencies'))
import frida


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region', required=True, type=str.lower)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch('[a-z]{2}', args.region):
        parser.error('Region must contain two ASCII letters, e.g. us or nl.')
    source_root = Path(__file__).resolve().parent
    source = ('globalThis.CAPCUT_LOCAL_REGION=' + json.dumps(args.region) + ';\n'
              'globalThis.CAPCUT_QUIET=true;\n'
              + (source_root / 'guard_capcut_region.js').read_text('utf-8') + '\n'
              + (source_root / 'show_capcut_pro_ui.js').read_text('utf-8'))
    source += '\n' + auth_source()
    if not APP.is_file():
        raise RuntimeError('CapCut executable is missing: ' + str(APP))
    if args.check_only:
        print('CHECK_OK region=' + args.region + ' frida=' + frida.__version__
              + ' diagnostics=off backups=off', flush=True)
        return
    device = frida.get_local_device()
    if any(p.name.lower() == 'capcut.exe' for p in device.enumerate_processes()):
        raise RuntimeError('Close CapCut before starting this profile.')
    restore_account()
    sessions = {}
    agents = {}
    startup_errors = []

    def message(item, data):
        if item.get('type') == 'error':
            startup_errors.append('Runtime hook could not be loaded.')
        # Native logout can be automatic after a failed account check.
        # JS disables forwarding; only Forget Saved Login erases the saved copy.

    def attach(pid):
        session = device.attach(pid)
        try:
            script = session.create_script(source)
            script.on('message', message)
            script.load()
        except Exception:
            session.detach()
            raise
        sessions[pid] = session
        agents[pid] = script

    prepare_region(args.region, backup=False)
    pid = device.spawn([str(APP)], cwd=str(APP.parent), stdio='pipe')
    try:
        attach(pid)
        if startup_errors:
            raise RuntimeError(startup_errors[0])
    except Exception:
        device.kill(pid)
        raise
    device.resume(pid)
    try:
        print('SPAWNED ' + str(pid), flush=True)
    except (BrokenPipeError, OSError):
        pass  # A slow startup may outlive the launcher's status pipe.
    # No further stdout/stderr after the launcher closes its memory-only pipes.
    try:
        while True:
            processes = [p for p in device.enumerate_processes()
                         if p.name.lower() == 'capcut.exe']
            if not any(p.pid == pid for p in processes):
                break
            for process in processes:
                if process.pid not in sessions:
                    try:
                        attach(process.pid)
                    except (frida.ProcessNotFoundError, frida.PermissionDeniedError,
                            frida.TransportError):
                        pass
            time.sleep(1)
    finally:
        for session in sessions.values():
            try:
                session.detach()
            except Exception:
                pass


if __name__ == '__main__':
    main()
