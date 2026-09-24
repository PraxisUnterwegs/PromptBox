import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_box/app_controller.dart';
import 'package:prompt_box/models.dart';
import 'package:prompt_box/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late DateTime now;
  late PromptBoxController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('prompt_box_controller_');
    now = DateTime(2026, 9, 18, 10);
    controller = PromptBoxController(
      store: JsonPromptStore(temp.path),
      clock: () => now,
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await temp.delete(recursive: true);
  });
  test('停机跨多天后，今天窗口为空且旧数据留在历史日期', () async {
    await controller.addPrompt('第一天');
    now = DateTime(2026, 9, 23, 9);
    await controller.checkDateRollover();
    expect(dateKey(controller.selectedDate!), '2026-09-23');
    expect(controller.currentDay!.entries, isEmpty);
    expect(controller.availableDays.map(dateKey), contains('2026-09-18'));
    await controller.selectDate(DateTime(2026, 9, 18));
    expect(controller.currentDay!.entries.single.content, '第一天');
  });
  test('正文和标签均可过滤', () async {
    await controller.createTag('DMP', 0xff0000ff);
    await controller.addPrompt('轨迹平滑');
    final entry = controller.currentDay!.entries.single;
    await controller.toggleTag(entry, controller.tags.single.id);
    controller.setQuery('轨迹');
    expect(controller.filteredEntries, [entry]);
    controller.setQuery('DMP');
    expect(controller.filteredEntries, [entry]);
    controller.setQuery('不存在');
    expect(controller.filteredEntries, isEmpty);
  });

  test('标签备注可创建并再次编辑', () async {
    final tag = await controller.createTag(
      '架构',
      0xff123456,
      description: '旧备注',
    );
    await controller.updateTag(tag!, name: '架构', description: '新备注');
    expect(controller.tags.single.description, '新备注');
    expect(
      (await JsonPromptStore(temp.path).readTags()).single.description,
      '新备注',
    );
  });
  test('编辑删除和排序都会持久化', () async {
    await controller.addPrompt('A');
    now = now.add(const Duration(seconds: 1));
    await controller.addPrompt('B');
    await controller.movePrompt(controller.currentDay!.entries.last, -1);
    await controller.editPrompt(controller.currentDay!.entries.first, 'B2');
    await controller.deletePrompt(controller.currentDay!.entries.last);
    final loaded = await JsonPromptStore(temp.path).readDay(now);
    expect(loaded.entries.single.content, 'B2');
  });

  test('主题选项即时更新并持久化', () async {
    await controller.setThemePreference(AppThemePreference.dark);
    expect(controller.themePreference, AppThemePreference.dark);
    final restarted = PromptBoxController(
      store: JsonPromptStore(temp.path),
      clock: () => now,
    );
    await restarted.initialize();
    expect(restarted.themePreference, AppThemePreference.dark);
    restarted.dispose();
  });
  test('quick access persists references and edits the original day', () async {
    await controller.addPrompt('first reusable prompt');
    final first = controller.currentDay!.entries.single;
    await controller.toggleQuickAccess(first);

    now = DateTime(2026, 9, 19, 11);
    await controller.checkDateRollover();
    await controller.addPrompt('second reusable prompt');
    final second = controller.currentDay!.entries.single;
    await controller.toggleQuickAccess(second);

    await controller.selectQuickAccess();
    expect(controller.quickAccessEntries.map((entry) => entry.content), [
      'first reusable prompt',
      'second reusable prompt',
    ]);

    await controller.editPrompt(
      controller.quickAccessEntries.first,
      'edited reusable prompt',
    );
    final original = await JsonPromptStore(
      temp.path,
    ).readDay(DateTime(2026, 9, 18));
    expect(original.entries.single.content, 'edited reusable prompt');

    final restarted = PromptBoxController(
      store: JsonPromptStore(temp.path),
      clock: () => now,
    );
    await restarted.initialize();
    await restarted.selectQuickAccess();
    expect(restarted.quickAccessEntries, hasLength(2));
    expect(
      restarted.quickAccessEntries.first.content,
      'edited reusable prompt',
    );
    restarted.dispose();
  });

  test('quick access supports tag filtering and unpinning', () async {
    final tag = await controller.createTag(
      'Reusable',
      0xff123456,
      description: 'frequent prompts',
    );
    await controller.addPrompt('tagged prompt');
    final entry = controller.currentDay!.entries.single;
    await controller.toggleTag(entry, tag!.id);
    await controller.toggleQuickAccess(entry);

    await controller.selectQuickAccess();
    controller.setTagFilter(tag.id);
    expect(controller.filteredEntries.single.content, 'tagged prompt');
    controller.setQuery('missing');
    expect(controller.filteredEntries, isEmpty);
    controller.setQuery('');

    await controller.toggleQuickAccess(controller.quickAccessEntries.single);
    expect(controller.quickAccessEntries, isEmpty);
    expect(
      (await JsonPromptStore(
        temp.path,
      ).readDay(DateTime(2026, 9, 18))).entries.single.content,
      'tagged prompt',
    );
  });

  test('大纲名称可选、可搜索，并与原日期及快速访问同步', () async {
    await controller.addPrompt('# 自动标题\n正文');
    final entry = controller.currentDay!.entries.single;
    expect(entry.outlineTitle, '自动标题');

    await controller.setOutlineName(entry, '  重要流程  ');
    expect(entry.outlineTitle, '重要流程');
    controller.setQuery('重要流程');
    expect(controller.filteredEntries, [entry]);
    controller.setQuery('');

    await controller.toggleQuickAccess(entry);
    await controller.selectQuickAccess();
    expect(controller.quickAccessEntries.single.outlineTitle, '重要流程');
    expect(
      (await JsonPromptStore(
        temp.path,
      ).readDay(now)).entries.single.outlineName,
      '重要流程',
    );

    await controller.setOutlineName(controller.quickAccessEntries.single, '  ');
    expect(controller.quickAccessEntries.single.outlineTitle, '自动标题');
    expect(
      (await JsonPromptStore(
        temp.path,
      ).readDay(now)).entries.single.outlineName,
      isNull,
    );
  });
}
