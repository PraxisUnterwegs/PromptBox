import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
// AppFlowy 2.x does not export its custom Markdown parser interface.
// ignore: implementation_imports
import 'package:appflowy_editor/src/plugins/markdown/decoder/parser/custom_node_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

const mathBlockType = 'promptbox_math';
const mathFormulaKey = 'formula';
const _mathSentinel = ':::promptbox-math:';

String prepareExtendedMarkdown(String source) {
  source = _normalizeCodeFences(source);
  final protectedSegments = RegExp(r'```[\s\S]*?```|\$\$[\s\S]*?\$\$');
  final prepared = source.replaceAllMapped(protectedSegments, (match) {
    final value = match.group(0)!;
    if (value.startsWith('```')) return value;
    final formula = value.substring(2, value.length - 2).trim();
    final encoded = base64Url.encode(utf8.encode(formula));
    return '\n$_mathSentinel$encoded\n';
  });
  return _removeStructuralBlankLines(prepared);
}

String _removeStructuralBlankLines(String source) {
  final lines = source.split('\n');
  final compacted = <String>[];
  var insideCodeFence = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      compacted.add(line);
      final hasClosingFence = trimmed.indexOf('```', 3) >= 0;
      if (!hasClosingFence) insideCodeFence = !insideCodeFence;
      continue;
    }
    // Markdown uses blank lines as structural separators. The editor already
    // represents each block separately, so keeping those lines creates large,
    // editable empty paragraphs between every heading and paragraph.
    if (!insideCodeFence && trimmed.isEmpty) continue;
    compacted.add(line);
  }
  return compacted.join('\n');
}

String _normalizeCodeFences(String source) {
  final lines = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var insideFence = false;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (!insideFence && trimmed.startsWith('```')) {
      // AppFlowy 2.x only recognizes fences at column zero and its closing
      // check is sensitive to trailing whitespace/Windows line endings.
      lines[i] = trimmed;
      if (trimmed.length > 3 && trimmed.substring(3).contains('```')) {
        continue;
      }
      insideFence = true;
    } else if (insideFence && RegExp(r'^```\s*$').hasMatch(trimmed)) {
      lines[i] = '```';
      insideFence = false;
    }
  }
  return lines.join('\n');
}

class MathBlockMarkdownParser extends CustomNodeParser {
  MathBlockMarkdownParser();

  @override
  Node? transform(String input) {
    if (!input.startsWith(_mathSentinel)) return null;
    try {
      final formula = utf8.decode(
        base64Url.decode(input.substring(_mathSentinel.length)),
      );
      return mathBlockNode(formula);
    } on FormatException {
      return null;
    }
  }
}

class MathBlockMarkdownEncoder extends NodeParser {
  const MathBlockMarkdownEncoder();
  @override
  String get id => mathBlockType;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final formula = node.attributes[mathFormulaKey] as String? ?? '';
    return '\$\$\n$formula\n\$\$${node.next == null ? '' : '\n'}';
  }
}

Node mathBlockNode(String formula) =>
    Node(type: mathBlockType, attributes: {mathFormulaKey: formula});

class InlineMathSyntax extends md.InlineSyntax {
  InlineMathSyntax() : super(r'(?<!\\)\$(?!\$)([^\$\n]+?)(?<!\\)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match.group(1) ?? '';
    final element = md.Element.text('promptbox-inline-math', match.group(0)!);
    element.attributes[mathFormulaKey] = jsonEncode(formula);
    parser.addNode(element);
    return true;
  }
}

class DisplayMathBlockSyntax extends md.BlockSyntax {
  const DisplayMathBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  md.Node parse(md.BlockParser parser) {
    final openingLine = parser.current.content;
    final opening = openingLine.indexOf(r'$$');
    final afterOpening = openingLine.substring(opening + 2);
    final formulaLines = <String>[];

    final sameLineClose = afterOpening.indexOf(r'$$');
    if (sameLineClose >= 0) {
      formulaLines.add(afterOpening.substring(0, sameLineClose));
      parser.advance();
    } else {
      if (afterOpening.isNotEmpty) formulaLines.add(afterOpening);
      parser.advance();
      while (!parser.isDone) {
        final line = parser.current.content;
        final closing = line.indexOf(r'$$');
        if (closing >= 0) {
          formulaLines.add(line.substring(0, closing));
          parser.advance();
          break;
        }
        formulaLines.add(line);
        parser.advance();
      }
    }

    final formula = formulaLines.join('\n').trim();
    // Keep the custom block childless. flutter_markdown treats text children
    // under custom block elements as an unfinished inline span.
    final element = md.Element('promptbox-display-math', const <md.Node>[]);
    element.attributes[mathFormulaKey] = jsonEncode(formula);
    return element;
  }
}

InlineSpan promptBoxTextSpanDecorator(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final encoded = text.attributes?[mathFormulaKey] as String?;
  if (encoded == null) {
    return defaultTextSpanDecoratorForAttribute(
      context,
      node,
      index,
      text,
      before,
      after,
    );
  }
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Math.tex(
        encoded,
        textStyle: before.style,
        onErrorFallback: (_) => Text(text.text, style: before.style),
      ),
    ),
  );
}

class MathBlockComponentBuilder extends BlockComponentBuilder {
  MathBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MathBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }
}

class MathBlockComponent extends BlockComponentStatelessWidget {
  const MathBlockComponent({
    super.key,
    required super.node,
    required super.configuration,
  });

  @override
  Widget build(BuildContext context) {
    final formula = node.attributes[mathFormulaKey] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onDoubleTap: () => _editFormula(context, formula),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              formula,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
              ),
              onErrorFallback: (_) => Text('公式语法错误：$formula'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editFormula(BuildContext context, String formula) async {
    final editorState = context.read<EditorState>();
    final text = TextEditingController(text: formula);
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('编辑 LaTeX 公式'),
            content: SizedBox(
              width: 520,
              child: TextField(
                controller: text,
                minLines: 3,
                maxLines: 8,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: r'例如：\frac{a}{b} = c',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, text.text),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    text.dispose();
    if (result != null) {
      final transaction =
          editorState.transaction..updateNode(node, {mathFormulaKey: result});
      await editorState.apply(transaction);
    }
  }
}

class MathElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final raw = element.attributes[mathFormulaKey];
    if (raw == null) return null;
    final formula = jsonDecode(raw) as String;
    return Math.tex(
      formula,
      textStyle: preferredStyle,
      onErrorFallback: (_) => Text(element.textContent, style: preferredStyle),
    );
  }
}

class DisplayMathElementBuilder extends MathElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final raw = element.attributes[mathFormulaKey];
    if (raw == null) return null;
    final formula = jsonDecode(raw) as String;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          formula,
          mathStyle: MathStyle.display,
          textStyle: preferredStyle?.copyWith(fontSize: 18),
          onErrorFallback:
              (_) => Text(element.textContent, style: preferredStyle),
        ),
      ),
    );
  }
}

class ExtendedMarkdownBody extends StatelessWidget {
  const ExtendedMarkdownBody({
    super.key,
    required this.data,
    this.selectable = true,
  });
  final String data;
  final bool selectable;

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    selectable: selectable,
    softLineBreak: true,
    blockSyntaxes: const [DisplayMathBlockSyntax()],
    inlineSyntaxes: [InlineMathSyntax()],
    builders: {
      'promptbox-inline-math': MathElementBuilder(),
      'promptbox-display-math': DisplayMathElementBuilder(),
    },
  );
}
