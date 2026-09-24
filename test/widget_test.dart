import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:prompt_box/app.dart';
import 'package:prompt_box/app_controller.dart';
import 'package:prompt_box/markdown_extensions.dart';
import 'package:prompt_box/models.dart';
import 'package:prompt_box/storage.dart';
import 'package:prompt_box/wysiwyg_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('今天和历史会话显示大纲，未来日期不显示', () {
    final today = DateTime(2026, 9, 19, 9);
    expect(shouldShowConversationOutline(today, today), isTrue);
    expect(
      shouldShowConversationOutline(
        today.subtract(const Duration(days: 1)),
        today,
      ),
      isTrue,
    );
    expect(
      shouldShowConversationOutline(today.add(const Duration(days: 1)), today),
      isFalse,
    );
  });

  testWidgets('Markdown 标题可正确渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownBody(data: '# Markdown 标题')),
      ),
    );
    await tester.pump();
    expect(find.text('Markdown 标题'), findsOneWidget);
  });

  testWidgets('输入框使用单区所见即所得编辑器并触发发送', (tester) async {
    final text = WysiwygMarkdownController('**实时预览**');
    var sent = false;
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Composer(
            controller: text,
            onLongEditor: () {},
            onSend: () => sent = true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(WysiwygMarkdownEditor), findsOneWidget);
    await tester.tap(find.byTooltip('发送'));
    expect(sent, isTrue);
  });

  testWidgets('输入框 Enter 换行，Ctrl+Enter 发送', (tester) async {
    final text = WysiwygMarkdownController();
    var sent = 0;
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppFlowyEditorLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: WysiwygMarkdownEditor(
              controller: text,
              onSubmit: () => sent++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppFlowyEditor));
    await tester.pump();
    tester.testTextInput.enterText('第一行');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, 0);
    tester.testTextInput.enterText('第一行\n第二行');
    await tester.pump();
    expect(text.markdown, contains('\n'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(sent, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('大纲可跳转到尚未构建的远处气泡', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1300, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final temp =
        (await tester.runAsync(
          () => Directory.systemTemp.createTemp('prompt_box_outline_'),
        ))!;
    addTearDown(() => temp.delete(recursive: true));
    final date = DateTime(2026, 9, 24);
    final store = JsonPromptStore(temp.path);
    final day = DayRecord(
      date: date,
      entries: [
        for (var index = 0; index < 35; index++)
          PromptEntry(
            id: 'entry-$index',
            content: '# Prompt $index\n正文 $index',
            createdAt: date.add(Duration(minutes: index)),
            updatedAt: date,
          ),
      ],
    );
    final controller = PromptBoxController(store: store, clock: () => date);
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await store.writeDay(day);
      await controller.initialize();
    });
    await tester.pumpWidget(PromptBoxApp(controller: controller));
    await tester.pumpAndSettle();

    const bubbleKey = ValueKey('prompt-bubble-entry-25');
    expect(find.byKey(bubbleKey), findsNothing);
    final outlineList = find.byType(ListView).last;
    for (
      var attempt = 0;
      attempt < 6 &&
          find.widgetWithText(ListTile, 'Prompt 25').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(outlineList, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(ListTile, 'Prompt 25'));
    await tester.pumpAndSettle();
    expect(find.byKey(bubbleKey), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Prompt 25'),
        matching: find.byTooltip('编辑大纲名称'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('默认名称：Prompt 25'), findsOneWidget);
    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, '关键大纲');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '关键大纲'), findsOneWidget);
    expect(controller.currentDay!.entries[25].content, '# Prompt 25\n正文 25');
  });

  testWidgets('空白所见即所得输入框可获得焦点并输入文字', (tester) async {
    final text = WysiwygMarkdownController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppFlowyEditorLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: WysiwygMarkdownEditor(controller: text),
          ),
        ),
      ),
    );
    await tester.pump();
    final editor = find.byType(AppFlowyEditor);
    expect(editor, findsOneWidget);
    await tester.tap(editor);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    tester.testTextInput.enterText('可以输入');
    await tester.pump(const Duration(milliseconds: 300));
    expect(text.markdown, contains('可以输入'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('行内与块级数学公式可渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExtendedMarkdownBody(
            data:
                r'行内 $E=mc^2$'
                '\n\n'
                r'$$\frac{a}{b}$$',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Math), findsNWidgets(2));
  });

  test('代码块和公式块可导入所见即所得文档', () {
    final controller = WysiwygMarkdownController(
      '```dart\nvoid main() {}\n```\n\n'
      r'$$\frac{a}{b}$$',
    );
    addTearDown(controller.dispose);
    final types = controller.editorState.document.root.children.map(
      (node) => node.type,
    );
    expect(types, contains('code'));
    expect(types, contains(mathBlockType));
    final exported = documentToMarkdown(
      controller.editorState.document,
      customParsers: const [MathBlockMarkdownEncoder()],
    );
    expect(exported, contains('```dart'));
    expect(exported, contains(r'\frac{a}{b}'));
    expect(exported, contains(r'$$'));
  });

  test('编辑器导入会移除结构性空行但保留代码块内部空行', () {
    final prepared = prepareExtendedMarkdown(
      '# 标题\n\n正文\n\n```dart\n第一行\n\n第三行\n```',
    );
    expect(prepared, startsWith('# 标题\n正文\n```dart'));
    expect(prepared, contains('第一行\n\n第三行'));
  });

  test('强制刷新会使用当前文档重建渲染状态并保留内容', () async {
    final controller = WysiwygMarkdownController();
    addTearDown(controller.dispose);
    final oldState = controller.editorState;
    await oldState.insertText(0, r'$E=mc^2$', path: [0]);

    controller.refreshRendering();

    expect(controller.editorState, isNot(same(oldState)));
    expect(controller.markdown, contains(r'$E=mc^2$'));
  });

  test('强制刷新会把直接输入的三反引号语法转换为代码块', () async {
    final controller = WysiwygMarkdownController();
    addTearDown(controller.dispose);
    await controller.editorState.insertText(
      0,
      '  ```dart\r\nvoid main() {}\r\n```   ',
      path: [0],
    );

    controller.refreshRendering();

    expect(controller.editorState.document.root.children.single.type, 'code');
    expect(controller.markdown, contains('void main() {}'));
  });

  testWidgets('长编辑器提供强制刷新渲染按钮', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LongEditorDialog(initialValue: r'$x^2$')),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('强制刷新渲染'), findsOneWidget);
    await tester.tap(find.byTooltip('强制刷新渲染'));
    await tester.pump();
    expect(find.text('已根据当前 Markdown 重新渲染'), findsOneWidget);
  });

  testWidgets('气泡可一键复制未经渲染的完整 Markdown', (tester) async {
    const markdown = '# 标题\n\n```dart\nvoid main() {}\n```';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final now = DateTime(2026, 9, 19, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptBubble(
            entry: PromptEntry(
              id: 'copy-test',
              content: markdown,
              createdAt: now,
              updatedAt: now,
            ),
            tags: const [],
            onEdit: () {},
            onDelete: () {},
            onMoveUp: () {},
            onMoveDown: () {},
            onToggleTag: (_) {},
            onCreateTag: (_, __, ___) async => null,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('复制 Markdown'));
    await tester.pump();
    expect(copied, markdown);
    expect(find.text('已复制完整 Markdown'), findsOneWidget);
  });
  testWidgets('collapsed bubble shows a compact title and can expand', (
    tester,
  ) async {
    var toggled = false;
    final now = DateTime(2026, 9, 20, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptBubble(
            entry: PromptEntry(
              id: 'collapse-test',
              content: '# Long prompt title\n\nSecond paragraph',
              createdAt: now,
              updatedAt: now,
            ),
            tags: const [],
            collapsed: true,
            onToggleCollapsed: () => toggled = true,
            onEdit: () {},
            onDelete: () {},
            onMoveUp: () {},
            onMoveDown: () {},
            onToggleTag: (_) {},
            onCreateTag: (_, __, ___) async => null,
          ),
        ),
      ),
    );

    expect(find.text('Long prompt title'), findsOneWidget);
    expect(find.byType(ExtendedMarkdownBody), findsNothing);
    await tester.tap(find.byTooltip('\u5c55\u5f00'));
    expect(toggled, isTrue);
  });

  testWidgets('bubble exposes quick access pin state', (tester) async {
    var toggled = false;
    final now = DateTime(2026, 9, 20, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptBubble(
            entry: PromptEntry(
              id: 'pin-test',
              content: 'Reusable prompt',
              createdAt: now,
              updatedAt: now,
            ),
            tags: const [],
            inQuickAccess: true,
            onToggleQuickAccess: () => toggled = true,
            onEdit: () {},
            onDelete: () {},
            onMoveUp: () {},
            onMoveDown: () {},
            onToggleTag: (_) {},
            onCreateTag: (_, __, ___) async => null,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('\u79fb\u51fa\u5feb\u901f\u8bbf\u95ee'));
    expect(toggled, isTrue);
  });

  testWidgets('tag filter dialog searches names and descriptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TagFilterDialog(
            selectedId: null,
            tags: [
              TagDefinition(
                id: 'backend',
                name: 'Backend',
                colorValue: 0xff123456,
                description: 'server work',
              ),
              TagDefinition(
                id: 'frontend',
                name: 'Frontend',
                colorValue: 0xff654321,
                description: 'visual interface',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Backend'), findsOneWidget);
    expect(find.text('Frontend'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'visual');
    await tester.pump();
    expect(find.text('Backend'), findsNothing);
    expect(find.text('Frontend'), findsOneWidget);
  });
}
