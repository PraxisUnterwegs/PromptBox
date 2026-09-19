目前需要先开启 Windows 的“开发者模式”，否则 Flutter 插件无法构建。

  1. 打开 Windows：

  设置 → 系统 → 高级 → 开发者选项 → 开发者模式

  2. 开启后，在当前项目目录打开 PowerShell，执行：

  flutter pub get
  flutter run -d windows

  Flutter 完成编译后会自动打开 PromptBox 窗口。测试过程中保持终端运行；结束时在终端按 q。

  如果要生成可直接双击运行的软件：

  flutter build windows --release

  构建成功后，程序位于：

  build\windows\x64\runner\Release\prompt_box.exe

  注意不要只复制 prompt_box.exe，发布时需要保留整个 Release 文件夹及其 DLL。