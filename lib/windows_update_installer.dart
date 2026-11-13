import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// PowerShell requires valid standard handles on Windows. A normal child
/// survives its parent and lets us observe startup errors and readiness.
class WindowsUpdateInstaller {
  static Future<WindowsInstallSession> prepare({
    required String executable,
    required String script,
    required String archive,
    required String target,
    required Directory work,
    required int applicationPid,
    required String digest,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final process = await Process.start(executable, [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script,
      '$applicationPid',
      archive,
      target,
      work.path,
      digest,
    ], workingDirectory: work.path);
    await process.stdin.close();
    final stdoutFile = File(p.join(work.path, 'bootstrap-stdout.log'));
    final stderrFile = File(p.join(work.path, 'bootstrap-stderr.log'));
    final stdoutDone = process.stdout.pipe(stdoutFile.openWrite());
    final stderrDone = process.stderr.pipe(stderrFile.openWrite());
    int? exitCode;
    unawaited(process.exitCode.then((code) => exitCode = code));
    final session = WindowsInstallSession(work);
    final watch = Stopwatch()..start();
    while (watch.elapsed < timeout) {
      final status = await session.readStatus();
      if (status?['state'] == 'ready') return session;
      if (status?['state'] == 'failed' || exitCode != null) {
        await Future.wait([stdoutDone, stderrDone]);
        final detail =
            utf8
                .decode(await stderrFile.readAsBytes(), allowMalformed: true)
                .trim();
        throw StateError(
          '更新助手启动失败：${status?['message'] ?? (detail.isEmpty ? '退出代码 $exitCode' : detail)}；日志：${work.path}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await session.cancel();
    throw TimeoutException('更新助手未在规定时间内就绪；应用未退出。日志：${work.path}', timeout);
  }
}

class WindowsInstallSession {
  WindowsInstallSession(this.work);
  final Directory work;
  Future<Map<String, dynamic>?> readStatus() async {
    final file = File(p.join(work.path, 'installer-status.json'));
    if (!await file.exists()) return null;
    try {
      return jsonDecode((await file.readAsString()).replaceFirst('\ufeff', ''))
          as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  Future<void> apply() async {
    await File(
      p.join(work.path, 'install.requested'),
    ).writeAsString('approved', flush: true);
  }

  Future<void> cancel() async {
    await File(
      p.join(work.path, 'install.cancelled'),
    ).writeAsString('cancelled', flush: true);
  }
}
