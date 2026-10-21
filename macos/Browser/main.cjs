'use strict';
const {app, BrowserWindow, Menu, session, dialog, nativeTheme} = require('electron');
const readline = require('node:readline');
const path = require('node:path');
let win, config, busy = false, delivered = false, timer;
const tr = (ru,en) => config?.language === 'en' ? en : ru;
const emit = (kind, data = {}) => process.stdout.write(JSON.stringify({kind, ...data})+'\n');
const input = readline.createInterface({input:process.stdin, crlfDelay:Infinity});
input.on('line', async line => {
  try {
    const data=JSON.parse(line);
    if(!config) {
      if(typeof data.stateRoot!=='string'||typeof data.state!=='string'||typeof data.nonce!=='string')throw 0;
      config=data;
      // Separate persistent browser state; Safari/Chrome profiles are never used.
      app.setPath('userData',path.join(config.stateRoot,'BrowserProfile'));
      await app.whenReady();await openWindow();
    } else if(data.command==='close') app.quit();
    else if(data.command==='retry') {busy=false;delivered=false;await transfer();}
  } catch (_) {emit('error',{message:tr('Ошибка запуска браузерного помощника.','The browser helper could not start.')});}
});
input.on('close',()=>app.quit());
function ready() {
  if(!win||win.isDestroyed())return false;
  try {const u=new URL(win.webContents.getURL());return u.origin==='https://www.capcut.com'&&(/^\/(my-edit|editor)(\/|$)/.test(u.pathname));}
  catch(_){return false;}
}
async function openWindow() {
  app.setName('CapCut Login');
  nativeTheme.themeSource = ['light','dark'].includes(config.theme) ? config.theme : 'system';
  const ses=session.defaultSession;
  ses.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
  ses.setPermissionCheckHandler(()=>false);
  ses.on('will-download',e=>e.preventDefault());
  win=new BrowserWindow({width:1080,height:820,minWidth:780,minHeight:620,title:tr('Вход в CapCut · capcut.com','Sign in to CapCut · capcut.com'),
    webPreferences:{nodeIntegration:false,contextIsolation:true,sandbox:true,webSecurity:true,session:ses}});
  const ua=win.webContents.getUserAgent().replace(/\sElectron\/[^ ]+/g,'').replace(/\scapcut-launcher-login\/[^ ]+/g,'');
  win.webContents.setUserAgent(ua);
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {label:'CapCut Login',submenu:[{label:tr('Передать вход в приложение','Transfer sign-in to the app'),click:()=>{busy=false;delivered=false;transfer();}},
      {type:'separator'},{label:tr('Закрыть окно входа','Close sign-in window'),role:'quit'}]},
    {label:tr('Правка','Edit'),submenu:[{role:'undo',label:tr('Отменить','Undo')},{role:'redo',label:tr('Повторить','Redo')},{type:'separator'},{role:'cut',label:tr('Вырезать','Cut')},{role:'copy',label:tr('Копировать','Copy')},{role:'paste',label:tr('Вставить','Paste')},{role:'selectAll',label:tr('Выделить всё','Select All')}]}
  ]));
  win.webContents.on('will-navigate',(event,url)=>{if(!url.startsWith('https://'))event.preventDefault();});
  win.webContents.setWindowOpenHandler(({url})=>{if(url.startsWith('https://'))win.loadURL(url);return {action:'deny'};});
  win.webContents.on('did-navigate',()=>transfer());
  win.webContents.on('did-navigate-in-page',()=>transfer());
  win.webContents.on('dom-ready',()=>transfer());
  win.on('closed',()=>{clearInterval(timer);app.quit();});
  await win.loadURL('https://www.capcut.com/login');
  emit('browser_ready');
  timer=setInterval(()=>transfer(),1000);
}
async function transfer() {
  if(busy||delivered||!ready())return;
  busy=true;emit('grant_requested');win.setTitle(tr('CapCut · Передаю вход в приложение…','CapCut · Transferring sign-in to the app…'));
  try {
    const state=JSON.stringify(config.state);
    const result=await win.webContents.executeJavaScript(`(async()=>{
      if(location.origin!=='https://www.capcut.com')throw new Error('origin');
      const csrf=document.cookie.match(/(?:^|;\\s*)passport_csrf_token=([^;]+)/)?.[1]
        ||document.cookie.match(/(?:^|;\\s*)passport_csrf_token_default=([^;]+)/)?.[1];
      if(!csrf)throw new Error('csrf');
      const response=await fetch('/passport/web/transfer/get_token/',{method:'POST',credentials:'include',
        headers:{'Content-Type':'application/x-www-form-urlencoded','x-tt-passport-csrf-token':decodeURIComponent(csrf)},
        body:new URLSearchParams({aid:'348188',state:${state}}).toString()});
      return await response.json();})()`,true);
    if(!ready())throw 0;
    const grant=result.data||result;
    if(!grant.domain&&result.domain)grant.domain=result.domain;
    if(typeof grant.token!=='string'||!grant.token.length)throw 0;
    if(grant.state&&grant.state!==config.state)throw 0;
    delivered=true;emit('grant',{nonce:config.nonce,grant});
    win.setTitle(tr('CapCut · Проверяю сеанс на сервере…','CapCut · Verifying session with the server…'));
  } catch (_) {
    emit('grant_error');
    const result=await dialog.showMessageBox(win,{type:'info',message:tr('Не удалось передать вход в приложение.','Could not transfer sign-in to the app.'),
      detail:tr('Повторите передачу после завершения входа на сайте CapCut.','Retry the transfer after completing sign-in on the CapCut website.'),buttons:[tr('Повторить','Retry'),tr('Закрыть','Close')],defaultId:0,cancelId:1});
    if(result.response===1){app.quit();return;}
    busy=false;
  }
}
app.on('window-all-closed',()=>app.quit());
