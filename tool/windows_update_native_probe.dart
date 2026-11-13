import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:prompt_box/windows_update_installer.dart';

Future<void> main(List<String> args) async {
  final work = Directory(args[0]);
  final mode = args[5];
  try {
    final session = await WindowsUpdateInstaller.prepare(
      executable: p.join(
        Platform.environment['SystemRoot']!,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      ),
      script: args[1],
      archive: args[2],
      target: args[3],
      work: work,
      applicationPid: pid,
      digest: args[4],
      timeout: const Duration(seconds: 30),
    );
    if (mode == 'reject') throw StateError('Corrupt update was accepted');
    if (mode == 'cancel') {
      await session.cancel();
      for (var attempt = 0; attempt < 100; attempt++) {
        if ((await session.readStatus())?['state'] == 'cancelled') return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('Installer did not acknowledge cancellation');
    }
    await session.apply();
    await File(
      p.join(work.path, 'parent-exiting.txt'),
    ).writeAsString('exiting', flush: true);
    // This is intentional: prove the real helper survives its parent exiting.
    exit(0);
  } catch (error) {
    if (mode == 'reject' && error.toString().contains('SHA-256 mismatch')) {
      await File(
        p.join(work.path, 'rejection-observed.txt'),
      ).writeAsString('$error');
      return;
    }
    rethrow;
  }
}
