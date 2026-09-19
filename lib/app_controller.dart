import 'package:flutter/foundation.dart';
import 'models.dart';
import 'storage.dart';

enum AppThemePreference { system, light, dark }

class PromptBoxController extends ChangeNotifier {
  PromptBoxController({required PromptStore store, DateTime Function()? clock})
    : _store = store,
      _clock = clock ?? DateTime.now;

  PromptStore _store;
  final DateTime Function() _clock;
  DayRecord? currentDay;
  DateTime? selectedDate;
  List<DateTime> availableDays = [];
  List<TagDefinition> tags = [];
  List<WeekNote> weekNotes = [];
  String query = '';
  String? selectedTagId;
  String? error;
  bool loading = true;
  AppThemePreference themePreference = AppThemePreference.system;
  DateTime? _knownToday;

  String get databasePath => _store.rootPath;
  DateTime get today => dateOnly(_clock());

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    try {
      final storedTheme = await AppPreferences.readString(
        AppPreferences.themePreferenceKey,
      );
      themePreference = AppThemePreference.values.firstWhere(
        (e) => e.name == storedTheme,
        orElse: () => AppThemePreference.system,
      );
      tags = await _store.readTags();
      weekNotes = await _store.readWeekNotes();
      availableDays = await _store.listDays();
      _knownToday = today;
      await selectDate(today, notify: false);
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> checkDateRollover() async {
    if (_knownToday != null && dateKey(_knownToday!) == dateKey(today)) {
      return;
    }
    _knownToday = today;
    availableDays = await _store.listDays();
    await selectDate(today);
  }

  Future<void> selectDate(DateTime date, {bool notify = true}) async {
    selectedDate = dateOnly(date);
    currentDay = await _store.readDay(selectedDate!);
    query = '';
    selectedTagId = null;
    if (notify) notifyListeners();
  }

  List<PromptEntry> get filteredEntries {
    final lower = query.trim().toLowerCase();
    return (currentDay?.entries ?? const <PromptEntry>[]).where((entry) {
      final tagNames = entry.tagIds
          .map(
            (id) =>
                tags.where((tag) => tag.id == id).map((tag) => tag.name).join(),
          )
          .join(' ');
      final matchesText =
          lower.isEmpty ||
          entry.content.toLowerCase().contains(lower) ||
          tagNames.toLowerCase().contains(lower);
      return matchesText &&
          (selectedTagId == null || entry.tagIds.contains(selectedTagId));
    }).toList();
  }

  Future<void> addPrompt(String content) async {
    if (content.trim().isEmpty) return;
    if (selectedDate == null || dateKey(selectedDate!) != dateKey(today)) {
      await selectDate(today);
    }
    final now = _clock();
    currentDay!.entries.add(
      PromptEntry(
        id: '${now.microsecondsSinceEpoch}',
        content: content.trimRight(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _persistDay();
  }

  Future<void> editPrompt(PromptEntry entry, String content) async {
    if (content.trim().isEmpty) return;
    entry.content = content.trimRight();
    entry.updatedAt = _clock();
    await _persistDay();
  }

  Future<void> deletePrompt(PromptEntry entry) async {
    currentDay!.entries.remove(entry);
    await _persistDay();
  }

  Future<void> movePrompt(PromptEntry entry, int delta) async {
    final entries = currentDay!.entries;
    final from = entries.indexOf(entry);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= entries.length) return;
    entries.removeAt(from);
    entries.insert(to, entry);
    await _persistDay();
  }

  Future<void> toggleTag(PromptEntry entry, String tagId) async {
    entry.tagIds.contains(tagId)
        ? entry.tagIds.remove(tagId)
        : entry.tagIds.add(tagId);
    entry.updatedAt = _clock();
    await _persistDay();
  }

  Future<TagDefinition?> createTag(
    String name,
    int colorValue, {
    String description = '',
  }) async {
    final clean = name.trim();
    if (clean.isEmpty ||
        tags.any((tag) => tag.name.toLowerCase() == clean.toLowerCase())) {
      return null;
    }
    final tag = TagDefinition(
      id: '${_clock().microsecondsSinceEpoch}',
      name: clean,
      colorValue: colorValue,
      description: description.trim(),
    );
    tags.add(tag);
    await _store.writeTags(tags);
    notifyListeners();
    return tag;
  }

  Future<void> updateTag(
    TagDefinition original, {
    required String name,
    required String description,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final index = tags.indexWhere((tag) => tag.id == original.id);
    if (index < 0) return;
    tags[index] = TagDefinition(
      id: original.id,
      name: clean,
      colorValue: original.colorValue,
      description: description.trim(),
    );
    await _store.writeTags(tags);
    notifyListeners();
  }

  Future<void> saveWeekNote(WeekNote note) async {
    weekNotes.removeWhere(
      (item) => item.year == note.year && item.week == note.week,
    );
    weekNotes.add(note);
    await _store.writeWeekNotes(weekNotes);
    notifyListeners();
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    themePreference = value;
    await AppPreferences.writeString(
      AppPreferences.themePreferenceKey,
      value.name,
    );
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setTagFilter(String? value) {
    selectedTagId = value;
    notifyListeners();
  }

  Future<void> changeDatabasePath(
    String newPath, {
    bool copyExisting = true,
  }) async {
    try {
      if (copyExisting) {
        await StorageLocation.copyDatabase(_store.rootPath, newPath);
      }
      await StorageLocation.remember(newPath);
      _store = JsonPromptStore(newPath);
      await initialize();
    } catch (e) {
      error = '无法切换数据目录：$e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _persistDay() async {
    try {
      await _store.writeDay(currentDay!);
      availableDays = await _store.listDays();
      error = null;
    } catch (e) {
      error = '保存失败：$e';
      rethrow;
    } finally {
      notifyListeners();
    }
  }
}
