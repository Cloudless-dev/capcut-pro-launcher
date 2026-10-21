// Only the Pro catalogue entrance. No request/response logging or licence hooks.
(() => {
  const requests = new Set();
  const hooked = new Set();
  function attach(address, handlers) {
    if (!address || address.isNull() || hooked.has(address.toString())) return;
    hooked.add(address.toString());
    Interceptor.attach(address, handlers);
  }
  function modify(buffer, count, bufferData) {
    if (count <= 0 || count > 100000) return;
    const data = bufferData(buffer);
    const body = data.readUtf8String(count);
    // Match the same two visibility fields as the existing diagnostic profile.
    const changed = body.replace(/("vip_entrance"\s*:\s*\{)([^}]*)(\})/,
      (_, head, inside, tail) => head + inside.replace(
        /("(?:enable|svip_enable)"\s*:\s*)false/g, '$1true ') + tail);
    if (changed === body) return;
    const bytes = unescape(encodeURIComponent(changed));
    if (bytes.length !== count) return;
    data.writeByteArray(Array.from(bytes, c => c.charCodeAt(0)));
  }
  Process.attachModuleObserver({
    onAdded(module) {
      if (!/^sscronet\.dll$/i.test(module.name)) return;
      const address = module.findExportByName('Cronet_Buffer_GetData');
      if (!address) return;
      const bufferData = new NativeFunction(address, 'pointer', ['pointer']);
      attach(module.findExportByName('Cronet_UrlRequest_InitWithParams'), {
        onEnter(args) {
          try {
            const url = args[2].readUtf8String();
            if (/^https:\/\/[^/]*capcut[^/]*\/lv\/v1\/commerce\/get_entrances(?:\?|$)/i.test(url)) {
              requests.add(args[0].toString());
            }
          } catch (_) {}
        }
      });
      attach(module.findExportByName('Cronet_UrlRequestCallback_CreateWith'), {
        onEnter(args) {
          attach(args[2], {
            onEnter(callbackArgs) {
              if (!requests.has(callbackArgs[1].toString())) return;
              try { modify(callbackArgs[3], callbackArgs[4].toInt32(), bufferData); }
              catch (_) {}
            }
          });
          // Release request identifiers on success, failure or cancellation.
          for (const index of [3, 4, 5]) {
            attach(args[index], {
              onEnter(callbackArgs) { requests.delete(callbackArgs[1].toString()); }
            });
          }
        }
      });
    }
  });
})();
