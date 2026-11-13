import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Keep clipboard HTML semantic and local: no scripts, remote image fetching,
/// browser stylesheets, or file references are executed by the importer.
Document documentFromClipboardHtml(String source) {
  final document = html.parse(source);
  final nodes = _blocks(document.body?.nodes ?? []);
  return Document(
    root: pageNode(children: nodes.isEmpty ? [paragraphNode()] : nodes),
  );
}

const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'main',
  'header',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'table',
  'hr',
};
const _ignoredTags = {'script', 'style', 'meta', 'link', 'head', 'noscript'};

List<Node> _blocks(List<dom.Node> input) {
  final result = <Node>[];
  final inline = <dom.Node>[];
  void append(Node node, {bool separate = false}) {
    if (separate &&
        result.isNotEmpty &&
        result.last.type == ParagraphBlockKeys.type &&
        result.last.delta?.isNotEmpty == true &&
        node.delta?.isNotEmpty == true) {
      result.add(paragraphNode());
    }
    result.add(node);
  }

  void flush() {
    if (inline.isEmpty) return;
    final delta = _inline(inline);
    if (delta.toPlainText().trim().isNotEmpty) {
      append(paragraphNode(delta: delta), separate: true);
    }
    inline.clear();
  }

  for (final item in input) {
    if (item is! dom.Element || !_blockTags.contains(item.localName)) {
      inline.add(item);
      continue;
    }
    flush();
    final tag = item.localName!;
    if (tag == 'ul' || tag == 'ol') {
      for (final li in item.children.where(
        (element) => element.localName == 'li',
      )) {
        final nested =
            li.children
                .where(
                  (element) =>
                      element.localName == 'ul' || element.localName == 'ol',
                )
                .toList();
        final delta = _inline(
          li.nodes.where((node) => !nested.contains(node)).toList(),
        );
        final node = Node(
          type:
              tag == 'ul'
                  ? BulletedListBlockKeys.type
                  : NumberedListBlockKeys.type,
          attributes: {'delta': delta.toJson()},
          children: _blocks(nested),
        );
        append(node);
      }
    } else if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      append(
        headingNode(
          level: int.parse(tag.substring(1)),
          delta: _inline(item.nodes),
        ),
      );
    } else if (tag == 'pre') {
      final code = item.querySelector('code');
      final language =
          RegExp(
            r'language-([\w+-]+)',
          ).firstMatch(code?.className ?? '')?.group(1) ??
          'auto';
      append(
        codeBlockNode(
          delta: Delta()..insert(code?.text ?? item.text),
          language: language,
        ),
      );
    } else if (tag == 'blockquote') {
      final children = _blocks(item.nodes);
      append(
        quoteNode(
          delta: children.firstOrNull?.delta ?? Delta(),
          children: children.skip(1).toList(),
        ),
      );
    } else if (tag == 'table') {
      result.addAll(htmlToDocument(item.outerHtml).root.children);
    } else if (tag == 'hr') {
      append(dividerNode());
    } else if (item.children.any(
      (child) => _blockTags.contains(child.localName),
    )) {
      result.addAll(_blocks(item.nodes));
    } else {
      append(paragraphNode(delta: _inline(item.nodes)), separate: true);
    }
  }
  flush();
  return result;
}

Delta _inline(
  List<dom.Node> nodes, [
  Map<String, dynamic> attributes = const {},
]) {
  final delta = Delta();
  for (final node in nodes) {
    if (node is dom.Text) {
      delta.insert(node.data.replaceAll('\r\n', '\n'), attributes: attributes);
    } else if (node is dom.Element) {
      final tag = node.localName;
      if (_ignoredTags.contains(tag)) continue;
      if (tag == 'br') {
        delta.insert('\n', attributes: attributes);
        continue;
      }
      if (tag == 'img') continue;
      final style = {
        for (final rule in (node.attributes['style'] ?? '').split(';'))
          if (rule.contains(':'))
            rule.split(':').first.trim().toLowerCase():
                rule.substring(rule.indexOf(':') + 1).trim().toLowerCase(),
      };
      final attrs = <String, dynamic>{...attributes};
      final weight = style['font-weight'];
      if (tag == 'strong' ||
          tag == 'b' ||
          weight == 'bold' ||
          (int.tryParse(weight ?? '') ?? 0) >= 600) {
        attrs[AppFlowyRichTextKeys.bold] = true;
      }
      if (tag == 'em' || tag == 'i' || style['font-style'] == 'italic') {
        attrs[AppFlowyRichTextKeys.italic] = true;
      }
      if (tag == 'code') attrs[AppFlowyRichTextKeys.code] = true;
      if (tag == 'u') attrs[AppFlowyRichTextKeys.underline] = true;
      if (tag == 'del' || tag == 's') {
        attrs[AppFlowyRichTextKeys.strikethrough] = true;
      }
      if (tag == 'a' && node.attributes['href'] != null) {
        attrs[AppFlowyRichTextKeys.href] = node.attributes['href'];
      }
      delta.addAll(_inline(node.nodes, attrs));
    }
  }
  return delta;
}
