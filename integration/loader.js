/* VK-1 independent dash host: no upstream edits or credentials in storage. */
(function () {
  'use strict'
  if (window.VK1Dash) { window.VK1Dash.mount(); return }
  var current = document.currentScript
  var nonce = current && current.nonce
  var pending = null, generation = 0, script = null, previousCursor = ''
  window.__vk1DashConfig = Object.assign({ mirror: true }, window.__vk1DashConfig || {}, nonce ? { nonce: nonce } : {})
  function mount() {
    if (window.__dshVk1Widget) return Promise.resolve()
    if (pending) return pending
    if (!document.body) return new Promise(function (resolve,reject) { document.addEventListener('DOMContentLoaded',function(){mount().then(resolve,reject)},{once:true}) })
    previousCursor = document.body.style.cursor
    var token = ++generation
    pending = new Promise(function(resolve,reject){
      script = document.createElement('script')
      script.src = '/vk-1/widget.js?v=20261010-2'
      if (window.__vk1DashConfig.nonce) script.nonce = window.__vk1DashConfig.nonce
      script.onload = function(){ pending=null; if(token!==generation){stopWidget();resolve();return} if(window.__dshVk1Widget)resolve();else reject(new Error('VK-1 mount failed')) }
      script.onerror = function(){pending=null;reject(new Error('VK-1 load failed'))}
      document.head.appendChild(script)
    })
    return pending
  }
  function stopWidget(){
    var registry=window.__dshAppearanceWidgets
    var widget=registry&&registry['dsh-vk1-balance-widget']
    if(widget&&typeof widget.stop==='function')widget.stop()
    if(registry)delete registry['dsh-vk1-balance-widget']
    if(document.body)document.body.style.cursor=previousCursor
  }
  function unmount(){++generation;stopWidget();if(script){script.remove();script=null}pending=null;closeDialog()}
  function closeDialog(){var d=document.getElementById('vk1-connect-dialog');if(d)d.remove()}
  function connectBalance(){
    closeDialog()
    var dialog=document.createElement('dialog')
    dialog.id='vk1-connect-dialog'
    dialog.style.cssText='max-width:min(380px,85vw);border:1px solid #667;border-radius:14px;padding:20px;background:#fff;color:#203170;font:15px/1.5 system-ui;z-index:2147483600'
    var title=document.createElement('h3');title.textContent='连接 DeepSeek 余额'
    var info=document.createElement('p');info.textContent='密钥仅用于查询余额，保存在服务端临时会话中；断开、会话过期或服务重启即清除。不会写入网页或浏览器存储。'
    var form=document.createElement('form')
    var label=document.createElement('label');label.textContent='API Key '
    var input=document.createElement('input');input.type='password';input.name='key';input.autocomplete='off';input.required=true;input.placeholder='sk-…';input.style.cssText='width:100%;box-sizing:border-box;padding:10px;margin:8px 0';label.appendChild(input)
    var status=document.createElement('p');status.setAttribute('role','status')
    var submit=document.createElement('button');submit.type='submit';submit.textContent='连接'
    var cancel=document.createElement('button');cancel.type='button';cancel.textContent='取消';cancel.style.marginLeft='12px';cancel.onclick=closeDialog
    form.append(label,status,submit,cancel);dialog.append(title,info,form);document.body.appendChild(dialog)
    dialog.addEventListener('cancel',closeDialog)
    form.addEventListener('submit',async function(e){
      e.preventDefault();submit.disabled=true;status.textContent='正在验证…'
      var key=input.value.trim();input.value=''
      try {
        var response=await fetch('/vk-1/api/session',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({key:key})})
        key=''
        var data=await response.json()
        if(!response.ok||!data.ok){status.textContent=data.error||'连接失败，请检查密钥或网络';submit.disabled=false;return}
        closeDialog()
      }catch(err){key='';status.textContent='连接失败，请稍后重试';submit.disabled=false}
    })
    dialog.showModal();input.focus()
  }
  async function disconnectBalance(){
    try { await fetch('/vk-1/api/session',{method:'DELETE',credentials:'same-origin',cache:'no-store'}) } catch(err) { console.error('[VK-1] disconnect failed') }
  }
  window.VK1Dash={mount:mount,unmount:unmount,connectBalance:connectBalance,disconnectBalance:disconnectBalance,status:function(){return{mounted:!!window.__dshVk1Widget,loading:!!pending}}}
  mount().catch(function(err){console.error('[VK-1 dash]',err.message)})
})()
