// Native upgrade fixture. This entry point is never used by release builds.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_box/app.dart';
import 'package:prompt_box/app_controller.dart';
import 'package:prompt_box/app_update.dart';
import 'package:prompt_box/storage.dart';

class _FixtureClient implements HttpClient {
  _FixtureClient(this.base);
  final Uri base;
  final _client = HttpClient();
  @override
  Duration? get connectionTimeout => _client.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _client.connectionTimeout = value;
  @override
  String? get userAgent => _client.userAgent;
  @override
  set userAgent(String? value) => _client.userAgent = value;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) {
    if (uri.host == 'api.github.com' && uri.path.endsWith('/releases')) {
      return _client.getUrl(base.resolve('releases.json'));
    }
    if (uri.host == 'github.com' && uri.path.endsWith('.zip')) {
      return _client.getUrl(base.resolve('update.zip'));
    }
    throw StateError('Unexpected integration request: $uri');
  }

  @override
  void close({bool force = false}) => _client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const root = String.fromEnvironment('PROMPTBOX_DEMO_ROOT');
  if (root.isEmpty) {
    throw StateError('An isolated integration root is required');
  }
  await initializeDateFormatting('zh_CN');
  await AppPreferences.useIsolatedFile(File(p.join(root, 'preferences.json')));
  final database =
      await AppPreferences.readString(AppPreferences.databasePathKey) ??
      p.join(root, 'database');
  final controller = PromptBoxController(store: JsonPromptStore(database));
  await controller.initialize();
  final port = int.parse(
    await File(p.join(root, 'feed-port.txt')).readAsString(),
  );
  runApp(
    PromptBoxApp(
      controller: controller,
      updaterFactory:
          (prepare) => AppUpdateService(
            createClient:
                () => _FixtureClient(Uri.parse('http://127.0.0.1:$port/')),
            tempDirectory:
                () async =>
                    Directory(p.join(root, 'downloads'))
                      ..createSync(recursive: true),
            prepareForRestart: prepare,
          ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  final version = (await PackageInfo.fromPlatform()).version;
  await File(p.join(root, 'launch-$version.json')).writeAsString(
    jsonEncode({
      'version': version,
      'pid': pid,
      'databasePath': controller.databasePath,
      'theme': controller.themePreference.name,
      'fontScale': controller.fontScale,
      'viewScale': controller.viewScale,
      'entries':
          controller.currentDay?.entries
              .map((entry) => entry.toJson())
              .toList(),
      'draftRestored':
          await File(
            p.join(root, 'pending-update-draft.json.restored'),
          ).exists(),
    }),
    flush: true,
  );
}
