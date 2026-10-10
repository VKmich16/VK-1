import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const lock = JSON.parse(fs.readFileSync(path.join(root,'integration/source-lock.json')))
const source = path.resolve(process.argv[3] || path.join(root,'community-reference'))
const release = process.argv[2]
assert(release && /^[a-zA-Z0-9._-]+$/.test(release), 'Usage: node integration/build.mjs RELEASE [SOURCE]')
assert.equal(execFileSync('git',['rev-parse','HEAD'],{cwd:source,encoding:'utf8'}).trim(),lock.commit,'Unreviewed commit: audit and update source-lock first')
assert.equal(execFileSync('git',['status','--porcelain'],{cwd:source,encoding:'utf8'}).trim(),'','Upstream source must be pristine')
const sha = data => crypto.createHash('sha256').update(data).digest('hex')
for(const [name,hash] of Object.entries(lock.sha256)) assert.equal(sha(fs.readFileSync(path.join(source,name))),hash,'Input changed: '+name)
let widget = fs.readFileSync(path.join(source,'dsh-plugin/widget.js'),'utf8')
const patches = JSON.parse(fs.readFileSync(path.join(root,'integration/patches.json')))
for(const patch of patches){
  assert.equal(widget.split(patch.old).length-1,1,'Patch anchor changed/ambiguous: '+patch.id)
  widget=widget.replace(patch.old,patch.new)
}
const output = path.join(root,'releases',release)
assert(!fs.existsSync(output),'Refuse to overwrite immutable release')
fs.mkdirSync(output,{recursive:true})
fs.writeFileSync(path.join(output,'widget.js'),widget)
let loader = fs.readFileSync(path.join(root,'integration/loader.js'),'utf8')
const loaderAnchor = /widget\.js\?v=[a-zA-Z0-9._-]+/g
assert.equal((loader.match(loaderAnchor)||[]).length,1,'Unique widget version anchor required')
loader=loader.replace(loaderAnchor,'widget.js?v='+release)
fs.writeFileSync(path.join(output,'loader.js'),loader)
fs.cpSync(path.join(source,'dsh-plugin/assets'),path.join(output,'assets'),{recursive:true})
fs.copyFileSync(path.join(source,'dsh-plugin/LICENSE'),path.join(output,'LICENSE'))
fs.copyFileSync(path.join(root,'integration/licenses/UPSTREAM-LICENSE'),path.join(output,'UPSTREAM-LICENSE'))
fs.writeFileSync(path.join(output,'index.html'),'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VK-1 桌宠</title><body><p>VK-1 桌宠：拖动人物；电脑右键、手机长按打开菜单。连接余额请用人物菜单。</p><script defer src="/vk-1/loader.js"></script></body></html>\n')
execFileSync(process.execPath,['--check',path.join(output,'widget.js')])
execFileSync(process.execPath,['--check',path.join(output,'loader.js')])
const files={}
function walk(dir){for(const f of fs.readdirSync(dir,{withFileTypes:true})){const full=path.join(dir,f.name);if(f.isDirectory())walk(full);else files[path.relative(output,full)]=sha(fs.readFileSync(full))}}
walk(output)
const manifest={release,upstream:'afdf6e21a688f0557acabcf4e0499272231ed233',community:lock.commit,communityVersion:lock.version,builtAt:new Date().toISOString(),patches:patches.map(p=>p.id),files}
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n')
console.log('BUILD PASS '+output+' ('+patches.length+' exact patches; '+Object.keys(files).length+' files)')
