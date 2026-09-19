import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

abstract class PromptStore {
  String get rootPath;
  Future<DayRecord> readDay(DateTime date);
  Future<void> writeDay(DayRecord day);
  Future<List<DateTime>> listDays();
  Future<List<TagDefinition>> readTags();
  Future<void> writeTags(List<TagDefinition> tags);
  Future<List<WeekNote>> readWeekNotes();
  Future<void> writeWeekNotes(List<WeekNote> notes);
}

class JsonPromptStore implements PromptStore {
  JsonPromptStore(this.rootPath);
  @override
  final String rootPath;

  String _dayPath(DateTime date) => p.join(
    rootPath,
    'days',
    date.year.toString(),
    date.month.toString().padLeft(2, '0'),
    '${dateKey(date)}.json',
  );

  Future<Map<String, Object?>> _readObject(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      final backup = File('$path.bak');
      final temp = File('$path.tmp');
      if (await backup.exists()) {
        await file.parent.create(recursive: true);
        await backup.rename(path);
      } else if (await temp.exists()) {
        await file.parent.create(recursive: true);
        await temp.rename(path);
      } else {
        return <String, Object?>{};
      }
    }
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } on FormatException catch (error) {
      throw FileSystemException('数据文件格式损坏：$error', path);
    }
  }

  Future<void> _writeObject(String path, Object value) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    final backup = File('$path.bak');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temp.rename(path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(path);
      }
      rethrow;
    }
  }

  @override
  Future<DayRecord> readDay(DateTime date) async {
    final data = await _readObject(_dayPath(date));
    return data.isEmpty
        ? DayRecord(date: dateOnly(date))
        : DayRecord.fromJson(data);
  }

  @override
  Future<void> writeDay(DayRecord day) =>
      _writeObject(_dayPath(day.date), day.toJson());

  @override
  Future<List<DateTime>> listDays() async {
    final root = Directory(p.join(rootPath, 'days'));
    if (!await root.exists()) return [];
    final result = <DateTime>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.json') continue;
      final parsed = DateTime.tryParse(p.basenameWithoutExtension(entity.path));
      if (parsed != null) result.add(parsed);
    }
    result.sort((a, b) => b.compareTo(a));
    return result;
  }

  @override
  Future<List<TagDefinition>> readTags() async {
    final data = await _readObject(p.join(rootPath, 'tags.json'));
    return (data['tags'] as List<Object?>? ?? const [])
        .map((e) => TagDefinition.fromJson((e! as Map).cast<String, Object?>()))
        .toList();
  }

  @override
  Future<void> writeTags(List<TagDefinition> tags) => _writeObject(
    p.join(rootPath, 'tags.json'),
    {'schemaVersion': 1, 'tags': tags.map((e) => e.toJson()).toList()},
  );

  @override
  Future<List<WeekNote>> readWeekNotes() async {
    final data = await _readObject(p.join(rootPath, 'week_notes.json'));
    return (data['notes'] as List<Object?>? ?? const [])
        .map((e) => WeekNote.fromJson((e! as Map).cast<String, Object?>()))
        .toList();
  }

  @override
  Future<void> writeWeekNotes(List<WeekNote> notes) => _writeObject(
    p.join(rootPath, 'week_notes.json'),
    {'schemaVersion': 1, 'notes': notes.map((e) => e.toJson()).toList()},
  );
}

class StorageLocation {
  static const _preferenceKey = AppPreferences.databasePathKey;
  static Future<String> resolve() async {
    final selected = await AppPreferences.readString(_preferenceKey);
    if (selected != null && selected.isNotEmpty) return selected;
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'PromptBox');
  }

  static Future<void> remember(String path) async {
    await AppPreferences.writeString(_preferenceKey, p.normalize(path));
  }

  static Future<void> copyDatabase(String source, String destination) async {
    final normalizedSource = p.normalize(p.absolute(source));
    final normalizedDestination = p.normalize(p.absolute(destination));
    if (normalizedSource == normalizedDestination ||
        p.isWithin(normalizedSource, normalizedDestination)) {
      throw FileSystemException('目标目录不能是当前数据库目录或其子目录', destination);
    }
    final sourceDir = Directory(source);
    await Directory(destination).create(recursive: true);
    if (!await sourceDir.exists()) return;
    await for (final entity in sourceDir.list(recursive: true)) {
      final target = p.join(destination, p.relative(entity.path, from: source));
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}

/// Settings stored in the operating system's per-user application support
/// directory. This is deliberately independent from the executable/install
/// directory so replacing a DEB package or a Windows portable bundle keeps the
/// selected database path and other preferences.
class AppPreferences {
  static const databasePathKey = 'database_path';
  static const themePreferenceKey = 'theme_preference';

  static Future<String?> readString(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  static Future<void> writeString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(key, value);
    if (!saved) {
      throw FileSystemException('Unable to save application setting: $key');
    }
  }
}
