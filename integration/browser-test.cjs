const puppeteer=require('puppeteer')
const http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert/strict')
const release=process.argv[2]||'20261010-1'
const root=path.resolve(__dirname,'../releases',release)
let balance=12.34
const server=http.createServer((req,res)=>{
 if(req.url.startsWith('/vk-1/api/balance')){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({ok:true,totalBalance:balance,currency:'CNY'}));return}
 if(req.url==='/frame'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><body>Cross-site iframe dashboard</body>');return}
 if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="margin:0;height:1800px;background:#162033"><button id="under" style="position:fixed;right:10px;bottom:10px">dash click</button><script src="/vk-1/loader.js"></script></body>');return}
 const rel=req.url.split('?')[0].replace(/^\/vk-1\//,'')
 if(rel.includes('..')){res.writeHead(404).end();return}
 const file=path.join(root,rel)
 if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return}
 const ext=path.extname(file);res.setHeader('Content-Type',({'.js':'application/javascript','.png':'image/png','.mp3':'audio/mpeg','.html':'text/html'})[ext]||'text/plain');fs.createReadStream(file).pipe(res)
})
const delay=ms=>new Promise(r=>setTimeout(r,ms))
let browser
const results=[]
const errors=[]
async function check(name, fn){await fn();results.push(name);console.log('PASS '+name)}
async function point(page){await page.waitForFunction(()=>{const e=document.querySelector('.dshvk1-root'),r=e.getBoundingClientRect();return Math.abs(r.left-parseFloat(e.style.left))<0.1&&Math.abs(r.top-parseFloat(e.style.top))<0.1});return page.evaluate(()=>{
 const r=document.querySelector('.dshvk1-root').getBoundingClientRect()
 for(let y=r.top+15;y<r.bottom-15;y+=9)for(let x=r.left+15;x<r.right-15;x+=9){const el=document.elementFromPoint(x,y);if(el&&el.tagName.toLowerCase()==='path'&&el.closest('.vk1-hit-shape')&&[[6,0],[-6,0],[0,6],[0,-6]].every(([dx,dy])=>document.elementFromPoint(x+dx,y+dy)===el))return{x,y}}
 throw Error('no solid shape')
})}
async function openMenu(page,touch=false){
 const p=await point(page)
 if(touch){const c=await page.createCDPSession();await c.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:p.x,y:p.y,id:1}]});await page.waitForSelector('.dshvk1-menu-open',{timeout:3000});await c.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await c.detach()}
 else await page.mouse.click(p.x,p.y,{button:'right'})
 await page.waitForSelector('.dshvk1-menu-open',{timeout:5000})
}
async function row(page,text){await page.evaluate(text=>{const e=[...document.querySelectorAll('.dshvk1-menu-row')].find(e=>e.tagName==='BUTTON'&&e.textContent.includes(text));if(!e)throw Error(text);e.click()},text)}
async function rect(page){return page.$eval('.dshvk1-root',e=>({x:parseFloat(e.style.left),y:parseFloat(e.style.top),w:e.getBoundingClientRect().width,h:e.getBoundingClientRect().height}))}
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r))
 const url='http://127.0.0.1:'+server.address().port
 browser=await puppeteer.launch({executablePath:process.env.CHROME_BIN||undefined,headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--host-resolver-rules=MAP iframe.vk1.test 127.0.0.1']})
 if(!process.env.MOBILE_ONLY) {
 const page=await browser.newPage();await page.setViewport({width:1280,height:800});page.on('pageerror',e=>errors.push(e.message))
 await page.goto(url);await page.waitForSelector('.vk1-hit-shape path[d]');await page.waitForFunction(()=>document.querySelector('.dshvk1-num').textContent==='12.34')
 await check('right-bottom, mirrored art, positive text determinant',async()=>{
  const r=await rect(page);assert.equal(r.x,1280-r.w);assert.equal(r.y,800-r.h)
  const d=await page.$eval('.dshvk1-panel',e=>{const m=new DOMMatrix(getComputedStyle(e).transform);return m.a*m.d-m.b*m.c});assert(d>0)
  assert(await page.$eval('.dshvk1-root',e=>e.classList.contains('dshvk1-mirror')))
 })
 await check('transparent pixels pass through to dash',async()=>{const id=await page.evaluate(()=>{const r=document.querySelector('.dshvk1-root').getBoundingClientRect();const c=document.createElement('canvas');c.width=c.height=610;const ctx=c.getContext('2d');ctx.drawImage(document.querySelector('.dshvk1-face'),0,0,610,610);for(let y=30;y<550;y+=30)for(let x=30;x<550;x+=30){if(ctx.getImageData(609-x,y,1,1).data[3])continue;const px=r.left+x/610*r.width,py=r.top+y/610*r.height;const b=document.querySelector('#under');b.style.cssText='position:fixed;left:'+ (px-2)+'px;top:'+(py-2)+'px;width:4px;height:4px;padding:0;z-index:1';return document.elementFromPoint(px,py).id}throw Error('No transparent test pixel')});assert.equal(id,'under')})
 await check('desktop right-click menu and complete preserved controls',async()=>{await openMenu(page);const text=await page.$eval('.dshvk1-menu',e=>e.textContent);for(const t of ['刷新余额','充值','火控雷达','尺寸','声音','位置','连接 DeepSeek'])assert(text.includes(t),'missing '+t+' from '+text);await row(page,'测试一次扣费')})
 await check('deduction animation and numeric update',async()=>{await page.waitForSelector('.dshvk1-floater');assert.equal(await page.$eval('.dshvk1-num',e=>e.textContent),'12.33')})
 await delay(1200)
 await check('mouse drag across embedded iframe and reload persistence',async()=>{
  await page.evaluate(url=>new Promise(resolve=>{const iframe=document.createElement("iframe");iframe.id="drag-iframe";iframe.onload=resolve;iframe.src=url.replace("127.0.0.1","iframe.vk1.test")+"/frame";iframe.style.cssText="position:fixed;left:300px;top:150px;width:800px;height:500px;border:0;z-index:2";document.body.appendChild(iframe)}),url)
  const p=await point(page);await page.mouse.move(p.x,p.y);await page.mouse.down();await page.mouse.move(p.x-400,p.y-250,{steps:12});await page.mouse.up();await delay(250)
  const before=await rect(page);assert(before.x<850);assert(before.y<500);assert.equal(await page.$eval(".dshvk1-stage",e=>e.style.pointerEvents),"none")
  await page.reload();await page.waitForSelector('.vk1-hit-shape path[d]');await delay(250);const after=await rect(page);assert.equal(after.x,before.x);assert.equal(after.y,before.y)
 })
 await check('resize preserves visible non-default placement',async()=>{await page.setViewport({width:1100,height:740});await delay(250);const r=await rect(page);assert(r.x>=0&&r.y>=0&&r.x+r.w<=1100&&r.y+r.h<=740)})
 await openMenu(page);await row(page,'模拟充值');await delay(2200)
 await check('rice animation and manual radar',async()=>{assert((await page.$$('.dshvk1-bowl')).length>0);await openMenu(page);await row(page,'打开火控雷达');await page.waitForFunction(()=>document.querySelector('.dshvk1-radar').textContent.includes('白饭'))})
 await check('idle rice auto-locks and feeds, emits hearts and iron',async()=>{await page.waitForSelector('.dshvk1-heart',{timeout:16000});await delay(600);assert((await page.$$('.dshvk1-bowl[src$="iron_bowl.png"]')).length>0)})
 await check('iron pot draggable onto head and removable by double-click',async()=>{const iron=await page.$('.dshvk1-bowl[src$="iron_bowl.png"]');const b=await iron.boundingBox();const r=await rect(page);await page.mouse.move(b.x+b.width/2,b.y+b.height/2);await page.mouse.down();await page.mouse.move(r.x+r.w*0.4442,r.y+r.h*0.28,{steps:12});await page.mouse.up();await delay(700);assert(await page.$eval('.dshvk1-face[src$="expression_21.png"]',e=>e.style.display==='block'));await page.mouse.click(r.x+r.w*0.50,r.y+r.h*0.30);await page.mouse.click(r.x+r.w*0.50,r.y+r.h*0.30);await page.waitForFunction(()=>!document.querySelector('.dshvk1-bowl[src$="iron_bowl.png"]'),{timeout:2000})})
 await check('mount is idempotent and unmount cleans layers',async()=>{await page.evaluate(async()=>{await window.VK1Dash.mount();await window.VK1Dash.mount()});assert.equal((await page.$$('.dshvk1-root')).length,1);await page.evaluate(()=>window.VK1Dash.unmount());assert.equal((await page.$$('.dshvk1-root,.dshvk1-stage,.dshvk1-menu')).length,0);await page.evaluate(()=>window.VK1Dash.mount());await page.waitForSelector('.vk1-hit-shape path[d]')})
 await page.screenshot({path:path.resolve(__dirname,'desktop-test.png')})
 assert.deepEqual(errors,[])
 }
 const mobileContext=await browser.createBrowserContext();const mobile=await mobileContext.newPage();await mobile.setViewport({width:390,height:844,isMobile:true,hasTouch:true,deviceScaleFactor:1});const mobileErrors=[];mobile.on('pageerror',e=>mobileErrors.push(e.message))
 await mobile.bringToFront();await mobile.goto(url);await mobile.waitForSelector('.vk1-hit-shape path[d]')
 await check('mobile responsive bottom-right default',async()=>{const r=await rect(mobile);assert.equal(r.w,192);assert.equal(r.x,198);assert.equal(r.y,652)})
 await check('real touchscreen long-press opens contained menu',async()=>{await openMenu(mobile,true);const box=await mobile.$eval('.dshvk1-menu',e=>{const r=e.getBoundingClientRect();return{x:r.left,y:r.top,right:r.right,bottom:r.bottom}});assert(box.x>=0&&box.y>=0&&box.right<=390&&box.bottom<=844);await row(mobile,'立即刷新')})
 await check('real touch drag cancels hold, moves character without page scrolling',async()=>{
  const p=await point(mobile),c=await mobile.createCDPSession();const before=await rect(mobile)
  await c.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:p.x,y:p.y,id:1}]})
  for(let i=1;i<=12;i++){await c.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:p.x-80*i/12,y:p.y-320*i/12,id:1}]});await delay(20)}
  await c.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await c.detach();await delay(700)
  const after=await rect(mobile);assert(after.y<before.y-200);assert.equal(await mobile.evaluate(()=>scrollY),0);assert.equal((await mobile.$$('.dshvk1-menu-open')).length,0)
 })
 await check('mobile position persists after refresh',async()=>{const r=await rect(mobile);await mobile.reload();await mobile.waitForSelector('.vk1-hit-shape path[d]');await delay(250);assert.deepEqual(await rect(mobile),r)})
 await check('cancelled touch does not leave dragging state',async()=>{const p=await point(mobile),c=await mobile.createCDPSession();await c.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:p.x,y:p.y,id:1}]});await c.send('Input.dispatchTouchEvent',{type:'touchCancel',touchPoints:[]});await c.detach();await delay(650);assert.equal((await mobile.$$('.dshvk1-dragging,.dshvk1-menu-open')).length,0)})
 await check('balance connection dialog is usable and has no stored key',async()=>{await openMenu(mobile,true);await row(mobile,'连接 DeepSeek');await mobile.waitForSelector('#vk1-connect-dialog[open]');assert.equal(await mobile.$eval('#vk1-connect-dialog input',e=>e.type),'password');assert(!(await mobile.evaluate(()=>Object.keys(localStorage).join(','))).includes('key'));await mobile.click('#vk1-connect-dialog button[type=button]')})
 await mobile.screenshot({path:path.resolve(__dirname,'mobile-test.png')});assert.deepEqual(mobileErrors,[])
 fs.writeFileSync(path.resolve(__dirname,'browser-test-report.json'),JSON.stringify({release,results,desktopErrors:errors,mobileErrors},null,2)+'\n')
})().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{if(browser)await browser.close();server.close()})
