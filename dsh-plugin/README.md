# VK-1 余额桌宠 · DSH 插件版

把本仓库的网页嵌入实现（`integration/`）打包成一个 **DeepSeek Harness bundle**，装进 DSH 后，
DSH 窗口右下角就会出现举着平板的角色，实时显示你的 DeepSeek 余额。

和原生 Windows / macOS 版相比，这是**窗口内挂件**：不跨应用置顶，不开原生窗口，
不额外安装运行时；跟着 DSH 界面一起加载，透明像素点击穿透保留。

## 功能

- 角色举平板显示余额；余额每下降 0.01 元，红闪 + 抖动 + 打击音效 + 头顶飘出 `-0.01`（0.2 秒一次串成一条）。
- 充值（余额上升）时右侧掉下米饭盆，**拖到角色身上**才一次性入账；10 秒不喂会被吸走。
- 米饭盆被吃掉的位置掉出**铁盆**：能拖、能扣在她头上，双击她的头取下。
- 四种表情：开心 / 紧张（扣费时）/ 傲娇（盆放太久）/ 冷脸（铁盆扣头时）。
- 有米饭盆时显示《战争雷霆》风格**火控雷达名牌**（距离 / 接近率 / 相对高度 / 方向环）。
- 右键（触屏长按）菜单：立即刷新余额 / 测试扣费 / 测试充值动画 / 演示连续扣费 / 尺寸 / 声音 / 位置 / 退出。
- 拖拽、位置与尺寸记忆、音效开关与音量，都存在本地。

## 余额从哪来（都由 DSH 宿主侧完成，凭据不进浏览器）

按优先级：

1. **DSH 已登录账号**：直接读充值 + 赠金额度，**不需要 API Key**；
2. 菜单里「连接 DeepSeek 余额…」临时填写的 API Key：只存 DSH 进程内存，断开或退出即清除；
3. DSH 凭据服务里的 `DEEPSEEK_API_KEY`。

## 它是怎么被加载的（关键）

- 宿主侧 `lib/index.js` 注册 `/vk-1/` 路由（挂件、素材、余额接口），并通过
  **`webserver/index-inject` 事件**登记一条 `script-src` 注入行，由 DSH 在自己的 index 里插入
  `/vk-1/loader.js`。
- 桌面版 DSH 的 index.html 由 Electron 直接读前端 dist 提供，**不经过** Host 的
  `webServer.renderIndex`，所以**不能用 `webServer.tapIndex`**（字符串改写不会被执行，
  社区旧插件就是因为这个在桌面版里一直不显示）。结构化注入行在桌面版由启动注入快照应用，
  在浏览器版（`dsh web`）由服务端渲染，两种形态都生效。
- 桌面版的启动注入快照在 **Host 启动时**采集，所以**安装或更新插件后必须重启一次 DSH 应用**
  （托盘 → 退出，再打开），页面上按 Ctrl+R 刷新不够。

## 安装

在 DSH 里让插件管理器从本地路径安装：

```text
C:\Users\闲鱼\Documents\deepseek-harness\bluefatfish-pet-plugin\dsh-plugin
```

安装后重启 DSH。之后可用 `/vk-1/api/diag` 检查路由与注入行是否生效。

## 目录

| 文件 | 作用 |
| --- | --- |
| `lib/index.js` | 宿主侧：注册 `/vk-1/` 路由，提供 `/vk-1/api/balance`、`/vk-1/api/session`、`/vk-1/api/diag`，并登记 index 注入行 |
| `widget.js` / `loader.js` | 页面挂件，由 `integration/` 的构建产出（社区 widget 1.0.2 + 37 条审计补丁） |
| `assets/` | 四张表情差分、米饭盆、铁盆、两个音效 |
| `cordis.patch.yml` | bundle 补丁层：向 Loader 插入宿主入口 |
| `build.mjs` | 重新生成 `widget.js` / `loader.js` / `assets/` |
| `selftest.mjs` | 用 mock Host ctx 自检：注入行、余额接口、路由和卸载（`node selftest.mjs`） |

## 重新生成页面挂件

```sh
git clone https://github.com/YCTS-otree/VK-1.git community-reference
git -C community-reference checkout 696e8915e37ed3c12d35feff9bcd7702d1be6247
node dsh-plugin/build.mjs dsh-1.0.0 community-reference
```

`integration/build.mjs` 会校验上游 commit 与每个文件的 sha256，补丁锚点不唯一就拒绝构建。

## 卸载 / 停用

插件管理器里停用或移除 `dsh-vk1-balance-pet`，然后重启 DSH，挂件即消失。
如果只想去掉挂件、保留依赖，停用 bundle 即可。
