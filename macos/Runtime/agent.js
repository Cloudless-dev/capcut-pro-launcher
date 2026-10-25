// Loaded only into the CapCut instance started by this launcher.
'use strict';
const cfg = globalThis.LAUNCH_CONFIG;
const target = cfg.region.toLowerCase();
if (!/^[a-z]{2}$/.test(target)) throw new Error('Invalid country code');
const tracked = new Map(), callbacks = new Set();
let nativeAuthActive = !!cfg.nativeAuth;
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
// Some native resource panels percent-encode a search term inside JSON.
// The API expects a JSON string, so Cyrillic must be decoded once here, while
// URL parameters, signed downloads and all other request fields stay intact.
function resourceSearchURL(raw) {
  const m=/^https:\/\/([a-z0-9.-]+)(?::443)?(\/[^?#]*)/i.exec(raw);
  return !!m && safeDomain(m[1].toLowerCase()) &&
    /^(?:\/artist\/v1\/(?:effect|panel)\/|\/lv\/v1\/)/.test(m[2]) &&
    /(?:^|\/|_)search(?:\/|_|$)/i.test(m[2]) &&
    !/[?&](?:sign|signature|x-bogus|x-signature|x-amz-signature|x-goog-signature)=/i.test(raw.split('#')[0]);
}
function normalizeResourceSearchBody(body) {
  if (typeof body !== 'string' || body.length>262144) return body;
  try { JSON.parse(body); } catch (_) { return body; }
  // Replace only string literals at known search keys. Re-serializing the whole
  // JSON would round 64-bit IDs or alter unrelated escaping and formatting.
  return body.replace(/("(?:query|keyword|search_word|search_text|search_query|search_keyword)"\s*:\s*)("(?:\\.|[^"\\])*")/g,
    (_,prefix,literal)=>{
      try {
        const original=JSON.parse(literal);
        if(!/%[0-9a-f]{2}/i.test(original))return prefix+literal;
        const decoded=decodeURIComponent(original);
        return /[\u0400-\u052f]/.test(decoded) ? prefix+JSON.stringify(decoded) : prefix+literal;
      } catch (_) {return prefix+literal;}
    });
}
function nativeAccountURL(raw, host) {
  if (!['passport-api-sg.capcutapi.com','passport16-normal-us-ttp.capcutapi.us'].includes(host)) return raw;
  const m=/^https:\/\/([a-z0-9.-]+)(?::443)?(\/passport\/(?:account\/info|token\/beat)\/v2\/[^#]*)$/i.exec(raw);
  return m && safeDomain(m[1].toLowerCase()) ? 'https://'+host+m[2] : raw;
}
function accountIdentity(result) {
  const user=result.data||{},uid=user.user_id_str??user.user_id??user.uid;
  const success=(result.message==='success'||String(result.ret)==='0') && /^\d+$/.test(String(uid)) && String(uid)!=='0';
  const code=user.error_code??result.error_code??result.ret??result.code;
  let displayName='';
  if(success) {
    displayName=['email','email_address','name','nick_name','screen_name'].map(k=>user[k])
      .find(v=>typeof v==='string'&&v.trim()) || 'user'+uid;
    displayName=displayName.trim().slice(0,120);
    if(displayName.includes('@')) {
      const [local,...domain]=displayName.split('@');
      if(!local.includes('*'))displayName=local.slice(0,2)+'***@'+domain.join('@');
    }
  }
  return {success,expired:!success&&String(code)==='13',displayName};
}
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
const nativeProfileCF = cfg.nativeAuth && cfg.nativeAuth.profileBase64 ? createCF(cfg.nativeAuth.profileBase64) : null;
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
      if (nativeProfileCF && nativeAuthActive) {
        // Read the exact official-login snapshot selected at launch, rather than
        // an older preferences cache in the CapCut process. Do not persist it
        // here: CapCut owns its native account, login and logout writes.
        if (!ret.isNull()) release(ret);
        ret.replace(retain(nativeProfileCF));
        emit('native_profile_loaded');
      } else if (profileCF && sessionActive) {
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
  let trackSearchUpload=()=>{};
  const uploadNames=['Cronet_UrlRequestParams_upload_data_provider_get','Cronet_UploadDataProvider_Read',
    'Cronet_UploadDataProvider_CreateWith','Cronet_UploadDataSink_OnReadSucceeded','Cronet_UploadDataProvider_Close'];
  const uploadAddresses=uploadNames.map(n=>module.findExportByName(n));
  if(uploadAddresses.every(p=>p!==null)) {
    const providerGet=new NativeFunction(uploadAddresses[0],'pointer',['pointer']);
    const providers=new Map(),sinks=new Map(),readHooks=new Set();
    function readUpload(a) {
      const entry=providers.get(a[0].toString());
      if(entry)sinks.set(a[1].toString(),{...entry,buffer:a[2]});
    }
    function attachRead(address) {
      if(address.isNull()||readHooks.has(address.toString()))return;
      readHooks.add(address.toString());Interceptor.attach(address,{onEnter:readUpload});
    }
    attachRead(uploadAddresses[1]);
    Interceptor.attach(uploadAddresses[2],{onEnter(a){attachRead(a[1]);}});
    Interceptor.attach(uploadAddresses[4],{onEnter(a){providers.delete(a[0].toString());}});
    Interceptor.attach(uploadAddresses[3],{onEnter(a){
      const key=a[0].toString(),entry=sinks.get(key);sinks.delete(key);
      if(!entry)return;
      try {
        const n=a[1].toUInt32();if(!n||n>262144)return;
        const data=bufferData(entry.buffer),body=data.readUtf8String(n);
        const changed=normalizeResourceSearchBody(body);if(changed===body)return;
        const bytes=Array.from(unescape(encodeURIComponent(changed)),c=>c.charCodeAt(0));
        if(bytes.length>n)return;
        // Keep the declared upload size and callback length. JSON permits
        // trailing whitespace; no buffer growth or native ownership changes.
        while(bytes.length<n)bytes.push(32);
        data.writeByteArray(bytes);emit('search_query_normalized',{path:entry.path});
      } catch (_) {emit('hook_error',{stage:'resource_search'});}
    }});
    trackSearchUpload=(params,url)=>{
      if(!resourceSearchURL(url))return;
      const provider=providerGet(params);
      if(!provider.isNull())providers.set(provider.toString(),{path:url.split('?')[0].replace(/^https:\/\/[^/]+/,'')});
    };
  }

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
        trackSearchUpload(a[3],url);
        if (/\/passport\/(?:web\/)?logout(?:[/?]|$)/.test(url)) {
          sessionActive=false;nativeAuthActive=false;emit('session_logout');return;
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
        const nativeCheck=cfg.nativeAuth ? nativeAccountURL(url,cfg.nativeAuth.sourceHost) : url;
        if (cfg.nativeAuth && nativeAuthActive && nativeCheck !== url) {
          const auth=cfg.nativeAuth;
          this.url=Memory.allocUtf8String(nativeCheck);
          a[2]=this.url;clear(a[3]);put(a[3],'sdk-version','2');put(a[3],'user-agent',cfg.userAgent);
          put(a[3],'x-tt-token',auth.xToken);put(a[3],'x-tt-passport-csrf-token',auth.csrfToken);
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
        const identity=accountIdentity(JSON.parse(text));
        if (cfg.nativeAuth && identity.success) {
          const user=JSON.parse(text).data||{};
          identity.accountMatches=String(user.user_id_str??user.user_id??user.uid)===String(cfg.nativeAuth.uid);
          if(!identity.accountMatches){identity.success=false;identity.expired=false;}
        }
        emit('account_verified',identity);
        if(!identity.success){sessionActive=false;nativeAuthActive=false;}
      } catch(_){emit('account_check_failed');}
    }});
  }});
  emit('cronet_ready');
}});
// Use CapCut's own category selector and resource lists. The bridge is optional:
// unsupported binaries keep their native font picker without blocking launch.
Process.attachModuleObserver({onAdded(module) {
  if(module.name!=='libVECreator.dylib'||!cfg.fonts)return;
  try {
    const addresses={};
    for(const key of ['gate','categories','copy','destroy','refresh','clear','property']) {
      const spec=cfg.fonts[key];
      if(!spec||!Number.isSafeInteger(spec.offset)||spec.offset<0||spec.offset>=module.size||
          !/^[0-9a-f]{32}$/.test(spec.prefix))throw Error('Unsupported font bridge');
      const address=module.base.add(spec.offset);
      const bytes=new Uint8Array(address.readByteArray(16));
      if(Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('')!==spec.prefix)throw Error('Font bridge changed');
      addresses[key]=address;
    }
    const allocateAt=Module.findGlobalExportByName('_Znwm'),releaseAt=Module.findGlobalExportByName('_ZdlPv');
    if(!allocateAt||!releaseAt)throw Error('Font allocator unavailable');
    const allocate=new NativeFunction(allocateAt,'pointer',['uint64']);
    const dispose=new NativeFunction(releaseAt,'void',['pointer']);
    const copy=new NativeFunction(addresses.copy,'void',['pointer','pointer']);
    const destroy=new NativeFunction(addresses.destroy,'void',['pointer']);
    const clearCategories=new NativeFunction(addresses.clear,'void',['pointer']);
    const views=new Map();
    const order=['Classic1','NEW','Retro-1','大热','russian','english'];
    const entrySize=144;
    function nativeString(at) {
      const tag=at.add(23).readU8(),length=tag&128?Number(at.add(8).readU64()):tag;
      if(length<0||length>400)throw Error('Invalid font category');
      return length?(tag&128?at.readPointer():at).readUtf8String(length):'';
    }
    function vector(at,size,maximum) {
      const begin=at.readPointer(),end=at.add(8).readPointer();
      const bytes=Number(end.sub(begin));
      if(bytes<0||bytes%size||bytes>size*maximum)throw Error('Invalid font vector');
      return {begin,bytes,count:bytes/size};
    }
    function hashBytes(hash,bytes) {
      for(const byte of bytes)hash=Math.imul(hash^byte,16777619)>>>0;
      return hash;
    }
    Interceptor.attach(addresses.categories,{onLeave(result) {
      try {
        if(result.isNull())return;
        const source=vector(result,entrySize,200);
        if(!source.count)return;
        const categories=new Map();
        for(let i=0;i<source.count;i++) {
          const item=source.begin.add(i*entrySize);
          const name=nativeString(item.add(8)),key=nativeString(item.add(32));
          if(!name||!key)throw Error('Font category layout changed');
          if(order.includes(key))categories.set(key,item);
        }
        if(!categories.has('russian')||!categories.has('english'))return;
        const selected=order.filter(key=>categories.has(key));
        const data=Memory.alloc(selected.length*entrySize),borrowed=Memory.alloc(24);
        let hash=2166136261;
        for(let i=0;i<selected.length;i++) {
          const item=categories.get(selected[i]);
          const bytes=item.readByteArray(entrySize);
          data.add(i*entrySize).writeByteArray(bytes);
          hash=hashBytes(hash,new Uint8Array(bytes));
          const fonts=vector(item.add(120),16,20000);
          if(fonts.bytes)hash=hashBytes(hash,new Uint8Array(fonts.begin.readByteArray(fonts.bytes)));
        }
        const end=data.add(selected.length*entrySize);
        borrowed.writePointer(data);borrowed.add(8).writePointer(end);borrowed.add(16).writePointer(end);
        const id=result.toString(),previous=views.get(id);
        if(previous&&previous.hash===hash) {result.replace(previous.header);return;}
        // Deep-copy using the installed binary's own C++ constructors: category
        // strings and resource shared_ptrs retain their normal ownership.
        const header=allocate(24);copy(header,borrowed);
        if(previous) {
          const old=previous.header.readByteArray(24);
          previous.header.writeByteArray(header.readByteArray(24));header.writeByteArray(old);
          destroy(header);dispose(header);previous.hash=hash;result.replace(previous.header);
        }else {
          // Native callers can retain a reference to this vector. Its header
          // lives in the editor's heap until process exit, including on detach.
          views.set(id,{header,hash});result.replace(header);
        }
        emit('font_categories_filtered',{count:selected.length+1});
      }catch(_) {emit('font_categories_unavailable');}
    }});
    // The first popup can precede the asynchronous font response. CapCut then
    // caches just "All" and skips rebuilding it, even after resources arrive.
    // Clear that incomplete owning QList before its normal refresh; the native
    // function rebuilds it and emits its usual notification on the UI thread.
    Interceptor.attach(addresses.refresh,{onEnter(args){
      try {
        const model=args[0];
        if(model.add(0x208).readU8()===1 && model.add(0x328).readS64().toNumber()===1)
          clearCategories(model.add(0x318));
      }catch(_) {emit('font_categories_unavailable');}
    }});
    Interceptor.attach(addresses.gate,{onLeave(result){result.replace(1);}});
    emit('font_categories_ready');
  }catch(_) {emit('font_categories_unavailable');}
}});
rpc.exports={status(){return {profileSeen,regionReads,sessionActive};}};
emit('agent_ready',{arch:Process.arch,region:target.toUpperCase()});
