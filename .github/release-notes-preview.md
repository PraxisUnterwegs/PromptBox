# PromptBox 0.1 Preview 2

这是 PromptBox 的首个公开预览版本，主要用于功能体验、兼容性验证和收集反馈，尚不是正式稳定版。

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

注意：Preview 构建尚未签名，也未完成大规模系统兼容性测试。请保留重要数据的独立备份，并通过 Issues 反馈问题。

## Preview 2 update

- Added the PromptBox logo to the Windows executable and Linux desktop integration.
- Added GNOME application-menu, dock, and window icon metadata to the DEB package.
- Kept theme and database-path settings in per-user storage across DEB upgrades and Windows bundle replacement.
- Added an upgrade-persistence regression test.
