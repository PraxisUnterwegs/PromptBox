import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_box/app_update.dart';
import 'package:prompt_box/update_settings.dart';

const assetName = 'PromptBox-preview-windows-x64.zip';
Map<String, dynamic> releaseData(
  String tag, {
  bool preview = true,
  String? digest,
  String? url,
}) => {
  'tag_name': tag,
  'prerelease': preview,
  'draft': false,
  'body': '版本说明',
  'assets': [
    {
      'name': assetName,
      'state': 'uploaded',
      'size': 1024,
      'digest': digest ?? 'sha256:${List.filled(64, 'a').join()}',
      'browser_download_url':
          url ??
          'https://github.com/PraxisUnterwegs/PromptBox/releases/download/$tag/$assetName',
    },
  ],
};

Map<String, dynamic> releaseFixture() => releaseData('v0.1.0-preview.7');

class FakeUpdates extends AppUpdateService {
  int checks = 0, downloads = 0, installs = 0;
  @override
  Future<void> check() async {
    checks++;
    release = UpdateRelease.select(
      [releaseFixture()],
      '0.1.0-preview.6',
      assetName,
    );
    notifyListeners();
  }

  @override
  Future<void> download() async {
    downloads++;
    downloaded = File('update.zip');
    notifyListeners();
  }

  @override
  Future<void> install({required String databasePath}) async {
    installs++;
  }
}

void main() {
  test('苹果平台原生数字版本恢复为预览语义版本，其他平台和正式版保持原值', () {
    expect(
      AppUpdateService.installedVersionFor('0.1.0.7', '7', 'macos'),
      '0.1.0-preview.7',
    );
    expect(
      AppUpdateService.installedVersionFor('0.1.0.10', '10', 'macos'),
      '0.1.0-preview.10',
    );
    expect(
      AppUpdateService.installedVersionFor('0.1.0', '7', 'macos'),
      '0.1.0',
    );
    expect(
      AppUpdateService.installedVersionFor('0.1.0.7', '8', 'macos'),
      '0.1.0.7',
    );
    expect(
      AppUpdateService.installedVersionFor('0.1.0-preview.7', '7', 'windows'),
      '0.1.0-preview.7',
    );
    expect(
      AppUpdateService.installedVersionFor('0.1.0-preview.7', '7', 'linux'),
      '0.1.0-preview.7',
    );
    final current = AppUpdateService.installedVersionFor(
      '0.1.0.9',
      '9',
      'macos',
    );
    expect(
      UpdateRelease.select(
        [releaseData('v0.1.0-preview.10')],
        current,
        assetName,
      )!.tag,
      'v0.1.0-preview.10',
    );
  });
  test('版本按数字比较，preview.10 大于 preview.9，正式版大于预览版', () {
    expect(
      ReleaseVersion.parse(
        'v0.1.0-preview.10',
      )!.compareTo(ReleaseVersion.parse('0.1.0-preview.9+9')!),
      greaterThan(0),
    );
    expect(
      ReleaseVersion.parse(
        '0.1.0',
      )!.compareTo(ReleaseVersion.parse('0.1.0-preview.10')!),
      greaterThan(0),
    );
    expect(
      ReleaseVersion.parse(
        '0.1.0+1',
      )!.compareTo(ReleaseVersion.parse('0.1.0+99')!),
      0,
    );
    expect(ReleaseVersion.parse('not-a-version'), isNull);
  });

  test('选取最新兼容 Release，排除草稿、降级和重复版本', () {
    final releases = [
      releaseData('v0.1.0-preview.7'),
      releaseData('v0.1.0-preview.10'),
      releaseData('v0.1.0-preview.8'),
    ];
    expect(
      UpdateRelease.select(releases, '0.1.0-preview.6', assetName)!.tag,
      'v0.1.0-preview.10',
    );
    expect(
      UpdateRelease.select(releases, '0.1.0-preview.10', assetName),
      isNull,
    );
    expect(
      UpdateRelease.select(
        [
          {...releaseData('v9.0.0'), 'draft': true},
        ],
        '0.1.0-preview.6',
        assetName,
      ),
      isNull,
    );
    expect(
      UpdateRelease.select(releases, '0.1.0-preview.6', 'macos-arm64.dmg'),
      isNull,
    );
  });

  test('正式版不接收预览版，预览版可以升级至正式版', () {
    expect(
      UpdateRelease.select(
        [releaseData('v1.1.0-preview.1')],
        '1.0.0',
        assetName,
      ),
      isNull,
    );
    expect(
      UpdateRelease.select(
        [releaseData('v1.0.0', preview: false)],
        '1.0.0-preview.6',
        assetName,
      )!.tag,
      'v1.0.0',
    );
  });

  test('拒绝无校验值、其他仓库、不安全下载 URL', () {
    for (final fixture in [
      releaseData('v1.0.0', digest: ''),
      releaseData(
        'v1.0.0',
        url:
            'http://github.com/PraxisUnterwegs/PromptBox/releases/download/file',
      ),
      releaseData(
        'v1.0.0',
        url: 'https://github.com/attacker/repo/releases/download/file',
      ),
      releaseData('v1.0.0', url: 'https://example.com/file'),
    ]) {
      expect(
        UpdateRelease.select([fixture], '0.1.0-preview.6', assetName),
        isNull,
      );
    }
  });

  test('按当前进程架构匹配产物，未知架构不回退到错误安装包', () {
    expect(AppUpdateService.assetFor('windows', Abi.windowsX64), assetName);
    expect(
      AppUpdateService.assetFor('linux', Abi.linuxX64),
      endsWith('amd64.deb'),
    );
    expect(
      AppUpdateService.assetFor('macos', Abi.macosArm64),
      endsWith('arm64.dmg'),
    );
    expect(
      () => AppUpdateService.assetFor('linux', Abi.linuxArm64),
      throwsUnsupportedError,
    );
    expect(
      () => AppUpdateService.assetFor('macos', Abi.macosX64),
      throwsUnsupportedError,
    );
  });

  testWidgets('检查、下载、安装分别由用户触发；取消确认不会继续', (tester) async {
    final service = FakeUpdates();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateSettings(service: service, databasePath: 'database'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.checks, 0);
    expect(service.downloads, 0);
    expect(service.installs, 0);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(service.checks, 1);
    expect(service.downloads, 0);
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.downloads, 0);
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认下载'));
    await tester.pumpAndSettle();
    expect(service.downloads, 1);
    expect(service.installs, 0);
    await tester.tap(find.text('安装更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.installs, 0);
    await tester.tap(find.text('安装更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认安装'));
    await tester.pumpAndSettle();
    expect(service.installs, 1);
  });
}
