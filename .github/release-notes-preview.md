# PromptBox 0.1 Preview 7

本次预览版主要用于功能体验、兼容性验证和收集反馈，尚不是正式稳定版。

## 本次更新

- 字体大小与界面比例独立调节，支持放大、缩小、重置，选择会自动保存。
- 新增完全手动的 GitHub 更新流程：手动检查 → 确认下载 → 再次确认安装；下载后不会自动安装。
- 按系统与进程架构选择安装包，检查版本、文件长度和 SHA-256，支持失败重试。
- Windows/macOS 安装助手等待正常退出后保留旧程序备份、替换并重启；Linux 通过系统授权安装 DEB。更新不会主动关闭编辑器。
- macOS 直接分发版关闭 App Sandbox，并保留旧沙盒偏好设置与数据库的兼容读取。
- 修复苹果平台数字版本名与 GitHub 预览版本比较，保证 macOS 正确检查新版本。
- 发布版本为 `0.1.0-preview.7+7`，DEB 版本为 `0.1.0-7`；macOS 原生版本名按 Flutter 规则为 `0.1.0.7`。

## Preview 5 update

- 新增左侧“明日计划”：今天写下明天的具体任务，到达计划日期后自动出现在“今天”；明日计划栏开始接收下一天的计划。
- 重启或离线跨多天后，计划仍保存在原定日期，不重复、不丢失；保留 Markdown、标签、大纲名称、排序和完成状态。
- 每个气泡操作栏新增低调的完成勾选框，勾选后显示绿色对勾，可再次点击取消。
- 完成状态持久保存，并在原日期、快速访问与明日计划间保持同步。
- 侧栏与气泡操作栏适配较小窗口，避免新增按钮导致溢出。
- 三平台统一构建：Linux x64 DEB、Windows x64 Portable、macOS arm64 DMG。DEB 内部版本号更新为 `0.1.0-5`。

主要功能：

- 本地优先的按日 Prompt 时间线与历史归档
- Markdown 所见即所得编辑及长编辑窗口
- 多行代码块、行内公式和独立公式块
- 今日及历史会话大纲与点击定位
- 标签、搜索、排序、编辑和 Markdown 一键复制
- 数据目录迁移、备份与恢复
- 深色、浅色及跟随系统主题

构建产物：

- `promptbox-preview-linux-amd64.deb`：Debian/Ubuntu x64 安装包
- `PromptBox-preview-windows-x64.zip`：Windows x64 便携版，解压后运行 `prompt_box.exe`
- `PromptBox-preview-macos-arm64.dmg`：macOS Apple Silicon（M 系列）版本，打开 DMG 后将 `PromptBox.app` 拖入“应用程序”。

注意：Preview 构建尚未签名，也未完成大规模系统兼容性测试。请保留重要数据的独立备份，并通过 Issues 反馈问题。

## Preview 2 update

- Added the PromptBox logo to the Windows executable and Linux desktop integration.
- Added GNOME application-menu, dock, and window icon metadata to the DEB package.
- Kept theme and database-path settings in per-user storage across DEB upgrades and Windows bundle replacement.
- Added an upgrade-persistence regression test.

## Preview 3 update

- Added collapsible Prompt bubbles for compact navigation through long conversations.
- Added a persistent Quick Access collection with starring, reordering, tags, search, and an outline.
- Quick Access edits stay synchronized with the original dated Prompt instead of creating duplicate content.
- Added searchable tag filtering by tag name or note.
- Added regression coverage for Quick Access persistence, original-content synchronization, collapsing, and tag search.

## Preview 4 update

- Fixed outline jumps to distant Prompt bubbles, including items outside the visible list.
- Added Ctrl+Enter to send from the main editor; Enter still inserts a new line.
- Added optional custom outline names. Clear a name to restore the automatically generated title.
- Custom outline names persist with the original Prompt and are available in Quick Access and search.

## macOS Apple Silicon build

macOS 版本与其他平台由当前预览版本的同一份源码构建，适用于苹果 M 系列芯片。本预览版采用临时签名，尚未经过 Apple 公证；如果系统拦截首次启动，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。
