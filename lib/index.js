import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// ============================================================================
// dsh-vk1-balance-pet —— Host half
//
// VK-1 余额桌宠的宿主侧。上游是 VKmich16/VK-1 仓库：
//   - 页面挂件由 integration/ 的构建（社区 widget 1.0.2 + 37 条审计补丁）产出，
//     提供四表情 / 米饭盆充值 / 铁盆 / 火控雷达 / 拖拽 / 音效等全部行为；
//   - 本文件只负责在 DSH 的 webServer 上把挂件、素材和余额接口端出来，
//     并把 loader 注入 index.html —— 与社区版 dsh-vk1-balance-widget 同一套做法。
//
// 余额来源优先级（都由 DSH 宿主侧完成，不把凭据送到浏览器）：
//   1. 菜单里「连接 DeepSeek 余额」临时填写的 API Key（仅存内存，断开/DOSH 退出即清除）
//   2. DSH 已登录账号的充值 + 赠金额度（deepseekAccount.getBalance）
//   3. DSH 凭据服务里的 DEEPSEEK_API_KEY（api.deepseek.com/user/balance）
// ============================================================================

const PACKAGE_ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const ASSETS_ROOT = path.join(PACKAGE_ROOT, 'assets')
const BALANCE_URL = 'https://api.deepseek.com/user/balance'
const BALANCE_TTL_MS = 8000
const MAX_SESSION_BODY = 8 * 1024

// 与 DSH 自带设置页一致的 Platform 客户端身份；版本号只用于网关识别调用来源。
const ACCOUNT_CLIENT = Object.freeze({
  version: '0.2.0-rc.2',
  locale: 'zh-CN',
  timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
})

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
}

// 静态路由：路径 -> [包内文件, Content-Type]
const STATIC_ROUTES = {
  '/vk-1/widget.js': ['widget.js', 'application/javascript; charset=utf-8'],
  '/vk-1/loader.js': ['loader.js', 'application/javascript; charset=utf-8'],
  '/vk-1/assets/expression_11.png': ['assets/expression_11.png', 'image/png'],
  '/vk-1/assets/expression_12.png': ['assets/expression_12.png', 'image/png'],
  '/vk-1/assets/expression_21.png': ['assets/expression_21.png', 'image/png'],
  '/vk-1/assets/expression_22.png': ['assets/expression_22.png', 'image/png'],
  '/vk-1/assets/rice.png': ['assets/rice.png', 'image/png'],
  '/vk-1/assets/iron_bowl.png': ['assets/iron_bowl.png', 'image/png'],
  '/vk-1/assets/hit.mp3': ['assets/hit.mp3', 'audio/mpeg'],
  '/vk-1/assets/feed.mp3': ['assets/feed.mp3', 'audio/mpeg'],
}

const name = 'dsh-vk1-balance-pet'
const inject = ['webServer', 'credentials', 'deepseekAccount']

function messageOf(error) {
  return String((error && error.message) || error).slice(0, 200)
}

function apply(ctx) {
  const disposers = []
  const fileCache = new Map()
  let overrideKey = null
  let balanceCache = null
  let balanceInFlight = null

  function readPackageFile(relPath) {
    if (!fileCache.has(relPath)) fileCache.set(relPath, fs.readFileSync(path.join(PACKAGE_ROOT, relPath)))
    return fileCache.get(relPath)
  }

  function sendJson(res, status, payload) {
    res.writeHead(status, JSON_HEADERS)
    res.end(JSON.stringify(payload))
  }

  // ------------------------------------------------------------- 余额读取 ---

  /** 把一个钱包数组里的 CNY 额度加总；没有任何 CNY 钱包时返回 null。 */
  function walletTotal(wallets) {
    let total = 0
    let seenCny = false
    for (const wallet of wallets) {
      if (!wallet || wallet.currency !== 'CNY') continue
      const value = Number(wallet.balance)
      if (!Number.isFinite(value)) continue
      seenCny = true
      total += value
    }
    return seenCny ? Math.round(total * 100) / 100 : null
  }

  /** DSH 已登录账号的可用余额 = 充值额度 + 赠金额度。 */
  async function readAccountBalance() {
    const detail = await ctx.deepseekAccount.getBalance(ACCOUNT_CLIENT)
    if (!detail || detail.status !== 'ready') return null
    const total = walletTotal([...(detail.value || []), ...(detail.bonusWallets || [])])
    if (total === null) return null
    return { totalBalance: total, currency: 'CNY' }
  }

  /** 用 API Key 走 DeepSeek 官方余额接口。 */
  async function readApiKeyBalance(key) {
    const res = await fetch(BALANCE_URL, {
      headers: { Authorization: 'Bearer ' + key, Accept: 'application/json' },
      signal: AbortSignal.timeout(20000),
    })
    if (!res.ok) throw new Error('HTTP ' + res.status)
    let data
    try {
      data = await res.json()
    } catch (err) {
      throw new Error('余额接口返回不是合法 JSON')
    }
    const infos = Array.isArray(data && data.balance_infos) ? data.balance_infos : []
    const num = (x) => (x && x.total_balance !== undefined ? Number(x.total_balance) : NaN)
    const info =
      infos.find((x) => x && x.currency === 'CNY' && num(x) > 0) ||
      infos.find((x) => x && x.currency === 'CNY') ||
      infos.find((x) => num(x) > 0) ||
      infos[0]
    if (!info || info.total_balance === undefined) throw new Error('余额接口返回结构异常')
    return { totalBalance: Number(info.total_balance), currency: String(info.currency || 'CNY') }
  }

  function failure(code, error, transient) {
    return { ok: false, code, error, ...(transient === undefined ? {} : { transient }) }
  }

  function isTransient(error) {
    return !/^HTTP 4\d\d/.test(messageOf(error))
  }

  async function loadBalance() {
    if (overrideKey !== null) {
      try {
        const payload = await readApiKeyBalance(overrideKey)
        return { ok: true, ...payload, updatedAt: new Date().toISOString() }
      } catch (error) {
        return failure('KEY', 'API Key 查询余额失败: ' + messageOf(error), isTransient(error))
      }
    }
    try {
      const account = await readAccountBalance()
      if (account !== null) {
        return { ok: true, ...account, updatedAt: new Date().toISOString() }
      }
    } catch (error) {
      ctx.logger?.warn?.('dsh-vk1-balance-pet: 账号余额读取失败: ' + messageOf(error))
    }
    let credential
    try {
      credential = await ctx.credentials.resolve('DEEPSEEK_API_KEY')
    } catch (error) {
      ctx.logger?.warn?.('dsh-vk1-balance-pet: 凭据读取失败: ' + messageOf(error))
    }
    if (credential && credential.value) {
      try {
        const payload = await readApiKeyBalance(credential.value)
        return { ok: true, ...payload, updatedAt: new Date().toISOString() }
      } catch (error) {
        return failure('KEY', 'API Key 查询余额失败: ' + messageOf(error), isTransient(error))
      }
    }
    return failure('NO_KEY', '未登录 DeepSeek 账号，也未配置 DEEPSEEK_API_KEY')
  }

  function getBalance() {
    const now = Date.now()
    if (balanceCache !== null && now - balanceCache.at < BALANCE_TTL_MS) {
      return Promise.resolve(balanceCache.payload)
    }
    if (balanceInFlight !== null) return balanceInFlight
    balanceInFlight = loadBalance()
      .then((payload) => {
        if (payload.ok) {
          balanceCache = { at: now, payload }
          return payload
        }
        if (payload.transient && balanceCache !== null) {
          return { ...balanceCache.payload, stale: true, error: payload.error }
        }
        return payload
      })
      .catch((error) => failure('ERROR', '余额服务异常: ' + messageOf(error)))
      .finally(() => { balanceInFlight = null })
    return balanceInFlight
  }

  // --------------------------------------------------------------- 会话 ---

  async function readSessionBody(req) {
    const chunks = []
    let size = 0
    for await (const chunk of req) {
      size += chunk.length
      if (size > MAX_SESSION_BODY) throw new Error('请求体过大')
      chunks.push(chunk)
    }
    if (size === 0) return {}
    try {
      return JSON.parse(Buffer.concat(chunks).toString('utf8'))
    } catch (error) {
      throw new Error('请求体不是合法 JSON')
    }
  }

  // --------------------------------------------------------------- 路由 ---

  for (const [routePath, [file, type]] of Object.entries(STATIC_ROUTES)) {
    disposers.push(ctx.webServer.register({
      kind: 'exact',
      path: routePath,
      handler: (req, res) => {
        try {
          const bytes = readPackageFile(file)
          res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store', 'Content-Length': String(bytes.length) })
          res.end(bytes)
        } catch (error) {
          res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' })
          res.end(file + ' 不可用: ' + messageOf(error))
        }
      },
    }))
  }

  disposers.push(ctx.webServer.register({
    kind: 'exact',
    path: '/vk-1/api/balance',
    handler: async (req, res) => {
      try {
        sendJson(res, 200, await getBalance())
      } catch (error) {
        sendJson(res, 200, failure('ERROR', '余额服务异常: ' + messageOf(error)))
      }
    },
  }))

  disposers.push(ctx.webServer.register({
    kind: 'exact',
    path: '/vk-1/api/session',
    handler: async (req, res) => {
      try {
        if (req.method === 'GET') {
          sendJson(res, 200, { ok: true, connected: overrideKey !== null, source: overrideKey !== null ? 'api-key' : 'dsh-account' })
          return
        }
        if (req.method === 'DELETE') {
          overrideKey = null
          balanceCache = null
          sendJson(res, 200, { ok: true })
          return
        }
        if (req.method !== 'POST') {
          sendJson(res, 405, { ok: false, error: '只支持 GET / POST / DELETE' })
          return
        }
        const body = await readSessionBody(req)
        const key = typeof (body && body.key) === 'string' ? body.key.trim() : ''
        if (!/^sk-[A-Za-z0-9_-]{8,}$/.test(key)) {
          sendJson(res, 400, { ok: false, error: 'API Key 格式不正确（应以 sk- 开头）' })
          return
        }
        let payload
        try {
          payload = await readApiKeyBalance(key)
        } catch (error) {
          sendJson(res, 400, { ok: false, error: '连接失败：' + messageOf(error) })
          return
        }
        overrideKey = key
        balanceCache = { at: Date.now(), payload: { ok: true, ...payload, updatedAt: new Date().toISOString() } }
        sendJson(res, 200, { ok: true, totalBalance: payload.totalBalance, currency: payload.currency })
      } catch (error) {
        sendJson(res, 400, { ok: false, error: messageOf(error) })
      }
    },
  }))

  // 结构化 index 注入：
  //   - 浏览器版（dsh web）由 frontend-static 的 renderIndex 在服务端渲染；
  //   - 桌面版 index.html 由 Electron 直接从前端 dist 提供，但启动时会把
  //     collectIndexInjections() 的结果经 IPC 交给页面，由页面按 kind 应用
  //     （script-src 走 <script src>），所以这一条在两种形态下都生效。
  // 不用 tapIndex：桌面版根本不经过 renderIndex，字符串变换不会被执行。
  const LOADER_SRC = '/vk-1/loader.js'
  const indexInject = (table) => {
    if (table.some((row) => row && row.kind === 'script-src' && row.src === LOADER_SRC)) return
    table.push({ kind: 'script-src', placement: 'body', src: LOADER_SRC })
  }
  ctx.on('webserver/index-inject', indexInject)

  // 诊断：确认路由与 index 注入都在当前 Host 里生效（桌面版需要重启一次才吃到启动快照）。
  disposers.push(ctx.webServer.register({
    kind: 'exact',
    path: '/vk-1/api/diag',
    handler: (req, res) => {
      let injections = []
      try {
        injections = ctx.webServer.collectIndexInjections()
      } catch (error) { /* 收集失败不致命 */ }
      sendJson(res, 200, {
        ok: true,
        routes: Object.keys(STATIC_ROUTES).concat(['/vk-1/api/balance', '/vk-1/api/session', '/vk-1/api/diag']),
        indexInjections: injections.map((row) => ({ kind: row.kind, placement: row.placement, src: row.src })),
        loaderInjected: injections.some((row) => row.kind === 'script-src' && row.src === LOADER_SRC),
      })
    },
  }))

  ctx.effect(() => () => {
    for (const dispose of disposers) {
      try { dispose() } catch (error) { /* 已被移除的路由忽略 */ }
    }
  }, 'dsh-vk1-balance-pet.routes')
}

export { name, inject, apply }
