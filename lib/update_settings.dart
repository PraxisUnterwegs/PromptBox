import 'dart:io';

import 'package:flutter/material.dart';

import 'app_update.dart';

class UpdateSettings extends StatelessWidget {
  const UpdateSettings({
    super.key,
    required this.service,
    required this.databasePath,
  });
  final AppUpdateService service;
  final String databasePath;

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(child: Text(body)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final release = service.release;
      final enabled = !service.busy && !service.installationPending;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('软件更新', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const Text('仅在您手动检查时访问 GitHub。下载和安装均需要分别确认；不会在后台自动更新。'),
          if (service.installedVersion != null)
            Text('当前版本：${service.installedVersion}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(service.status),
          ),
          if (release != null) ...[
            Text(
              '${release.tag} · ${(release.size / 1048576).toStringAsFixed(1)} MB',
            ),
            if (release.notes.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('版本说明'),
                children: [SelectableText(release.notes)],
              ),
          ],
          if (service.busy) LinearProgressIndicator(value: service.progress),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? service.check : null,
                icon: const Icon(Icons.refresh),
                label: const Text('检查更新'),
              ),
              OutlinedButton.icon(
                onPressed:
                    !enabled || release == null || service.downloaded != null
                        ? null
                        : () async {
                          if (await _confirm(
                            context,
                            '确认下载更新',
                            '从 GitHub 仓库 ${UpdateRelease.repository} 下载 ${release.tag}？\n安装包：${release.name}\n大小：${(release.size / 1048576).toStringAsFixed(1)} MB\n下载完成后不会自动安装。',
                            '确认下载',
                          )) {
                            await service.download();
                          }
                        },
                icon: const Icon(Icons.download),
                label: const Text('下载更新'),
              ),
              FilledButton.icon(
                onPressed:
                    !enabled || service.downloaded == null
                        ? null
                        : () async {
                          final detail =
                              Platform.isLinux
                                  ? '系统将请求管理员授权，用 DEB 包替换已安装的版本。完成后请保存编辑内容并重新打开软件。'
                                  : '授权后，请先保存编辑内容，再自行关闭 PromptBox。安装程序会等待正常退出，然后备份旧程序、替换并重新启动。请勿同时启动其他 PromptBox 实例。';
                          if (await _confirm(
                            context,
                            '确认安装更新',
                            '安装 ${release!.tag}？\n$detail\n历史数据库和个人设置保存在独立目录。',
                            '确认安装',
                          )) {
                            await service.install(databasePath: databasePath);
                          }
                        },
                icon: const Icon(Icons.system_update),
                label: const Text('安装更新'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
