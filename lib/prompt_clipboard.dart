import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

class PromptClipboardData {
  const PromptClipboardData({this.text, this.html, this.images = const []});
  final String? text, html;
  final List<Uint8List> images;
}

/// Reading occurs only on an explicit paste gesture, never in the background.
class PromptClipboard {
  static Future<PromptClipboardData> read() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return PromptClipboardData(
        text: (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      );
    }
    final reader = await clipboard.read();
    final html = await reader.readValue(Formats.htmlText);
    final text = await reader.readValue(Formats.plainText);
    final images = <Uint8List>[];
    for (final item in reader.items) {
      final format =
          item.canProvide(Formats.png)
              ? Formats.png
              : item.canProvide(Formats.jpeg)
              ? Formats.jpeg
              : null;
      if (format != null) {
        final completer = Completer<Uint8List>();
        final progress = item.getFile(format, (file) async {
          try {
            completer.complete(await file.readAll());
          } catch (error, stack) {
            completer.completeError(error, stack);
          }
        }, onError: completer.completeError);
        if (progress != null) images.add(await completer.future);
      } else {
        final uri = await item.readValue(Formats.fileUri);
        if (uri != null &&
            uri.scheme == 'file' &&
            RegExp(
              r'\.(png|jpe?g|gif|webp|bmp)$',
              caseSensitive: false,
            ).hasMatch(uri.path)) {
          images.add(await File.fromUri(uri).readAsBytes());
        }
      }
    }
    return PromptClipboardData(text: text, html: html, images: images);
  }
}
