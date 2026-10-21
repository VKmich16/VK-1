import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// 重新生成插件包里的页面挂件与素材：
//   1. 跑 integration/build.mjs（社区 widget 1.0.2 + 37 条审计补丁，带 commit/hash 校验）；
//   2. 把生成的 widget.js / loader.js / assets 拷进本插件包。
//
// 用法：node dsh-plugin/build.mjs <release-name> <community-reference-dir>
//   community-reference-dir 是 YCTS-otree/VK-1 的干净检出（固定 commit，见 integration/source-lock.json）。
// 生成后把 lib/index-v1.js 改成 lib/index-vN.js 再回来，或重启 DSH，宿主才会重新导入。

const pluginRoot = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.dirname(pluginRoot)
const release = process.argv[2]
const source = process.argv[3] || process.env.VK1_COMMUNITY_SOURCE
if (!release || !source) {
  console.error('用法: node dsh-plugin/build.mjs <release-name> <community-reference-dir>')
  process.exit(1)
}

execFileSync(process.execPath, [path.join(repoRoot, 'integration', 'build.mjs'), release, source], {
  cwd: repoRoot,
  stdio: 'inherit',
})

const built = path.join(repoRoot, 'releases', release)
for (const file of ['widget.js', 'loader.js']) {
  fs.copyFileSync(path.join(built, file), path.join(pluginRoot, file))
}
fs.mkdirSync(path.join(pluginRoot, 'assets'), { recursive: true })
for (const file of fs.readdirSync(path.join(built, 'assets'))) {
  fs.copyFileSync(path.join(built, 'assets', file), path.join(pluginRoot, 'assets', file))
}
console.log('插件包已更新: ' + pluginRoot)
