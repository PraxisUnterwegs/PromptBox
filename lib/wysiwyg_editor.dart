import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/material.dart';
// AppFlowy 2.5 does not export its cursor-preserving node insertion helpers.
// ignore: implementation_imports
import 'package:appflowy_editor/src/editor/editor_component/service/shortcuts/command/copy_paste_extension.dart';

import 'markdown_extensions.dart';
import 'image_storage.dart';
import 'prompt_clipboard.dart';
import 'rich_text_import.dart';

final _formatFenceToCodeBlock = CharacterShortcutEvent(
  key: 'format fenced code marker to code block',
  character: '\n',
  handler:
      (editorState) async => formatMarkdownSymbol(
        editorState,
        (node) => node.type != CodeBlockKeys.type,
        (_, text, __) => RegExp(r'^```[^`\s]*$').hasMatch(text),
        (text, node, delta) => [
          codeBlockNode(
            language:
                text.substring(3).trim().isEmpty
                    ? 'auto'
                    : text.substring(3).trim(),
          ),
          if (node.children.isNotEmpty) ...node.children,
        ],
      ),
);

class WysiwygMarkdownController extends ChangeNotifier {
  WysiwygMarkdownController([String markdown = '']) {
    _replaceState(markdown);
  }

  late EditorState editorState;
  StreamSubscription<(TransactionTime, Transaction)>? _subscription;
  String _markdown = '';
  final List<PendingImage> images = [];
  bool pasting = false;
  bool _disposed = false;

  String get markdown => _markdown;
  bool get isEmpty => _markdown.trim().isEmpty && images.isEmpty;

  void replaceImages(List<PendingImage> value) {
    images
      ..clear()
      ..addAll(value);
    notifyListeners();
  }

  void removeImage(PendingImage image) {
    images.remove(image);
    notifyListeners();
  }

  Future<void> pasteFromClipboard({
    bool plainText = false,
    bool allowImages = true,
  }) async {
    if (pasting) return;
    pasting = true;
    notifyListeners();
    try {
      final data = await PromptClipboard.read();
      if (!_disposed) {
        await pasteData(data, plainText: plainText, allowImages: allowImages);
      }
    } finally {
      if (!_disposed) {
        pasting = false;
        notifyListeners();
      }
    }
  }

  Future<void> pasteData(
    PromptClipboardData data, {
    bool plainText = false,
    bool allowImages = true,
  }) async {
    final text = data.text ?? '';
    final sourceIsMarkdown = RegExp(
      r'(^|\n)\s{0,3}(#{1,6} |[-*+] |\d+[.)] |```)|\*\*[^\n]+\*\*|\*[^\s*][^\n]*\*|__[^\n]+__',
    ).hasMatch(text);
    Document? document;
    if (!plainText &&
        !sourceIsMarkdown &&
        data.html?.trim().isNotEmpty == true) {
      final rich = documentFromClipboardHtml(data.html!);
      if (rich.root.children.any(
        (node) =>
            node.delta?.toPlainText().trim().isNotEmpty == true ||
            node.children.isNotEmpty,
      )) {
        document = rich;
      }
    }
    if (!plainText && document == null && data.images.isNotEmpty) {
      if (!allowImages) throw StateError('请在聊天输入框中粘贴图片');
      final decoded = <PendingImage>[];
      for (final bytes in data.images) {
        decoded.add(await PendingImage.decode(bytes));
      }
      if (!_disposed) {
        images.addAll(decoded);
        notifyListeners();
      }
      return;
    }
    if (document == null && text.isEmpty) return;
    document ??=
        plainText
            ? Document(
              root: pageNode(
                children:
                    text
                        .replaceAll('\r\n', '\n')
                        .replaceAll('\r', '\n')
                        .split('\n')
                        .map(
                          (line) => paragraphNode(delta: Delta()..insert(line)),
                        )
                        .toList(),
              ),
            )
            : markdownToDocument(
              prepareExtendedMarkdown(text),
              customParsers: [MathBlockMarkdownParser()],
              customInlineSyntaxes: [InlineMathSyntax()],
            );
    final nodes = document.root.children.toList();
    if (nodes.isEmpty || _disposed) return;
    editorState.selection ??= Selection.collapsed(Position(path: [0]));
    if (nodes.length == 1) {
      await editorState.pasteSingleLineNode(nodes.first);
    } else {
      await editorState.pasteMultiLineNodes(nodes);
    }
    _markdown = _exportMarkdown();
    notifyListeners();
  }

  void setMarkdown(String value) {
    _subscription?.cancel();
    editorState.dispose();
    _replaceState(value);
    notifyListeners();
  }

  void clear() {
    images.clear();
    setMarkdown('');
  }

  /// Rebuilds the WYSIWYG document from its current Markdown representation.
  /// This is intentionally manual so a user can recover if an editor shortcut
  /// was not converted into a rendered block while typing.
  void refreshRendering() {
    final currentMarkdown = _exportMarkdown();
    setMarkdown(currentMarkdown);
  }

  String _exportMarkdown() =>
      documentToMarkdown(
        editorState.document,
        customParsers: const [MathBlockMarkdownEncoder()],
      ).trimRight();

  void _replaceState(String value) {
    _markdown = value;
    editorState = EditorState(
      document:
          value.trim().isEmpty
              ? Document.blank(withInitialText: true)
              : markdownToDocument(
                prepareExtendedMarkdown(value),
                customParsers: [MathBlockMarkdownParser()],
                customInlineSyntaxes: [InlineMathSyntax()],
              ),
    );
    _subscription = editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) {
        _markdown = _exportMarkdown();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    editorState.dispose();
    super.dispose();
  }
}

class WysiwygMarkdownEditor extends StatelessWidget {
  const WysiwygMarkdownEditor({
    super.key,
    required this.controller,
    this.autoFocus = false,
    this.showToolbar = true,
    this.onSubmit,
    this.allowImages = true,
  });

  final WysiwygMarkdownController controller;
  final bool autoFocus;
  final bool showToolbar;
  final VoidCallback? onSubmit;
  final bool allowImages;

  Future<void> _paste(BuildContext context, {bool plain = false}) async {
    try {
      await controller.pasteFromClipboard(
        plainText: plain,
        allowImages: allowImages,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('粘贴失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactParagraphConfiguration = BlockComponentConfiguration(
      padding: (_) => const EdgeInsets.symmetric(vertical: 3),
      textStyle: (node) => const TextStyle(height: 1.4),
    );
    return ListenableBuilder(
      listenable: controller,
      builder:
          (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showToolbar)
                _EditorToolbar(
                  editorState: controller.editorState,
                  onPaste: controller.pasting ? null : () => _paste(context),
                ),
              Expanded(
                child: AppFlowyEditor(
                  key: ValueKey(controller.editorState),
                  editorState: controller.editorState,
                  autoFocus: autoFocus,
                  contextMenuItems: [
                    [
                      ContextMenuItem(
                        getName: () => '剪切',
                        onPressed: handleCut,
                      ),
                      ContextMenuItem(
                        getName: () => '复制',
                        onPressed: handleCopy,
                      ),
                      ContextMenuItem(
                        getName: () => '粘贴',
                        onPressed: (_) => _paste(context),
                      ),
                    ],
                  ],
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
                      configuration: compactParagraphConfiguration,
                    ),
                    CodeBlockKeys.type: CodeBlockComponentBuilder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                      styleBuilder:
                          () => CodeBlockStyle(
                            backgroundColor:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    mathBlockType: MathBlockComponentBuilder(),
                  },
                  characterShortcutEvents: [
                    _formatFenceToCodeBlock,
                    ...codeBlockCharacterEvents,
                    ...standardCharacterShortcutEvents,
                  ],
                  commandShortcutEvents: [
                    CommandShortcutEvent(
                      key: 'promptbox paste',
                      getDescription: () => '粘贴图片 / Markdown / 富文本',
                      command: 'ctrl+v',
                      macOSCommand: 'cmd+v',
                      handler: (_) {
                        _paste(context);
                        return KeyEventResult.handled;
                      },
                    ),
                    CommandShortcutEvent(
                      key: 'promptbox paste plain',
                      getDescription: () => '粘贴纯文本',
                      command: 'ctrl+shift+v',
                      macOSCommand: 'cmd+shift+v',
                      handler: (_) {
                        _paste(context, plain: true);
                        return KeyEventResult.handled;
                      },
                    ),
                    if (onSubmit != null)
                      CommandShortcutEvent(
                        key: 'send prompt',
                        getDescription: () => '发送 Prompt',
                        command: 'ctrl+enter',
                        macOSCommand: 'ctrl+enter,cmd+enter',
                        handler: (_) {
                          onSubmit!();
                          return KeyEventResult.handled;
                        },
                      ),
                    ...codeBlockCommands(),
                    ...standardCommandShortcutEvents,
                  ],
                  editorStyle: EditorStyle.desktop(
                    textScaleFactor:
                        MediaQuery.textScalerOf(context).scale(15) / 15,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    cursorColor: Theme.of(context).colorScheme.primary,
                    selectionColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .22),
                    textStyleConfiguration: TextStyleConfiguration(
                      text: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      bold: const TextStyle(fontWeight: FontWeight.w700),
                      italic: const TextStyle(fontStyle: FontStyle.italic),
                      code: TextStyle(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        backgroundColor:
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    textSpanDecorator: promptBoxTextSpanDecorator,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.editorState, this.onPaste});
  final EditorState editorState;
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      children: [
        IconButton(
          tooltip: '粘贴图片 / Markdown / 富文本',
          visualDensity: VisualDensity.compact,
          iconSize: 19,
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste),
        ),
        _button(
          Icons.format_bold,
          '粗体',
          () => editorState.toggleAttribute(AppFlowyRichTextKeys.bold),
        ),
        _button(
          Icons.format_italic,
          '斜体',
          () => editorState.toggleAttribute(AppFlowyRichTextKeys.italic),
        ),
        _button(
          Icons.code,
          '行内代码',
          () => editorState.toggleAttribute(AppFlowyRichTextKeys.code),
        ),
        const VerticalDivider(indent: 8, endIndent: 8),
        _button(
          Icons.title,
          '标题',
          () =>
              _formatBlock(HeadingBlockKeys.type, {HeadingBlockKeys.level: 2}),
        ),
        _button(Icons.notes, '正文', () => _formatBlock(ParagraphBlockKeys.type)),
        _button(
          Icons.format_list_bulleted,
          '项目列表',
          () => _formatBlock(BulletedListBlockKeys.type),
        ),
        _button(
          Icons.format_list_numbered,
          '编号列表',
          () => _formatBlock(NumberedListBlockKeys.type),
        ),
        _button(
          Icons.format_quote,
          '引用',
          () => _formatBlock(QuoteBlockKeys.type),
        ),
        _button(Icons.data_object, '代码块', _formatCodeBlock),
        _button(Icons.functions, '公式块', _formatMathBlock),
      ],
    ),
  );

  Widget _button(IconData icon, String tooltip, VoidCallback action) =>
      IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 19,
        onPressed: action,
        icon: Icon(icon),
      );

  void _formatBlock(String type, [Map<String, dynamic> attributes = const {}]) {
    editorState.formatNode(
      null,
      (node) => node.copyWith(
        type: type,
        attributes: {...node.attributes, ...attributes},
      ),
    );
  }

  void _formatCodeBlock() {
    editorState.formatNode(
      null,
      (node) => codeBlockNode(delta: node.delta, language: 'auto'),
    );
  }

  void _formatMathBlock() {
    editorState.formatNode(
      null,
      (node) => mathBlockNode(
        node.delta?.toPlainText().trim().isNotEmpty == true
            ? node.delta!.toPlainText().trim()
            : r'x^2',
      ),
    );
  }
}
