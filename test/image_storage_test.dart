import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_box/app_controller.dart';
import 'package:prompt_box/image_storage.dart';
import 'package:prompt_box/models.dart';
import 'package:prompt_box/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStore extends JsonPromptStore {
  _FailingStore(super.rootPath);
  bool failWrites = false;
  @override
  Future<void> writeDay(DayRecord day) async {
    if (failWrites) throw const FileSystemException('simulated write failure');
    await super.writeDay(day);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PendingImage image;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('promptbox-images-');
    image = PendingImage(
      pngBytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      width: 1,
      height: 1,
    );
  });
  tearDown(() async => temp.delete(recursive: true));

  test('图片仅按年月建目录，同一天跨重启继续编号，次日从01开始', () async {
    final store = PromptImageStorage(temp.path);
    final first = await store.save(DateTime(2026, 11, 13), [image, image]);
    expect(first.map((item) => item.relativePath), [
      'days/2026_image/11/2026-11-13_Image01.png',
      'days/2026_image/11/2026-11-13_Image02.png',
    ]);
    final third = await PromptImageStorage(
      temp.path,
    ).save(DateTime(2026, 11, 13), [image]);
    expect(third.single.relativePath, endsWith('Image03.png'));
    final tomorrow = await store.save(DateTime(2026, 11, 14), [image]);
    expect(
      tomorrow.single.relativePath,
      'days/2026_image/11/2026-11-14_Image01.png',
    );
    expect(
      await Directory(
        p.join(temp.path, 'days', '2026_image', '11', '13'),
      ).exists(),
      isFalse,
    );
    expect(
      await File(
        PromptImageStorage.resolve(temp.path, first.first.relativePath),
      ).readAsBytes(),
      image.pngBytes,
    );
    expect(first.first.sha256, sha256.convert(image.pngBytes).toString());
  });

  test('并发保存不覆盖已有文件，跨月跨年保持结构', () async {
    final date = DateTime(2026, 11, 13);
    final results = await Future.wait(
      List.generate(
        3,
        (_) => PromptImageStorage(temp.path).save(date, [image]),
      ),
    );
    expect(
      results.expand((items) => items).map((item) => item.relativePath).toSet(),
      hasLength(3),
    );
    expect(
      (await PromptImageStorage(
        temp.path,
      ).save(DateTime(2026, 12, 1), [image])).single.relativePath,
      'days/2026_image/12/2026-12-01_Image01.png',
    );
    expect(
      (await PromptImageStorage(
        temp.path,
      ).save(DateTime(2027, 1, 1), [image])).single.relativePath,
      'days/2027_image/01/2027-01-01_Image01.png',
    );
  });

  test('图片消息写入JSON，重启和迁移后相对路径仍能读取', () async {
    final store = JsonPromptStore(temp.path);
    final controller = PromptBoxController(
      store: store,
      clock: () => DateTime(2026, 11, 13),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.addPrompt('', images: [image]);
    final saved = (await store.readDay(DateTime(2026, 11, 13))).entries.single;
    expect(saved.content, isEmpty);
    expect(saved.title, '图片 · 1 张');
    expect(saved.toJson()['images'], isNotEmpty);
    final destination = await Directory.systemTemp.createTemp(
      'promptbox-image-migration-',
    );
    addTearDown(() => destination.delete(recursive: true));
    await StorageLocation.copyDatabase(temp.path, destination.path);
    final moved =
        (await JsonPromptStore(
          destination.path,
        ).readDay(DateTime(2026, 11, 13))).entries.single;
    expect(
      await File(
        PromptImageStorage.resolve(
          destination.path,
          moved.images.single.relativePath,
        ),
      ).readAsBytes(),
      image.pngBytes,
    );
  });

  test('JSON写入失败时移除新图片和失败条目，不影响草稿或旧文件', () async {
    final store = _FailingStore(temp.path);
    final controller = PromptBoxController(
      store: store,
      clock: () => DateTime(2026, 11, 13),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    store.failWrites = true;
    await expectLater(
      controller.addPrompt('待重试', images: [image]),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.currentDay!.entries, isEmpty);
    final files =
        await Directory(
          p.join(temp.path, 'days'),
        ).list(recursive: true).where((entity) => entity is File).toList();
    expect(files, isEmpty);
  });

  test('旧JSON兼容且拒绝越界图片路径', () {
    final now = DateTime(2026, 11, 13);
    final original = PromptEntry(
      id: 'old',
      content: '旧文字',
      createdAt: now,
      updatedAt: now,
    );
    expect(PromptEntry.fromJson(original.toJson()).images, isEmpty);
    for (final unsafe in [
      '../secret.png',
      '/tmp/image.png',
      'days/2026_image/11/../../secret.png',
    ]) {
      expect(
        () => PromptImageStorage.resolve(temp.path, unsafe),
        throwsFormatException,
      );
    }
  });
}
