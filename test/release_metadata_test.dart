import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('发布标签、Flutter 构建版本和 Linux 包版本一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)![1]!;
    final parts = version.split('+');
    final base = parts.first.split('-').first;
    final build = parts.last;
    final deb = File('packaging/linux/control').readAsStringSync();
    expect(deb, contains('Version: $base-$build'));
    if (Platform.environment['GITHUB_REF_TYPE'] == 'tag') {
      expect(
        Platform.environment['GITHUB_REF_NAME'],
        'v${parts.first}',
        reason: '发布 tag 必须与 pubspec.yaml 的语义版本一致',
      );
    }
    final workflow =
        File('.github/workflows/release-preview.yml').readAsStringSync();
    expect(workflow, contains('PREVIEW_NUMBER: "$build"'));
    final appleVersion = parts.first.replaceAll(RegExp(r'[^\d.]'), '');
    final appleCheck = workflow
        .split('\n')
        .firstWhere(
          (line) =>
              line.contains('test "') &&
              line.contains('CFBundleShortVersionString'),
        );
    expect(appleCheck.trim(), endsWith('= $appleVersion'));
  });
}
