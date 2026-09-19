import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'app_controller.dart';
import 'markdown_extensions.dart';
import 'models.dart';
import 'storage.dart';
import 'wysiwyg_editor.dart';

bool shouldShowConversationOutline(DateTime? selectedDate, DateTime today) =>
    selectedDate != null &&
    dateOnly(today).difference(dateOnly(selectedDate)).inDays >= 0;

class PromptBoxApp extends StatelessWidget {
  const PromptBoxApp({super.key, required this.controller});
  final PromptBoxController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder:
        (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PromptBox',
          localizationsDelegates: const [
            AppFlowyEditorLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          themeMode: switch (controller.themePreference) {
            AppThemePreference.system => ThemeMode.system,
            AppThemePreference.light => ThemeMode.light,
            AppThemePreference.dark => ThemeMode.dark,
          },
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: PromptBoxHome(controller: controller),
        ),
  );

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff5b67f1),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.dark
              ? const Color(0xff111318)
              : const Color(0xfff7f7fb),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    );
  }
}

class PromptBoxHome extends StatefulWidget {
  const PromptBoxHome({super.key, required this.controller});
  final PromptBoxController controller;
  @override
  State<PromptBoxHome> createState() => _PromptBoxHomeState();
}

class _PromptBoxHomeState extends State<PromptBoxHome>
    with WidgetsBindingObserver {
  final _composer = WysiwygMarkdownController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _bubbleKeys = {};
  Timer? _rolloverTimer;

  PromptBoxController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rolloverTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => controller.checkDateRollover(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rolloverTimer?.cancel();
    _composer.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.checkDateRollover();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _NavigationRail(
                controller: controller,
                onHistory: _showHistory,
                onSettings: _showSettings,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _conversation()),
              if (_showOutline) ...[
                const VerticalDivider(width: 1),
                SizedBox(width: 250, child: _outline()),
              ],
            ],
          ),
        ),
      );
    },
  );

  bool get _showOutline =>
      shouldShowConversationOutline(controller.selectedDate, controller.today);

  Widget _conversation() => Column(
    children: [
      _toolbar(),
      if (controller.error != null)
        MaterialBanner(
          content: Text(controller.error!),
          leading: const Icon(Icons.error_outline),
          actions: [TextButton(onPressed: () {}, child: const Text('知道了'))],
        ),
      Expanded(
        child:
            controller.filteredEntries.isEmpty
                ? _emptyState()
                : ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
                  itemCount: controller.filteredEntries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final entry = controller.filteredEntries[index];
                    return PromptBubble(
                      key: _bubbleKeys.putIfAbsent(entry.id, GlobalKey.new),
                      entry: entry,
                      tags: controller.tags,
                      onEdit: () => _editPrompt(entry),
                      onDelete: () => _deletePrompt(entry),
                      onMoveUp: () => controller.movePrompt(entry, -1),
                      onMoveDown: () => controller.movePrompt(entry, 1),
                      onToggleTag: (id) => controller.toggleTag(entry, id),
                      onCreateTag:
                          (name, note, color) => controller.createTag(
                            name,
                            color,
                            description: note,
                          ),
                    );
                  },
                ),
      ),
      Composer(
        controller: _composer,
        onLongEditor: _openLongEditor,
        onSend: _send,
      ),
    ],
  );

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dateTitle(controller.selectedDate ?? controller.today),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                DateFormat(
                  'yyyy 年 M 月 d 日 EEEE',
                  'zh_CN',
                ).format(controller.selectedDate ?? controller.today),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _search,
            onChanged: controller.setQuery,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索正文与标签',
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String?>(
          tooltip: '标签筛选',
          icon: Badge(
            isLabelVisible: controller.selectedTagId != null,
            child: const Icon(Icons.filter_list),
          ),
          onSelected: controller.setTagFilter,
          itemBuilder:
              (_) => [
                const PopupMenuItem(value: null, child: Text('全部标签')),
                ...controller.tags.map(
                  (tag) => PopupMenuItem(value: tag.id, child: Text(tag.name)),
                ),
              ],
        ),
        IconButton(
          tooltip: '管理标签',
          onPressed: _manageTags,
          icon: const Icon(Icons.label_outline),
        ),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 54,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text(
          controller.query.isEmpty ? '把想到的 Prompt 写在这里' : '没有匹配结果',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          '支持 Markdown、标签与即时保存',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    ),
  );

  Widget _outline() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          '大纲',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: controller.currentDay?.entries.length ?? 0,
          itemBuilder: (_, index) {
            final entry = controller.currentDay!.entries[index];
            return ListTile(
              dense: true,
              leading: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              title: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                final bubbleContext = _bubbleKeys[entry.id]?.currentContext;
                if (bubbleContext != null) {
                  Scrollable.ensureVisible(
                    bubbleContext,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    alignment: .1,
                  );
                }
              },
            );
          },
        ),
      ),
    ],
  );

  Future<void> _send() async {
    final value = _composer.markdown;
    if (value.trim().isEmpty) return;
    await controller.addPrompt(value);
    _composer.clear();
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openLongEditor() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => LongEditorDialog(initialValue: _composer.markdown),
    );
    if (value != null) _composer.setMarkdown(value);
  }

  Future<void> _editPrompt(PromptEntry entry) async {
    final value = await showDialog<String>(
      context: context,
      builder:
          (_) =>
              LongEditorDialog(initialValue: entry.content, title: '编辑 Prompt'),
    );
    if (value != null && value.trim().isNotEmpty) {
      await controller.editPrompt(entry, value);
    }
  }

  Future<void> _deletePrompt(PromptEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('删除这条 Prompt？'),
            content: const Text('此操作无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed == true) await controller.deletePrompt(entry);
  }

  Future<void> _manageTags() async => showDialog<void>(
    context: context,
    builder: (_) => TagManagerDialog(controller: controller),
  );
  Future<void> _showHistory() async => showDialog<void>(
    context: context,
    builder: (_) => HistoryDialog(controller: controller),
  );
  Future<void> _showSettings() async => showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(controller: controller),
  );

  String _dateTitle(DateTime date) {
    final distance = controller.today.difference(dateOnly(date)).inDays;
    return switch (distance) {
      0 => '今天',
      1 => '昨天',
      2 => '前天',
      _ => DateFormat('M 月 d 日').format(date),
    };
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.controller,
    required this.onHistory,
    required this.onSettings,
  });
  final PromptBoxController controller;
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_mosaic,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'PromptBox',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var offset = 0; offset < 3; offset++)
          _dayTile(
            context,
            controller.today.subtract(Duration(days: offset)),
            switch (offset) {
              0 => '今天',
              1 => '昨天',
              _ => '前天',
            },
            switch (offset) {
              0 => Icons.today,
              1 => Icons.history,
              _ => Icons.history_toggle_off,
            },
          ),
        const Divider(indent: 14, endIndent: 14),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('历史数据库'),
          onTap: onHistory,
        ),
        const Spacer(),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('设置'),
          onTap: onSettings,
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            '本地优先 · 自动保存',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );

  Widget _dayTile(
    BuildContext context,
    DateTime date,
    String title,
    IconData icon,
  ) {
    final selected =
        controller.selectedDate != null &&
        dateKey(controller.selectedDate!) == dateKey(date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(DateFormat('M/d').format(date)),
        onTap: () => controller.selectDate(date),
      ),
    );
  }
}

class PromptBubble extends StatelessWidget {
  const PromptBubble({
    super.key,
    required this.entry,
    required this.tags,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleTag,
    required this.onCreateTag,
  });
  final PromptEntry entry;
  final List<TagDefinition> tags;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<String> onToggleTag;
  final Future<TagDefinition?> Function(String name, String note, int color)
  onCreateTag;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExtendedMarkdownBody(data: entry.content, selectable: true),
              if (entry.tagIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      entry.tagIds.map((id) {
                        final matches = tags.where((tag) => tag.id == id);
                        if (matches.isEmpty) return const SizedBox.shrink();
                        final tag = matches.first;
                        return Tooltip(
                          message:
                              tag.description.isEmpty
                                  ? tag.name
                                  : tag.description,
                          child: Chip(
                            label: Text(tag.name),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(color: tag.color),
                            backgroundColor: tag.color.withValues(alpha: .12),
                          ),
                        );
                      }).toList(),
                ),
              ],
              Row(
                children: [
                  Text(
                    DateFormat('HH:mm').format(entry.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '复制 Markdown',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _copyMarkdown(context),
                    icon: const Icon(Icons.content_copy, size: 19),
                  ),
                  IconButton(
                    tooltip: '添加或移除标签',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _chooseTag(context),
                    icon: const Icon(Icons.label_outline, size: 19),
                  ),
                  IconButton(
                    tooltip: '上移',
                    visualDensity: VisualDensity.compact,
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.arrow_upward, size: 19),
                  ),
                  IconButton(
                    tooltip: '下移',
                    visualDensity: VisualDensity.compact,
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.arrow_downward, size: 19),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                  IconButton(
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 19),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _chooseTag(BuildContext context) async {
    final tagId = await showDialog<String>(
      context: context,
      builder:
          (_) => TagPickerDialog(
            tags: tags,
            selectedIds: entry.tagIds.toSet(),
            onCreateTag: onCreateTag,
          ),
    );
    if (tagId != null) onToggleTag(tagId);
  }

  Future<void> _copyMarkdown(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已复制完整 Markdown'),
          duration: Duration(seconds: 1),
        ),
      );
  }
}

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onLongEditor,
    required this.onSend,
  });
  final WysiwygMarkdownController controller;
  final VoidCallback onLongEditor;
  final VoidCallback onSend;
  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            height: 126,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: WysiwygMarkdownEditor(
              controller: widget.controller,
              autoFocus: false,
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: '长编辑器',
          onPressed: widget.onLongEditor,
          icon: const Icon(Icons.open_in_new),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: '发送',
          onPressed: widget.controller.isEmpty ? null : widget.onSend,
          icon: const Icon(Icons.send),
        ),
      ],
    ),
  );
}

class LongEditorDialog extends StatefulWidget {
  const LongEditorDialog({
    super.key,
    required this.initialValue,
    this.title = '长编辑器',
  });
  final String initialValue;
  final String title;
  @override
  State<LongEditorDialog> createState() => _LongEditorDialogState();
}

class _LongEditorDialogState extends State<LongEditorDialog> {
  late final WysiwygMarkdownController _controller;
  @override
  void initState() {
    super.initState();
    _controller = WysiwygMarkdownController(widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(48),
    child: SizedBox(
      width: 900,
      height: 620,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '强制刷新渲染',
                  onPressed: () {
                    _controller.refreshRendering();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('已根据当前 Markdown 重新渲染'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                  },
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, _controller.markdown),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: WysiwygMarkdownEditor(
              controller: _controller,
              autoFocus: true,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _controller.markdown),
                  child: const Text('保存并回填'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class TagPickerDialog extends StatefulWidget {
  const TagPickerDialog({
    super.key,
    required this.tags,
    required this.selectedIds,
    required this.onCreateTag,
  });
  final List<TagDefinition> tags;
  final Set<String> selectedIds;
  final Future<TagDefinition?> Function(String name, String note, int color)
  onCreateTag;
  @override
  State<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<TagPickerDialog> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  int _color = Colors.indigo.toARGB32();
  static const _colors = [
    Colors.indigo,
    Colors.teal,
    Colors.orange,
    Colors.pink,
    Colors.blue,
    Colors.green,
    Colors.deepPurple,
    Colors.red,
  ];

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加或移除标签'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.tags.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('还没有标签，可以直接在下面创建。'),
              ),
            ...widget.tags.map(
              (tag) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 8, backgroundColor: tag.color),
                title: Text(tag.name),
                subtitle:
                    tag.description.isEmpty ? null : Text(tag.description),
                trailing: Icon(
                  widget.selectedIds.contains(tag.id)
                      ? Icons.check_circle
                      : Icons.add_circle_outline,
                ),
                onTap: () => Navigator.pop(context, tag.id),
              ),
            ),
            const Divider(height: 26),
            Text('新建标签', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '标签名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '标签备注（可选）'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children:
                  _colors
                      .map(
                        (color) => InkWell(
                          onTap:
                              () => setState(() => _color = color.toARGB32()),
                          child: CircleAvatar(
                            radius: 13,
                            backgroundColor: color,
                            child:
                                _color == color.toARGB32()
                                    ? const Icon(
                                      Icons.check,
                                      size: 15,
                                      color: Colors.white,
                                    )
                                    : null,
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton.icon(
        onPressed:
            _name.text.trim().isEmpty
                ? null
                : () async {
                  final tag = await widget.onCreateTag(
                    _name.text,
                    _note.text,
                    _color,
                  );
                  if (context.mounted && tag != null) {
                    Navigator.pop(context, tag.id);
                  }
                },
        icon: const Icon(Icons.add),
        label: const Text('创建并添加'),
      ),
    ],
  );
}

class TagManagerDialog extends StatefulWidget {
  const TagManagerDialog({super.key, required this.controller});
  final PromptBoxController controller;
  @override
  State<TagManagerDialog> createState() => _TagManagerDialogState();
}

class _TagManagerDialogState extends State<TagManagerDialog> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  int _color = Colors.indigo.toARGB32();
  static const colors = [
    Colors.indigo,
    Colors.teal,
    Colors.orange,
    Colors.pink,
    Colors.blue,
    Colors.green,
    Colors.deepPurple,
    Colors.red,
  ];
  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('管理标签'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controller.tags.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('还没有标签。创建后可在任意气泡上添加。'),
            ),
          ...widget.controller.tags.map(
            (tag) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 8, backgroundColor: tag.color),
              title: Text(tag.name),
              subtitle: Text(tag.description.isEmpty ? '无备注' : tag.description),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () => _editTag(tag),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '新标签名称'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '标签备注（可选）'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children:
                colors
                    .map(
                      (color) => InkWell(
                        onTap: () => setState(() => _color = color.toARGB32()),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: color,
                          child:
                              _color == color.toARGB32()
                                  ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                  : null,
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: () async {
          await widget.controller.createTag(
            _name.text,
            _color,
            description: _note.text,
          );
          _name.clear();
          _note.clear();
          setState(() {});
        },
        child: const Text('创建'),
      ),
    ],
  );

  Future<void> _editTag(TagDefinition tag) async {
    final name = TextEditingController(text: tag.name);
    final note = TextEditingController(text: tag.description);
    final save = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('编辑标签'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '标签名称'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '标签备注'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    if (save == true) {
      await widget.controller.updateTag(
        tag,
        name: name.text,
        description: note.text,
      );
      if (mounted) setState(() {});
    }
    name.dispose();
    note.dispose();
  }
}

class HistoryDialog extends StatefulWidget {
  const HistoryDialog({super.key, required this.controller});
  final PromptBoxController controller;
  @override
  State<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<HistoryDialog> {
  late int _year;
  late int _month;
  @override
  void initState() {
    super.initState();
    _year = widget.controller.today.year;
    _month = widget.controller.today.month;
  }

  @override
  Widget build(BuildContext context) {
    final years =
        <int>{
            widget.controller.today.year,
            ...widget.controller.availableDays.map((e) => e.year),
          }.toList()
          ..sort((a, b) => b.compareTo(a));
    final days =
        widget.controller.availableDays
            .where(
              (day) =>
                  day.year == _year &&
                  day.month == _month &&
                  widget.controller.today.difference(day).inDays > 2,
            )
            .toList();
    final weeks = <int>{...days.map(isoWeekNumber)}.toList()..sort();
    return Dialog(
      child: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 10, 10),
              child: Row(
                children: [
                  Text(
                    '历史数据库',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  DropdownButton<int>(
                    value: _year,
                    items:
                        years
                            .map(
                              (year) => DropdownMenuItem(
                                value: year,
                                child: Text('$year 年'),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setState(() => _year = value!),
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<int>(
                    value: _month,
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} 月'),
                      ),
                    ),
                    onChanged: (value) => setState(() => _month = value!),
                  ),
                  const Spacer(),
                  Text(
                    '${days.length} 个有记录的日期',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (weeks.isNotEmpty)
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children:
                      weeks
                          .map(
                            (week) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: const Icon(
                                  Icons.calendar_view_week,
                                  size: 16,
                                ),
                                label: Text('第 $week 周'),
                                onPressed: () => _editWeek(week),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
            Expanded(
              child:
                  days.isEmpty
                      ? const Center(child: Text('这个月还没有归档记录'))
                      : GridView.builder(
                        padding: const EdgeInsets.all(18),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 2.1,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: days.length,
                        itemBuilder: (_, index) {
                          final day = days[index];
                          return Card(
                            color:
                                Theme.of(context).colorScheme.surfaceContainer,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await widget.controller.selectDate(day);
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      DateFormat('M 月 d 日').format(day),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '第 ${isoWeekNumber(day)} 周 · ${DateFormat('EEEE', 'zh_CN').format(day)}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWeek(int week) async {
    final existing = widget.controller.weekNotes.where(
      (note) => note.year == _year && note.week == week,
    );
    final note =
        existing.isEmpty ? WeekNote(year: _year, week: week) : existing.first;
    final text = TextEditingController(text: note.summary);
    final selectedTags = <String>{...note.tagIds};
    final result = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text('$_year 年第 $week 周'),
                  content: SizedBox(
                    width: 430,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: text,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: '工作内容简介',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            children:
                                widget.controller.tags
                                    .map(
                                      (tag) => FilterChip(
                                        label: Text(tag.name),
                                        selected: selectedTags.contains(tag.id),
                                        onSelected:
                                            (selected) => setDialogState(() {
                                              selected
                                                  ? selectedTags.add(tag.id)
                                                  : selectedTags.remove(tag.id);
                                            }),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, text.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
          ),
    );
    text.dispose();
    if (result != null) {
      note.summary = result;
      note.tagIds
        ..clear()
        ..addAll(selectedTags);
      await widget.controller.saveWeekNote(note);
      setState(() {});
    }
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.controller});
  final PromptBoxController controller;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('设置'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('外观', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<AppThemePreference>(
            segments: const [
              ButtonSegment(
                value: AppThemePreference.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: AppThemePreference.light,
                icon: Icon(Icons.light_mode),
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('深色'),
              ),
            ],
            selected: {widget.controller.themePreference},
            onSelectionChanged:
                (values) => widget.controller.setThemePreference(values.first),
          ),
          const SizedBox(height: 24),
          Text('历史数据库目录', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SelectableText(
            widget.controller.databasePath,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _changePath,
                icon: const Icon(Icons.folder_open),
                label: const Text('迁移到其他目录'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _backup,
                icon: const Icon(Icons.backup_outlined),
                label: const Text('导出备份'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('从备份恢复'),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 8),
          Text(
            '迁移后路径会被记住，重启应用仍从新目录读取。云盘同步目录由对应云盘客户端负责同步。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );

  Future<String?> _pickDirectory() =>
      FilePicker.platform.getDirectoryPath(dialogTitle: '选择文件夹');
  Future<void> _changePath() async {
    final path = await _pickDirectory();
    if (path == null || path == widget.controller.databasePath) return;
    await _run(() => widget.controller.changeDatabasePath(path));
  }

  Future<void> _backup() async {
    final path = await _pickDirectory();
    if (path == null) return;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    await _run(
      () => StorageLocation.copyDatabase(
        widget.controller.databasePath,
        p.join(path, 'PromptBox_backup_$stamp'),
      ),
    );
  }

  Future<void> _restore() async {
    final path = await _pickDirectory();
    if (path == null) return;
    await _run(
      () => widget.controller.changeDatabasePath(path, copyExisting: false),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }
}
