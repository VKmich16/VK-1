# build.mjs

VK-1 独立网页构建器。读取 source-lock.json 验证社区 commit、干净状态和每个输入 SHA-256；按 patches.json 唯一锚点应用补丁。遇到未知 commit/hash/歧义锚点立即停止，不修改上游，不覆盖 release。

用法：在项目根运行 `node integration/build.mjs RELEASE [候选上游目录]`。产物 `releases/RELEASE/` 内含 JS、原素材、MIT 许可及 manifest。自动将loader的widget版本查询同步为release标识。Node 无安装依赖，仅语法校验，交互需另跑 browser-test.cjs。
