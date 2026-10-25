// Normalize only percent-encoded Cyrillic in known JSON search fields.
(() => {
  function resourceSearchURL(raw) {
    const m=/^https:\/\/([a-z0-9.-]+)(?::443)?(\/[^?#]*)/i.exec(raw);
    return !!m && /(^|\.)(capcutapi\.com|capcutapi\.us)$/.test(m[1].toLowerCase()) &&
      /^(?:\/artist\/v1\/(?:effect|panel)\/|\/lv\/v1\/)/.test(m[2]) &&
      /(?:^|\/|_)search(?:\/|_|$)/i.test(m[2]) &&
      !/[?&](?:sign|signature|x-bogus|x-signature|x-amz-signature|x-goog-signature)=/i.test(raw.split('#')[0]);
  }
  function normalizeResourceSearchBody(body) {
    if(typeof body!=='string'||body.length>262144)return body;
    try{JSON.parse(body);}catch(_){return body;}
    return body.replace(/("(?:query|keyword|search_word|search_text|search_query|search_keyword)"\s*:\s*)("(?:\\.|[^"\\])*")/g,(_,prefix,literal)=>{
      try{
        const original=JSON.parse(literal);if(!/%[0-9a-f]{2}/i.test(original))return prefix+literal;
        const decoded=decodeURIComponent(original);return /[\u0400-\u052f]/.test(decoded)?prefix+JSON.stringify(decoded):prefix+literal;
      }catch(_){return prefix+literal;}
    });
  }
  if(typeof Process==='undefined'){module.exports={resourceSearchURL,normalizeResourceSearchBody};return;}
  const notify=kind=>send({kind});
  Process.attachModuleObserver({onAdded(module){
    if(!/^sscronet\.dll$/i.test(module.name))return;
    try{
      const names=['Cronet_UrlRequestParams_upload_data_provider_get','Cronet_UploadDataProvider_Read','Cronet_UploadDataProvider_CreateWith','Cronet_UploadDataSink_OnReadSucceeded','Cronet_UploadDataProvider_Close','Cronet_Buffer_GetData','Cronet_UrlRequest_InitWithParams'];
      const addresses=names.map(n=>module.findExportByName(n));if(addresses.some(a=>a===null)){notify('search_unavailable');return;}
      const providerGet=new NativeFunction(addresses[0],'pointer',['pointer']);
      const bufferData=new NativeFunction(addresses[5],'pointer',['pointer']);
      const providers=new Set(),sinks=new Map(),readHooks=new Set();
      function attachRead(address){
        if(address.isNull()||readHooks.has(address.toString()))return;
        readHooks.add(address.toString());Interceptor.attach(address,{onEnter(a){if(providers.has(a[0].toString()))sinks.set(a[1].toString(),a[2]);}});
      }
      attachRead(addresses[1]);
      Interceptor.attach(addresses[2],{onEnter(a){attachRead(a[1]);}});
      Interceptor.attach(addresses[4],{onEnter(a){providers.delete(a[0].toString());}});
      Interceptor.attach(addresses[6],{onEnter(a){try{if(resourceSearchURL(a[2].readUtf8String())){const p=providerGet(a[3]);if(!p.isNull())providers.add(p.toString());}}catch(_){}}});
      Interceptor.attach(addresses[3],{onEnter(a){
        const key=a[0].toString(),buffer=sinks.get(key);sinks.delete(key);if(!buffer)return;
        try{
          const n=a[1].toUInt32();if(!n||n>262144)return;
          const data=bufferData(buffer),body=data.readUtf8String(n),changed=normalizeResourceSearchBody(body);if(changed===body)return;
          const bytes=Array.from(unescape(encodeURIComponent(changed)),c=>c.charCodeAt(0));if(bytes.length>n)return;
          while(bytes.length<n)bytes.push(32);data.writeByteArray(bytes);notify('search_query_normalized');
        }catch(_){notify('search_unavailable');}
      }});
      notify('search_ready');
    }catch(_){notify('search_unavailable');}
  }});
})();
