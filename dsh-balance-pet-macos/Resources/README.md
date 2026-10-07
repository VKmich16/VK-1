# 默认素材与来源

图片基础和原版音效来自本仓库 `原版（Windows版）/DSH余额桌宠.zip`。Windows 原版图片与音效完整保留在仓库的 `原版（Windows版）/DSH余额桌宠/`。

1.2.0 将默认图片替换为已生成的左侧头发与鲸尾补全版本；直接复制透明 PNG，没有拉伸、裁切或再次生成。补全图含轻微生成重绘，不能视作原图逐像素不变的扩边。

1.3.0 新增三张同项目其他对话中已生成的角色图，均为 1536×1024 RGBA 原文件复制：GPT龙娘和大小姐Claude取自“创建并优化DSH大肥鱼桌宠”的第一组成品；北美猫娘Gemini取自“按人设修改大肥鱼图片”的 `character.png` 透明背景清理版。没有重新生成或改动图片内容。

| 文件 | 用途 | SHA-256 |
| --- | --- | --- |
| `sprite.png` | 1536 × 1024 RGBA，补全头发与鲸尾的大肥鱼及手持平板 | `a98329d36dd9169a1856f3a396bc9e602ed1a739bd3097eead1b744c6bb3dd71` |
| `sprite-gpt.png` | GPT龙娘：白发、龙角、龙尾 | `41f79346666fbb776ee2baef2a0cf044850a50e30c177b3adf9bb14e84296467` |
| `sprite-claude.png` | 大小姐Claude：橙发、花饰、无尾巴 | `81f0e787057dd9d5e400e5f43a44a1b55da4adfa7329aa712d986531cbd5d90d` |
| `sprite-gemini.png` | 北美猫娘Gemini：蓝紫发、异色瞳、毛绒尾巴 | `ad5fbeb07c2212476d4670ec56b8e7202e21f05b42ab0461cf3150a43f91a2ef` |
| `sprite-deepseek-offline.png` | 用户提供的 1536 × 1024 RGBA 抱盆图；仅用于蓝色大肥鱼未连接状态，原文件直接复制 | `fb4c5cb3001ca43d268d2e3bdf39b9d984e28d592e3b73e46e6fd44ccebb4555` |
| `hit.mp3` | 原版扣费打击音效 | `43fa877b537d8cbfbd676d76109b9a960551bfeae06c62e2d1a7d64d3994cb29` |

补全图片来源、参考与提示词见 [`artwork/left-completion-v1`](../artwork/left-completion-v1/README.md)。Windows 原始 1024 × 1024 图片 SHA-256 为 `5bc1d8f1f347c430dd662ad8ff3da8d0dff3df9f290712efe36d004b7b103e69`。

余额文字、状态点及动画由 macOS 应用实时绘制。`PetCharacter.swift` 为每个角色保存文字安全区，`PetLayout.swift` 将其映射到视图；图片绘制和透明命中使用同一缩放矩形。以下坐标以各原图左上角为原点：

| 角色 | 左上 TL | 右上 TR | 左下 BL | 右下 BR |
| --- | --- | --- | --- | --- |
| 蓝色大肥鱼 / GPT龙娘 / 大小姐Claude | (1060,699) | (1413,644) | (1090,889) | (1443,834) |
| 北美猫娘Gemini | (1065,699) | (1400,646) | (1095,889) | (1430,836) |

Gemini 的右手伸入屏幕较多，因此文字区域单独收窄以避开手指。

原版作者说明 UI 图片由其处理；原版暂未附许可证。这里保留来源说明，不另行授予原版代码、素材或衍生图片的许可。
