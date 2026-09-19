import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_box/models.dart';
import 'package:prompt_box/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late JsonPromptStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('prompt_box_test_');
    store = JsonPromptStore(temp.path);
  });
  tearDown(() async => temp.delete(recursive: true));

  test('日期数据写入后可完整读取且路径由 path API 生成', () async {
    final date = DateTime(2026, 9, 18);
    final entry = PromptEntry(
      id: 'one',
      content: '# 任务\n正文',
      createdAt: date,
      updatedAt: date,
      tagIds: ['tag'],
    );
    await store.writeDay(DayRecord(date: date, entries: [entry]));
    final loaded = await store.readDay(date);
    expect(loaded.entries.single.content, '# 任务\n正文');
    expect(loaded.entries.single.tagIds, ['tag']);
    expect(
      await File(
        p.join(temp.path, 'days', '2026', '09', '2026-09-18.json'),
      ).exists(),
      isTrue,
    );
  });
  test('历史日期按新到旧列出', () async {
    await store.writeDay(DayRecord(date: DateTime(2026, 9, 10)));
    await store.writeDay(DayRecord(date: DateTime(2026, 9, 18)));
    expect((await store.listDays()).map(dateKey), ['2026-09-18', '2026-09-10']);
  });
  test('标签与周简介持久化', () async {
    await store.writeTags([
      const TagDefinition(
        id: 't',
        name: '重构',
        colorValue: 0xff112233,
        description: '核心模块',
      ),
    ]);
    await store.writeWeekNotes([
      WeekNote(year: 2026, week: 38, summary: '完成迁移', tagIds: ['t']),
    ]);
    expect((await store.readTags()).single.name, '重构');
    expect((await store.readTags()).single.description, '核心模块');
    expect((await store.readWeekNotes()).single.summary, '完成迁移');
  });
  test('数据库目录可复制备份和恢复', () async {
    await store.writeDay(
      DayRecord(
        date: DateTime(2026, 9, 18),
        entries: [
          PromptEntry(
            id: '1',
            content: 'backup',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      ),
    );
    final backup = p.join(temp.parent.path, '${p.basename(temp.path)}_backup');
    addTearDown(() async {
      final dir = Directory(backup);
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await StorageLocation.copyDatabase(temp.path, backup);
    expect(
      (await JsonPromptStore(
        backup,
      ).readDay(DateTime(2026, 9, 18))).entries.single.content,
      'backup',
    );
  });

  test('自定义数据库路径在模拟重启后仍可解析', () async {
    final selected = p.join(temp.parent.path, 'custom_prompt_box');
    await StorageLocation.remember(selected);
    expect(await StorageLocation.resolve(), p.normalize(selected));
  });

  test('settings survive application bundle replacement', () async {
    final selected = p.join(temp.parent.path, 'persistent_prompt_box');
    await StorageLocation.remember(selected);
    await AppPreferences.writeString(AppPreferences.themePreferenceKey, 'dark');

    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();

    expect(await StorageLocation.resolve(), p.normalize(selected));
    expect(
      await AppPreferences.readString(AppPreferences.themePreferenceKey),
      'dark',
    );
  });

  test('拒绝将数据库递归复制到自身子目录', () async {
    expect(
      () =>
          StorageLocation.copyDatabase(temp.path, p.join(temp.path, 'backup')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('原子写入中断后可从备份文件恢复', () async {
    final date = DateTime(2026, 9, 18);
    await store.writeDay(
      DayRecord(
        date: date,
        entries: [
          PromptEntry(
            id: 'recover',
            content: '可恢复',
            createdAt: date,
            updatedAt: date,
          ),
        ],
      ),
    );
    final file = File(
      p.join(temp.path, 'days', '2026', '09', '2026-09-18.json'),
    );
    await file.rename('${file.path}.bak');
    expect((await store.readDay(date)).entries.single.content, '可恢复');
    expect(await file.exists(), isTrue);
  });
}
