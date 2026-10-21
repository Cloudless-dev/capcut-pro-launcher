// Forward only this user's server-issued session to CapCut API requests.
// No response, entitlement or authentication-result changes.
(() => {
  const session = globalThis.CAPCUT_AUTH_SESSION;
  if (!session || !session.cookieHeader) return;
  const attached = new Set();
  let active = true;
  Process.attachModuleObserver({onAdded(module) {
    if (!/^sscronet\.dll$/i.test(module.name)) return;
    const find = name => module.findExportByName(name);
    const init = find('Cronet_UrlRequest_InitWithParams');
    if (!init || attached.has(init.toString())) return;
    const sizeAddress = find('Cronet_UrlRequestParams_request_headers_size');
    const atAddress = find('Cronet_UrlRequestParams_request_headers_at');
    const addAddress = find('Cronet_UrlRequestParams_request_headers_add');
    if (!sizeAddress || !atAddress || !addAddress) throw new Error('Unsupported Cronet header API');
    attached.add(init.toString());
    const size = new NativeFunction(sizeAddress,'uint64',['pointer']);
    const at = new NativeFunction(atAddress,'pointer',['pointer','uint64']);
    const add = new NativeFunction(addAddress,'void',['pointer','pointer']);
    const clear = new NativeFunction(find('Cronet_UrlRequestParams_request_headers_clear'),'void',['pointer']);
    const create = new NativeFunction(find('Cronet_HttpHeader_Create'),'pointer',[]);
    const destroy = new NativeFunction(find('Cronet_HttpHeader_Destroy'),'void',['pointer']);
    const nameGet = new NativeFunction(find('Cronet_HttpHeader_name_get'),'pointer',['pointer']);
    const nameSet = new NativeFunction(find('Cronet_HttpHeader_name_set'),'void',['pointer','pointer']);
    const valueSet = new NativeFunction(find('Cronet_HttpHeader_value_set'),'void',['pointer','pointer']);
    function put(params, name, value) {
      if (!value) return;
      const encoded = Memory.allocUtf8String(value);
      for (let i=0,n=Number(size(params));i<n;i++) {
        const header = at(params,i);
        if (nameGet(header).readUtf8String().toLowerCase()===name) { valueSet(header,encoded); return; }
      }
      const header = create();
      try { nameSet(header,Memory.allocUtf8String(name)); valueSet(header,encoded); add(params,header); }
      finally { destroy(header); }
    }
    Interceptor.attach(init,{onEnter(args) {
      const url = args[2].readUtf8String();
      const match = /^https:\/\/([a-z0-9.-]+)(?::443)?\//i.exec(url);
      if (!match) return;
      const host = match[1].toLowerCase();
      if (!(host.endsWith('.capcutapi.com') || host.endsWith('.capcutapi.us'))) return;
      if (/\/passport\/(?:web\/)?logout(?:[/?]|$)/.test(url)) {
        // This also happens on automatic invalidation. Do not erase the saved
        // browser session: a later launch must ask the server whether it is valid.
        active = false;
        send({kind:'auth_session_logout'});
        return;
      }
      if (!active) return;
      if (/\/passport\/account\/info\/v2\//.test(url)) {
        // Match the request which already validated this session on the server.
        this.authUrl = Memory.allocUtf8String('https://' + session.sourceHost
          + '/passport/account/info/v2/?aid=359289&device_platform=windows');
        args[2] = this.authUrl;
        clear(args[3]);
        put(args[3],'sdk-version','2');
        put(args[3],'user-agent','CapCut/9.6.0.4097 (Windows)');
        send({kind:'auth_session_request_applied',endpoint:'/passport/account/info/v2/',host:session.sourceHost});
      }
      put(args[3],'cookie',session.cookieHeader);
      put(args[3],'x-tt-token',session.xToken);
      put(args[3],'x-tt-passport-csrf-token',session.csrfToken);
    }});
  }});
})();
