# dsh-plugin · VK-1 余额桌宠的 DSH 网页插件版

把本仓库的 Windows 桌宠（`windows/`）搬进 **DSH（DeepSeek Harness）网页界面**：角色待在页面左下角，举着的平板显示余额；扣费红闪受击、充值掉米盆、四表情与铁盆玩法都在。

> 这是本仓库自己维护的一份 DSH 移植，和 README 里提到的两个社区版（[@YCTS-otree](https://github.com/YCTS-otree/VK-1) · [@TsukiKenga](https://github.com/TsukiKenga/dsh-balance-pet-extend)）互不依赖，装一个即可。

## 为什么不能「直接装仓库」

DSH 的插件市场/`dsh plugin add` 要求包根目录有 `package.json` 且声明 `dsh.bundle.patch`。本仓库根目录是「Windows + macOS + 网页嵌入」三份实现的合集，没有这些文件，所以：

```
dsh plugin --profile desktop add github:VKmich16/VK-1
# pnpm 会装出一个占位包 VK-1@0.0.0（package.json 内容是 _pnpmPlaceholder）
# 随后 DSH 报：这个包没有声明组合包，不能作为插件管理（not-bundle），并回滚
```

**插件包在这个子目录里**，安装要指到它：

```powershell
# 本机路径（开发 / 自用）
dsh plugin --profile desktop add link:D:\path\to\VK-1\dsh-plugin

# 从 GitHub 安装：仓库根不是包，要用 path: 指到子目录
# PowerShell 里 # 之后会被当成注释，整条参数必须加引号
dsh plugin --profile desktop add "github:VKmich16/VK-1#path:/dsh-plugin"

# 还没合并、想直接试某个分支时：ref 和 path 用 & 连起来
dsh plugin --profile desktop add "github:<owner>/VK-1#<branch>&path:/dsh-plugin"
```

装完**刷新一次页面**（`webserver/index-inject` 的行是渲染 index 时现收的，已打开的页面不会自己长出来）。

### 装完看不到？两条通道时效不一样

| 你用的是 | 注入表从哪来 | 装完怎么生效 |
| --- | --- | --- |
| 网页版（浏览器开 `dsh web` 的地址） | 每次请求 `/` 现收 | 刷新页面即可 |
| 桌面版（Electron 窗口） | 宿主进程启动时收一次，经 IPC 交给壳后一直缓存 | **重启 DSH**（单纯 Ctrl+R 拿到的还是旧表） |

桌面版走这条是因为它的 `/` 是从 `dsh-web-frontend/dist` 直发的静态文件，不经过 `renderIndex`；注入行只随 `ready` 消息给一次。

## 它怎么取余额

三级来源，按顺序试，前一条能用就用；显示口径与 DSH 设置页「账户」一致（正常钱包是主余额，赠送钱包单独显示在菜单里，不合并）：

| 顺序 | 来源 | 走什么 |
| --- | --- | --- |
| 1 | **宿主账号服务**（设置页同一个实现） | `ctx.deepseekAccount.getBalance(client)`：请求头、token 刷新、401 失效都由宿主处理，插件不碰 token |
| 2 | DSH 账号凭证自己查 | `<issuer>/api/v0/users/get_user_summary`，头 `x-dsh-auth-token`（服务不可用/接口变动时兜底） |
| 3 | **DeepSeek API Key** | `https://api.deepseek.com/user/balance`，头 `Authorization: Bearer` |

都没有时平板显示 `--`，不报错、不影响 DSH 本身。凭据只在本机读取、只在内存里用，不落盘、不上传。

## 操作

| 操作 | 效果 |
| --- | --- |
| 左键拖角色 | 移动；松手吸附到最近的底角 |
| 拖米饭盆到角色身上 | 喂给她，充值的钱一次入账 |
| 拖铁盆到头上 | 扣在头上，她变冷脸并顶着盆抖 |
| 双击头（头顶有盆时） | 她弹一下，铁盆消失 |
| 右键 | 菜单：刷新余额 / 测试扣费 / 测试充值 / 尺寸 / 声音 / 隐藏 |

尺寸给了 **200 / 240 / 280 / 340 / 420 / 520 / 640** 七档，菜单里点哪档立刻生效、不用关菜单重新开；首次按窗口高度自动选一档（大屏 340，一般 280，小窗 240），另外绘制尺寸上限是视口短边的 80%，选大了也不会溢出屏幕。位置和档位都存在 `localStorage`，下次打开还在原处。

余额取不到时，平板显示 `--`，右键菜单底部会写出具体原因（接口 404 / HTTP 401 / 结构异常），不用猜。

米饭盆 **10 秒**不喂会被自动吸走（`pot_off` 音效），余额直接追到服务端值。

## 实现要点（给改代码的人）

- 宿主 `lib/index.js` 只做三件事：挂素材路由（白名单）、查余额归一化、往 `index.html` 注入一行引导脚本。
- 注入走 `webserver/index-inject` 的**内联 script 行**，自己建 `<script src>` 并吞掉 `onerror`：路由不在时静默失败，绝不连累宿主 boot。web 形态另注册 `tapIndex` 兜底。
- `credentials` 服务用 `ctx.get()` 读（可选服务），不写进 `inject`：老宿主上写进去会让整个插件永远不 apply。
- **`ctx.get('credentials')` 必须每次现取，不能存成常量**：boot 时 `webServer` 常比 `credentials` 先就绪，在 apply 里取一次就缓存，冷启动会永远拿到 `undefined`——症状是「刚开机时取不到余额，热重载一次又好了」。取不到时还有兜底：直接读 `<DSH_HOME>/.credentials.yaml`（只认 `deepseek-account-platform/default` 的 token/issuer 和 refs 里的 `DEEPSEEK_API_KEY`，不引 YAML 依赖）。
- `/dsh-vk1/balance.json` 带 `diag: {service, fileAccount, fileApiKey}` 三个布尔值（不含凭据内容），用来区分「服务没就绪」还是「凭据真的没有」。
- 浏览器侧 `pet.js` 是不依赖框架的单文件；容器 `pointer-events:none`，只有命中椭圆和道具接鼠标，透明区域不挡点击。
- 素材全部来自本仓库 `windows/`（MIT）。`iron_bowl.png` 从 2880² 缩到 640²，其余原样。
- **平板文字是按量出来的四边形贴的**：对 1024² 立绘取屏幕暗区的四角 → `TL(559,702) TR(942,642) BR(980,858) BL(587,919)`，得到中心 `(74.9%, 76.2%)`、宽 `37.86%`、高 `21.37%`、顶边倾角 `−8.9°`。四个表情差分位置一致。**换立绘要重新量**，否则文字会歪。
- 自检页支持 `?vk1size=420` 强制指定尺寸（绕过视口上限），截图核对几何时用。
- 宿主会在 `<DSH_HOME>/storages/dsh-vk1-pet/lifecycle.log` 记 `apply:start / apply:ok / routes:registered / routes:disposed`。插件"装上了却没反应"时先看这个文件：没有 `apply:ok` 说明卡在加载阶段，有 `routes:disposed` 说明实例被 dispose 过。
- 宿主对**加载失败**的 bundle 的处理是把它从 `dsh.profile.bundles` 里直接摘掉（路由 404、页面上的桌宠变成没有余额的空壳）。所以 `apply` 里所有可能抛的操作都包了 try/catch，路由重复注册也只记日志不抛。

## 许可

插件代码 MIT，与仓库一致；素材版权见根目录 `LICENSE` 与 README 的「许可」一节。
