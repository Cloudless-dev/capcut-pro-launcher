"""Private stdio protocol. Never accepts credentials via command-line arguments."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error


def emit(kind, **fields):
    print(json.dumps({'kind': kind, **fields}, ensure_ascii=False), flush=True)


class LaunchFailure(ValueError):
    def __init__(self, code, message):
        super().__init__(message); self.code=code


def validate_region(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z]{2}', value):
        raise ValueError('Введите двухбуквенный код страны, например US, TR или NL.')
    return value.upper()


def validate_app(path):
    app = Path(path).expanduser().resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.lemon.lvoverseas':
        raise ValueError('Выберите официальное приложение CapCut.app.')
    exe = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if not exe.is_file():
        raise ValueError('Исполняемый файл CapCut не найден.')
    result = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--ignore-resources', str(app)], capture_output=True)
    if result.returncode:
        raise ValueError('Подпись CapCut не прошла проверку. Установите официальную сборку.')
    details = subprocess.run(['/usr/bin/codesign','-dv','--verbose=2',str(app)],capture_output=True,text=True)
    if 'TeamIdentifier=22MMUN2RN5' not in details.stderr:
        raise ValueError('Издатель CapCut не совпадает с официальным ByteDance.')
    return app, exe, info


def running_capcut():
    result = subprocess.run(['/bin/ps','-axo','pid=,comm='],capture_output=True,text=True,check=True)
    return [int(line.strip().split(None,1)[0]) for line in result.stdout.splitlines()
            if line.rstrip().endswith('/Contents/MacOS/CapCut')]


def prepare_region(root, region, backup_root):
    """Validate both files before any writes; preserve an independent rollback copy."""
    root = Path(root).expanduser().resolve()
    paths = [root/'TTNet/tt_net_config.config',root/'Config/DeviceRegister']
    original = [p.read_bytes() for p in paths]
    native,n = re.subn(rb'(?<![A-Za-z_])store_region&#\*[^@]*@\$\*',
                      b'store_region&#*'+region.lower().encode()+b'@$*',original[0])
    device,m = re.subn(rb'(?m)^(real_region=)[A-Za-z]{2}',
                       lambda x:x.group(1)+region.encode(),original[1])
    if n != 1 or m != 1:
        raise ValueError('Формат региональных файлов этой версии CapCut не распознан. Изменения не внесены.')
    folder = Path(backup_root) / (time.strftime('%Y%m%d-%H%M%S')+'-'+secrets.token_hex(3))
    folder.mkdir(parents=True, mode=0o700)
    for p,data in zip(paths,original):
        dest=folder/p.name;dest.write_bytes(data);dest.chmod(0o600)
    (folder/'source.json').write_text(json.dumps({'dataRoot':str(root),'region':region}))
    try:
        for p,data in zip(paths,[native,device]):
            with p.open('wb') as f:f.write(data)
    except Exception:
        for p,data in zip(paths,original):p.write_bytes(data)
        raise
    return paths, original, folder


def backup_native_regions(folder):
    prefs = Path.home()/'Library/Preferences/com.capcut.CapCut.plist'
    values = {}
    try:
        data = plistlib.loads(prefs.read_bytes())
        for name in ('Common.basevalue.store_region_of_uid', 'Common.basevalue.store_region_of_did'):
            values[name] = data.get(name)
    except FileNotFoundError:
        return {}
    dest = folder/'native-regions.json'
    dest.write_text(json.dumps(values)); dest.chmod(0o600)
    return values


def restore_native_regions(values):
    for name, value in values.items():
        command = ['/usr/bin/defaults', 'write', 'com.capcut.CapCut', name, '-string', value] if isinstance(value, str) else ['/usr/bin/defaults', 'delete', 'com.capcut.CapCut', name]
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def account_display_label(user):
    label=next((user[k].strip() for k in ('email','email_address','name','nick_name','nickname','screen_name')
                if isinstance(user.get(k),str) and user[k].strip()),'')
    if not label:label='user'+str(user.get('user_id_str') or user.get('user_id') or user.get('uid') or '')
    if '@' in label:
        local,domain=label.split('@',1)
        if '*' not in local:label=local[:2]+'***@'+domain
    return label[:120]


def checked_session(session, user_agent, identity=None):
    if not session:
        return None
    allowed={'passport-api-sg.capcutapi.com','passport16-normal-us-ttp.capcutapi.us'}
    if session.get('sourceHost') not in allowed:
        raise ValueError('Неподдерживаемый домен сохранённого сеанса.')
    for name in ['cookieHeader','xToken','csrfToken','sourceHost']:
        value=session.get(name,'')
        if not isinstance(value,str) or '\r' in value or '\n' in value:
            raise ValueError('Неверный формат сеанса.')
    req=urllib.request.Request('https://'+session['sourceHost']+'/passport/account/info/v2/?aid=359289&device_platform=macos',
        headers={'Cookie':session['cookieHeader'],'x-tt-token':session['xToken'],'sdk-version':'2','User-Agent':user_agent})
    # Never forward session headers across an HTTP redirect.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args,**kwargs):return None
    try:
        with urllib.request.build_opener(NoRedirect).open(req,timeout=20) as response:reply=json.load(response)
    except urllib.error.HTTPError as error:
        try:reply=json.loads(error.read(100000))
        except Exception:raise LaunchFailure('network_error','Сервер CapCut временно недоступен. Повторите проверку позже.') from None
    except Exception:
        raise LaunchFailure('network_error','Не удалось проверить вход. Проверьте соединение и повторите.') from None
    user=reply.get('data') or {}
    if (reply.get('message')!='success' and str(reply.get('ret'))!='0') or not (user.get('user_id_str') or user.get('user_id') or user.get('uid')):
        details=reply.get('data') or {}
        code=details.get('error_code',reply.get('error_code',reply.get('ret',reply.get('code'))))
        if str(code)=='13':raise LaunchFailure('session_expired','Сессия истекла. Войдите в профиль заново.')
        raise LaunchFailure('auth_rejected','Сервер не принял сохранённый вход. Выполните повторную авторизацию.')
    def field(*keys):return next((str(user[k]) for k in keys if user.get(k) is not None and user[k] != ''),'')
    uid=field('user_id_str','user_id','uid')
    if session.get('uid') and str(session['uid'])!=uid:raise ValueError('Сохранённый сеанс относится к другому аккаунту.')
    if identity is not None:identity['displayName']=account_display_label(user)
    profile={'uid':uid,'xToken':session['xToken'],'csrfToken':session.get('csrfToken',''),
        'avatar_url':field('avatar_url','avatar'),'nick_name':field('name','nick_name','nickname'),
        'screen_name':field('screen_name','name'),'description':field('description'),
        'gender':user.get('gender',0),'is_looki_uid':user.get('is_looki_uid') is True,
        'sec_user_id':field('sec_user_id'),'third_platform':field('third_platform')}
    return base64.b64encode(json.dumps(profile,ensure_ascii=False,separators=(',',':')).encode()).decode()


def start(config):
    import frida
    region=validate_region(config['region'])
    if running_capcut():raise ValueError('Полностью закройте CapCut перед запуском через лаунчер.')
    app,exe,info=validate_app(config['appPath'])
    resources=Path(config['resources']).resolve()
    state=Path(config['stateRoot']).expanduser().resolve();state.mkdir(parents=True,exist_ok=True,mode=0o700)
    user_agent='CapCut/'+info['CFBundleShortVersionString']+' (macOS)'
    if config.get('requireSession') and not config.get('session'):
        raise LaunchFailure('auth_missing','Сначала войдите в выбранный профиль через браузер.')
    profile=checked_session(config.get('session'),user_agent)
    native_auth=None
    if config.get('nativeSession'):
        identity={}
        checked_native_session(config['nativeSession'],user_agent,identity)
        native_auth={**config['nativeSession'],'sourceHost':identity['sourceHost']}
    emit('session_checked',present=profile is not None)
    paths=[]; original=[]; native_original={}; run=None; proc=None; session=None; target_pid=None
    manager=frida.get_device_manager(); address=''
    try:
        paths,original,backup=prepare_region(config['dataRoot'],region,state/'backups')
        native_original=backup_native_regions(backup)
        run=state/'runtime'/secrets.token_hex(12);run.mkdir(parents=True,mode=0o700)
        gadget=run/'LauncherBridge.dylib';shutil.copy2(resources/'LauncherBridge.dylib',gadget)
        token=secrets.token_hex(32)
        sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
        settings={'interaction':{'type':'listen','address':'127.0.0.1','port':port,'token':token,'on_load':'wait'}}
        gadget.with_suffix('.config').write_text(json.dumps(settings));gadget.with_suffix('.config').chmod(0o600)
        env={k:v for k,v in os.environ.items() if not k.startswith(('DYLD_','FRIDA_'))}
        env['DYLD_INSERT_LIBRARIES']=str(gadget)
        address=f'127.0.0.1:{port}'
        # Native CapCut stderr can contain account data; do not persist it.
        proc=subprocess.Popen(['/usr/bin/open','-W','-n','--env','DYLD_INSERT_LIBRARIES='+str(gadget),str(app)],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        device=None
        for _ in range(150):
            if proc.poll() is not None:raise ValueError('CapCut завершился до подключения помощника.')
            try:
                device=manager.add_remote_device(address,token=token)
                processes=device.enumerate_processes()
                if not processes:raise frida.ServerNotRunningError('not ready')
                target_pid=processes[0].pid;break
            except (frida.ServerNotRunningError,frida.TransportError):time.sleep(.1)
        else:raise ValueError('Не удалось загрузить помощник. Эта сборка CapCut может ограничивать запуск библиотек.')
        session=device.attach('Gadget')
        agent_config={'region':region,'session':config.get('session'),'profileBase64':profile,'nativeAuth':native_auth,
                      'userAgent':user_agent,'showProUI':config.get('showProUI',True),'probe':config.get('probe',False)}
        code='globalThis.LAUNCH_CONFIG='+json.dumps(agent_config)+';\n'+(resources/'agent.js').read_text()
        script=session.create_script(code);errors=[];ready=set()
        def message(item,data):
            if item.get('type')=='error':
                errors.append(item.get('description','Agent error'));emit('error',message='Ошибка подключения модуля запуска.')
            elif item.get('type')=='send':
                payload=item['payload'];kind=payload.get('kind','event');ready.add(kind)
                emit(kind,**{k:v for k,v in payload.items() if k!='kind'})
                if kind=='account_verified' and payload.get('accountMatches') is False:
                    emit('error',code='account_mismatch',message='Сохранённый сеанс относится к другому аккаунту.')
                    if target_pid:
                        try:os.kill(target_pid,signal.SIGTERM)
                        except ProcessLookupError:pass
        script.on('message',message);script.load()
        if errors or not {'preferences_ready','cronet_ready','agent_ready'}.issubset(ready):
            raise ValueError('Версия сетевой библиотеки CapCut не поддерживается.')
        device.resume(target_pid)
        emit('started',pid=target_pid,region=region,version=info['CFBundleShortVersionString'],backup=str(backup))
        while proc.poll() is None:time.sleep(.5)
        emit('stopped',code=proc.returncode)
    except BaseException:
        if target_pid:
            try:os.kill(target_pid,signal.SIGTERM)
            except ProcessLookupError:pass
        if proc and proc.poll() is None:
            proc.terminate()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill();proc.wait()
        for p,data in zip(paths,original):p.write_bytes(data)
        restore_native_regions(native_original)
        raise
    finally:
        if session:
            try:session.detach()
            except Exception:pass
        try:manager.remove_remote_device(address)
        except Exception:pass
        if run:shutil.rmtree(run,ignore_errors=True)


def checked_native_session(session, user_agent, identity=None):
    # Native Google/email/QR sign-ins already contain a CapCut token. No Google
    # credentials or cookies are imported, and tokens never leave official APIs.
    failures=[]
    for host in ('passport-api-sg.capcutapi.com','passport16-normal-us-ttp.capcutapi.us'):
        try:
            if identity is None:return checked_session({**session,'sourceHost':host},user_agent)
            profile=checked_session({**session,'sourceHost':host},user_agent,identity)
            identity['sourceHost']=host
            return profile
        except LaunchFailure as error:failures.append(error)
    if any(e.code=='network_error' for e in failures):
        raise LaunchFailure('network_error','Не удалось проверить вход. Проверьте соединение и повторите.')
    if all(e.code=='session_expired' for e in failures):
        raise LaunchFailure('session_expired','Сессия CapCut истекла. Войдите заново в приложении CapCut.')
    raise LaunchFailure('auth_rejected','Войдите в аккаунт в приложении CapCut.')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    if args.check:
        import frida
        emit('check_ok',frida=frida.__version__,arch=os.uname().machine);return
    try:
        raw=sys.stdin.readline(500000)
        if not raw.endswith('\n'):raise ValueError('Неверный запрос запуска.')
        config=json.loads(raw)
        if config.get('action') in ('verify','verify_native'):
            if not config.get('session'):raise LaunchFailure('auth_missing','В этом профиле ещё нет сохранённого входа.')
            identity={}
            if config.get('action')=='verify_native':checked_native_session(config['session'],config.get('userAgent','CapCut/9.6.0 (macOS)'),identity)
            else:checked_session(config['session'],config.get('userAgent','CapCut/9.6.0 (macOS)'))
            emit('session_valid',**identity);return
        start(config)
    except Exception as e:
        # Known errors have fixed messages; exception repr may contain request secrets.
        message=str(e) if isinstance(e,(ValueError,FileNotFoundError,PermissionError)) else 'Не удалось запустить CapCut. Проверьте настройки и повторите.'
        emit('error',message=message,code=getattr(e,'code','launch_error'));sys.exit(1)

if __name__=='__main__':main()
