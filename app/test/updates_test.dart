import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_ui/app/app.dart';
import 'package:endlessnet_client_ui/dashboard/board.dart';
import 'package:endlessnet_client_ui/app/launch_config.dart';
import 'package:endlessnet_client_ui/app/session.dart';
import 'package:endlessnet_client_ui/update/controller.dart';
import 'package:endlessnet_client_ui/update/releases.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> metadata({
  String tag = 'v0.4.0',
  List<int> bytes = const [1, 2, 3],
}) => {
  'draft': false,
  'prerelease': false,
  'tag_name': tag,
  'assets': [
    {
      'name': 'EndlessNet-$tag-windows-amd64.msi',
      'state': 'uploaded',
      'browser_download_url':
          'https://github.com/endless-net/client-ui/releases/download/$tag/EndlessNet-$tag-windows-amd64.msi',
      'size': bytes.length,
      'digest': 'sha256:${sha256.convert(bytes)}',
    },
  ],
};
WindowsRelease release() => WindowsRelease.decode(jsonEncode(metadata()));

class Source implements ReleaseSource {
  Future<WindowsRelease> Function() fetch = () async => release();
  int checks = 0;
  bool closed = false;
  @override
  Future<WindowsRelease> latest() {
    checks++;
    return fetch();
  }

  @override
  void close() {
    closed = true;
  }
}

class UnavailableClient implements UiRuntimePlatform {
  @override
  Future<UiLaunchConfig> readConfig() async =>
      throw const UiConfigurationFailure();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = '$value';
  }

  @override
  String? value(String name) => values[name];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(
    this.body, {
    this.statusCode = 200,
    this.contentLength = -1,
    String? location,
  }) {
    if (location != null) headers.set(HttpHeaders.locationHeader, location);
  }
  final Stream<List<int>> body;
  @override
  final int statusCode, contentLength;
  @override
  final headers = Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  final headers = Headers();
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  Client(this.response);
  final Future<HttpClientResponse> Function(Uri) response;
  final urls = <Uri>[];
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return Request(response(url));
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('versions compare numerically; invalid or unrepresentable MSI versions fail', () {
    expect(
      ReleaseVersion('v0.10.0').compareTo(ReleaseVersion('0.9.99')),
      greaterThan(0),
    );
    for (final bad in [
      '0.01.0',
      'v1.0.0',
      'v0.1.0-beta',
      'v0.256.0',
      'v0.1.65536',
    ]) {
      expect(() => ReleaseVersion(bad), throwsA(isA<UpdateFailure>()));
    }
  });

  test(
    'GitHub release requires one exact MSI, digest, stable tag and origin',
    () {
      expect(release().version.text, '0.4.0');
      final mutations = <void Function(Map<String, dynamic>)>[
        (m) => m['draft'] = true,
        (m) => m['prerelease'] = true,
        (m) => m['tag_name'] = 'v0.4.0-beta',
        (m) => m['assets'] = [],
        (m) => (m['assets'] as List).add((m['assets'] as List).single),
        (m) => m['assets'][0]['browser_download_url'] =
            'https://evil.invalid/update.msi',
        (m) => m['assets'][0].remove('digest'),
        (m) => m['assets'][0]['size'] = 0,
        (m) => m['assets'][0]['state'] = 'new',
      ];
      for (final change in mutations) {
        final m = metadata();
        change(m);
        expect(
          () => WindowsRelease.decode(jsonEncode(m)),
          throwsA(isA<UpdateFailure>()),
        );
      }
    },
  );

  test('check never downloads; same/older versions are current, source failure is an error', () async {
    final source = Source();
    final controller = UpdateController(
      ReleaseVersion('0.4.0'),
      source,
      (_) async => fail('unexpected install'),
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.status, UpdateStatus.current);
    source.fetch = () async =>
        WindowsRelease.decode(jsonEncode(metadata(tag: 'v0.3.0')));
    await controller.check();
    expect(controller.status, UpdateStatus.current);
    source.fetch = () async => throw const UpdateFailure();
    await controller.check();
    expect(controller.status, UpdateStatus.failed);
  });

  testWidgets(
    'startup and minute checks work when Client configuration is unavailable',
    (tester) async {
      final source = Source();
      final controller = UpdateController(
        ReleaseVersion('0.3.0'),
        source,
        (_) async => 0,
      );
      await tester.pumpWidget(
        MainApp(
          dashboardStore: const BoardStore(null),
          platform: UnavailableClient(),
          openUpdates: () async => controller,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Настройки приложения. Доступно обновление'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Скачать и обновить'), findsOneWidget);
      expect(source.checks, 1);
      await tester.pump(const Duration(seconds: 58));
      expect(source.checks, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(source.checks, 2);
      await tester.pumpWidget(const SizedBox());
      expect(source.closed, isTrue);
      await tester.pump(const Duration(minutes: 2));
      expect(source.checks, 2);
    },
  );

  test(
    'confirmed update is single-flight and requests the selected version',
    () async {
      final source = Source();
      final entered = Completer<WindowsRelease>(), finished = Completer<int>();
      var installs = 0;
      final controller = UpdateController(ReleaseVersion('0.3.0'), source, (
        release,
      ) {
        installs++;
        entered.complete(release);
        return finished.future;
      });
      addTearDown(controller.dispose);
      await controller.check();
      final pending = controller.update();
      expect((await entered.future).version.text, '0.4.0');
      await controller.update();
      await controller.check();
      expect(installs, 1);
      finished.complete(0);
      await pending;
      expect(controller.status, UpdateStatus.completed);
    },
  );

  test('installer failure and reboot are factual results; disposing does not cancel MSI', () async {
    for (final code in [1, 1602, 3010, 1641]) {
      final controller = UpdateController(
        ReleaseVersion('0.3.0'),
        Source(),
        (_) async => code,
      );
      await controller.check();
      await controller.update();
      expect(
        controller.status,
        code == 3010 || code == 1641
            ? UpdateStatus.restart
            : UpdateStatus.failed,
      );
      controller.dispose();
    }
    final done = Completer<int>(), entered = Completer<void>();
    final controller = UpdateController(ReleaseVersion('0.3.0'), Source(), (_) {
      entered.complete();
      return done.future;
    });
    await controller.check();
    final pending = controller.update();
    await entered.future;
    controller.dispose();
    done.complete(0);
    await pending;
  });

  test('bounded HTTPS fetch rejects errors, oversized metadata and foreign redirect', () async {
    for (final response in [
      Response(Stream.value([]), statusCode: 403),
      Response(Stream.value(List.filled(512 * 1024 + 1, 32))),
      Response(
        Stream.value([]),
        statusCode: 302,
        location: 'https://evil.invalid/update.msi',
      ),
    ]) {
      final client = Client((_) async => response);
      final source = GitHubReleases(clientFactory: () => client);
      await expectLater(source.latest(), throwsA(anything));
      expect(client.closed, isTrue);
      source.close();
    }
  });

  test('timeout closes one request and the next minute can retry with a new client', () async {
    final slow = Client(
      (_) => Future.delayed(
        const Duration(milliseconds: 40),
        () => Response(Stream.value([])),
      ),
    );
    final good = Client(
      (_) async => Response(Stream.value(utf8.encode(jsonEncode(metadata())))),
    );
    var calls = 0;
    final source = GitHubReleases(
      clientFactory: () => calls++ == 0 ? slow : good,
      metadataTimeout: const Duration(milliseconds: 5),
    );
    await expectLater(source.latest(), throwsA(anything));
    expect((await source.latest()).version.text, '0.4.0');
    expect(slow.closed, isTrue);
    expect(good.closed, isTrue);
    source.close();
  });
}
