import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_box/image_storage.dart';
import 'package:prompt_box/update_draft.dart';

void main() {
  test('升级草稿保存文字、PNG和计划日期，恢复后不重复恢复旧备份', () async {
    final directory = await Directory.systemTemp.createTemp(
      'promptbox-update-draft-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'draft.json'));
    final store = UpdateDraftStore(file: () async => file);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await store.save('较早草稿', []);
    await store.save('**尚未发送**\n\n第二段', [
      PendingImage(pngBytes: bytes, width: 1, height: 1),
    ], plannedDate: DateTime(2026, 11, 14));
    final draft = await store.read();
    expect(draft!.markdown, '**尚未发送**\n\n第二段');
    expect(draft.images.single.pngBytes, bytes);
    expect(draft.plannedDate, DateTime(2026, 11, 14));
    await store.consume();
    expect(await store.read(), isNull);
    await store.save('第二次更新的草稿', []);
    await store.consume();
    expect(await store.read(), isNull);
    expect(await File('${file.path}.restored').exists(), isTrue);
  });
}
