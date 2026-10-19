import assert from 'node:assert/strict'
import { apply, name, inject } from './lib/index.js'

const routes = new Map()
const listeners = new Map()
const disposers = []

const ctx = {
  logger: { warn: (...args) => console.warn('[warn]', ...args) },
  webServer: {
    register(route) {
      const key = route.kind + ' ' + route.path
      assert.equal(routes.has(key), false, 'duplicate route ' + key)
      routes.set(key, route)
      return () => routes.delete(key)
    },
    tapIndex() {
      throw new Error('tapIndex 不应再被使用：桌面版不经过 renderIndex')
    },
    collectIndexInjections() {
      const table = []
      for (const listener of listeners.get('webserver/index-inject') ?? []) listener(table)
      return table
    },
  },
  on(event, listener) {
    const list = listeners.get(event) ?? []
    list.push(listener)
    listeners.set(event, list)
    return () => {}
  },
  credentials: {
    async resolve() {
      return undefined
    },
  },
  deepseekAccount: {
    async getBalance() {
      return {
        status: 'ready',
        value: [{ currency: 'CNY', balance: '12.34' }],
        bonusWallets: [{ currency: 'CNY', balance: '1.00' }],
      }
    },
  },
  effect(fn) {
    const dispose = fn()
    if (typeof dispose === 'function') disposers.push(dispose)
  },
}

console.log('name:', name, 'inject:', inject.join(','))
apply(ctx)

// 1. 结构化 index 注入（桌面版唯一生效的方式）
const injections = ctx.webServer.collectIndexInjections()
const loaderRow = injections.find((row) => row.kind === 'script-src' && row.src === '/vk-1/loader.js')
assert.ok(loaderRow, '缺少 loader script-src 注入行')
console.log('index injection ok:', JSON.stringify(loaderRow))

// 2. 余额接口：账号额度 = 12.34 + 1.00
async function call(path, method = 'GET') {
  const route = routes.get('exact ' + path)
  assert.ok(route, '缺少路由 ' + path)
  let status = 0
  let body = ''
  const res = {
    writeHead(code) { status = code },
    end(chunk) { body += chunk ?? '' },
  }
  const req = { method, async *[Symbol.asyncIterator]() {} }
  await route.handler(req, res)
  return { status, json: body ? JSON.parse(body) : undefined, body }
}

const balance = await call('/vk-1/api/balance')
assert.equal(balance.status, 200)
assert.equal(balance.json.ok, true)
assert.equal(balance.json.totalBalance, 13.34)
assert.equal(balance.json.currency, 'CNY')
console.log('balance ok:', JSON.stringify(balance.json))

// 3. 诊断接口能看到注入行
const diag = await call('/vk-1/api/diag')
assert.equal(diag.json.loaderInjected, true)
console.log('diag ok: routes=' + diag.json.routes.length)

// 4. 静态资源路由齐全
for (const path of ['/vk-1/widget.js', '/vk-1/loader.js', '/vk-1/assets/expression_11.png', '/vk-1/assets/rice.png', '/vk-1/assets/hit.mp3']) {
  assert.ok(routes.has('exact ' + path), '缺少静态路由 ' + path)
}
console.log('static routes ok:', routes.size)

// 5. 卸载后路由清空（ctx.effect disposer）
for (const dispose of disposers) dispose()
assert.equal(routes.size, 0, '卸载后路由应全部移除')
console.log('SELFTEST PASS')
