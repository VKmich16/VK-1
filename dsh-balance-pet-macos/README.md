# DSH大肥鱼桌宠 · macOS

用于 DeepSeek Harness 的原生余额桌宠，基于本仓库中的 Windows 原版移植。1.3.1 支持四个内置角色：**蓝色大肥鱼、GPT龙娘、大小姐Claude、北美猫娘Gemini**，保留原版 `hit.mp3` 音效；余额在每个角色手持的倾斜平板内显示。

它是独立的 Swift + AppKit 应用，可读取 DSH 凭证；无需修改或持续运行 DSH。目前维护和支持 macOS 13+。

![蓝色大肥鱼与余额](docs/screenshots/01-connected.png)

## 构建与运行

需要 Xcode 命令行工具或 Xcode。无第三方依赖、无需联网下载包。

```sh
./build.sh
open 'dist/DSH大肥鱼桌宠.app'
```

默认编译当前机器架构。可选 `ARCH=arm64`、`ARCH=x86_64` 或 `ARCH=universal ./build.sh`；universal 同时包含 Apple Silicon 与 Intel。构建会验证临时签名，成功后替换同名产物，不清空整个 `dist` 目录。

应用不显示 Dock 图标，菜单栏有 ¥ 图标。首次出现在主屏左下角，之后记住位置。旧版本的 `DSHBalancePet` 配置目录沿用，原有偏好无需迁移。

## 操作

| 操作 | 效果 |
| --- | --- |
| 左键拖动 | 移动；默认松手吸附当前屏幕左下角，可关闭 |
| 右键 / Control + 单击 | 打开菜单 |
| 菜单栏 ¥ | 查看余额、凭证来源及操作菜单 |
| 切换角色 | 右键或菜单栏选择四个角色，立即生效并记住选择 |
| 透明区域 / 飘字区域 | 鼠标穿透 |
| 立即刷新余额 | 对齐真实余额，跳过排队动画；请求中或限流等待期不可重复刷新 |
| 测试一次扣费 / 演示连续扣费 | 仅演示，不修改真实余额，不发起扣费 |
| 尺寸 | 基础高度 110 / 150 / 210 / 280 pt，宽度按图片比例扩展为 1.5 倍 |
| 音效 | 开关原版打击音，默认开启 |
| 重新读取凭证 | 凭证变化后重新连接，旧请求结果会丢弃 |
| 退出 | 正常保存位置并退出 |

每下降一分钱，红闪、震动、播放音效并飘出 `-0.01`；间隔 0.2 秒。超过 400 分的变化直接对齐，避免长时间播放积压动画。充值立即显示，并根据连续两次服务器余额计算到账金额。演示余额与真实余额分开处理。

新版图片保持 1536×1024 的原始宽高比，同一尺寸档下角色高度与旧版一致；鲸尾向左扩展。余额、币种符号与连接状态点一起跟随平板倾斜和震动，长金额自动缩小以保留完整数字。图片空白处与上方飘字区域继续支持鼠标穿透。

切换角色保留当前余额、扣费动画、刷新间隔、窗口位置和尺寸。每个角色使用自己的透明点击区域和平板坐标；旧配置首次升级继续显示蓝色大肥鱼。

| 角色 | 外观 |
| --- | --- |
| GPT龙娘 | 白发、龙角与鳞片龙尾 |
| 大小姐Claude | 橙发、花饰与象牙白服装 |
| 北美猫娘Gemini | 蓝紫发、异色瞳与毛绒尾巴 |

[![四个角色与示例余额](docs/previews/four-characters-usage.webp)](docs/screenshots/four-characters-usage.png)

蓝色大肥鱼在未配置 API Key / 账号凭证、连接中或连接失败时，改为显示抱盆图，不显示余额标题、金额、状态点或金额飘字；连接成功后自动恢复手持平板和余额显示。其他三个角色保持原有显示方式。

[![大肥鱼未连接状态](docs/previews/deepseek-offline.webp)](docs/screenshots/deepseek-offline.png)

## 凭证与余额

按顺序读取第一个配置来源：

1. 环境变量 `DSHPET_KEY`。
2. 可执行文件旁的 `apikey.txt`（应用包内为 `Contents/MacOS/apikey.txt`）。
3. 配置目录的 `apikey.txt`，右键“设置 API Key…”写入这里。
4. `~/.dsh/.credentials.yaml` 的 `DEEPSEEK_API_KEY`。
5. 同一 YAML 文件的 `deepseek-account-platform/default` 账号记录。

设置窗口隐藏输入内容，保存采用权限 `0600` 的临时文件原子替换，失败会提示。环境变量及应用内 Key 的优先级高于设置窗口保存的 Key。推荐使用设置窗口，不要把密钥放进仓库或应用发布包。

| 模式 | 请求地址 | 认证 |
| --- | --- | --- |
| API Key | `https://api.deepseek.com/user/balance` | `Authorization: Bearer …` |
| DSH 平台账号 | 凭证内 HTTPS `issuer` + `/api/v0/users/get_user_summary` | `x-dsh-auth-token` |

账号余额读取 `data.biz_data.normal_wallets` 与 `bonus_wallets` 的 **CNY** 总和。数字以十进制定点方式解析，合计后四舍五入到分。USD 不会冒充人民币；缺少有效 CNY、错误信封或异常数值会显示错误并保留最后读数。不会自行兑换货币。

账号请求只使用本地凭证记录的 HTTPS issuer，拒绝含用户名、查询参数等不安全格式的地址，并拒绝所有 HTTP 重定向。应用不把凭证写入日志。默认每 30 秒请求一次，可改为 10 / 30 / 60 / 300 秒；间隔从上次请求完成后计算。429 优先遵守 `Retry-After`（秒数或 HTTP 日期，最多 24 小时），未提供时逐次退避，最多 5 分钟。

YAML 读取器支持 DSH 常用的块式映射、引号与注释。账号验证登录会自动读取 `deepseek-account-platform/default.payload` 内的 `token` 与 `issuer`，同时兼容旧版直接字段格式；无需另建 API Key。它不是通用 YAML 解析器，不支持锚点、别名或多行凭证。

## 本地文件

默认目录：`~/Library/Application Support/DSHBalancePet/`。

| 文件 | 内容 |
| --- | --- |
| `apikey.txt` | 手动保存的 API Key |
| `state.json` | 所选角色、尺寸、音效、刷新间隔及窗口位置 |
| `status.json` | 最近运行状态、余额与窗口信息，每秒原子更新 |
| `pet.log` / `pet.log.1` | 本地诊断日志，单份约 1 MiB 后轮换；可能包含余额 |
| `pet.lock` | 防止同一配置目录重复启动；退出/崩溃后系统释放锁 |

`DSHPET_HOME=/some/dir` 指定独立配置目录。`DSHPET_OFFLINE=1` 完全跳过凭证读取与联网，适合演示和测试。

## 验证与诊断

```sh
./verify.sh

BIN='./dist/DSH大肥鱼桌宠.app/Contents/MacOS/DSHBalancePet'
"$BIN" --selftest       # 离线回归、资源解码、平板定位与透明命中检查
"$BIN" --snapshot DIR   # 四角色共 84 张状态、尺寸、透明及平板近景预览，使用示例余额
"$BIN" --windows        # 当前配置目录的最近状态；停止/过期返回非零
"$BIN" --screens        # 显示器布局
"$BIN" --reset          # 退出桌宠后，仅清除保存的位置，保留其他偏好
"$BIN" --check          # 可选：读取真实凭证并实际查询一次余额
```

`verify.sh` 使用隔离的临时配置和离线模式；覆盖回归测试、素材一致性、签名、启动、重复实例与位置重置。输出在 `build/verification`。GitHub Actions 在推送时构建 universal 包、执行同一验证并保存下载产物。本机已通过 Apple Silicon 原生及 Rosetta 的 Intel 指令集测试；1.1.1 已通过本机 DSH 账号验证登录的实际余额查询；Intel 实机运行及其他账号环境仍需对应验证。

## 源码与来源

- `AppConfig.swift`：凭证、路径、设置与日志。
- `BalanceClient.swift`：请求、严格响应解析与精确金额。
- `PetModel.swift`：余额和动画；`PollSchedule.swift`：请求调度。
- `PetController.swift`：窗口、菜单、轮询与音效。
- `PetCharacter.swift`：四个内置角色的名称、图片与各自平板坐标。
- `PetView.swift` / `PetAssets.swift` / `PetLayout.swift`：角色切换绘制、等比缩放和透明区域交互。
- `Diagnostics.swift` / `*SelfTests.swift`：离线回归与诊断。
- `Resources/`：四张角色 PNG，以及从 Windows 原版逐字节复制的 `hit.mp3`。
- `artwork/left-completion-v1/`：补全图片、参考、提示词与原始素材检查记录。

Windows 原版代码及素材完整保存在仓库的 `原版（Windows版）`，来源见 [素材说明](Resources/README.md)。旧音效生成脚本保留供参考，默认构建不再使用。

本应用使用本地临时签名，未经过 Apple 开发者签名与公证。构建通过不等于所有 macOS/Intel 机型均已实测；离屏截图也不等于所有跨应用鼠标交互均已验证。

## 更新记录

版本变更统一记录在[仓库首页的更新记录](../README.md#更新记录)，包括 v1.3.1 离线抱盆状态和 v1.3.0 四角色切换。
