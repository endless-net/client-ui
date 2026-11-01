import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/app/app.dart';
import 'package:endlessnet_client_ui/app/launch_config.dart';
import 'package:endlessnet_client_ui/app/session.dart';
import 'package:endlessnet_client_ui/app/windows_runtime_platform.dart';
import 'package:endlessnet_client_ui/client/contract_identity.dart';
import 'package:endlessnet_client_ui/client/enrollment_client.dart';
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'enrollment_controller_test.dart' as fixture;
import 'launch_config_test.dart' as config_fixture;
import 'server_trust_controller_test.dart' as trust_fixture;

final class TestPlatform implements UiRuntimePlatform {
  TestPlatform({fixture.FakeClient? client})
    : client = client ?? fixture.FakeClient() {
    this.client.digest = clientContractSha256;
  }
  final config = UiLaunchConfig.decode(
    Uint8List.fromList(utf8.encode(jsonEncode(config_fixture.launchValues()))),
    nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
  );
  final fixture.FakeClient client;
  final store = fixture.MemoryCorrelation();
  final events = <String>[];
  Completer<void>? configWait, connectWait, storageWait, closeWait;
  bool failConfig = false, failStorage = false, failConnectionClose = false;
  int browserCalls = 0;

  @override
  Future<UiLaunchConfig> readConfig() async {
    events.add('config');
    await configWait?.future;
    if (failConfig) throw StateError('raw-secret-path-diagnostic');
    return config;
  }

  @override
  Future<UiClientConnection> connect(UiLaunchConfig config) async {
    events.add('connect');
    await connectWait?.future;
    return UiClientConnection(client, () async {
      events.add('connection.close');
      if (failConnectionClose) throw StateError('raw-close-diagnostic');
    });
  }

  @override
  Future<UiCorrelationStorage> openStorage(UiLaunchConfig config) async {
    events.add('storage');
    await storageWait?.future;
    if (failStorage) throw StateError('raw-storage-diagnostic');
    return UiCorrelationStorage(store, () async {
      events.add('storage.close');
      await closeWait?.future;
    });
  }

  @override
  Future<bool> openBrowser(Uri url) async {
    browserCalls++;
    return true;
  }

  void originalAttempt() {
    store.records[config.profile.id] = EnrollmentCorrelation(
      profileId: config.profile.id,
      controlOrigin: config.profile.controlOrigin,
      requestId: fixture.requestId,
      hostname: 'original-host',
      mode: api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
    );
    client.value = fixture.makeAttempt(
      profileId: config.profile.id,
      phase: api.EnrollmentPhase.ENROLLMENT_PHASE_DENIED,
    );
  }
}

Future<void> turns() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  testWidgets(
    'exit during explicit reconnect waits for old resources and cannot start a new connection',
    (tester) async {
      final p = TestPlatform()
        ..originalAttempt()
        ..closeWait = Completer<void>();
      p.client.lookupFailure = ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-secret'),
        16384,
      );
      await tester.pumpWidget(MainApp(platform: p));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переподключиться к локальному клиенту'));
      await tester.pump();
      expect(find.text('Переподключение…'), findsOneWidget);
      final exited = tester.binding.handleRequestAppExit();
      await tester.pump();
      await tester.pump();
      p.closeWait!.complete();
      await tester.pumpAndSettle();
      expect(await exited, AppExitResponse.exit);
      expect(p.events, [
        'config',
        'connect',
        'storage',
        'connection.close',
        'storage.close',
      ]);
      expect(p.client.enrolls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'explicit reconnect closes old session and recovers original UUID on a fresh connection',
    (tester) async {
      final p = TestPlatform()..originalAttempt();
      p.client.lookupFailure = ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-secret'),
        16384,
      );
      await tester.pumpWidget(MainApp(platform: p));
      await tester.pumpAndSettle();
      expect(
        find.text('Переподключиться к локальному клиенту'),
        findsOneWidget,
      );
      p.client.lookupFailure = null;
      await tester.tap(find.text('Переподключиться к локальному клиенту'));
      await tester.pumpAndSettle();
      expect(p.events, [
        'config',
        'connect',
        'storage',
        'connection.close',
        'storage.close',
        'config',
        'connect',
        'storage',
      ]);
      expect(p.client.lookup!.requestId, fixture.requestId);
      expect(p.client.enrolls, 0);
      expect(p.browserCalls, 0);
      expect(find.text('Регистрация отклонена'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('session invalidates accepted trust when enrollment observes rotation, without another trust RPC', () async {
    final client = trust_fixture.TrustClient();
    final p = TestPlatform(client: client)..originalAttempt();
    client.identity = trust_fixture.announcement(
      profile: p.config.profile.id,
      trusted: true,
    );
    final s = await UiSession.open(p, cancelled: () => false);
    await s.initialize();
    await s.trust.bind(p.config.profile);
    expect(s.trust.trusted, isTrue);
    final old = s.trust.observation!;
    client.value.metadata.revision += 1;
    client.value.restriction = api.Restriction(
      reasonKey: 'client.server_identity.changed',
    );
    await s.enrollment.refresh();
    expect(s.trust.observation, isNull);
    expect(s.trust.trusted, isFalse);
    expect(await s.trust.confirm(old), isFalse);
    expect(client.reads, 1);
    expect(client.trusts, 0);
    expect(client.enrolls, 0);
    expect(s.enrollment.correlation!.requestId, fixture.requestId);
    await s.close();
  });
  test('production platform rejects an unconfigured launch without selecting a fallback', () async {
    await expectLater(
      WindowsUiRuntimePlatform([]).readConfig(),
      throwsA(isA<UiConfigurationFailure>()),
    );
  });
  test('session restores original UUID and closes once, without automatic mutations or browser', () async {
    final p = TestPlatform()..originalAttempt();
    final s = await UiSession.open(p, cancelled: () => false);
    final initialized = s.initialize();
    expect(identical(initialized, s.initialize()), isTrue);
    await initialized;
    expect(s.trust.state.name, 'detached');
    expect(p.client.lookup!.requestId, fixture.requestId);
    expect(p.client.enrolls, 0);
    expect(p.browserCalls, 0);
    expect(await s.openBrowser(Uri.parse('https://foreign.example')), isFalse);
    final close = s.close();
    expect(identical(close, s.close()), isTrue);
    await close;
    expect(p.events, [
      'config',
      'connect',
      'storage',
      'connection.close',
      'storage.close',
    ]);
    await s.initialize();
    expect(p.client.lookups, 1);
    final reopened = await UiSession.open(p, cancelled: () => false);
    await reopened.initialize();
    expect(p.client.lookup!.requestId, fixture.requestId);
    expect(p.client.enrolls, 0);
    await reopened.close();
  });

  test('session browser seam accepts only the current explicit action and stops after close', () async {
    final p = TestPlatform()..originalAttempt();
    final now = DateTime.now().toUtc();
    p.client.value = fixture.makeAttempt(profileId: p.config.profile.id)
      ..createdAt = Timestamp.fromDateTime(now)
      ..deadline = Timestamp.fromDateTime(now.add(const Duration(minutes: 22)));
    p.client.value.browserAction.expiresAt = Timestamp.fromDateTime(
      now.add(const Duration(minutes: 10)),
    );
    final s = await UiSession.open(p, cancelled: () => false);
    await s.initialize();
    final action = s.enrollment.browserAction;
    expect(action, isNotNull);
    expect(p.browserCalls, 0);
    expect(await s.openBrowser(action!), isTrue);
    expect(await s.openBrowser(Uri.parse('https://foreign.example')), isFalse);
    await s.close();
    expect(await s.openBrowser(action), isFalse);
    expect(p.browserCalls, 1);
  });

  test('cancel at each asynchronous acquisition boundary closes exactly acquired resources', () async {
    for (final stage in ['config', 'connect', 'storage']) {
      final p = TestPlatform();
      final gate = Completer<void>();
      switch (stage) {
        case 'config':
          p.configWait = gate;
        case 'connect':
          p.connectWait = gate;
        case 'storage':
          p.storageWait = gate;
      }
      var cancel = false;
      final open = UiSession.open(p, cancelled: () => cancel);
      final result = expectLater(open, throwsA(isA<UiStartupCancelled>()));
      await turns();
      expect(p.events.last, stage);
      cancel = true;
      gate.complete();
      await result;
      expect(
        p.events.where((e) => e.endsWith('.close')).toList(),
        switch (stage) {
          'config' => <String>[],
          'connect' => ['connection.close'],
          _ => ['connection.close', 'storage.close'],
        },
      );
      expect(p.client.enrolls, 0);
    }
  });

  test('storage acquisition failure closes connection without retry', () async {
    final p = TestPlatform()..failStorage = true;
    await expectLater(
      UiSession.open(p, cancelled: () => false),
      throwsStateError,
    );
    expect(p.events, ['config', 'connect', 'storage', 'connection.close']);
  });

  test('cleanup continues after a transport close failure and remains typed on aborted startup', () async {
    final p = TestPlatform()
      ..storageWait = Completer<void>()
      ..failConnectionClose = true;
    var cancel = false;
    final opened = UiSession.open(p, cancelled: () => cancel);
    final result = expectLater(opened, throwsA(isA<UiCleanupFailure>()));
    await turns();
    cancel = true;
    p.storageWait!.complete();
    await result;
    expect(p.events.sublist(3), ['connection.close', 'storage.close']);
  });

  test(
    'close disposes controller before a late lookup and awaits storage release',
    () async {
      final p = TestPlatform()
        ..originalAttempt()
        ..closeWait = Completer<void>();
      p.client.pendingLookup = Completer<api.EnrollmentAttempt>();
      final s = await UiSession.open(p, cancelled: () => false);
      final initialized = s.initialize();
      await turns();
      expect(p.client.lookups, 1);
      var closed = false;
      final closing = s.close().then((_) => closed = true);
      await turns();
      expect(closed, isFalse);
      p.client.pendingLookup!.complete(p.client.value);
      await initialized;
      expect(s.enrollment.currentAttempt, isNull);
      p.closeWait!.complete();
      await closing;
      expect(p.client.enrolls, 0);
    },
  );

  testWidgets(
    'shell shows safe startup error, retries same platform and renders real enrollment panel',
    (tester) async {
      final p = TestPlatform()..failConfig = true;
      await tester.pumpWidget(MainApp(platform: p));
      await tester.pumpAndSettle();
      expect(find.textContaining('raw-secret'), findsNothing);
      expect(find.text('Повторить подключение'), findsOneWidget);
      p.failConfig = false;
      await tester.tap(find.text('Повторить подключение'));
      await tester.pumpAndSettle();
      expect(find.text('Подключите этот компьютер'), findsOneWidget);
      expect(p.client.enrolls, 0);
      expect(p.browserCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(p.events.where((e) => e == 'storage.close').length, 1);
    },
  );

  testWidgets(
    'OS exit waits for session storage; repeated exit requests share cleanup',
    (tester) async {
      final p = TestPlatform()..closeWait = Completer<void>();
      await tester.pumpWidget(MainApp(platform: p));
      await tester.pumpAndSettle();
      var returned = false;
      final exited = tester.binding.handleRequestAppExit().then((r) {
        returned = true;
        return r;
      });
      await tester.pump();
      await tester.pump();
      expect(returned, isFalse);
      expect(find.text('Завершение работы…'), findsOneWidget);
      final second = tester.binding.handleRequestAppExit();
      p.closeWait!.complete();
      expect(await exited, AppExitResponse.exit);
      expect(await second, AppExitResponse.exit);
      expect(p.events.where((e) => e == 'connection.close').length, 1);
      expect(p.events.where((e) => e == 'storage.close').length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'exit during acquisition waits and closes late connection without opening storage',
    (tester) async {
      final p = TestPlatform()..connectWait = Completer<void>();
      await tester.pumpWidget(MainApp(platform: p));
      await tester.pump();
      expect(p.events.last, 'connect');
      final exited = tester.binding.handleRequestAppExit();
      await tester.pump();
      await tester.pump();
      p.connectWait!.complete();
      await tester.pumpAndSettle();
      expect(await exited, AppExitResponse.exit);
      expect(p.events, ['config', 'connect', 'connection.close']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cleanup failure cancels normal OS exit, releases remaining storage and hides diagnostics',
    (tester) async {
      final p = TestPlatform()..failConnectionClose = true;
      await tester.pumpWidget(MainApp(platform: p));
      await tester.pumpAndSettle();
      final exited = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(await exited, AppExitResponse.cancel);
      expect(p.events.where((e) => e == 'storage.close').length, 1);
      expect(find.textContaining('raw-close'), findsNothing);
      expect(
        find.text('Не удалось завершить работу с локальным хранилищем.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
