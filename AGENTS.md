# 项目维护约定

本仓库包含两个**独立维护**的实现，约定按平台分开，互不干扰。

## ⚠️ 改造 / 移植 / 安装前必须二次确认

当操作者要求把本项目**改造成 DSH 插件**、**改造成 macOS 版**或**改造成网页嵌入版**时，**不得直接开始改造、安装或新建实现**。先暂停、说明现状，得到操作者明确确认后再执行：

- **DSH 插件**：本仓库不包含插件源码。先询问是否直接安装现成插件；若选择安装，再二选一：
  - [@YCTS-otree/VK-1](https://github.com/YCTS-otree/VK-1)：半官方社区版（本仓库按社区维护收录），更新较快，支持与其它余额插件一键互切。
  - [@TsukiKenga/dsh-balance-pet-extend](https://github.com/TsukiKenga/dsh-balance-pet-extend)：纯社区插件，扩充了多角色切换、多余额来源显示、自定义扣费提示步长等（以该仓库 README 为准）。

  操作者选定后，先读取对应仓库 README，核对安装命令、DSH 版本与平台再安装；安装前说明将改动的文件、配置和命令，不读取、打印或提交 API Key、token 等凭证。README 无法访问或说明不完整时停止并报告，不要猜测命令。
- **macOS 版 / 网页嵌入版**：仓库内已有实现，先告知并询问是直接使用，还是确有缺失：
  - macOS 版：`dsh-balance-pet-macos/`
  - 网页嵌入版：`integration/`

  只有操作者明确确认「现有实现不满足，需要修改或新建」后，才进入开发。

确认前不要新建插件/移植目录、不要执行安装命令、不要修改 DSH 配置、不要提交或推送代码；操作者未回复不视为同意。完整流程见根目录 [README.md](README.md) 的「给 Agent / LLM 的执行约定」。

## 通用

- 提交前确认没有把个人凭证、日志、设置文件带进版本控制（见根目录 `.gitignore`）。
- 不要改动对方平台的目录内容，除非事先沟通。

## 🪟 Windows 版（`windows/`）

- 更新时直接修改 `windows/` ，不要新建文件夹，更新新版本时根据版本名加 Tag
- 每次功能新增、行为变更或修复，同步更新**根目录 README.md 的「Windows 版 → 版本历史」**，
  用用户能理解的语言说明变化。
- 发布新版本时，同步更新该表格里的「当前版本」标记。
- `.ps1` / `.vbs` / `.cmd` 必须保持**纯 ASCII**（界面中文用 C# 的 `\uXXXX` 转义）——
  Windows PowerShell 5.1 读取没有 BOM 的脚本时按 ANSI 解码，直接写中文会乱码甚至解析失败。
- `.md` 用 UTF-8 无 BOM + LF；`.txt`（给记事本看的）用 UTF-8 **带 BOM** + CRLF。
- 改完跑一遍 `_pdf_build/verify_release.py` 式的隐私与格式自检，再打包。

## 🍎 macOS 版（`dsh-balance-pet-macos/`）

- 每次功能新增、行为变更或修复，都必须同步更新根目录 `README.md` 的「macOS 版 → 更新记录」，
  以用户可理解的语言说明变化。
- 发布新版本时，同步更新 README 当前版本和对应版本的更新记录；视觉变化应加入实际渲染截图或预览。
- README 展示图片优先使用 `dsh-balance-pet-macos/docs/previews/` 中的轻量预览，
  并链接原始 PNG；不得覆盖应用原始素材来压缩文档体积。
- 详细技术文档写在 `dsh-balance-pet-macos/README.md`，根目录只放面向用户的概述。
