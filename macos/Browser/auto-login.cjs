'use strict';

// Runs only in the official site's main frame. No node/IPC bridge is exposed.
function loginStep(credentials, stage) {
  if (location.origin !== 'https://www.capcut.com') return {action:'interaction'};
  const visible = e => e && e.getBoundingClientRect().height > 0 && !e.disabled;
  const setValue = (e,value) => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,value);
    e.dispatchEvent(new Event('input',{bubbles:true}));
    e.dispatchEvent(new Event('change',{bubbles:true}));
  };
  const email = Array.from(document.querySelectorAll('input[type=email][name=username]')).find(visible);
  const password = Array.from(document.querySelectorAll('input[type=password]')).find(visible);
  const primary = Array.from(document.querySelectorAll('button.lv_sign_in_panel_wide-primary-button')).find(visible);
  const errors = Array.from(document.querySelectorAll('[role=alert], [class*=error]')).filter(visible);
  if(errors.some(e => /incorrect|invalid|wrong|too many|неверн|слишком много/i.test(e.textContent))) return {action:'error'};
  if(Array.from(document.querySelectorAll('input[autocomplete=one-time-code], iframe[title*=captcha i]')).some(visible))return {action:'interaction'};
  if(stage==='password_submitted')return {action:'waiting'};
  if(password) {
    // Never submit registration, password-reset or third-party login forms.
    if(password.name!=='password'||password.autocomplete!=='current-password')return {action:'interaction'};
    if(!credentials || !credentials.password)return {action:'interaction'};
    if(stage!=='password_filled') {
      if(email)setValue(email,credentials.email);
      setValue(password,credentials.password);return {action:'password_filled'};
    }
    const submit = Array.from(document.querySelectorAll('button.lv_sign_in_panel_wide-sign-in-button')).find(visible);
    if(submit) {submit.click();return {action:'password_submitted'};}
    return {action:'waiting'};
  }
  if (email && stage !== 'email_submitted') {
    if (stage !== 'email_filled') { setValue(email,credentials.email); return {action:'email_filled'}; }
    if (visible(primary)) { primary.click(); return {action:'email_submitted'}; }
    return {action:'waiting'};
  }
  // The server-rendered entry can appear before its click handler is attached.
  // Retry opening the method while that same entry is still on screen.
  if (stage === 'initial' || stage === 'email_selected') {
    const entry = Array.from(document.querySelectorAll('*')).find(e => e.children.length === 0 && e.textContent.trim() === 'Continue with email' && visible(e));
    if (entry) { entry.click(); return {action:'email_selected'}; }
  }
  return {action:'waiting'};
}

module.exports = {loginStep};
