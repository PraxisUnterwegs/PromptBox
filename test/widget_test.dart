import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:prompt_box/app.dart';
import 'package:prompt_box/markdown_extensions.dart';
import 'package:prompt_box/models.dart';
import 'package:prompt_box/wysiwyg_editor.dart';

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
}
