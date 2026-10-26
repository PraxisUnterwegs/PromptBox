import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_box/app_update.dart';

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes, {this.statusCode = 200});
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  final responses = <_Response>[];
  final urls = <Uri>[];
  @override
  Duration? connectionTimeout;
  @override
  String? userAgent;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return _Request(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _Client client;
  late AppUpdateService service;
  final bytes = utf8.encode('zip');
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('promptbox-download-test-');
    client = _Client();
    service = AppUpdateService(
      createClient: () => client,
      loadVersion: () async => '0.1.0-preview.6',
      tempDirectory: () async => temp,
    );
    final name = AppUpdateService.assetFor(
      Platform.operatingSystem,
      Abi.current(),
    );
    client.responses.add(
      _Response(
        utf8.encode(
          jsonEncode([
            {
              'tag_name': 'v0.1.0-preview.7',
              'prerelease': true,
              'draft': false,
              'assets': [
                {
                  'name': name,
                  'state': 'uploaded',
                  'size': bytes.length,
                  'digest': 'sha256:${sha256.convert(bytes)}',
                  'browser_download_url':
                      'https://github.com/PraxisUnterwegs/PromptBox/releases/download/v0.1.0-preview.7/$name',
                },
              ],
            },
          ]),
        ),
      ),
    );
  });
  tearDown(() async {
    service.dispose();
    await temp.delete(recursive: true);
  });

  test('检查不下载，完整下载且 SHA256 匹配才允许安装', () async {
    expect(client.urls, isEmpty);
    await service.check();
    expect(client.urls, hasLength(1));
    expect(client.urls.single.host, 'api.github.com');
    expect(service.downloaded, isNull);
    client.responses.add(_Response(bytes));
    await service.download();
    expect(service.downloaded, isNotNull);
    expect(await service.downloaded!.readAsBytes(), bytes);
    expect(service.installationPending, isFalse);
    await service.downloaded!.writeAsString('bad');
    await service.install(databasePath: temp.path);
    expect(service.downloaded, isNull);
    expect(service.installationPending, isFalse);
    expect(service.status, contains('SHA-256'));
  });

  test('拒绝截断、超长或哈希不匹配的安装包，失败后可以重试', () async {
    await service.check();
    for (final payload in [
      utf8.encode('z'),
      utf8.encode('long'),
      utf8.encode('bad'),
    ]) {
      client.responses.add(_Response(payload));
      await service.download();
      expect(service.downloaded, isNull);
      expect(service.busy, isFalse);
      expect(service.status, contains('操作失败'));
    }
    client.responses.add(_Response(bytes));
    await service.download();
    expect(service.downloaded, isNotNull);
  });

  test('GitHub 限流错误可显示且不会继续下载', () async {
    client.responses[0] = _Response([], statusCode: 403);
    await service.check();
    expect(service.release, isNull);
    expect(service.busy, isFalse);
    expect(service.status, contains('403'));
    expect(client.urls, hasLength(1));
  });
}
