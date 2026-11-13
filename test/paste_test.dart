import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_box/prompt_clipboard.dart';
import 'package:prompt_box/rich_text_import.dart';
import 'package:prompt_box/wysiwyg_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('图片粘贴先生成可移除的草稿附件，不向文字写入路径', () async {
    final controller = WysiwygMarkdownController();
    addTearDown(controller.dispose);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await controller.pasteData(PromptClipboardData(images: [png, png]));
    expect(controller.images, hasLength(2));
    expect(controller.images.first.width, 1);
    expect(controller.markdown, isEmpty);
    expect(controller.isEmpty, isFalse);
    controller.removeImage(controller.images.first);
    expect(controller.images, hasLength(1));
    controller.clear();
    expect(controller.isEmpty, isTrue);
  });

  test('粘贴Markdown立即解析加粗斜体和列表，保留空行与空格', () async {
    final controller = WysiwygMarkdownController();
    addTearDown(controller.dispose);
    await controller.pasteData(
      const PromptClipboardData(
        text: '**加粗** 和 *斜体*\n\n- 项目一\n- 项目二\n\n1. 第一步\n2. 第二步\n\n保留  两个空格',
      ),
    );
    final nodes = controller.editorState.document.root.children;
    expect(
      nodes.map((node) => node.type),
      containsAll([BulletedListBlockKeys.type, NumberedListBlockKeys.type]),
    );
    final first = nodes.first.delta!.toJson();
    expect(
      first.any(
        (operation) => (operation['attributes'] as Map?)?['bold'] == true,
      ),
      isTrue,
    );
    expect(
      first.any(
        (operation) => (operation['attributes'] as Map?)?['italic'] == true,
      ),
      isTrue,
    );
    expect(nodes.where((node) => node.delta?.isEmpty == true), isNotEmpty);
    expect(controller.markdown, contains('\n\n'));
    expect(controller.markdown, contains('保留  两个空格'));
    controller.refreshRendering();
    expect(controller.markdown, contains('**加粗**'));
  });

  test('富文本保留嵌套强调、CSS样式、段落、br和嵌套列表', () {
    final doc = documentFromClipboardHtml(
      '<p><strong>粗体 <em>粗斜体</em></strong> 和 <span style="font-style:italic;font-weight:700">样式</span><br>下一行</p><p>另一段</p><ul><li>项目<ul><li>子项</li></ul></li></ul><ol><li>步骤一</li><li>步骤二</li></ol>',
    );
    final nodes = doc.root.children;
    expect(nodes.first.delta!.toPlainText(), contains('粗体 粗斜体 和 样式\n下一行'));
    expect(
      nodes.first.delta!.toJson().any(
        (op) =>
            op['insert'] == '粗斜体' &&
            (op['attributes'] as Map)['bold'] == true &&
            (op['attributes'] as Map)['italic'] == true,
      ),
      isTrue,
    );
    expect(nodes.where((node) => node.delta?.isEmpty == true), isNotEmpty);
    final list = nodes.firstWhere(
      (node) => node.type == BulletedListBlockKeys.type,
    );
    expect(list.children.single.type, BulletedListBlockKeys.type);
    expect(
      nodes.where((node) => node.type == NumberedListBlockKeys.type),
      hasLength(2),
    );
  });

  test('粘贴富文本可保存为Markdown，纯文本粘贴不解析标记', () async {
    final controller = WysiwygMarkdownController();
    addTearDown(controller.dispose);
    await controller.pasteData(
      const PromptClipboardData(
        text: '粗体\n\n第二段',
        html: '<p><b>粗体</b></p><p>第二段</p>',
      ),
    );
    expect(controller.markdown, contains('**粗体**\n\n第二段'));
    controller.clear();
    await controller.pasteData(
      const PromptClipboardData(text: '**原样**'),
      plainText: true,
    );
    expect(
      controller.editorState.document.root.children.first.delta!.toPlainText(),
      '**原样**',
    );
    expect(
      controller.editorState.document.root.children.first.delta!.toJson().every(
        (op) => (op['attributes'] as Map?)?['bold'] != true,
      ),
      isTrue,
    );
  });

  test('富文本代码中的空格和空行不被压缩，也不执行外部图片或脚本', () {
    final doc = documentFromClipboardHtml(
      '<script>bad()</script><pre><code class="language-dart">  first\n\n    second</code></pre><img src="https://example.com/private.png">',
    );
    expect(doc.root.children.single.type, 'code');
    expect(
      doc.root.children.single.delta!.toPlainText(),
      '  first\n\n    second',
    );
  });
}
