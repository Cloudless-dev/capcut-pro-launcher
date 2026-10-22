// Loaded only into the CapCut instance started by this launcher.
'use strict';
const cfg = globalThis.LAUNCH_CONFIG;
const target = cfg.region.toLowerCase();
if (!/^[a-z]{2}$/.test(target)) throw new Error('Invalid country code');
const tracked = new Map(), callbacks = new Set();
let sessionActive = !!cfg.session, profileSeen = false, regionReads = 0;
const emit = (kind, fields = {}) => send({kind, ...fields});
const safeDomain = h => /(^|\.)(capcutapi\.com|capcutapi\.us)$/.test(h);
// Device registration and TTNet can replace the startup region while CapCut is
// running. Apply the user's selection at the API boundary as well. Authentication
// and signed download URLs keep their original routing and signature material.
function regionURL(raw, country) {
  if (!/^[A-Z]{2}$/.test(country)) throw new Error('Invalid country code');
  const parsed = /^https:\/\/([a-z0-9.-]+)(?::443)?(\/[^?#]*)(\?[^#]*)?(#.*)?$/i.exec(raw);
  if (!parsed || !safeDomain(parsed[1].toLowerCase()) ||
      /^\/(?:passport|monitor_pc)(?:\/|$)/i.test(parsed[2])) return raw;
  const query = parsed[3] || '';
  if (/[?&](?:sign|signature|x-bogus|x-signature|x-amz-signature|x-goog-signature)=/i.test(query)) return raw;
  const changed = query.replace(/([?&](?:region|store_region|real_region)=)([a-z]{2})(?=&|$)/gi,
    (_, key) => key + country);
  return changed === query ? raw : raw.slice(0, raw.indexOf('?')) + changed + (parsed[4] || '');
}
function regionHeadersAllowed(raw) {
  const parsed = /^https:\/\/([a-z0-9.-]+)(?::443)?(\/[^?#]*)/i.exec(raw);
  return !!parsed && safeDomain(parsed[1].toLowerCase()) &&
    !/^\/(?:passport|monitor_pc)(?:\/|$)/i.test(parsed[2]) &&
    !/[?&](?:sign|signature|x-bogus|x-signature|x-amz-signature|x-goog-signature)=/i.test(raw.split('#')[0]);
}
const regionHeaderNames = new Set(['store-country-code', 'x-tt-store-region', 'x-tt-region']);
const cf = Process.getModuleByName('CoreFoundation');
const cfFn = (n, r, a) => new NativeFunction(cf.getExportByName(n), r, a);
const makeCF = cfFn('CFStringCreateWithCString','pointer',['pointer','pointer','uint']);
const getCString = cfFn('CFStringGetCString','bool',['pointer','pointer','long','uint']);
const getType = cfFn('CFGetTypeID','ulong',['pointer']);
const stringType = cfFn('CFStringGetTypeID','ulong',[]);
const dataType = cfFn('CFDataGetTypeID','ulong',[]);
const dataLength = cfFn('CFDataGetLength','long',['pointer']);
const dataBytes = cfFn('CFDataGetBytePtr','pointer',['pointer']);
const release = cfFn('CFRelease','void',['pointer']);
const retain = cfFn('CFRetain','pointer',['pointer']);
function cfString(p) {
  if (!p || p.isNull() || getType(p).toString() !== stringType().toString()) return '';
  const b = Memory.alloc(16384);
  return getCString(p,b,16384,0x08000100) ? b.readUtf8String() : '';
}
function createCF(s) { return makeCF(ptr(0),Memory.allocUtf8String(s),0x08000100); }
const regionCF = createCF(target);
const profileCF = cfg.profileBase64 ? createCF(cfg.profileBase64) : null;
const domainOK = d => /capcut|lemon|bytedance/i.test(d);
const regionKey = k => /(?:^|[./])store_region_of_(uid|did)$/i.test(k);
const accountKey = k => /(?:^|[./])Account[./]user_info$/i.test(k);
function cfValueText(p) {
  if (!p || p.isNull()) return '';
  if (getType(p).toString() === dataType().toString()) {
    const n = Number(dataLength(p));
    return n > 0 && n < 16384 ? dataBytes(p).readUtf8String(n) : '';
  }
  return cfString(p);
}
const prefGet = cf.getExportByName('CFPreferencesCopyValue');
const prefSet = cfFn('CFPreferencesSetValue','void',['pointer','pointer','pointer','pointer','pointer']);
const prefSync = cfFn('CFPreferencesSynchronize','bool',['pointer','pointer','pointer']);
Interceptor.attach(prefGet, {
  onEnter(a) { this.key = cfString(a[0]); this.domain = cfString(a[1]); this.args = [a[0],a[1],a[2],a[3]]; },
  onLeave(ret) {
    if (!domainOK(this.domain)) return;
    if (regionKey(this.key)) {
      if (!ret.isNull()) release(ret);
      ret.replace(retain(regionCF)); regionReads++;
      emit('region_preference',{key:this.key,domain:this.domain,region:target.toUpperCase()});
    } else if (accountKey(this.key)) {
      profileSeen = true;
      emit('account_preference',{key:this.key,domain:this.domain,present:!ret.isNull()});
      if (profileCF && sessionActive) {
        // The caller explicitly selected this authenticated account in the launcher.
        prefSet(this.args[0],profileCF,this.args[1],this.args[2],this.args[3]);
        prefSync(this.args[1],this.args[2],this.args[3]);
        if (!ret.isNull()) release(ret);
        ret.replace(retain(profileCF));
        emit('profile_restored');
      }
    } else if (cfg.probe && /account|region|user_info|basevalue/i.test(this.key)) {
      emit('preference_key',{key:this.key,domain:this.domain});
    }
  }
});
Interceptor.attach(cf.getExportByName('CFPreferencesSetValue'), {
  onEnter(a) {
    const key=cfString(a[0]),domain=cfString(a[2]);
    if (!domainOK(domain)) return;
    if (regionKey(key)) { a[1]=regionCF; emit('region_write',{region:target.toUpperCase()}); }
  }
});
emit('preferences_ready');
Process.attachModuleObserver({onAdded(module) {
  if (module.name !== 'libsscronet.dylib') return;
  const fn = (name,r,a) => new NativeFunction(module.getExportByName(name),r,a);
  const size = fn('Cronet_UrlRequestParams_request_headers_size','uint64',['pointer']);
  const at = fn('Cronet_UrlRequestParams_request_headers_at','pointer',['pointer','uint64']);
  const add = fn('Cronet_UrlRequestParams_request_headers_add','void',['pointer','pointer']);
  const clear = fn('Cronet_UrlRequestParams_request_headers_clear','void',['pointer']);
  const create = fn('Cronet_HttpHeader_Create','pointer',[]);
  const destroy = fn('Cronet_HttpHeader_Destroy','void',['pointer']);
  const nameGet = fn('Cronet_HttpHeader_name_get','pointer',['pointer']);
  const valueGet = fn('Cronet_HttpHeader_value_get','pointer',['pointer']);
  const nameSet = fn('Cronet_HttpHeader_name_set','void',['pointer','pointer']);
  const valueSet = fn('Cronet_HttpHeader_value_set','void',['pointer','pointer']);
  const bufferData = fn('Cronet_Buffer_GetData','pointer',['pointer']);
  function put(p,name,value) {
    if (!value) return;
    const encoded=Memory.allocUtf8String(value);
    for (let i=0,n=Number(size(p));i<n;i++) {
      const h=at(p,i);
      if (nameGet(h).readUtf8String().toLowerCase()===name) {valueSet(h,encoded);return;}
    }
    const h=create();
    try {nameSet(h,Memory.allocUtf8String(name));valueSet(h,encoded);add(p,h);} finally {destroy(h);}
  }
  Interceptor.attach(module.getExportByName('Cronet_UrlRequest_InitWithParams'),{
    onEnter(a) {
      try {
        let url=a[2].readUtf8String();
        const m=/^https:\/\/([a-z0-9.-]+)(?::443)?\//i.exec(url);
        if (!m || !safeDomain(m[1].toLowerCase())) return;
        if (/\/passport\/(?:web\/)?logout(?:[/?]|$)/.test(url)) {
          sessionActive=false;emit('session_logout');return;
        }
        const changed=regionURL(url,target.toUpperCase());
        if(changed!==url) {
          this.url=Memory.allocUtf8String(changed);a[2]=this.url;url=changed;
          emit('request_region_updated',{region:target.toUpperCase(),source:'query'});
        }
        if(regionHeadersAllowed(url)) {
          for(let i=0,n=Number(size(a[3]));i<n;i++) {
            const h=at(a[3],i),name=nameGet(h).readUtf8String().toLowerCase();
            if(!regionHeaderNames.has(name))continue;
            const value=valueGet(h).readUtf8String();
            if(!/^[a-z]{2}$/i.test(value)||value.toUpperCase()===target.toUpperCase())continue;
            valueSet(h,Memory.allocUtf8String(target));
            emit('request_region_updated',{region:target.toUpperCase(),source:'header'});
          }
        }
        const catalog=/\/artist\/v1\/|\/lv\/v1\/commerce\/get_entrances(?:[?]|$)/.test(url);
        if (catalog) {
          const r=/(?:[?&])(?:region|store_region)=([^&]*)/i.exec(url);
          emit('catalog_request',{region:r?decodeURIComponent(r[1]):null,path:url.split('?')[0].replace(/^https:\/\/[^/]+/,'')});
        }
        let kind='';
        if (/\/passport\/account\/info\/v2\//.test(url)) {
          kind='account';
          if (cfg.session && sessionActive) {
            this.url=Memory.allocUtf8String('https://'+cfg.session.sourceHost+'/passport/account/info/v2/?aid=359289&device_platform=macos');
            a[2]=this.url;clear(a[3]);put(a[3],'sdk-version','2');put(a[3],'user-agent',cfg.userAgent);
          }
        } else if (/\/lv\/v1\/commerce\/get_entrances(?:[?]|$)/.test(url)) kind='entrances';
        if (cfg.session && sessionActive) {
          put(a[3],'cookie',cfg.session.cookieHeader);put(a[3],'x-tt-token',cfg.session.xToken);
          put(a[3],'x-tt-passport-csrf-token',cfg.session.csrfToken);
        }
        if (kind) tracked.set(a[0].toString(),{kind,chunks:[],length:0});
      } catch (_) {emit('hook_error',{stage:'request'});}
    }
  });
  function attachOnce(p,handler) {
    if(p.isNull()||callbacks.has(p.toString()))return;
    callbacks.add(p.toString());Interceptor.attach(p,handler);
  }
  Interceptor.attach(module.getExportByName('Cronet_UrlRequestCallback_CreateWith'),{onEnter(a) {
    attachOnce(a[2],{onEnter(b) {
      const r=tracked.get(b[1].toString());if(!r)return;
      try {
        const n=b[4].toInt32();if(n<=0||n>200000||r.length+n>500000)return;
        const data=bufferData(b[3]);let text=data.readUtf8String(n);
        if(r.kind==='entrances' && cfg.showProUI) {
          const changed=text.replace(/("vip_entrance"\s*:\s*\{)([^}]*)(\})/,
            (_,h,inside,t)=>h+inside.replace(/("(?:enable|svip_enable)"\s*:\s*)false/g,'$1true ')+t);
          if(changed!==text) {
            const bytes=unescape(encodeURIComponent(changed));
            if(bytes.length===n) {data.writeByteArray(Array.from(bytes,c=>c.charCodeAt(0)));emit('catalog_ui_enabled');}
          }
        }
        r.chunks.push(Array.from(new Uint8Array(data.readByteArray(n))));r.length+=n;
      } catch(_){emit('hook_error',{stage:'response'});}
    }});
    for(let i=3;i<=5;i++)attachOnce(a[i],{onEnter(b) {
      const key=b[1].toString(),r=tracked.get(key);tracked.delete(key);
      if(!r||r.kind!=='account')return;
      try {
        const bytes=r.chunks.flat();const text=decodeURIComponent(bytes.map(b=>'%'+b.toString(16).padStart(2,'0')).join(''));
        const result=JSON.parse(text);const ok=result.message==='success'||String(result.ret)==='0';
        const errorCode=result.data?.error_code ?? result.error_code ?? result.ret ?? result.code;
        emit('account_verified',{success:ok,expired:!ok && String(errorCode)==='13'});
        if(!ok)sessionActive=false;
      } catch(_){emit('account_check_failed');}
    }});
  }});
  emit('cronet_ready');
}});
rpc.exports={status(){return {profileSeen,regionReads,sessionActive};}};
emit('agent_ready',{arch:Process.arch,region:target.toUpperCase()});
