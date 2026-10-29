// ============================================================================
// dsh-vk1-pet —— 宿主侧
// ============================================================================
// VK-1 余额桌宠（https://github.com/VKmich16/VK-1）的 DSH Web 插件版。
//
// 宿主只做三件事：
//   ① 把桌宠素材（立绘 / 四表情 / 米盆 / 铁盆 / 音效）按白名单挂成 HTTP 路由；
//   ② 查余额并归一化成 pet.js 认的一种形状（DSH 账号凭证优先，API Key 兜底）；
//   ③ 往 index.html 注入一行引导脚本，把 pet.js 拉进页面。
//
// 设计约束（都是踩过的）：
//   · 桌面版（Electron）能用的注入通道是 `webserver/index-inject` 的**内联 script 行**；
//     `script-src` 行加载失败会连累 boot。内联行自己建 <script src> 并吞掉 onerror，
//     路由不在时静默失败，绝不拖慢/拖垮宿主。
//   · `webserver/index-inject` 表是**每次渲染 index 时现收**的，所以运行中 hot apply
//     也能生效；但已经打开的页面要刷新一次才拿得到。
//   · credentials 服务用 ctx.get() 读（可选服务），不写进 inject —— 老宿主上写进去会
//     导致插件永远不 apply。
// ============================================================================

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, '..')
const ASSET_DIR = path.join(ROOT, 'assets')

const ROUTE_PREFIX = '/dsh-vk1'
const BALANCE_TTL_MS = 8_000
const FETCH_TIMEOUT_MS = 20_000

// 生命周期记号：宿主没有日志文件，插件"为什么没生效 / 为什么被摘掉"只能靠这行。
const DSH_HOME = process.env.DSH_HOME || path.join(os.homedir(), '.dsh')
const LIFECYCLE_LOG = path.join(DSH_HOME, 'storages', 'dsh-vk1-pet', 'lifecycle.log')

function mark(event) {
  try {
    fs.mkdirSync(path.dirname(LIFECYCLE_LOG), { recursive: true })
    fs.appendFileSync(LIFECYCLE_LOG, `${new Date().toISOString()} pid=${process.pid} ${event}\n`, 'utf8')
  } catch {
    /* 记号写不进去也不影响插件 */
  }
}


// 素材白名单：路由只服务这张表里的文件，文件名先经 path.basename 收敛。
const ASSET_TYPES = {
  'sprite.png': 'image/png',
  'expression_11.png': 'image/png',
  'expression_12.png': 'image/png',
  'expression_21.png': 'image/png',
  'expression_22.png': 'image/png',
  'rice.png': 'image/png',
  'iron_bowl.png': 'image/png',
  'pat_hand_0.png': 'image/png',
  'pat_hand_1.png': 'image/png',
  'pat_hand_2.png': 'image/png',
  'pat_hand_3.png': 'image/png',
  'pat_hand_4.png': 'image/png',
  'hit.mp3': 'audio/mpeg',
  'feed.mp3': 'audio/mpeg',
  'pot_land.mp3': 'audio/mpeg',
  'pot_off.mp3': 'audio/mpeg',
}

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
}

// 桌面端注入行：内联脚本自建 <script src>，onerror 吞掉。
const INJECT_ROW_TEXT =
  '(function(){try{var d=document.body||document.head||document.documentElement;if(!d)return;' +
  `var s=document.createElement("script");s.src="${ROUTE_PREFIX}/pet.js";` +
  's.async=true;s.onerror=function(){};d.appendChild(s)}catch(e){}})()'

const NAME = 'dsh-vk1-pet'
const inject = ['webServer']

// 自检页：证明「桌宠 + 余额路由」本身是好的，与 DSH 宿主无关。
const SELFTEST_HTML = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VK-1 余额桌宠 · 自检</title>
<style>
html,body{margin:0;height:100%;background:#f4f6f9;color:#38506e;
  font:14px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif}
main{max-width:640px;padding:38px 34px}
h1{font-size:17px;margin:0 0 10px}
p{margin:6px 0;color:#5d7391;font-size:13px}
code{background:#e7ecf4;border-radius:5px;padding:1px 5px;font-size:12.5px}
.bar{margin-top:22px;padding:14px 16px;background:#fff;border:1px solid #e2e8f2;border-radius:10px;
  font:12.5px/1.7 ui-monospace,Consolas,monospace;white-space:pre-wrap}
</style></head>
<body><main>
<h1>VK-1 余额桌宠 · 自检页</h1>
<p>这个页面不属于 DSH 界面，只是把桌宠脚本单独跑一遍：角色应该出现在左下角，平板上有余额。</p>
<p>右键角色有菜单；<code>测试扣费</code> / <code>测试充值</code> 可以看动画，不用等到真的花掉钱。</p>
<p>余额接口：<code>/dsh-vk1/balance.json</code></p>
<div class="bar" id="stat">探测中…</div>
<script src="/dsh-vk1/pet.js"></script>
<script>
(function(){
  var el=document.getElementById('stat');
  function probe(){
    fetch('/dsh-vk1/balance.json',{cache:'no-store'}).then(function(r){return r.json()}).then(function(v){
      el.textContent = 'balance.json -> ' + JSON.stringify(v, null, 2)
    }).catch(function(e){ el.textContent = 'balance.json 请求失败: ' + e });
  }
  probe();
  setInterval(probe, 5000);
})();
</script>
</main></body></html>`


function readFileCached(cache, file) {
  if (cache.has(file)) return cache.get(file)
  const bytes = fs.readFileSync(path.join(ASSET_DIR, file))
  cache.set(file, bytes)
  return bytes
}

function pickWalletTotal(wallets, amountKey) {
  if (!Array.isArray(wallets)) return null
  let cny = null
  for (const wallet of wallets) {
    if (!wallet || typeof wallet !== 'object') continue
    const currency = String(wallet.currency || '').toUpperCase()
    const raw = wallet[amountKey]
    const amount = typeof raw === 'string' ? Number(raw) : raw
    if (!Number.isFinite(amount)) continue
    if (currency === 'CNY') cny = amount
    if (cny !== null) break
  }
  return cny
}

// DSH 账号余额：<issuer>/api/v0/users/get_user_summary，响应可能带 code/data 外壳。
function parseAccountSummary(json) {
  let payload = json && typeof json === 'object' ? json : null
  if (payload === null) return null
  if (Object.hasOwn(payload, 'code') || Object.hasOwn(payload, 'data')) {
    if (payload.code !== undefined && Number(payload.code) !== 0) return null
    payload = payload.data
  }
  if (!payload || typeof payload !== 'object') return null
  if (Object.hasOwn(payload, 'biz_code') || Object.hasOwn(payload, 'biz_data')) {
    if (payload.biz_code !== undefined && Number(payload.biz_code) !== 0) return null
    payload = payload.biz_data
  }
  if (!payload || typeof payload !== 'object') return null
  const normal = pickWalletTotal(payload.normal_wallets, 'balance')
  const bonus = pickWalletTotal(payload.bonus_wallets, 'balance')
  if (normal === null && bonus === null) return null
  // 与设置页一致：正常钱包是主余额，赠送钱包单独列，不合并成一个数
  return { total: normal === null ? bonus : normal, bonus: bonus === null ? 0 : bonus, currency: 'CNY' }
}

// API Key 余额：/user/balance 的 balance_infos，正数优先 / CNY 优先。
function parseApiKeyBalance(json) {
  const infos = json && Array.isArray(json.balance_infos) ? json.balance_infos : null
  if (infos === null || infos.length === 0) return null
  const num = (x) => (x && x.total_balance !== undefined ? Number(x.total_balance) : NaN)
  const currency = (x) => String((x && x.currency) || '').toUpperCase()
  const info =
    infos.find((x) => currency(x) === 'CNY' && num(x) > 0) ||
    infos.find((x) => num(x) > 0) ||
    infos.find((x) => currency(x) === 'CNY') ||
    infos[0]
  const amount = num(info)
  if (!Number.isFinite(amount)) return null
  return { total: amount, currency: currency(info) || 'CNY' }
}

export const name = NAME
export { inject }

export function apply(root) {
  mark('apply:start')
  // 整个 apply 不允许抛：宿主对「加载失败的 bundle」的处理是把包从 profile 的
  // dsh.profile.bundles 里直接摘掉，表现为插件消失、路由 404，连报错都看不到。
  try {
    applyInner(root)
    mark('apply:ok')
  } catch (error) {
    mark(`apply:throw ${String((error && error.message) || error)}`)
  }
}

function applyInner(root) {
  // ① 注入行最早注册：这里不依赖任何服务。
  root.effect(() => {
    const off = root.on('webserver/index-inject', (table) => {
      try {
        if (!Array.isArray(table)) return
        for (const row of table) {
          if (!row) continue
          if (row.kind === 'script-src' && String(row.src || '').includes(`${ROUTE_PREFIX}/pet.js`)) return
          if (row.kind === 'script' && typeof row.text === 'string' && row.text.includes(`${ROUTE_PREFIX}/pet.js`)) return
        }
        table.push({ kind: 'script', placement: 'body', text: INJECT_ROW_TEXT })
      } catch {
        /* 注入表结构变了就静默放弃 */
      }
    })
    return () => {
      try {
        off()
      } catch {
        /* ignore */
      }
    }
  }, 'dsh-vk1-pet: index injection')


  // ② 其余逻辑等服务就绪。
  root.inject(['webServer'], (ctx) => {
    const disposers = []
    const assetCache = new Map()
    let petJsCache = null
    let balanceCache = null
    let balanceInFlight = null

    // ⚠️ 必须**每次现取**：boot 时 webServer 常常先于 credentials 就绪，
    // 在这里把 ctx.get('credentials') 缓存成常量，冷启动就永远是 undefined，
    // 表现是「进程刚起来时余额取不到，热加载一次又好了」。
    function credentialsService() {
      try {
        return typeof ctx.get === 'function' ? ctx.get('credentials') : undefined
      } catch {
        return undefined
      }
    }

    // 凭据服务的兜底：直接读 <DSH_HOME>/.credentials.yaml。
    // 只认两个形状（账号 grant 和 refs 里的 API Key），不引 YAML 依赖、不打印内容。
    const CREDENTIALS_FILE = path.join(DSH_HOME, '.credentials.yaml')
    let yamlCache = { mtimeMs: null, account: null, apiKey: null }

    function scalar(raw) {
      const text = String(raw == null ? '' : raw).trim()
      if (text.length === 0) return ''
      const quoted = /^(['"])(.*)\1$/.exec(text)
      return quoted ? quoted[2] : text
    }

    function parseAccountGrant(text) {
      const lines = text.split(/\r?\n/)
      let start = -1
      let headerIndent = 0
      for (let i = 0; i < lines.length; i++) {
        const m = /^(\s*)deepseek-account-platform\/default:\s*$/.exec(lines[i])
        if (m !== null) {
          start = i
          headerIndent = m[1].length
          break
        }
      }
      if (start === -1) return null
      let payloadIndent = -1
      let token = ''
      let issuer = ''
      for (let i = start + 1; i < lines.length; i++) {
        const line = lines[i]
        if (line.trim().length === 0 || line.trim().startsWith('#')) continue
        const indent = line.length - line.trimStart().length
        if (indent <= headerIndent) break
        const payload = /^(\s*)payload:\s*$/.exec(line)
        if (payload !== null) {
          payloadIndent = payload[1].length
          continue
        }
        if (payloadIndent === -1 || indent <= payloadIndent) continue
        const field = /^(\s*)(token|issuer):\s*(.+)$/.exec(line)
        if (field === null) continue
        if (field[2] === 'token' && token === '') token = scalar(field[3])
        if (field[2] === 'issuer' && issuer === '') issuer = scalar(field[3])
      }
      return token && issuer ? { token, issuer } : null
    }

    function parseRefValue(text, key) {
      const lines = text.split(/\r?\n/)
      let inRefs = false
      let refsIndent = 0
      for (const line of lines) {
        if (line.trim().length === 0 || line.trim().startsWith('#')) continue
        const indent = line.length - line.trimStart().length
        if (/^\s*refs:\s*$/.test(line)) {
          inRefs = true
          refsIndent = indent
          continue
        }
        if (!inRefs) continue
        if (indent <= refsIndent) break
        const m = new RegExp('^\\s*' + key + ':\\s*(.+)$').exec(line)
        if (m !== null) {
          const value = scalar(m[1])
          return value || null
        }
      }
      return null
    }

    function credentialsFromFile() {
      try {
        const stat = fs.statSync(CREDENTIALS_FILE)
        if (yamlCache.mtimeMs === stat.mtimeMs) return yamlCache
        const text = fs.readFileSync(CREDENTIALS_FILE, 'utf8')
        yamlCache = {
          mtimeMs: stat.mtimeMs,
          account: parseAccountGrant(text),
          apiKey: parseRefValue(text, 'DEEPSEEK_API_KEY'),
        }
      } catch {
        yamlCache = { mtimeMs: null, account: null, apiKey: null }
      }
      return yamlCache
    }

    function petJs() {
      const file = path.join(ROOT, 'pet.js')
      const stat = fs.statSync(file)
      if (petJsCache !== null && petJsCache.mtimeMs === stat.mtimeMs) return petJsCache.text
      petJsCache = { text: fs.readFileSync(file, 'utf8'), mtimeMs: stat.mtimeMs }
      return petJsCache.text
    }

    // 官方账号服务：DSH 设置页「账户」里那个余额就是走它（`ctx.deepseekAccount.getBalance`）。
    // 复用它的好处：请求头（x-client-*）、token 刷新、401 失效处理、钱包解析全是宿主在做，
    // 我们连 token 都不用碰；代价是它是内部接口，所以下面保留了自取自解析的兜底。
    function accountService() {
      try {
        return typeof ctx.get === 'function' ? ctx.get('deepseekAccount') : undefined
      } catch {
        return undefined
      }
    }

    function clientIdentity() {
      return {
        version: process.env.DSH_CLIENT_VERSION || '0.0.0',
        locale: typeof Intl !== 'undefined' ? Intl.DateTimeFormat().resolvedOptions().locale || 'zh-CN' : 'zh-CN',
        timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
      }
    }

    // 钱包数组取金额：CNY 优先、正数优先（与设置页一致：正常钱包和赠送钱包分开看）
    function pickWalletAmount(wallets) {
      if (!Array.isArray(wallets) || wallets.length === 0) return null
      const amount = (w) => Number(w && w.balance)
      const currency = (w) => String((w && w.currency) || '').toUpperCase()
      const pick =
        wallets.find((w) => currency(w) === 'CNY' && amount(w) > 0) ||
        wallets.find((w) => amount(w) > 0) ||
        wallets.find((w) => currency(w) === 'CNY') ||
        wallets[0]
      const value = amount(pick)
      return Number.isFinite(value) ? value : null
    }

    async function fetchServiceBalance() {
      const account = accountService()
      if (!account || typeof account.getBalance !== 'function') return null
      const result = await account.getBalance(clientIdentity())
      if (!result || result.status !== 'ready') return null
      const normal = pickWalletAmount(result.value)
      const bonus = pickWalletAmount(result.bonusWallets)
      if (normal === null && bonus === null) return null
      return {
        total: normal === null ? bonus : normal,
        bonus: bonus === null ? 0 : bonus,
        currency: 'CNY',
        source: 'DSH 账号（设置页同源）',
      }
    }

    async function accountCredentials() {
      const service = credentialsService()
      if (service && typeof service.readRecord === 'function') {
        try {
          const record = await service.readRecord('deepseek-account-platform/default')
          const payload = record && record.payload ? record.payload : null
          const token = payload && typeof payload.token === 'string' ? payload.token : ''
          const issuer = payload && typeof payload.issuer === 'string' ? payload.issuer : ''
          if (token && issuer) return { token, issuer, source: 'DSH 账号' }
        } catch {
          /* 落到文件兜底 */
        }
      }
      const fromFile = credentialsFromFile().account
      return fromFile ? { ...fromFile, source: 'DSH 账号（凭据文件）' } : null
    }

    async function apiKeyCredential() {
      const service = credentialsService()
      if (service && typeof service.resolve === 'function') {
        try {
          const cred = await service.resolve('DEEPSEEK_API_KEY')
          if (cred && cred.value) return { value: cred.value, source: 'DeepSeek API Key' }
        } catch {
          /* 落到文件兜底 */
        }
      }
      const key = credentialsFromFile().apiKey
      return key ? { value: key, source: 'DeepSeek API Key（凭据文件）' } : null
    }

    async function fetchAccountBalance() {
      const grant = await accountCredentials()
      if (grant === null) return null
      const base = new URL(grant.issuer.endsWith('/') ? grant.issuer : grant.issuer + '/')
      const url = new URL('api/v0/users/get_user_summary', base).toString()
      const res = await fetch(url, {
        headers: { Accept: 'application/json', 'x-dsh-auth-token': grant.token },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      })
      if (!res.ok) throw new Error(`账号余额接口 HTTP ${res.status}`)
      const parsed = parseAccountSummary(await res.json())
      if (parsed === null) throw new Error('账号余额接口返回结构异常')
      return { ...parsed, source: grant.source }
    }

    async function fetchApiKeyBalance() {
      const credential = await apiKeyCredential()
      if (credential === null) return null
      const res = await fetch('https://api.deepseek.com/user/balance', {
        headers: { Accept: 'application/json', Authorization: `Bearer ${credential.value}` },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      })
      if (!res.ok) throw new Error(`余额接口 HTTP ${res.status}`)
      const parsed = parseApiKeyBalance(await res.json())
      if (parsed === null) throw new Error('余额接口返回结构异常')
      return { ...parsed, source: credential.source }
    }

    // 排障用：告诉调用方「账号服务 / 凭据服务看不看得见、文件兜底解析出没有」，不含任何凭据内容
    function credentialDiag() {
      const service = credentialsService()
      const file = credentialsFromFile()
      return {
        accountService: accountService() !== undefined,
        service: service !== undefined,
        fileAccount: file.account !== null,
        fileApiKey: file.apiKey !== null,
      }
    }

    async function fetchBalance() {
      const failures = []
      // 顺序：宿主账号服务（设置页同源，最不容易出错）→ 自取自解析 → API Key
      for (const attempt of [fetchServiceBalance, fetchAccountBalance, fetchApiKeyBalance]) {
        try {
          const hit = await attempt()
          if (hit !== null) {
            return { ok: true, ...hit, diag: credentialDiag(), updatedAt: new Date().toISOString() }
          }
        } catch (error) {
          failures.push(String((error && error.message) || error).slice(0, 200))
        }
      }
      const service = credentialsService()
      const file = credentialsFromFile()
      const detail = [
        service ? '凭据服务可见' : '凭据服务不可见',
        file.account ? '凭据文件里有账号' : '凭据文件里没账号',
        file.apiKey ? '有 API Key' : '没 API Key',
      ].join('；')
      return {
        ok: false,
        code: 'NO_SOURCE',
        diag: credentialDiag(),
        error: failures.length > 0 ? failures.join(' / ') : `没有可用的余额来源（${detail}）`,
      }
    }

    function getBalance() {
      const now = Date.now()
      if (balanceCache !== null && now - balanceCache.at < BALANCE_TTL_MS) {
        return Promise.resolve(balanceCache.payload)
      }
      if (balanceInFlight !== null) return balanceInFlight
      balanceInFlight = fetchBalance()
        .then((payload) => {
          if (payload.ok) {
            balanceCache = { at: now, payload }
            return payload
          }
          // 瞬时失败时沿用上一次的值，避免动画误判成「归零」
          if (balanceCache !== null) return { ...balanceCache.payload, stale: true, error: payload.error }
          return payload
        })
        .catch((error) => ({
          ok: false,
          code: 'ERROR',
          error: String((error && error.message) || error).slice(0, 200),
        }))
        .finally(() => {
          balanceInFlight = null
        })
      return balanceInFlight
    }

    function register(path, handler) {
      try {
        disposers.push(ctx.webServer.register({ kind: 'exact', path, handler }))
      } catch (error) {
        // 同路径已被上一个还没 dispose 干净的实例占着：不抛（抛了宿主会把整个包摘掉），
        // 记一笔就好——旧 handler 仍在服务，等它释放后下次 apply 自然接上。
        mark(`route:duplicate ${path} ${String((error && error.message) || error)}`)
      }
    }

    // 回环信任栅栏：余额与自检页只在回环 Host 下应答，挡 DNS rebinding。
    function isLoopbackRequest(req) {
      try {
        const host = String(req.headers.host || '').toLowerCase().replace(/:\d+$/, '').replace(/^\[/, '').replace(/\]$/, '')
        if (host === 'localhost' || host.endsWith('.localhost') || host === '::1') return true
        const quad = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host)
        return quad !== null && Number(quad[1]) === 127 && [quad[2], quad[3], quad[4]].every((x) => Number(x) <= 255)
      } catch {
        return false
      }
    }

    function forbidNonLoopback(req, res) {
      if (isLoopbackRequest(req)) return false
      res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' })
      res.end('forbidden host')
      return true
    }

    // 素材
    for (const [file, type] of Object.entries(ASSET_TYPES)) {
      register(`${ROUTE_PREFIX}/assets/${file}`, (req, res) => {
        try {
          const bytes = readFileCached(assetCache, file)
          res.writeHead(200, {
            'Content-Type': type,
            'Cache-Control': 'public, max-age=3600',
            'Content-Length': String(bytes.length),
          })
          res.end(bytes)
        } catch (error) {
          res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' })
          res.end(`${file} unavailable: ${String((error && error.message) || error)}`)
        }
      })
    }

    // 浏览器脚本
    register(`${ROUTE_PREFIX}/pet.js`, (req, res) => {
      try {
        const text = petJs()
        res.writeHead(200, {
          'Content-Type': 'text/javascript; charset=utf-8',
          'Cache-Control': 'no-store',
        })
        res.end(text)
      } catch (error) {
        res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' })
        res.end(`pet.js unavailable: ${String((error && error.message) || error)}`)
      }
    })

    // 余额
    register(`${ROUTE_PREFIX}/balance.json`, async (req, res) => {
      if (forbidNonLoopback(req, res)) return
      try {
        const payload = await getBalance()
        res.writeHead(200, JSON_HEADERS)
        res.end(JSON.stringify(payload))
      } catch (error) {
        res.writeHead(200, JSON_HEADERS)
        res.end(JSON.stringify({ ok: false, code: 'ERROR', error: String((error && error.message) || error).slice(0, 200) }))
      }
    })

    // 自检页：不依赖 DSH 宿主，直接看「桌宠本身 + 余额路由」是不是好的。
    register(`${ROUTE_PREFIX}/selftest.html`, (req, res) => {
      if (forbidNonLoopback(req, res)) return
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' })
      res.end(SELFTEST_HTML)
    })

    // web 形态的兜底通道（桌面壳走 index-inject）
    try {
      disposers.push(
        ctx.webServer.tapIndex((html) => {
          if (typeof html !== 'string' || html.includes(`${ROUTE_PREFIX}/pet.js`)) return html
          const tag = `<script async src="${ROUTE_PREFIX}/pet.js"></script>`
          return html.includes('</body>') ? html.replace('</body>', `${tag}</body>`) : html + tag
        }),
      )
    } catch {
      /* 老宿主没有 tapIndex */
    }

    ctx.effect(() => {
      mark('routes:registered')
      mark(`credentials:${credentialsService() ? 'visible' : 'undefined'}`)
      mark(`account:${accountService() ? 'visible' : 'undefined'}`)
      return () => {
        mark('routes:disposed')
        for (const dispose of disposers) {
          try {
            dispose()
          } catch {
            /* ignore */
          }
        }
      }
    }, 'dsh-vk1-pet: routes')
  })
}
