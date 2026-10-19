# 项目维护约定

本仓库包含两个**独立维护**的实现，约定按平台分开，互不干扰。

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
