import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/app/app.dart';
import 'package:endlessnet_client_ui/app/launch_config.dart';
import 'package:endlessnet_client_ui/app/session.dart';
import 'package:endlessnet_client_ui/app/windows_runtime_platform.dart';
import 'package:endlessnet_client_ui/client/contract_identity.dart';
import 'package:endlessnet_client_ui/client/enrollment_client.dart';
import 'package:endlessnet_client_ui/client/connectivity_client.dart';
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/recent_logs_client.dart';
import 'package:endlessnet_client_ui/client/session_login_client.dart';
import 'package:endlessnet_client_ui/client/session_login_correlation.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'enrollment_controller_test.dart' as fixture;
import 'launch_config_test.dart' as config_fixture;
import 'server_trust_controller_test.dart' as trust_fixture;
import 'session_login_test.dart' as login_fixture;

final class SessionConnectivity implements ConnectivityClient {
  SessionConnectivity(this.client);
  final EnrollmentClient client;
  int connects = 0, disconnects = 0;
  bool failStatus = false;
  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) =>
      client.runtimeInfo(timeout);
  @override
  Future<api.Status> status(Duration timeout) async {
    if (failStatus) {
      throw ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-status-failure'),
        4096,
      );
    }
    return client.status(timeout);
  }

  @override
  Future<void> connect(api.ConnectRequest request, Duration timeout) async {
    connects++;
  }

  @override
  Future<void> disconnect(
    api.DisconnectRequest request,
    Duration timeout,
  ) async {
    disconnects++;
  }
}

class InstalledClient extends fixture.FakeClient {
  InstalledClient(this.instance);
  String instance;
  @override
  Future<api.EnrollmentAttempt> enroll(
    api.EnrollRequest request,
    Duration timeout,
  ) {
    value.requestId = request.requestId;
    return super.enroll(request, timeout);
  }

  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async {
    final runtime = await super.runtimeInfo(timeout);
    runtime.instanceId = instance;
    runtime.capabilities.add(
      api.CapabilityStatus(
        capability: api.Capability.CAPABILITY_CONNECTION,
        restriction: api.Restriction(
          availability: api.Availability.AVAILABILITY_AVAILABLE,
        ),
      ),
    );
    return runtime;
  }
}

final class InstalledLogsClient extends InstalledClient
    implements RecentLogsClient {
  InstalledLogsClient(super.instance);

  final requests = <api.ListRecentLogsRequest>[];
  bool unavailable = false;

  @override
  Future<api.ListRecentLogsResponse> recentLogs(
    api.ListRecentLogsRequest request,
    Duration timeout,
  ) async {
    requests.add(request);
    if (unavailable) {
      throw ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-service-failure'),
        4096,
      );
    }
    final first = request.page.pageToken.isEmpty;
    return api.ListRecentLogsResponse(
      logs: [
        api.LogEntry(
          message: first
              ? '{"time":"2026-11-22T00:00:00Z","level":"INFO",'
                    '"msg":"client.request","operation":"server_key",'
                    '"outcome":"success","code":"2xx","trace_id":"fixture-trace"}'
              : 'Попытка подключения запущена',
          timestamp: Timestamp.fromDateTime(DateTime.utc(2026, 11, 22)),
        ),
      ],
      page: api.PageResponse(
        metadata: api.SnapshotMetadata(instanceId: instance),
        nextPageToken: first ? 'second-page' : '',
      ),
    );
  }
}

final class InstalledSessionClient extends InstalledClient
    implements SessionLoginClient {
  InstalledSessionClient(super.instance);

  int sessionReads = 0;
  late api.Session userSession;
  Completer<void>? sessionReadWait;

  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async {
    final runtime = await super.runtimeInfo(timeout);
    runtime.capabilities.add(
      api.CapabilityStatus(
        capability: api.Capability.CAPABILITY_SESSION_LOGIN,
        restriction: api.Restriction(
          availability: api.Availability.AVAILABILITY_AVAILABLE,
        ),
      ),
    );
    return runtime;
  }

  @override
  Future<api.GetSessionResponse> session(
    api.GetSessionRequest request,
    Duration timeout,
  ) async {
    sessionReads++;
    final result = api.GetSessionResponse(
      session: userSession,
      metadata: snapshot.metadata,
    );
    await sessionReadWait?.future;
    return result;
  }

  @override
  Future<api.SessionLoginAttempt> sessionLogin(
    api.GetSessionLoginRequest request,
    Duration timeout,
  ) async => throw StateError('unexpected login attempt lookup');

  @override
  Future<api.SessionLoginAttempt> startSessionLogin(
    api.StartSessionLoginRequest request,
    Duration timeout,
  ) async => throw StateError('unexpected login mutation');
}

final class SessionCorrelation extends fixture.MemoryCorrelation
    implements SessionLoginCorrelationStore {
  final _sessionStore = login_fixture.Store();

  @override
  Future<SessionLoginCorrelation?> readSessionLogin(String id, String origin) =>
      _sessionStore.readSessionLogin(id, origin);

  @override
  Future<void> saveSessionLogin(SessionLoginCorrelation correlation) =>
      _sessionStore.saveSessionLogin(correlation);
}

final class TestPlatform implements UiRuntimePlatform {
  TestPlatform({fixture.FakeClient? client, fixture.MemoryCorrelation? store})
    : client = client ?? fixture.FakeClient(),
      store = store ?? fixture.MemoryCorrelation() {
    this.client.digest = clientContractSha256;
  }
  var config = UiLaunchConfig.decode(
    Uint8List.fromList(utf8.encode(jsonEncode(config_fixture.launchValues()))),
    nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
  );
  late final connectivity = SessionConnectivity(client);
  final fixture.FakeClient client;
  final fixture.MemoryCorrelation store;
  final events = <String>[];
  Completer<void>? configWait, connectWait, storageWait, closeWait;
  bool failConfig = false, failStorage = false, failConnectionClose = false;
  UiConfigurationFailure? configurationFailure;
  int browserCalls = 0;

  @override
  Future<UiLaunchConfig> readConfig() async {
    events.add('config');
    await configWait?.future;
    if (configurationFailure case final failure?) throw failure;
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
    }, connectivity: connectivity);
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
    'startup retries failed discovery indefinitely with a bounded delay',
    (tester) async {
      final platform = TestPlatform()..failConfig = true;
      await tester.pumpWidget(MainApp(platform: platform));
      await tester.pump();
      expect(platform.events, ['config']);
      await tester.pump(const Duration(seconds: 1));
      expect(platform.events, ['config', 'config']);
      await tester.pump(const Duration(seconds: 1));
      expect(platform.events, ['config', 'config']);
      await tester.pump(const Duration(seconds: 1));
      expect(platform.events, ['config', 'config', 'config']);
      for (final delay in [4, 8, 16, 30, 30, 30]) {
        final attempts = platform.events.length;
        await tester.pump(Duration(seconds: delay));
        expect(platform.events.length, attempts + 1);
      }
      platform.failConfig = false;
      await tester.tap(find.text('Повторить подключение'));
      await tester.pump();
      expect(platform.events.sublist(platform.events.length - 3), [
        'config',
        'connect',
        'storage',
      ]);
      expect(platform.connectivity.connects, 0);
      expect(platform.connectivity.disconnects, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('untrusted discovery waits for explicit retry', (tester) async {
    final platform = TestPlatform()
      ..configurationFailure = const UiConfigurationFailure(
        UiConfigurationProblem.untrusted,
      );
    await tester.pumpWidget(MainApp(platform: platform));
    await tester.pump(const Duration(minutes: 1));
    expect(platform.events, ['config']);
    platform.configurationFailure = null;
    await tester.tap(find.text('Повторить подключение'));
    await tester.pump();
    expect(platform.events, ['config', 'config', 'connect', 'storage']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a dead status channel is reopened and exit cancels later retries',
    (tester) async {
      final seed = TestPlatform();
      final platform = TestPlatform(
        client: InstalledClient(seed.config.pipe.instanceId),
      );
      platform.client.snapshot.metadata.instanceId =
          platform.config.pipe.instanceId;
      await tester.pumpWidget(MainApp(platform: platform));
      await tester.pump();
      platform.connectivity.failStatus = true;
      await tester.pump(platform.config.pollInterval);
      expect(platform.events.where((event) => event == 'connect').length, 1);
      platform.connectivity.failStatus = false;
      await tester.pump(const Duration(seconds: 1));
      expect(platform.events.where((event) => event == 'connect').length, 2);
      platform.connectivity.failStatus = true;
      await tester.pump(platform.config.pollInterval);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
      expect(platform.events.where((event) => event == 'connect').length, 2);
      expect(platform.connectivity.connects, 0);
      expect(platform.connectivity.disconnects, 0);
    },
  );

  testWidgets('automatic recovery discovers a new service instance', (
    tester,
  ) async {
    final initial = config_fixture.launchValues()['instance_id'] as String;
    final client = InstalledClient(initial);
    final platform = TestPlatform(client: client);
    client.snapshot.metadata.instanceId = initial;
    await tester.pumpWidget(MainApp(platform: platform));
    await tester.pump();
    const next = 'a0000000-0000-4000-8000-000000000001';
    client.instance = next;
    client.snapshot.metadata.instanceId = next;
    platform.config = UiLaunchConfig.decode(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(config_fixture.launchValues()..['instance_id'] = next),
        ),
      ),
      nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
    );
    await tester.pump(platform.config.pollInterval);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(platform.events.where((event) => event == 'config').length, 2);
    expect(platform.events.where((event) => event == 'connect').length, 2);
    expect(platform.connectivity.connects, 0);
    expect(platform.connectivity.disconnects, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'ready control refreshes an expired session after an older read',
    () async {
      final values = config_fixture.launchValues();
      final client = InstalledSessionClient(values['instance_id'] as String);
      final p = TestPlatform(client: client, store: SessionCorrelation());
      client.snapshot = api.Status(
        metadata: fixture.metadata()..instanceId = client.instance,
        activeProfileId: p.config.profile.id,
        nodeId: 'same-node',
        controlState: api.ControlState.CONTROL_STATE_REGISTERED,
      );
      client.userSession = api.Session(
        state: api.SessionState.SESSION_STATE_EXPIRED,
      );
      final s = await UiSession.open(p, cancelled: () => false);
      addTearDown(s.close);
      await s.initialize();
      final login = s.sessionLogin!;
      expect(login.sessionExpired, isTrue);
      expect(login.canStart, isTrue);

      final previousRead = Completer<void>();
      client.sessionReadWait = previousRead;
      final refresh = login.refresh();
      await turns();
      expect(client.sessionReads, 2);

      client.sessionReadWait = null;
      client.userSession = api.Session(
        state: api.SessionState.SESSION_STATE_ACTIVE,
        expiresAt: Timestamp.fromDateTime(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      client.snapshot
        ..controlState = api.ControlState.CONTROL_STATE_READY
        ..connectionPhase = api.ConnectionPhase.CONNECTION_PHASE_LOCAL_READY;
      await s.connectivity.refresh();
      previousRead.complete();
      await refresh;
      await turns();

      expect(login.sessionActive, isTrue);
      expect(login.canStart, isFalse);
      await s.connectivity.refresh();
      expect(client.sessionReads, 3);
      expect(p.browserCalls, 0);
    },
  );

  test('explicit login connects once after registration, reopen never auto-connects', () async {
    final values = config_fixture.launchValues();
    final client = InstalledClient(values['instance_id'] as String);
    final p = TestPlatform(client: client);
    client.snapshot = api.Status(
      metadata: fixture.metadata()..instanceId = client.instance,
    );
    client.value =
        fixture.makeAttempt(
            profileId: p.config.profile.id,
            phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED,
          )
          ..metadata.instanceId = client.instance
          ..nodeId = 'same-node'
          ..accountId = 'account'
          ..networkId = 'network';
    client.snapshot
      ..activeProfileId = p.config.profile.id
      ..nodeId = 'same-node'
      ..accountId = 'account'
      ..network = api.Network(id: 'network')
      ..storedState = api.StoredStatePresence(nodeCredentialPresent: true)
      ..controlState = api.ControlState.CONTROL_STATE_NOT_REGISTERED
      ..connectionPhase = api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED;
    // No prior attempt exists before the explicit enrollment action.
    client.lookupFailure = ClientCallFailure.fromGrpc(
      grpc.GrpcError.notFound('fixture'),
      4096,
    );
    final session = await UiSession.open(p, cancelled: () => false);
    await session.initialize();
    expect(p.connectivity.connects, 0);
    client.lookupFailure = null;
    await session.startEnrollment(
      'this-PC',
      api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
    );
    await turns();
    expect(p.connectivity.connects, 1);
    await session.enrollment.refresh();
    await turns();
    expect(p.connectivity.connects, 1);
    await session.close();
    expect(p.connectivity.disconnects, 0);
    final reopened = await UiSession.open(p, cancelled: () => false);
    await reopened.initialize();
    await turns();
    expect(p.connectivity.connects, 1);
    await reopened.close();
  });

  testWidgets('MCP button opens the access dialog', (tester) async {
    await tester.pumpWidget(MainApp(platform: TestPlatform()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MCP'));
    await tester.pumpAndSettle();
    expect(find.text('Доступ по MCP'), findsOneWidget);
    expect(find.text('Разрешить'), findsOneWidget);
    expect(
      find.textContaining('Разрешение сохраняется после перезапуска Windows'),
      findsOneWidget,
    );

    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Доступ по MCP'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, skip: !Platform.isWindows);

  testWidgets('logs button opens both journals and pages Client entries', (
    tester,
  ) async {
    final client = InstalledLogsClient(
      config_fixture.launchValues()['instance_id'] as String,
    );
    final platform = TestPlatform(client: client);
    await tester.pumpWidget(MainApp(platform: platform));
    await tester.pumpAndSettle();

    final logsButton = find.text('Журналы');
    if (Platform.isWindows) {
      final mcp = find.text('MCP');
      expect(tester.getCenter(logsButton).dy, tester.getCenter(mcp).dy);
    }
    await tester.tap(logsButton);
    await tester.pumpAndSettle();
    expect(find.text('server_key'), findsOneWidget);
    expect(find.textContaining('INFO · success · 2xx'), findsOneWidget);
    expect(find.text('trace_id: fixture-trace'), findsNothing);
    await tester.tap(find.text('server_key'));
    await tester.pumpAndSettle();
    expect(find.text('msg: client.request'), findsOneWidget);
    expect(find.text('trace_id: fixture-trace'), findsOneWidget);
    await tester.tap(find.text('server_key'));
    await tester.pumpAndSettle();
    expect(
      client.requests.single.profile.profileId,
      platform.config.profile.id,
    );

    await tester.tap(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    expect(find.text('server_key'), findsOneWidget);
    expect(find.text('Попытка подключения запущена'), findsOneWidget);
    expect(find.text('Показать ещё'), findsNothing);
    expect(client.requests.last.page.pageToken, 'second-page');
    expect(
      client.requests.last.page.pageSize,
      client.requests.first.page.pageSize,
    );

    client.unavailable = true;
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось прочитать журнал службы Client.'),
      findsOneWidget,
    );
    expect(find.text('raw-service-failure'), findsNothing);

    await tester.tap(find.text('Интерфейс'));
    await tester.pumpAndSettle();
    expect(find.text('app · sessionInitialized'), findsOneWidget);

    client.unavailable = false;
    await tester.tap(find.text('Служба Client'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();
    expect(find.text('Показать ещё'), findsOneWidget);
    expect(find.text('Попытка подключения запущена'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('EndlessNet'), findsOneWidget);
    expect(platform.connectivity.connects, 0);
    expect(platform.connectivity.disconnects, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('UI journal opens when the Client session cannot start', (
    tester,
  ) async {
    await tester.pumpWidget(
      MainApp(platform: TestPlatform()..failConfig = true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журналы'));
    await tester.pumpAndSettle();
    expect(find.text('Служба Client недоступна.'), findsOneWidget);

    await tester.tap(find.text('Интерфейс'));
    await tester.pumpAndSettle();
    expect(find.text('app · sessionUnavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

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
    'hiding and restoring the window keeps its session and refreshes status',
    (tester) async {
      final values = config_fixture.launchValues();
      final client = InstalledClient(values['instance_id'] as String);
      final platform = TestPlatform(client: client);
      client.snapshot = api.Status(
        metadata: fixture.metadata()..instanceId = client.instance,
        activeProfileId: platform.config.profile.id,
        nodeId: 'same-node',
        accountId: 'account',
        network: api.Network(id: 'network'),
        controlState: api.ControlState.CONTROL_STATE_REGISTERED,
        connectionPhase: api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
      );

      await tester.pumpWidget(MainApp(platform: platform));
      await tester.pumpAndSettle();
      expect(find.text('Соединение: отключено'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      client.snapshot.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTING;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.textContaining('Соединение: подключение'), findsOneWidget);
      expect(platform.events, ['config', 'connect', 'storage']);
      expect(platform.connectivity.connects, 0);
      expect(platform.connectivity.disconnects, 0);
      await tester.pumpWidget(const SizedBox());
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
