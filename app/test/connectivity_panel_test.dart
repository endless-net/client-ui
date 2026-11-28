import 'dart:async';

import 'package:endlessnet_client_ui/client/connectivity_client.dart';
import 'package:endlessnet_ui/endlessnet_ui.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/connectivity/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'connectivity_controller_test.dart' as fixture;

final class DnsFixture extends fixture.ConnectivityFixture
    implements DiagnosticsClient {
  api.DnsApplication application =
      api.DnsApplication(
        accountId: 'a',
        networkId: 'network',
        nodeId: 'node',
        state: api.DnsApplyState.DNS_APPLY_STATE_FAILED,
        failure: api.DnsApplyFailure.DNS_APPLY_FAILURE_OS_APPLY,
      )..mergeFromProto3Json({
        'targetMapRevision': '9',
        'lastAppliedMapRevision': '8',
      });
  Completer<void>? gate;
  @override
  Future<api.Diagnostics> diagnostics(
    String profileId,
    Duration timeout,
  ) async {
    final response = api.Diagnostics(
      metadata: value.metadata,
      status: value,
      dns: api.DnsDiagnostics(application: application),
    );
    await gate?.future;
    return response;
  }
}

void main() {
  testWidgets('device panel distinguishes target and locally applied map', (
    tester,
  ) async {
    final client = fixture.ConnectivityFixture();
    final agent = api.AgentStatus(
      nodeId: 'node',
      networkId: 'network',
      snapshotState: api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_ABSENT,
    )..mergeFromProto3Json({'targetMapRevision': '9007199254740993'});
    client.value
      ..agent = agent
      ..serviceState = api.ServiceState.SERVICE_STATE_ERROR
      ..failures.add(
        api.Failure(
          code: api.ErrorCode.ERROR_CODE_APPLY_FAILED,
          reasonKey: 'client.connection.apply_failed',
        ),
      );
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectivityPanel(controller: c, simple: true),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('Получена карта ревизии 9007199254740993.'),
      findsOneWidget,
    );
    expect(find.textContaining('пока не подтверждено'), findsOneWidget);
    expect(
      find.textContaining(
        'Применение или очистка сетевых настроек не завершены.',
      ),
      findsOneWidget,
    );
    client.value.failures.clear();
    client.value.failures.add(
      api.Failure(
        code: api.ErrorCode.ERROR_CODE_RESOURCE_CONFLICT,
        reasonKey: 'client.connection.resource_conflict',
        actionOwner: api.ActionOwner.ACTION_OWNER_DEVICE_ADMINISTRATOR,
      ),
    );
    client.value.overlayAddresses.add('100.64.0.7');
    agent
      ..snapshotState = api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_PREVIOUS
      ..mergeFromProto3Json({'mapRevision': '8'});
    await c.refresh();
    await tester.pump();
    expect(find.textContaining('предыдущей карте ревизии 8.'), findsOneWidget);
    expect(
      find.text(
        'Сетевая настройка конфликтует с настройками ОС на этом устройстве.',
      ),
      findsOneWidget,
    );
    expect(find.text('Адрес EndlessNet: 100.64.0.7'), findsNothing);
    agent.mapRevision = agent.targetMapRevision;
    await c.refresh();
    await tester.pump();
    expect(
      find.textContaining('Карта ревизии 9007199254740993 применялась ранее.'),
      findsOneWidget,
    );
    agent.snapshotState = api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT;
    client.value.failures.clear();
    await c.refresh();
    await tester.pump();
    expect(
      find.text('На этом устройстве применена карта ревизии 9007199254740993.'),
      findsOneWidget,
    );
    expect(find.text('Адрес EndlessNet: 100.64.0.7'), findsOneWidget);
    agent.nodeId = 'another';
    await c.refresh();
    await tester.pump();
    expect(find.textContaining('9007199254740993'), findsNothing);
  });

  testWidgets('DNS check shows rejected update and previous OS revision', (
    tester,
  ) async {
    final client = DnsFixture()..value.accountId = 'a';
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(body: ConnectivityPanel(controller: c, simple: true)),
      ),
    );
    await tester.tap(find.text('Проверить DNS'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Не удалось применить настройки DNS ревизии 9.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Последняя подтверждённая ревизия — 8.'),
      findsOneWidget,
    );
    client.application.nodeId = 'foreign';
    await tester.tap(find.text('Проверить DNS'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось прочитать диагностику DNS.'), findsOneWidget);
    expect(find.textContaining('ревизии 9'), findsNothing);
  });
  test('late DNS response is discarded after rebinding', () async {
    final client = DnsFixture()..value.accountId = 'a';
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    client.gate = Completer();
    final read = c.readDNS();
    client.value = fixture.disconnected()
      ..activeProfileId = 'second'
      ..nodeId = 'second-node'
      ..accountId = 'b';
    await c.bind(fixture.profile('second'));
    client.gate!.complete();
    await read;
    expect(c.dns, isNull);
    expect(c.dnsLoading, isFalse);
  });

  testWidgets('failed IPC read hides failures from the previous snapshot', (
    tester,
  ) async {
    final client = fixture.ConnectivityFixture();
    client.value.failures.add(
      api.Failure(reasonKey: 'client.connection.trust_required'),
    );
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(body: ConnectivityPanel(controller: c, simple: true)),
      ),
    );
    final trustMessage = find.textContaining('Не удалось подтвердить подпись');
    expect(trustMessage, findsOneWidget);

    client.readFailure = StateError('private transport diagnostic');
    await c.refresh();
    await tester.pump();
    expect(trustMessage, findsNothing);
    expect(
      find.text('Не удалось прочитать состояние локальной службы.'),
      findsOneWidget,
    );
    expect(find.textContaining('private transport diagnostic'), findsNothing);

    client.readFailure = null;
    client.value.failures
      ..clear()
      ..add(api.Failure(reasonKey: 'client.connection.map_rejected'));
    await c.refresh();
    await tester.pump();
    expect(trustMessage, findsNothing);
    expect(find.text('Карта сети отклонена при проверке.'), findsOneWidget);
    for (final entry in {
      'client.connection.dns_assignment_invalid':
          'В назначении DNS есть ошибка. Проверьте настройки DNS этой сети.',
      'client.connection.dns_unsupported':
          'Эта версия службы не поддерживает назначенные настройки DNS.',
    }.entries) {
      client.value.failures
        ..clear()
        ..add(api.Failure(reasonKey: entry.key));
      await c.refresh();
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('endpoint refresh degradation does not hide a ready tunnel', (
    tester,
  ) async {
    final client = fixture.ConnectivityFixture();
    client.value
      ..serviceState = api.ServiceState.SERVICE_STATE_CONNECTED
      ..connectionPhase = api.ConnectionPhase.CONNECTION_PHASE_CONNECTED
      ..controlState = api.ControlState.CONTROL_STATE_DEGRADED
      ..failures.add(
        api.Failure(
          reasonKey: 'client.connection.endpoint_refresh_unconfirmed',
        ),
      );
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(body: ConnectivityPanel(controller: c, simple: true)),
      ),
    );
    expect(find.text('Туннель готов'), findsOneWidget);
    expect(
      find.textContaining('Сервер не подтвердил обновление'),
      findsOneWidget,
    );
  });

  testWidgets(
    'sole-node local ready is explicit and never claims a peer path',
    (tester) async {
      final client = fixture.ConnectivityFixture();
      client.value
        ..serviceState = api.ServiceState.SERVICE_STATE_LOCAL_READY
        ..connectionPhase = api.ConnectionPhase.CONNECTION_PHASE_LOCAL_READY
        ..controlState = api.ControlState.CONTROL_STATE_READY
        ..mergeFromProto3Json({'mapRevision': '18446744073709551615'})
        ..overlayAddresses.add('100.64.0.1/32')
        ..agent = api.AgentStatus(
          snapshotState: api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT,
        );
      final c = fixture.controller(client);
      await c.bind(fixture.profile());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectivityPanel(controller: c),
            ),
          ),
        ),
      );
      expect(find.text('Туннель готов'), findsOneWidget);
      client.value.peerCount = 1;
      await c.refresh();
      await tester.pump();
      expect(find.text('Туннель готов'), findsNothing);
      expect(client.connects, 0);
    },
  );

  testWidgets('recovery is visible without claiming application access', (
    tester,
  ) async {
    final client = fixture.ConnectivityFixture();
    client.value.serviceState = api.ServiceState.SERVICE_STATE_RECOVERING;
    client.value.connectionPhase =
        api.ConnectionPhase.CONNECTION_PHASE_CONNECTING;
    client.value.clearAgent();
    final c = fixture.controller(client);
    await c.bind(fixture.profile());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(body: ConnectivityPanel(controller: c)),
      ),
    );
    expect(
      find.text('Соединение: подключение или восстановление выполняется'),
      findsOneWidget,
    );

    client.value.connectionPhase =
        api.ConnectionPhase.CONNECTION_PHASE_UNSPECIFIED;
    await c.refresh();
    await tester.pump();
    expect(
      find.text('Соединение: служба восстанавливает состояние'),
      findsOneWidget,
    );
    expect(client.connects, 0);
  });

  testWidgets('distinguishes scheduled retries from required login', (
    tester,
  ) async {
    final client = fixture.ConnectivityFixture();
    client.value
      ..serviceState = api.ServiceState.SERVICE_STATE_ERROR
      ..connectionPhase = api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED
      ..failures.add(
        api.Failure(reasonKey: 'client.connection.retry_scheduled'),
      );
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(body: ConnectivityPanel(controller: c, simple: true)),
      ),
    );
    expect(
      find.text('Соединение: повтор подключения запланирован'),
      findsOneWidget,
    );
    client.value.failures
      ..clear()
      ..add(api.Failure(reasonKey: 'client.connection.login_required'));
    await c.refresh();
    await tester.pump();
    expect(find.text('Соединение: требуется вход'), findsOneWidget);
    expect(c.canConnect, isFalse);
    expect(client.connects, 0);
  });

  testWidgets('main panel keeps ready status with peers on different paths', (
    tester,
  ) async {
    final client = fixture.ConnectivityFixture();
    client.value
      ..serviceState = api.ServiceState.SERVICE_STATE_CONNECTED
      ..controlState = api.ControlState.CONTROL_STATE_READY
      ..connectionPhase = api.ConnectionPhase.CONNECTION_PHASE_CONNECTED
      ..peerCount = 3;
    client.value.peerTransports.addAll([
      api.PeerTransportStatus(peerId: 'phone'),
      api.PeerTransportStatus(peerId: 'server'),
      api.PeerTransportStatus(peerId: 'laptop'),
    ]);
    final c = fixture.controller(client);
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectivityPanel(controller: c, simple: true),
          ),
        ),
      ),
    );
    expect(find.text('Туннель готов'), findsOneWidget);
    expect(find.text('Нет подтверждённого пути'), findsNWidgets(3));

    client.value.peerTransports[0].selectedPath = api.PathKind.PATH_KIND_DIRECT;
    client.value.peerTransports[1].selectedPath = api.PathKind.PATH_KIND_RELAY;
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Туннель готов'), findsOneWidget);
    expect(find.text('Устройство: phone'), findsOneWidget);
    expect(find.text('Устройство: server'), findsOneWidget);
    expect(find.text('Устройство: laptop'), findsOneWidget);
    expect(find.text('Путь: Direct'), findsOneWidget);
    expect(find.text('Путь: Relay'), findsOneWidget);
    expect(find.text('Нет подтверждённого пути'), findsOneWidget);

    client.value.peerTransports[0].clearSelectedPath();
    client.value.peerTransports[1].clearSelectedPath();
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Туннель готов'), findsOneWidget);
    expect(find.text('Нет подтверждённого пути'), findsNWidgets(3));
  });

  for (final entry in {
    'client.connection.map_revision_rollback':
        'Получена карта с ревизией ниже уже подтверждённой.',
    'client.connection.map_issue_time_rollback': 'Время выпуска полученной карты раньше времени выпуска уже подтверждённой карты.',
    'client.connection.map_content_conflict': 'Для одной ревизии и времени выпуска получены карты с разным содержимым.',
    'client.connection.control_conflict': 'Сервер управления отклонил запрос из-за конфликта состояния (ABORTED).',
    'client.connection.session_create_failed':
        'Служба не смогла создать локальный сеанс туннеля',
    'client.connection.session_connect_failed':
        'Сеанс создан, но служба не смогла завершить настройку туннеля',
    'client.connection.session_interrupted':
        'После подключения рабочий цикл туннеля завершился с ошибкой',
    'client.connection.endpoint_announcement_failed':
        'Не удалось завершить публикацию сетевого адреса устройства',
    'client.connection.map_queue_full': 'Очередь карт сети заполнена',
    'client.connection.state_capacity':
        'Достигнут предел размера локального состояния клиента',
    'client.connection.state_unavailable': 'Локальное состояние клиента отсутствует, повреждено или недоступно для чтения',
    'client.connection.state_write_unconfirmed':
        'Служба не смогла подтвердить запись локального состояния клиента',
    'client.connection.failed': 'Служба не сообщила, какая операция',
    'client.connection.trust_required':
        'Проверьте адрес сервера и установленную версию',
    'client.connection.credential_expired':
        'проверит возможность продления для того же устройства',
    'client.connection.deadline':
        'Время подключения или восстановления истекло',
    'client.connection.registration_revoked': 'Регистрация устройства отозвана',
  }.entries) {
    testWidgets('recovery reason ${entry.key} has a safe next action', (
      tester,
    ) async {
      final client = fixture.ConnectivityFixture();
      client.value.serviceState = api.ServiceState.SERVICE_STATE_ERROR;
      client.value.failures.add(api.Failure(reasonKey: entry.key));
      final c = fixture.controller(client);
      await c.bind(fixture.profile());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectivityPanel(controller: c),
            ),
          ),
        ),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(client.connects, 0);
    });
  }
  testWidgets(
    'blocked target explains new authorized admission without claiming a confirmed revoke',
    (tester) async {
      final client = fixture.ConnectivityFixture();
      client.value.serviceState = api.ServiceState.SERVICE_STATE_POLICY_BLOCKED;
      client.value.failures.add(
        api.Failure(
          code: api.ErrorCode.ERROR_CODE_POLICY_BLOCKED,
          reasonKey: 'client.connection.access_denied',
        ),
      );
      final c = fixture.controller(client);
      await c.bind(fixture.profile());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectivityPanel(controller: c),
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          'Если регистрация отозвана, для возврата нужен новый авторизованный допуск',
        ),
        findsOneWidget,
      );
      expect(find.text('Запрет подтверждён'), findsNothing);
      expect(client.connects, 0);
      expect(client.disconnects, 0);
    },
  );
  testWidgets(
    'acknowledged apply and Direct path remain separate from application availability',
    (tester) async {
      final client = fixture.ConnectivityFixture();
      final c = fixture.controller(client);
      await c.bind(fixture.profile());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectivityPanel(controller: c),
            ),
          ),
        ),
      );
      expect(find.text('Соединение: отключено'), findsOneWidget);
      client.onCommand = () {
        client.value.intent.desiredState =
            api.DesiredState.DESIRED_STATE_CONNECTED;
        client.value.connectionPhase =
            api.ConnectionPhase.CONNECTION_PHASE_CONNECTING;
        client.value.serviceState = api.ServiceState.SERVICE_STATE_RECOVERING;
        client.value.metadata.revision += 1;
      };
      await tester.tap(find.text('Подключить'));
      await tester.pumpAndSettle();
      expect(
        find.text('Соединение: подключение или восстановление выполняется'),
        findsOneWidget,
      );
      client.value.serviceState = api.ServiceState.SERVICE_STATE_CONNECTED;
      client.value.controlState = api.ControlState.CONTROL_STATE_READY;
      client.value.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTED;
      client.value.peerTransports.add(
        api.PeerTransportStatus(
          peerId: 'peer-a',
          selectedPath: api.PathKind.PATH_KIND_DIRECT,
        ),
      );
      client.value.agent = api.AgentStatus(directPathCount: 1)
        ..mapRevision = api.AgentStatus().mapRevision + 8;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Туннель готов'), findsOneWidget);
      expect(find.text('Локальное применение: неизвестно'), findsOneWidget);
      client.value.agent
        ..nodeId = client.value.nodeId
        ..networkId = client.value.network.id
        ..snapshotState = api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT
        ..targetMapRevision = client.value.agent.mapRevision;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('На этом устройстве применена карта ревизии 8.'),
        findsOneWidget,
      );
      expect(find.text('Путь: Direct'), findsOneWidget);
      expect(
        find.text(
          'Работа приложения второго устройства проверяется отдельно от сетевого пути.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(client.disconnects, 0);
    },
  );

  testWidgets(
    'offline, expiry and uncertain cleanup show safe next action without raw diagnostics',
    (tester) async {
      final client = fixture.ConnectivityFixture();
      final c = fixture.controller(client);
      addTearDown(c.dispose);
      client.value.intent.desiredState =
          api.DesiredState.DESIRED_STATE_CONNECTED;
      client.value.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTED;
      client.value.serviceState = api.ServiceState.SERVICE_STATE_DEGRADED;
      client.value.controlState = api.ControlState.CONTROL_STATE_OFFLINE_CACHE;
      client.value.agent = api.AgentStatus(
        directPathCount: 1,
        connectionPaused: true,
      )..mapRevision = api.AgentStatus().mapRevision + 8;
      await c.bind(fixture.profile());
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectivityPanel(controller: c),
            ),
          ),
        ),
      );
      expect(
        find.text('Соединение: сервер управления недоступен'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Новые соединения запрещены.'),
        findsOneWidget,
      );
      client.value.credential = api.CredentialStatus(
        state: api.CredentialState.CREDENTIAL_STATE_EXPIRED,
      );
      client.value.session = api.Session(
        state: api.SessionState.SESSION_STATE_EXPIRED,
      );
      client.value.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_UNSPECIFIED;
      client.value.serviceState = api.ServiceState.SERVICE_STATE_ERROR;
      client.value.failures.addAll([
        api.Failure(
          code: api.ErrorCode.ERROR_CODE_APPLY_FAILED,
          reasonKey: 'client.connection.cleanup_unconfirmed',
          actionOwner: api.ActionOwner.ACTION_OWNER_DEVICE_ADMINISTRATOR,
        ),
        api.Failure(reasonKey: 'synthetic-secret-backend-detail'),
      ]);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Учётные данные устройства истекли.'),
        findsOneWidget,
      );
      expect(find.textContaining('Сеанс пользователя истёк.'), findsOneWidget);
      expect(
        find.text('Очистка сетевых ресурсов не подтверждена.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('обратитесь к администратору устройства'),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic-secret'), findsNothing);
      client.readFailure = StateError('synthetic-secret native error');
      await c.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('Соединение: фактическое состояние неизвестно'),
        findsOneWidget,
      );
      expect(find.text('Локальное применение: неизвестно'), findsOneWidget);
      final connect = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Подключить'),
      );
      expect(connect.onPressed, isNull);
    },
  );
  for (final entry in {
    api.TransportSearchState.TRANSPORT_SEARCH_STATE_SEARCHING:
        'Поиск Direct выполняется',
    api.TransportSearchState.TRANSPORT_SEARCH_STATE_BACKOFF:
        'Повторный поиск Direct запланирован',
    api.TransportSearchState.TRANSPORT_SEARCH_STATE_EXHAUSTED:
        'Доступный Direct-вариант пока не найден',
    api.TransportSearchState.TRANSPORT_SEARCH_STATE_UNSUPPORTED:
        'Для предложенного транспорта требуется обновление клиента',
  }.entries) {
    testWidgets('Relay stays available while ${entry.key}', (tester) async {
      final client = fixture.ConnectivityFixture();
      client.value.serviceState = api.ServiceState.SERVICE_STATE_CONNECTED;
      client.value.controlState = api.ControlState.CONTROL_STATE_READY;
      client.value.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTED;
      client.value.peerTransports.add(
        api.PeerTransportStatus(
          peerId: 'peer-b',
          selectedPath: api.PathKind.PATH_KIND_RELAY,
          engine: 'amneziawg',
          protocolVersion: '3.1',
          transportProfileId: 'profile-7',
          searchState: entry.key,
          reasonKey: 'synthetic-private-diagnostic',
        ),
      );
      final c = fixture.controller(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConnectivityPanel(controller: c),
            ),
          ),
        ),
      );
      expect(find.text('Туннель готов'), findsOneWidget);
      expect(find.text('Путь: Relay'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(
        find.textContaining('Транспорт: AmneziaWG; версия: 3.1'),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic-private-diagnostic'), findsNothing);
      client.readFailure = StateError('IPC unavailable');
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Путь: Relay'), findsNothing);
      expect(
        find.text('Последний известный путь: Relay (не подтверждён)'),
        findsOneWidget,
      );
      expect(find.text(entry.value), findsNothing);
      expect(find.text('Состояние поиска Direct устарело'), findsOneWidget);
      client.readFailure = null;
      client.value.peerTransports.single.selectedPath =
          api.PathKind.PATH_KIND_DIRECT;
      await c.resume();
      await tester.pumpAndSettle();
      expect(find.text('Путь: Direct'), findsOneWidget);
      client.runtime.contractSha256 = 'b' * 64;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Путь: Direct'), findsNothing);
      expect(
        find.textContaining('несовместимый локальный клиент'),
        findsOneWidget,
      );
      expect(client.connects, 0);
      expect(client.disconnects, 0);
    });
  }
}
