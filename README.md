# PromptBox

[![Build Preview](https://github.com/PraxisUnterwegs/PromptBox/actions/workflows/release-preview.yml/badge.svg)](https://github.com/PraxisUnterwegs/PromptBox/actions/workflows/release-preview.yml)
[![Latest Preview](https://img.shields.io/github/v/release/PraxisUnterwegs/PromptBox?include_prereleases&label=preview)](https://github.com/PraxisUnterwegs/PromptBox/releases)

PromptBox 是一款本地优先、跨平台的 Prompt 与灵感管理工具。它用聊天时间线保存零散想法，同时提供 Markdown 所见即所得编辑、标签、日期归档和可迁移的数据目录。

> 当前处于 Preview 阶段，适合体验和反馈，不建议把它作为唯一的数据副本。重要内容请定期使用内置备份功能导出。

## 为什么开发 PromptBox

Prompt 往往散落在聊天记录、便签和不同项目中。PromptBox 希望提供一个简单、可搜索、可长期保存的本地空间：像发消息一样快速记录，又能通过 Markdown、标签、大纲和日期历史重新找到内容。

## 主要功能

- 今天、昨天、前天快捷入口，以及按日期浏览的历史数据库。
- 小输入框与长编辑窗口均采用单区 Markdown 所见即所得编辑。
- 支持标题、粗体、斜体、列表、引用、行内代码和多行代码块。
- 支持 `$...$` 行内 LaTeX 公式和 `$$...$$` 独立公式块。
- 长编辑器可手动强制刷新渲染，处理偶发的 Markdown 未转换情况。
- 每日会话及快速访问大纲，可点击标题快速定位气泡；重要条目可自定义大纲名称。
- 气泡可折叠，也可加入左侧常驻的快速访问栏。
- 每个气泡可一键复制完整 Markdown 原文。
- 气泡编辑、删除、排序，以及带颜色和备注的自定义标签。
- 按正文、大纲名称和标签搜索，支持浅色、深色与跟随系统主题。
- 本地 JSON 数据库，可迁移到 OneDrive、Dropbox、iCloud Drive 等本地同步目录。
- 数据目录导出备份、恢复与原子写入保护。

## 下载和安装

预览构建位于 [GitHub Releases](https://github.com/PraxisUnterwegs/PromptBox/releases)。

### Windows x64

下载 `PromptBox-preview-windows-x64.zip`，完整解压后运行其中的 `prompt_box.exe`。不要只把 EXE 单独移走，它需要同目录中的 DLL 和 `data` 文件夹。

Windows 可能会对尚未签名的 Preview 程序显示 SmartScreen 提示，请确认下载来源为本仓库后再决定是否运行。

### Debian / Ubuntu x64

下载 `promptbox-preview-linux-amd64.deb`，然后执行：

```bash
sudo apt install ./promptbox-preview-linux-amd64.deb
```

安装后可从应用菜单启动 PromptBox，或在终端运行：

```bash
promptbox
```

当前 `.deb` 面向 Debian/Ubuntu 的 x86_64/amd64 桌面环境，尚未提供 ARM Linux 构建。

## 基本使用

1. 在底部编辑器中输入内容，使用工具栏应用 Markdown 格式；点击发送或按 Ctrl+Enter 发送，直接按 Enter 换行。
2. 需要编辑长内容时，点击输入框右侧的“长编辑器”按钮。
3. 若代码块或公式偶尔未转换，在长编辑器右上角点击“强制刷新渲染”。
4. 使用气泡底部的复制按钮获取未经渲染的完整 Markdown。
5. 使用右侧大纲快速跳转；点击大纲条目旁的编辑图标可设置专用名称，留空保存可恢复默认名称。使用标签和顶部搜索框整理内容。
6. 点击气泡上的星标可将常用 Prompt 加入左侧“快速访问”。
7. 在设置中迁移数据目录、导出备份或从备份恢复。

代码块可以通过工具栏创建，也可以输入语言围栏后按回车：

````markdown
```dart
void main() {
  print('Hello PromptBox');
}
```
````

数学公式示例：

```markdown
行内公式：$E = mc^2$

独立公式：
$$
\frac{a}{b} = c
$$
```

## 数据存储

PromptBox 默认把数据保存在系统应用支持目录。每个自然日对应一个 UTF-8 JSON 文件：

```text
PromptBox/
  tags.json
  quick_access.json
  week_notes.json
  days/
    2026/
      09/
        2026-09-19.json
```

应用每分钟检查日期边界。跨天后会自然创建新的“今天”，旧内容保留在原日期中，不会批量移动文件。数据库写入使用临时文件和备份文件降低意外中断造成的数据损坏风险。

## 从源码运行

项目当前使用 Flutter 3.29.2 / Dart 3.7 系列验证。

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows  # Windows
flutter run -d linux    # Debian / Ubuntu
```

桌面程序需要在对应宿主系统上构建：

```bash
flutter build windows --release
flutter build linux --release
```

仓库中的 GitHub Actions 会在推送 `v*-preview.*` 标签时，分别使用 Windows 和 Ubuntu runner 构建并创建预发布 Release。本次暂不构建 macOS arm64。

## Preview 限制

- 尚未进行代码签名、公证或长期兼容性验证。
- 历史搜索目前针对选定日期，而非一次性跨全部日期搜索。
- 多设备同时写入同一云同步目录时，暂不自动合并冲突。
- Linux 包主要面向常见 Debian/Ubuntu x64 桌面环境，其他发行版尚未系统测试。
- UI、数据格式和安装方式在正式版前仍可能调整。

## 反馈

如果遇到渲染、数据迁移或平台兼容问题，请在 [Issues](https://github.com/PraxisUnterwegs/PromptBox/issues) 中附上操作系统、复现步骤和截图。
