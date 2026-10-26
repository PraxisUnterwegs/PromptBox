import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.numbers, this.pre);
  final List<int> numbers;
  final List<String> pre;

  static ReleaseVersion? parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(value);
    if (match == null) return null;
    return ReleaseVersion([
      for (var i = 1; i <= 3; i++) int.parse(match[i]!),
    ], match[4]?.split('.') ?? []);
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final order = numbers[i].compareTo(other.numbers[i]);
      if (order != 0) return order;
    }
    if (pre.isEmpty || other.pre.isEmpty) {
      return pre.isEmpty == other.pre.isEmpty ? 0 : (pre.isEmpty ? 1 : -1);
    }
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final a = int.tryParse(pre[i]);
      final b = int.tryParse(other.pre[i]);
      final order =
          a != null && b != null
              ? a.compareTo(b)
              : a != null
              ? -1
              : b != null
              ? 1
              : pre[i].compareTo(other.pre[i]);
      if (order != 0) return order;
    }
    return pre.length.compareTo(other.pre.length);
  }
}

class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.notes,
    required this.url,
    required this.name,
    required this.size,
    required this.digest,
  });
  final String tag, notes, name, digest;
  final Uri url;
  final int size;

  static const repository = 'PraxisUnterwegs/PromptBox';

  static UpdateRelease? select(
    List<dynamic> releases,
    String installed,
    String assetName,
  ) {
    final current = ReleaseVersion.parse(installed);
    if (current == null) throw const FormatException('无法识别当前版本');
    UpdateRelease? selected;
    ReleaseVersion best = current;
    for (final raw in releases) {
      final release = raw as Map<String, dynamic>;
      if (release['draft'] == true) continue;
      // Stable installations stay on stable; previews may graduate to stable.
      if (current.pre.isEmpty && release['prerelease'] == true) continue;
      final tag = release['tag_name'] as String? ?? '';
      final version = ReleaseVersion.parse(tag);
      if (version == null || version.compareTo(best) <= 0) continue;
      if (current.pre.isEmpty && version.pre.isNotEmpty) continue;
      for (final rawAsset in release['assets'] as List<dynamic>? ?? []) {
        final asset = rawAsset as Map<String, dynamic>;
        if (asset['name'] != assetName || asset['state'] != 'uploaded') {
          continue;
        }
        final url = Uri.tryParse(
          asset['browser_download_url'] as String? ?? '',
        );
        final digest = asset['digest'] as String? ?? '';
        final size = asset['size'] as int? ?? 0;
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.userInfo.isNotEmpty ||
            url.hasPort ||
            !url.path.startsWith('/$repository/releases/download/') ||
            !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
            size <= 0) {
          continue;
        }
        selected = UpdateRelease(
          tag: tag,
          notes: release['body'] as String? ?? '',
          url: url,
          name: assetName,
          size: size,
          digest: digest.substring(7).toLowerCase(),
        );
        best = version;
      }
    }
    return selected;
  }
}

/// Constructing this service performs no I/O. Network access only occurs in
/// check() and download(), each called by a separate, explicit UI action.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    HttpClient Function()? createClient,
    Future<String> Function()? loadVersion,
    Future<Directory> Function()? tempDirectory,
  }) : _createClient = createClient ?? HttpClient.new,
       _loadVersion =
           loadVersion ??
           (() async => (await PackageInfo.fromPlatform()).version),
       _tempDirectory = tempDirectory ?? getTemporaryDirectory;
  final HttpClient Function() _createClient;
  final Future<String> Function() _loadVersion;
  final Future<Directory> Function() _tempDirectory;
  bool busy = false;
  bool installationPending = false;
  String status = '尚未检查更新';
  String? installedVersion;
  UpdateRelease? release;
  File? downloaded;
  double? progress;
  Directory? _staging;
  bool _disposed = false;

  static String assetFor(String os, Abi abi) => switch ((os, abi)) {
    ('windows', Abi.windowsX64) => 'PromptBox-preview-windows-x64.zip',
    ('linux', Abi.linuxX64) => 'promptbox-preview-linux-amd64.deb',
    ('macos', Abi.macosArm64) => 'PromptBox-preview-macos-arm64.dmg',
    _ => throw UnsupportedError('当前系统或架构尚无发布包：$os / $abi'),
  };

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _network<T>(Future<T> Function(HttpClient) action) async {
    final client =
        _createClient()..connectionTimeout = const Duration(seconds: 20);
    client.userAgent = 'PromptBox-update';
    try {
      return await action(client);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || installationPending) return;
    busy = true;
    _changed();
    try {
      await action();
    } catch (e) {
      status = '操作失败，可手动重试：$e';
    } finally {
      busy = false;
      progress = null;
      _changed();
    }
  }

  Future<void> check() => _run(() async {
    status = '正在检查 GitHub Releases…';
    release = null;
    downloaded = null;
    final assetName = assetFor(Platform.operatingSystem, Abi.current());
    final version = await _loadVersion();
    installedVersion = version;
    await _network((client) async {
      final releases = <dynamic>[];
      // Paginate instead of relying on /latest, which excludes preview builds.
      for (var page = 1; page <= 10; page++) {
        final request = await client.getUrl(
          Uri.https(
            'api.github.com',
            '/repos/${UpdateRelease.repository}/releases',
            {'per_page': '100', 'page': '$page'},
          ),
        );
        request.headers.set('Accept', 'application/vnd.github+json');
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) {
          throw HttpException('GitHub 返回 ${response.statusCode}（可能达到请求限额）');
        }
        final json =
            jsonDecode(
                  await utf8.decoder
                      .bind(response)
                      .join()
                      .timeout(const Duration(seconds: 30)),
                )
                as List<dynamic>;
        releases.addAll(json);
        if (json.length < 100) break;
        if (page == 10) {
          throw const FormatException('版本列表过长，请前往 GitHub Releases 查看');
        }
      }
      release = UpdateRelease.select(releases, version, assetName);
    });
    status =
        release == null
            ? '没有更新的兼容版本（当前 $installedVersion）'
            : '发现 ${release!.tag}';
  });

  Future<void> download() => _run(() async {
    final update = release;
    if (update == null) throw StateError('请先手动检查更新');
    downloaded = null;
    if (_staging != null && await _staging!.exists()) {
      await _staging!.delete(recursive: true);
    }
    final temp = await _tempDirectory();
    _staging = await temp.createTemp('promptbox-update-');
    final partial = File(p.join(_staging!.path, '${update.name}.part'));
    status = '正在下载 ${update.tag}…';
    try {
      await _network((client) async {
        final request = await client.getUrl(update.url);
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) {
          throw HttpException('下载返回 ${response.statusCode}');
        }
        var received = 0;
        final sink = partial.openWrite();
        try {
          await for (final bytes in response.timeout(
            const Duration(seconds: 60),
          )) {
            received += bytes.length;
            if (received > update.size) {
              throw const FormatException('安装包大小超出预期');
            }
            sink.add(bytes);
            progress = received / update.size;
            _changed();
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (received != update.size) throw const FormatException('安装包下载不完整');
      });
      await _verify(partial, update);
      downloaded = await partial.rename(p.join(_staging!.path, update.name));
      status = '下载并校验完成，等待您确认安装';
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  });

  Future<void> _verify(File file, UpdateRelease update) async {
    if (await file.length() != update.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            update.digest) {
      throw const FormatException('SHA-256 校验失败，请重新下载');
    }
  }

  Future<void> install({required String databasePath}) => _run(() async {
    final file = downloaded;
    final update = release;
    if (file == null || update == null) throw StateError('请先确认并下载更新');
    try {
      await _verify(
        file,
        update,
      ); // Recheck immediately before invoking any installer.
    } catch (_) {
      downloaded = null;
      rethrow;
    }
    if (Platform.isLinux) {
      final result = await Process.run('pkexec', ['dpkg', '-i', file.path]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'pkexec dpkg',
          [],
          '${result.stderr}',
          result.exitCode,
        );
      }
      downloaded = null;
      installationPending = true;
      status = '安装成功；请保存编辑内容，关闭并重新打开 PromptBox';
    } else {
      final windows = Platform.isWindows;
      final name = windows ? 'install_windows.ps1' : 'install_macos.sh';
      final script = File(p.join(_staging!.path, name));
      final source = await rootBundle.loadString('packaging/updater/$name');
      await script.writeAsBytes([
        if (windows) ...[0xef, 0xbb, 0xbf],
        ...utf8.encode(source),
      ], flush: true);
      final executable =
          windows
              ? p.join(
                Platform.environment['SystemRoot'] ??
                    (throw UnsupportedError('无法定位 Windows 系统目录')),
                'System32',
                'WindowsPowerShell',
                'v1.0',
                'powershell.exe',
              )
              : '/bin/sh';
      final target =
          windows ? p.dirname(Platform.resolvedExecutable) : _macBundle();
      final database = p.normalize(p.absolute(databasePath));
      if (p.equals(database, target) || p.isWithin(target, database)) {
        throw StateError('数据库位于程序安装目录中，请先在设置中迁移到独立目录再更新');
      }
      // The helper waits for a normal exit. We never kill the app or discard drafts.
      final arguments =
          windows
              ? [
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy',
                'Bypass',
                '-WindowStyle',
                'Hidden',
                '-File',
                script.path,
              ]
              : [script.path];
      await Process.start(executable, [
        ...arguments,
        '$pid',
        file.path,
        target,
        _staging!.path,
      ], mode: ProcessStartMode.detached);
      installationPending = true;
      downloaded = null;
      status =
          '安装已授权。请保存编辑内容并关闭 PromptBox；退出后替换并重启。失败详情见 ${p.join(_staging!.path, 'install.log')}';
    }
  });

  String _macBundle() {
    var dir = Directory(p.dirname(Platform.resolvedExecutable));
    while (dir.parent.path != dir.path) {
      if (p.extension(dir.path) == '.app') return dir.path;
      dir = dir.parent;
    }
    throw UnsupportedError('请从已安装的 PromptBox.app 中更新');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
