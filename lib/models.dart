import 'package:flutter/material.dart';

String dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class PromptEntry {
  PromptEntry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    List<String>? tagIds,
  }) : tagIds = tagIds ?? <String>[];
  final String id;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<String> tagIds;

  String get title {
    final lines = content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    if (lines.isEmpty) return '无标题 Prompt';
    final cleaned = lines.first.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    return cleaned.length > 48 ? '${cleaned.substring(0, 48)}…' : cleaned;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tagIds': tagIds,
  };
  factory PromptEntry.fromJson(Map<String, Object?> json) => PromptEntry(
    id: json['id']! as String,
    content: json['content']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    tagIds: (json['tagIds'] as List<Object?>? ?? const []).cast<String>(),
  );
}

class DayRecord {
  DayRecord({required this.date, List<PromptEntry>? entries})
    : entries = entries ?? <PromptEntry>[];
  final DateTime date;
  final List<PromptEntry> entries;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'date': dateKey(date),
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  factory DayRecord.fromJson(Map<String, Object?> json) => DayRecord(
    date: DateTime.parse(json['date']! as String),
    entries:
        (json['entries'] as List<Object?>? ?? const [])
            .map(
              (e) => PromptEntry.fromJson((e! as Map).cast<String, Object?>()),
            )
            .toList(),
  );
}

class TagDefinition {
  const TagDefinition({
    required this.id,
    required this.name,
    required this.colorValue,
    this.description = '',
  });
  final String id;
  final String name;
  final int colorValue;
  final String description;
  Color get color => Color(colorValue);
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': colorValue,
    'description': description,
  };
  factory TagDefinition.fromJson(Map<String, Object?> json) => TagDefinition(
    id: json['id']! as String,
    name: json['name']! as String,
    colorValue: json['color']! as int,
    description: json['description'] as String? ?? '',
  );
}

class WeekNote {
  WeekNote({
    required this.year,
    required this.week,
    this.summary = '',
    List<String>? tagIds,
  }) : tagIds = tagIds ?? <String>[];
  final int year;
  final int week;
  String summary;
  final List<String> tagIds;
  String get id => '$year-W${week.toString().padLeft(2, '0')}';
  Map<String, Object?> toJson() => {
    'year': year,
    'week': week,
    'summary': summary,
    'tagIds': tagIds,
  };
  factory WeekNote.fromJson(Map<String, Object?> json) => WeekNote(
    year: json['year']! as int,
    week: json['week']! as int,
    summary: json['summary'] as String? ?? '',
    tagIds: (json['tagIds'] as List<Object?>? ?? const []).cast<String>(),
  );
}

int isoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final weekOneThursday = firstThursday.add(
    Duration(days: 4 - firstThursday.weekday),
  );
  return 1 + thursday.difference(weekOneThursday).inDays ~/ 7;
}
