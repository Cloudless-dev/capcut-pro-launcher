// Scoped guard for local region cache writes in CapCut. No subscription data touched.
(() => {
  const target = String(globalThis.CAPCUT_LOCAL_REGION || 'nl').toLowerCase();
  if (!/^[a-z]{2}$/.test(target)) throw new Error('Region must contain two ASCII letters');
  const seen = new Set();
  const emit = event => { if (!globalThis.CAPCUT_QUIET) send(event); };
  Process.attachModuleObserver({
    onAdded(module) {
      if (!/^(advapi32|kernelbase)\.dll$/i.test(module.name)) return;
      const address = module.findExportByName('RegSetValueExW');
      if (!address || seen.has(address.toString())) return;
      seen.add(address.toString());
      Interceptor.attach(address, {
        onEnter(args) {
          try {
            const name = args[1].readUtf16String();
            if (!/^store_region_of_(uid|did)$/.test(name)) return;
            const original = args[3].toInt32() === 1 && args[5].toInt32() <= 128
              ? args[4].readUtf16String() : '<non-string>';
            if (original === target) return;
            this.forcedRegion = Memory.allocUtf16String(target);
            args[3] = ptr(1); // REG_SZ
            args[4] = this.forcedRegion;
            args[5] = ptr(6); // two UTF-16 letters and terminating NUL
            this.changed = {name, original, enforced: target};
          } catch (error) {
            emit({kind:'region_guard_error',pid:Process.id,error:String(error)});
          }
        },
        onLeave(result) {
          if (this.changed) emit({kind:'region_guard_write',pid:Process.id,
            at:Date.now(),...this.changed,result:result.toInt32()});
        }
      });
      emit({kind:'region_guard_ready',pid:Process.id,module:module.name,region:target});
    }
  });
})();
