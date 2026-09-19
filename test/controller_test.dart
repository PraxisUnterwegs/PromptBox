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
}
