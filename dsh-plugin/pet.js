// ============================================================================
// dsh-vk1-pet —— 浏览器侧（桌宠本体）
// ============================================================================
// 上游 VK-1 的 Windows 桌宠是 WinForms + 逐像素透明窗口，这里改成页面内浮层：
//   · 角色立绘 + 一块透明平板，余额画在平板上；
//   · 余额每跌 0.01 就红闪 + 抖 + 打击音，头顶飘 -0.01，0.2 秒一次串成一条；
//   · 余额涨了 → 右侧掉一盆米饭，拖到角色身上才入账；
//   · 吃掉的盆会留下一个铁盆，扣在头上变冷脸，双击头取下来。
//
// 约定：
//   · 不依赖任何框架，不碰 DSH 的 DOM 结构，只往 document.body 挂一个 fixed 层；
//   · 容器 pointer-events:none，只有「命中椭圆」和道具接鼠标，透明区域不挡点击；
//   · 任何异常都自己吞掉，绝不把宿主页面搞崩。
// ============================================================================

;(function () {
  'use strict'

  if (window.__DSH_VK1_PET__) return
  window.__DSH_VK1_PET__ = true

  var PREFIX = '/dsh-vk1'
  var STORE_KEY = 'dsh-vk1-pet:v1'
  var POLL_MS = 3000
  var TICK_MS = 200
  var TICK_MAX = 40
  var POT_TIMEOUT_MS = 10000

  var SIZES = [200, 240, 280, 340, 420, 520, 640]
  var SIZE_MIN = 160
  var SIZE_MAX = 800

  // 平板在立绘里的精确位置（对 1024² 立绘逐像素量出来的四角）：
  //   TL(559,702) TR(942,642) BR(980,858) BL(587,919)
  //   → 中心 (74.90%, 76.20%)、宽 37.86%、高 21.37%、顶边倾角 −8.9°
  var PLATE = { left: 74.9, top: 76.2, width: 37.86, height: 21.37, angle: -8.9 }
  var ART = {
    happy: PREFIX + '/assets/expression_11.png',
    nervous: PREFIX + '/assets/expression_22.png',
    aloof: PREFIX + '/assets/expression_12.png',
    calm: PREFIX + '/assets/expression_21.png',
  }

  var state = {
    size: null,
    sound: true,
    hidden: false,
    left: null,
    bottom: 18,
  }
  try {
    var saved = JSON.parse(localStorage.getItem(STORE_KEY) || 'null')
    if (saved && typeof saved === 'object') {
      // 老版本存的是 small/medium/large，按像素迁移（都往小里挪一档，旧版整体偏大）
      var legacy = { small: 240, medium: 340, large: 520 }
      var size = saved.size
      if (typeof size === 'string' && legacy[size]) size = legacy[size]
      if (typeof size === 'number' && isFinite(size) && size >= SIZE_MIN && size <= SIZE_MAX) state.size = size
      if (typeof saved.sound === 'boolean') state.sound = saved.sound
      if (typeof saved.hidden === 'boolean') state.hidden = saved.hidden
      if (typeof saved.left === 'number' && isFinite(saved.left)) state.left = saved.left
      if (typeof saved.bottom === 'number' && isFinite(saved.bottom)) state.bottom = saved.bottom
    }
  } catch (err) {
    /* 存档坏了就用默认值 */
  }

  function persist() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(state))
    } catch (err) {
      /* ignore */
    }
  }

  // ---------------------------------------------------------------- 音效 --
  var audio = {}
  function sound(name, volume) {
    if (!state.sound) return
    try {
      var pool = audio[name]
      if (!pool) {
        pool = audio[name] = []
        for (var i = 0; i < 3; i++) {
          var a = new Audio(PREFIX + '/assets/' + name + '.mp3')
          a.preload = 'auto'
          pool.push(a)
        }
      }
      var el = pool[(pool.__next = ((pool.__next || 0) + 1) % pool.length)]
      el.volume = Math.max(0, Math.min(1, volume === undefined ? 0.55 : volume))
      el.currentTime = 0
      var p = el.play()
      if (p && typeof p.catch === 'function') p.catch(function () {})
    } catch (err) {
      /* 没声音不影响功能 */
    }
  }

  // ---------------------------------------------------------------- 样式 --
  var CSS = [
    '#dsh-vk1-root{position:fixed;z-index:2147483000;pointer-events:none;user-select:none;-webkit-user-select:none;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif}',
    '#dsh-vk1-root *{box-sizing:border-box}',
    '.vk1-sprite{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;pointer-events:none;transition:filter .12s linear}',
    '.vk1-hit{position:absolute;left:44%;top:26%;width:54%;height:62%;border-radius:46% 54% 48% 52%/44% 46% 54% 56%;pointer-events:auto;cursor:grab;touch-action:none}',
    '.vk1-hit.vk1-drag{cursor:grabbing}',
    '.vk1-plate{position:absolute;left:' +
      PLATE.left +
      '%;top:' +
      PLATE.top +
      '%;width:' +
      PLATE.width +
      '%;height:' +
      PLATE.height +
      '%;transform:translate(-50%,-50%) rotate(' +
      PLATE.angle +
      'deg);transform-origin:50% 50%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6%;pointer-events:none;color:#eaf2ff;text-shadow:0 0 6px rgba(70,140,255,.45)}',
    '.vk1-plate-label{letter-spacing:.06em;color:#8fb4ea;font-weight:600;line-height:1}',
    '.vk1-plate-amount{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:.01em;line-height:1}',
    '.vk1-plate-offline .vk1-plate-amount{color:#7d8ba1;text-shadow:none}',
    '.vk1-flash{animation:vk1-flash .18s linear}',
    '@keyframes vk1-flash{0%{filter:brightness(1)}40%{filter:brightness(1.35) drop-shadow(0 0 14px rgba(255,60,60,.95))}100%{filter:brightness(1)}}',
    '.vk1-shake{animation:vk1-shake .16s linear}',
    '@keyframes vk1-shake{0%{transform:translate(0,0) rotate(0)}25%{transform:translate(-5px,2px) rotate(-1.2deg)}50%{transform:translate(5px,-2px) rotate(1.2deg)}75%{transform:translate(-3px,1px) rotate(-.6deg)}100%{transform:translate(0,0) rotate(0)}}',
    '.vk1-wear{animation:vk1-wear .22s linear infinite}',
    '@keyframes vk1-wear{0%{transform:rotate(-1.1deg)}50%{transform:rotate(1.1deg)}100%{transform:rotate(-1.1deg)}}',
    '.vk1-float{position:absolute;pointer-events:none;font-family:ui-monospace,Consolas,monospace;font-weight:700;white-space:nowrap;text-shadow:0 1px 3px rgba(0,0,0,.65);animation:vk1-rise .95s ease-out forwards}',
    '@keyframes vk1-rise{0%{opacity:0;transform:translate(-50%,6px) scale(.9)}18%{opacity:1}100%{opacity:0;transform:translate(-50%,-46px) scale(1.02)}}',
    '.vk1-drain{color:#ff5a5a}',
    '.vk1-credit{color:#5ce08a}',
    '.vk1-rice{position:absolute;pointer-events:auto;cursor:grab;touch-action:none;filter:drop-shadow(0 6px 10px rgba(0,0,0,.45));transition:opacity .25s linear}',
    '.vk1-rice-drop{animation:vk1-drop .62s cubic-bezier(.33,.66,.45,1)}',
    '@keyframes vk1-drop{0%{transform:translateY(-240%);opacity:.35}58%{transform:translateY(0);opacity:1}72%{transform:translateY(-16%)}86%{transform:translateY(0)}94%{transform:translateY(-5%)}100%{transform:translateY(0)}}',
    '.vk1-rice-tag{position:absolute;left:50%;top:-18px;transform:translateX(-50%);color:#ffd479;font-size:11px;font-weight:700;white-space:nowrap;text-shadow:0 1px 3px #000}',
    '.vk1-pot{position:absolute;pointer-events:auto;cursor:grab;touch-action:none;filter:drop-shadow(0 4px 8px rgba(0,0,0,.5))}',
    '.vk1-menu{position:fixed;min-width:178px;background:#1b2233;border:1px solid rgba(120,160,230,.35);border-radius:10px;box-shadow:0 14px 34px rgba(0,0,0,.55);padding:6px;pointer-events:auto;font-size:12.5px;color:#dfe7f5;z-index:2147483001}',
    '.vk1-menu button{display:flex;align-items:center;justify-content:space-between;gap:12px;width:100%;background:none;border:0;color:inherit;font:inherit;padding:7px 9px;border-radius:7px;cursor:pointer;text-align:left}',
    '.vk1-menu button:hover{background:rgba(120,170,255,.18)}',
    '.vk1-menu .vk1-sep{height:1px;margin:4px 6px;background:rgba(120,160,230,.22)}',
    '.vk1-menu .vk1-meta{color:#8b9ab5;font-size:11px;padding:2px 9px 4px}',
    '.vk1-menu .vk1-on{color:#6fc7ff;font-weight:700}',
    '.vk1-sizes{display:grid;grid-template-columns:repeat(4,1fr);gap:4px;padding:2px 8px 7px}',
    '.vk1-sizes button{display:block;width:100%;padding:5px 0;border-radius:6px;border:1px solid rgba(120,160,230,.25);background:rgba(120,170,255,.06);color:#c8d4e8;font:inherit;font-size:11px;cursor:pointer;text-align:center}',
    '.vk1-sizes button:hover{background:rgba(120,170,255,.2)}',
    '.vk1-sizes button.vk1-on{border-color:#6fc7ff;color:#6fc7ff;background:rgba(111,199,255,.16);font-weight:700}',
    '.vk1-restore{position:fixed;left:14px;bottom:10px;width:14px;height:14px;border-radius:50%;background:rgba(120,170,255,.35);border:1px solid rgba(160,200,255,.5);cursor:pointer;z-index:2147483000;pointer-events:auto;opacity:.45}',
    '.vk1-restore:hover{opacity:1}',
  ].join('')

  function ensureStyle() {
    if (document.getElementById('dsh-vk1-style')) return
    var tag = document.createElement('style')
    tag.id = 'dsh-vk1-style'
    tag.textContent = CSS
    document.head.appendChild(tag)
  }

  // ---------------------------------------------------------------- 主体 --
  var root = null
  var sprite = null
  var plate = null
  var plateAmount = null
  var hit = null
  var floatLayer = null
  var menu = null

  var booked = null // 显示出来的余额
  var real = null // 服务端给的余额
  var bonus = 0 // 赠送钱包（设置页里单独一行，这里只进菜单）
  var expression = 'happy'
  var tickTimer = null
  var tickQueue = 0
  var pot = null
  var potAmount = 0
  var potTimer = null
  var ironPot = null
  var worn = false
  var polling = false
  var restoreChip = null

  var lastError = null

  // 首次运行按窗口高度选档：小窗口默认更小，免得挡住界面按钮
  if (state.size === null) state.size = window.innerHeight >= 1000 ? 340 : window.innerHeight >= 800 ? 280 : 240

  // 实际绘制尺寸：不超过视口的 80%，防止选了大档在小窗口里溢出。
  // 调试/截图时可用 ?vk1size=420 强制指定（绕过视口上限，只在自检页用得上）。
  function sizePx() {
    var forced = forcedSize()
    if (forced !== null) return forced
    var cap = Math.min(window.innerWidth, window.innerHeight) * 0.8
    return Math.round(Math.min(state.size, cap))
  }

  function forcedSize() {
    try {
      var raw = new URLSearchParams(window.location.search).get('vk1size')
      if (!raw) return null
      var n = Number(raw)
      return isFinite(n) && n >= SIZE_MIN && n <= SIZE_MAX ? Math.round(n) : null
    } catch (err) {
      return null
    }
  }

  function sizeOrDefault() {
    return state.size || 280
  }

  function fmt(value) {
    if (value === null || !isFinite(value)) return '--'
    return Number(value).toFixed(2)
  }

  function renderAmount() {
    if (!plateAmount) return
    plateAmount.textContent = fmt(booked)
    plate.classList.toggle('vk1-plate-offline', booked === null)
  }

  function setExpression(name) {
    if (!sprite || expression === name) return
    expression = name
    sprite.src = ART[name] || ART.happy
  }

  function layout() {
    if (!root) return
    var px = sizePx()
    root.style.width = px + 'px'
    root.style.height = px + 'px'
    // 字号跟着平板走：平板高 = px*21.37%，标签 + 金额要装得下
    if (plate) plate.style.fontSize = px * 0.032 + 'px'
    if (plateAmount) plateAmount.style.fontSize = px * 0.072 + 'px'
    clampPosition()
    applyPosition()
    if (state.hidden) root.style.display = 'none'
  }

  function clampPosition() {
    var px = sizePx()
    var maxLeft = Math.max(0, window.innerWidth - px * 0.72)
    var maxBottom = Math.max(0, window.innerHeight - px * 0.55)
    if (state.left === null) state.left = 18
    state.left = Math.min(Math.max(0, state.left), maxLeft)
    state.bottom = Math.min(Math.max(0, state.bottom), maxBottom)
  }

  function applyPosition() {
    root.style.left = state.left + 'px'
    root.style.bottom = state.bottom + 'px'
  }

  function ensureRoot() {
    if (root) return root
    ensureStyle()
    root = document.createElement('div')
    root.id = 'dsh-vk1-root'

    sprite = document.createElement('img')
    sprite.className = 'vk1-sprite'
    sprite.alt = ''
    sprite.draggable = false
    sprite.src = ART.happy

    plate = document.createElement('div')
    plate.className = 'vk1-plate'
    var label = document.createElement('div')
    label.className = 'vk1-plate-label'
    label.textContent = 'DSH 余额'
    plateAmount = document.createElement('div')
    plateAmount.className = 'vk1-plate-amount'
    plateAmount.textContent = '--'
    plate.appendChild(label)
    plate.appendChild(plateAmount)

    floatLayer = document.createElement('div')
    floatLayer.style.cssText = 'position:absolute;inset:0;pointer-events:none'

    hit = document.createElement('div')
    hit.className = 'vk1-hit'

    root.appendChild(sprite)
    root.appendChild(plate)
    root.appendChild(floatLayer)
    root.appendChild(hit)
    document.body.appendChild(root)

    bindPetEvents()
    layout()
    return root
  }

  function showPet() {
    ensureRoot()
    state.hidden = false
    persist()
    root.style.display = ''
    if (restoreChip) {
      restoreChip.remove()
      restoreChip = null
    }
  }

  function hidePet() {
    state.hidden = true
    persist()
    if (root) root.style.display = 'none'
    if (!restoreChip) {
      restoreChip = document.createElement('div')
      restoreChip.className = 'vk1-restore'
      restoreChip.title = '显示 VK-1 余额桌宠'
      restoreChip.addEventListener('click', showPet)
      document.body.appendChild(restoreChip)
    }
  }

  // ---------------------------------------------------------- 余额与动画 --
  function floatText(text, cls, x, y) {
    if (!floatLayer) return
    var el = document.createElement('div')
    el.className = 'vk1-float ' + (cls || 'vk1-drain')
    el.textContent = text
    el.style.left = (x === undefined ? 73 : x) + '%'
    el.style.top = (y === undefined ? 15 : y) + '%'
    floatLayer.appendChild(el)
    setTimeout(function () {
      el.remove()
    }, 1000)
  }

  function shakePet() {
    if (!root) return
    root.classList.remove('vk1-shake')
    // 强制重排让动画能重播
    void root.offsetWidth
    root.classList.add('vk1-shake')
    setTimeout(function () {
      root.classList.remove('vk1-shake')
    }, 200)
  }

  function flashPet() {
    if (!sprite) return
    sprite.classList.remove('vk1-flash')
    void sprite.offsetWidth
    sprite.classList.add('vk1-flash')
    setTimeout(function () {
      sprite.classList.remove('vk1-flash')
    }, 200)
  }

  function oneTick() {
    flashPet()
    shakePet()
    sound('hit', 0.5)
    var old = booked
    booked = Math.max(0, Number((booked - 0.01).toFixed(2)))
    renderAmount()
    floatText('-' + Number(Math.min(0.01, Math.max(0, old - booked)).toFixed(2)), 'vk1-drain')
  }

  function runTicks(count) {
    tickQueue = Math.min(TICK_MAX, tickQueue + count)
    if (tickTimer !== null) return
    setExpression('nervous')
    tickTimer = setInterval(function () {
      if (tickQueue <= 0 || booked === null || real === null) {
        clearInterval(tickTimer)
        tickTimer = null
        tickQueue = 0
        if (booked !== null && real !== null) booked = real
        renderAmount()
        setExpression(worn ? 'calm' : pot ? 'aloof' : 'happy')
        return
      }
      tickQueue -= 1
      oneTick()
      if (tickQueue <= 0 && real !== null) {
        // 最后把差值补齐（-0.01 舍入之外的零头）
        booked = real
        renderAmount()
      }
    }, TICK_MS)
  }

  function applyServerBalance(payload) {
    if (!payload || payload.ok !== true || typeof payload.total !== 'number') {
      lastError = payload && payload.error ? String(payload.error).slice(0, 120) : '返回结构异常'
      if (booked === null) {
        renderAmount()
        if (plate) plate.classList.add('vk1-plate-offline')
      }
      return
    }
    lastError = null
    bonus = typeof payload.bonus === 'number' && isFinite(payload.bonus) ? payload.bonus : 0
    var value = Number(payload.total)
    if (!isFinite(value)) return
    var first = real === null && booked === null
    real = value

    if (first) {
      booked = value
      renderAmount()
      return
    }
    if (tickTimer !== null) {
      // 正在扣费动画中：只更新目标值，动画收尾时对齐
      return
    }
    if (booked === null) {
      booked = value
      renderAmount()
      return
    }
    var delta = value - booked
    if (delta <= -0.005) {
      var count = Math.round(Math.min(TICK_MAX, -delta / 0.01))
      runTicks(Math.max(1, count))
      return
    }
    if (delta >= 0.005) {
      dropRicePot(delta)
      return
    }
    booked = value
    renderAmount()
  }

  function poll() {
    if (polling) return
    polling = true
    fetch(PREFIX + '/balance.json', { cache: 'no-store' })
      .then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status)
        return res.json()
      })
      .then(applyServerBalance)
      .catch(function (error) {
        lastError = '请求失败（' + String((error && error.message) || error) + '）'
        if (booked === null) renderAmount()
      })
      .then(function () {
        polling = false
      })
  }

  // -------------------------------------------------------------- 米饭盆 --
  function petRect() {
    var r = root.getBoundingClientRect()
    return { left: r.left, top: r.top, width: r.width, height: r.height }
  }

  function dropRicePot(amount) {
    if (!root) return
    if (pot) {
      // 已经有盆没喂：把「还没入账的总额」对齐成差额，而不是一次次累加
      // （每轮 poll 都会算出同一个差额，累加会让金额翻倍）
      potAmount = Math.max(potAmount, amount)
      var tag = pot.querySelector('.vk1-rice-tag')
      if (tag) tag.textContent = '+' + fmt(potAmount)
      return
    }
    potAmount = amount
    pot = document.createElement('div')
    pot.className = 'vk1-rice'
    var px = sizePx()
    pot.style.width = Math.round(px * 0.19) + 'px'
    pot.style.height = Math.round(px * 0.19) + 'px'
    // 落在角色旁边：贴左边就落右侧，贴右边就落左侧，别盖住平板
    var onLeftHalf = state.left + px / 2 < window.innerWidth / 2
    pot.style.left = onLeftHalf ? px * 1.01 + 'px' : -px * 0.2 + 'px'
    pot.__side = onLeftHalf ? 1 : -1
    var potImg = document.createElement('img')
    potImg.src = PREFIX + '/assets/rice.png'
    potImg.draggable = false
    potImg.style.cssText = 'width:100%;height:100%;object-fit:contain;display:block;pointer-events:none'
    pot.appendChild(potImg)
    var tagEl = document.createElement('div')
    tagEl.className = 'vk1-rice-tag'
    tagEl.textContent = '+' + fmt(potAmount)
    pot.appendChild(tagEl)
    root.appendChild(pot)

    // 从上方落下 + 弹一下（用 CSS 动画：后台标签页里 rAF 会被节流，动画不会）
    pot.style.top = px * 0.62 + 'px'
    pot.classList.add('vk1-rice-drop')
    setTimeout(function () {
      if (!pot) return
      pot.classList.remove('vk1-rice-drop')
      sound('pot_land', 0.5)
      setTimeout(function () {
        if (pot) setExpression('aloof')
      }, POT_TIMEOUT_MS - 2500)
    }, 640)
    bindDrag(pot, {
      onDrop: function (clientX, clientY) {
        var r = petRect()
        var cx = r.left + r.width * 0.62
        var cy = r.top + r.height * 0.58
        var inside = Math.abs(clientX - cx) < r.width * 0.32 && Math.abs(clientY - cy) < r.height * 0.34
        if (inside) feedPot()
      },
    })

    potTimer = setTimeout(function () {
      if (!pot) return
      sound('pot_off', 0.4)
      pot.style.opacity = '0'
      var dying = pot
      pot = null
      setTimeout(function () {
        dying.remove()
      }, 280)
      // 盆被吸走：显示值直接追到服务端
      if (real !== null) {
        booked = real
        renderAmount()
      }
      setExpression('happy')
    }, POT_TIMEOUT_MS)
  }

  function feedPot() {
    if (!pot) return
    clearTimeout(potTimer)
    potTimer = null
    var amount = potAmount
    var dying = pot
    pot = null
    dying.remove()
    sound('feed', 0.6)
    if (real !== null) booked = real
    renderAmount()
    floatText('+' + fmt(amount), 'vk1-credit', 73, 12)
    setExpression('happy')
    spawnIronPot(dying.style.left, dying.style.top)
  }

  // ---------------------------------------------------------------- 铁盆 --
  function spawnIronPot(atLeft, atTop) {
    if (ironPot) return
    ironPot = document.createElement('img')
    ironPot.className = 'vk1-pot'
    ironPot.draggable = false
    ironPot.src = PREFIX + '/assets/iron_bowl.png'
    var px = sizePx()
    ironPot.style.width = Math.round(px * 0.26) + 'px'
    ironPot.style.height = 'auto'
    ironPot.style.left = atLeft || px * 1.01 + 'px'
    ironPot.style.top = atTop || px * 0.72 + 'px'
    root.appendChild(ironPot)
    bindDrag(ironPot, {
      onDrop: function (clientX, clientY) {
        var r = petRect()
        var headX = r.left + r.width * 0.7
        var headY = r.top + r.height * 0.22
        var onHead = Math.abs(clientX - headX) < r.width * 0.26 && Math.abs(clientY - headY) < r.height * 0.24
        if (onHead) wearIronPot()
      },
    })
  }

  function wearIronPot() {
    if (!ironPot || worn) return
    worn = true
    var px = sizePx()
    ironPot.style.left = px * 0.52 + 'px'
    ironPot.style.top = px * 0.02 + 'px'
    ironPot.style.width = Math.round(px * 0.34) + 'px'
    ironPot.classList.add('vk1-wear')
    setExpression('calm')
  }

  function removeIronPot() {
    if (!worn || !ironPot) return
    worn = false
    ironPot.classList.remove('vk1-wear')
    ironPot.remove()
    ironPot = null
    sound('pot_off', 0.3)
    setExpression(pot ? 'aloof' : 'happy')
  }

  // ------------------------------------------------------------ 拖拽基础 --
  function bindDrag(el, options) {
    var opts = options || {}
    var dragging = false
    var startX = 0
    var startY = 0
    var baseLeft = 0
    var baseTop = 0

    function down(event) {
      if (event.button !== 0) return
      dragging = true
      startX = event.clientX
      startY = event.clientY
      var parentRect = (el.parentElement || root).getBoundingClientRect()
      baseLeft = el.getBoundingClientRect().left - parentRect.left
      baseTop = el.getBoundingClientRect().top - parentRect.top
      el.style.transition = 'none'
      el.classList.add('vk1-drag')
      try {
        if (el.setPointerCapture) el.setPointerCapture(event.pointerId)
      } catch (err) {
        /* 合成事件没有活动指针，抓不到就算了 */
      }
      event.preventDefault()
      event.stopPropagation()
    }

    function move(event) {
      if (!dragging) return
      var dx = event.clientX - startX
      var dy = event.clientY - startY
      el.style.left = baseLeft + dx + 'px'
      el.style.top = baseTop + dy + 'px'
      event.preventDefault()
    }

    function up(event) {
      if (!dragging) return
      dragging = false
      el.classList.remove('vk1-drag')
      el.style.transition = ''
      if (typeof opts.onDrop === 'function') opts.onDrop(event.clientX, event.clientY)
      event.preventDefault()
      event.stopPropagation()
    }

    el.addEventListener('pointerdown', down)
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', up)
    el.addEventListener('pointercancel', up)
  }

  // ---------------------------------------------------------- 桌宠交互 --
  function bindPetEvents() {
    var dragging = false
    var startX = 0
    var startY = 0
    var baseLeft = 0
    var baseBottom = 0
    var moved = false

    hit.addEventListener('pointerdown', function (event) {
      if (event.button !== 0) return
      dragging = true
      moved = false
      startX = event.clientX
      startY = event.clientY
      baseLeft = state.left
      baseBottom = state.bottom
      hit.classList.add('vk1-drag')
      try {
        if (hit.setPointerCapture) hit.setPointerCapture(event.pointerId)
      } catch (err) {
        /* ignore */
      }
      event.preventDefault()
      event.stopPropagation()
    })

    hit.addEventListener('pointermove', function (event) {
      if (!dragging) return
      var dx = event.clientX - startX
      var dy = event.clientY - startY
      if (Math.abs(dx) + Math.abs(dy) > 3) moved = true
      state.left = baseLeft + dx
      state.bottom = baseBottom - dy
      clampPosition()
      applyPosition()
      event.preventDefault()
    })

    hit.addEventListener('pointerup', function (event) {
      if (!dragging) return
      dragging = false
      hit.classList.remove('vk1-drag')
      if (moved) {
        // 松手吸附到最近的底角
        var my = state.left + sizePx() * 0.36
        state.left = my < window.innerWidth / 2 ? 18 : window.innerWidth - sizePx() * 0.72 - 18
        clampPosition()
        applyPosition()
        persist()
      }
      event.preventDefault()
      event.stopPropagation()
    })

    hit.addEventListener('dblclick', function (event) {
      if (worn) {
        removeIronPot()
        event.preventDefault()
        event.stopPropagation()
      }
    })

    hit.addEventListener('contextmenu', function (event) {
      event.preventDefault()
      event.stopPropagation()
      openMenu(event.clientX, event.clientY)
    })
  }

  // ---------------------------------------------------------------- 菜单 --
  function closeMenu() {
    if (menu) {
      menu.remove()
      menu = null
    }
  }

  function menuButton(label, hint, onClick, active) {
    var b = document.createElement('button')
    var span = document.createElement('span')
    span.textContent = label
    b.appendChild(span)
    if (hint) {
      var tag = document.createElement('span')
      tag.textContent = hint
      tag.className = active ? 'vk1-on' : ''
      b.appendChild(tag)
    }
    b.addEventListener('click', function (event) {
      event.stopPropagation()
      closeMenu()
      onClick()
    })
    return b
  }

  function openMenu(x, y) {
    closeMenu()
    ensureRoot()
    menu = document.createElement('div')
    menu.className = 'vk1-menu'

    var amount = document.createElement('div')
    amount.className = 'vk1-meta'
    amount.textContent = '余额 ¥' + fmt(booked) + (real !== null && booked !== null && Math.abs(real - booked) > 0.004 ? '（服务端 ¥' + fmt(real) + '）' : '')
    menu.appendChild(amount)

    if (bonus > 0.004) {
      var bonusLine = document.createElement('div')
      bonusLine.className = 'vk1-meta'
      bonusLine.textContent = '赠送 ¥' + fmt(bonus) + '（不计入上面的余额）'
      menu.appendChild(bonusLine)
    }

    menu.appendChild(menuButton('立即刷新余额', '', poll))
    menu.appendChild(menuButton('测试扣费动画', '', function () {
      if (booked !== null) {
        tickQueue = 0
        flashPet()
        shakePet()
        sound('hit', 0.5)
        floatText('-0.01', 'vk1-drain')
      }
    }))
    menu.appendChild(menuButton('测试充值动画', '', function () {
      if (booked !== null) dropRicePot(1)
    }))

    var sep = document.createElement('div')
    sep.className = 'vk1-sep'
    menu.appendChild(sep)

    var sizes = SIZES
    var label = document.createElement('div')
    label.className = 'vk1-meta'
    label.textContent = '尺寸（当前 ' + sizePx() + ' px）'
    menu.appendChild(label)

    var grid = document.createElement('div')
    grid.className = 'vk1-sizes'
    for (var i = 0; i < sizes.length; i++) {
      ;(function (pxValue) {
        var b = document.createElement('button')
        b.textContent = String(pxValue)
        if (sizeOrDefault() === pxValue) b.classList.add('vk1-on')
        b.addEventListener('click', function (event) {
          // 换档不关菜单：方便连着试几档
          event.stopPropagation()
          state.size = pxValue
          persist()
          layout()
          var buttons = grid.querySelectorAll('button')
          for (var j = 0; j < buttons.length; j++) buttons[j].classList.toggle('vk1-on', buttons[j] === b)
          label.textContent = '尺寸（当前 ' + sizePx() + ' px）'
        })
        grid.appendChild(b)
      })(sizes[i])
    }
    menu.appendChild(grid)

    menu.appendChild(menuButton('声音', state.sound ? '开' : '关', function () {
      state.sound = !state.sound
      persist()
    }, state.sound))

    menu.appendChild(menuButton('隐藏桌宠', '', hidePet))

    if (lastError) {
      var errLine = document.createElement('div')
      errLine.className = 'vk1-meta'
      errLine.style.color = '#e2807a'
      errLine.textContent = '余额接口：' + lastError
      menu.appendChild(errLine)
    }

    var about = document.createElement('div')
    about.className = 'vk1-meta'
    about.textContent = 'VK-1 余额桌宠 · DSH 插件版'
    menu.appendChild(about)

    document.body.appendChild(menu)
    var rect = menu.getBoundingClientRect()
    var left = Math.min(x, window.innerWidth - rect.width - 8)
    var top = Math.min(y, window.innerHeight - rect.height - 8)
    menu.style.left = Math.max(8, left) + 'px'
    menu.style.top = Math.max(8, top) + 'px'

    setTimeout(function () {
      function outside(event) {
        if (menu && !menu.contains(event.target)) {
          closeMenu()
          document.removeEventListener('pointerdown', outside, true)
        }
      }
      document.addEventListener('pointerdown', outside, true)
    }, 0)
  }

  // ---------------------------------------------------------------- 启动 --
  function boot() {
    ensureRoot()
    if (state.hidden) hidePet()
    renderAmount()
    poll()
    setInterval(function () {
      if (!document.hidden) poll()
    }, POLL_MS)
    window.addEventListener('resize', function () {
      if (root) {
        clampPosition()
        applyPosition()
      }
    })
    // 托盘图标那种「双击就抖一下」的替代：页签可见性回来时立刻刷新一次
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) poll()
    })
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true })
  } else {
    boot()
  }
})()
