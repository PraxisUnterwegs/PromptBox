import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/material.dart';

import 'markdown_extensions.dart';

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

  String get markdown => _markdown;
  bool get isEmpty => _markdown.trim().isEmpty;

  void setMarkdown(String value) {
    _subscription?.cancel();
    editorState.dispose();
    _replaceState(value);
    notifyListeners();
  }

  void clear() => setMarkdown('');

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
  });

  final WysiwygMarkdownController controller;
  final bool autoFocus;
  final bool showToolbar;

  @override
  Widget build(BuildContext context) {
    final compactParagraphConfiguration = BlockComponentConfiguration(
      padding: (_) => EdgeInsets.zero,
      textStyle:
          (node) =>
              node.delta?.isEmpty ?? true
                  ? const TextStyle(fontSize: 8, height: 1)
                  : const TextStyle(height: 1.18),
    );
    return ListenableBuilder(
      listenable: controller,
      builder:
          (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showToolbar)
                _EditorToolbar(editorState: controller.editorState),
              Expanded(
                child: AppFlowyEditor(
                  key: ValueKey(controller.editorState),
                  editorState: controller.editorState,
                  autoFocus: autoFocus,
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
                    ...codeBlockCommands(),
                    ...standardCommandShortcutEvents,
                  ],
                  editorStyle: EditorStyle.desktop(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    cursorColor: Theme.of(context).colorScheme.primary,
                    selectionColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .22),
                    textStyleConfiguration: TextStyleConfiguration(
                      text: TextStyle(
                        fontSize: 15,
                        height: 1.18,
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
  const _EditorToolbar({required this.editorState});
  final EditorState editorState;

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
