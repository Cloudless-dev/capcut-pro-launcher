// Executed only in the dedicated sign-in window on https://www.capcut.com.
// The password stays in CapCut's page; only a server-issued one-time grant leaves it.
(async () => {
  const nonce = __CAPCUT_NONCE__;
  const state = __CAPCUT_STATE__;
  const send = value => window.chrome.webview.postMessage(JSON.stringify({nonce, ...value}));
  try {
    if (location.origin !== 'https://www.capcut.com') throw new Error('wrong_origin');
    const csrf = document.cookie.match(/(?:^|;\s*)passport_csrf_token=([^;]+)/)?.[1]
      || document.cookie.match(/(?:^|;\s*)passport_csrf_token_default=([^;]+)/)?.[1];
    if (!csrf) { send({type:'error', code:'csrf_missing'}); return; }
    // Same endpoint, fields and CSRF header used by CapCut's public web module 46388.
    const response = await fetch('/passport/web/transfer/get_token/', {
      method:'POST', credentials:'include',
      headers:{'Content-Type':'application/x-www-form-urlencoded',
        'x-tt-passport-csrf-token':decodeURIComponent(csrf)},
      body:new URLSearchParams({aid:'348188', state}).toString()
    });
    const result = await response.json();
    send({type:'grant', httpStatus:response.status, result});
  } catch (_) { send({type:'error', code:'transfer_request_failed'}); }
})();
