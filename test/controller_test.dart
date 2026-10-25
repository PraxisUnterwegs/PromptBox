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
  test('明日计划在零点成为今天，下一天计划栏为空且不重复转入', () async {
    now = DateTime(2026, 9, 18, 23, 59, 59);
    await controller.selectTomorrowPlan();
    await controller.addPrompt('# 明早先完成实验\n对照组与结果记录');
    final plan = controller.currentDay!.entries.single;
    await controller.setOutlineName(plan, '早起第一件事');
    await controller.toggleTag(plan, 'research');
    await controller.toggleQuickAccess(plan);
    await controller.selectDate(DateTime(2026, 9, 18));
    expect(controller.currentDay!.entries, isEmpty);

    now = DateTime(2026, 9, 19);
    await controller.checkDateRollover();
    expect(controller.selectedDate, DateTime(2026, 9, 19));
    expect(controller.currentDay!.entries.single.id, plan.id);
    expect(controller.currentDay!.entries.single.outlineTitle, '早起第一件事');
    expect(controller.currentDay!.entries.single.tagIds, ['research']);
    await controller.checkDateRollover();
    await controller.checkDateRollover();
    expect(controller.currentDay!.entries, hasLength(1));
    await controller.selectTomorrowPlan();
    expect(controller.selectedDate, DateTime(2026, 9, 20));
    expect(controller.currentDay!.entries, isEmpty);
    await controller.selectQuickAccess();
    expect(controller.quickAccessEntries.single.id, plan.id);
  });

  test('明日计划重启仍保留，离线跨多天后留在应属日期', () async {
    await controller.selectTomorrowPlan();
    await controller.addPrompt('明天的任务');
    final restarted = PromptBoxController(
      store: JsonPromptStore(temp.path),
      clock: () => now,
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    await restarted.selectTomorrowPlan();
    expect(restarted.currentDay!.entries.single.content, '明天的任务');

    now = DateTime(2026, 9, 23, 8);
    await restarted.initialize();
    expect(restarted.currentDay!.entries, isEmpty);
    await restarted.selectDate(DateTime(2026, 9, 19));
    expect(restarted.currentDay!.entries.single.content, '明天的任务');
    await restarted.selectTomorrowPlan();
    expect(restarted.currentDay!.entries, isEmpty);
  });

  test('明日计划支持编辑排序删除，重启后内容顺序正确', () async {
    await controller.selectTomorrowPlan();
    await controller.addPrompt('任务 A');
    now = now.add(const Duration(seconds: 1));
    await controller.addPrompt('任务 B');
    now = now.add(const Duration(seconds: 1));
    await controller.addPrompt('任务 C');
    await controller.movePrompt(controller.currentDay!.entries.last, -1);
    await controller.editPrompt(controller.currentDay!.entries[1], '任务 C 修改');
    await controller.deletePrompt(controller.currentDay!.entries.last);
    final saved = await JsonPromptStore(
      temp.path,
    ).readDay(DateTime(2026, 9, 19));
    expect(saved.entries.map((e) => e.content), ['任务 A', '任务 C 修改']);
    expect(controller.tomorrowPlanSelected, isTrue);
  });

  test('零点后计时器尚未刷新时，新增计划仍写入新的明天', () async {
    now = DateTime(2026, 12, 31, 23, 59, 59);
    await controller.selectTomorrowPlan();
    await controller.addPrompt('元旦任务');
    now = DateTime(2027, 1, 1, 0, 0, 1);
    await controller.addPrompt('一月二日任务');
    expect(controller.selectedDate, DateTime(2027, 1, 2));
    final store = JsonPromptStore(temp.path);
    expect(
      (await store.readDay(DateTime(2027, 1, 1))).entries.single.content,
      '元旦任务',
    );
    expect(
      (await store.readDay(DateTime(2027, 1, 2))).entries.single.content,
      '一月二日任务',
    );
  });

  test('月末闰日目标日期与零点倒计时正确', () {
    now = DateTime(2028, 2, 28, 23, 59, 59);
    expect(controller.tomorrow, DateTime(2028, 2, 29));
    expect(controller.timeUntilNextDay, const Duration(seconds: 1));
    now = DateTime(2028, 2, 29, 23, 59, 59);
    expect(controller.tomorrow, DateTime(2028, 3, 1));
  });

  test('完成勾选可取消，并在明日计划跨天、快速访问和重启后保持同步', () async {
    await controller.selectTomorrowPlan();
    await controller.addPrompt('计划和普通 Prompt 都可以勾选');
    final entry = controller.currentDay!.entries.single;
    expect(entry.completed, isFalse);
    await controller.toggleCompleted(entry);
    expect(entry.completed, isTrue);
    await controller.toggleQuickAccess(entry);
    await controller.selectQuickAccess();
    expect(controller.quickAccessEntries.single.completed, isTrue);
    await controller.toggleCompleted(controller.quickAccessEntries.single);
    expect(
      (await JsonPromptStore(
        temp.path,
      ).readDay(DateTime(2026, 9, 19))).entries.single.completed,
      isFalse,
    );
    await controller.toggleCompleted(controller.quickAccessEntries.single);
    now = DateTime(2026, 9, 19, 8);
    await controller.checkDateRollover();
    expect(controller.currentDay!.entries.single.completed, isTrue);
    expect(controller.currentDay!.entries.single.content, entry.content);

    final restarted = PromptBoxController(
      store: JsonPromptStore(temp.path),
      clock: () => now,
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.currentDay!.entries.single.completed, isTrue);
    final legacy = entry.toJson()..remove('completed');
    expect(PromptEntry.fromJson(legacy).completed, isFalse);
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
