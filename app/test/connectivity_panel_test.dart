import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/connectivity/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'connectivity_controller_test.dart' as fixture;

void main() {
  testWidgets(
    'acknowledged apply and Direct path remain separate from application availability',
    (tester) async {
      final client = fixture.ConnectivityFixture();
      final c = fixture.controller(client);
      await c.bind(fixture.profile());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('Соединение: подключение выполняется'), findsOneWidget);
      expect(find.text('Direct-путь: не подтверждён'), findsOneWidget);
      client.value.serviceState = api.ServiceState.SERVICE_STATE_CONNECTED;
      client.value.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTED;
      client.value.agent = api.AgentStatus(directPathCount: 1)
        ..mapRevision = api.AgentStatus().mapRevision + 8;
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Соединение: подключено'), findsOneWidget);
      expect(find.text('Локальное применение: подтверждено'), findsOneWidget);
      expect(find.text('Direct-путь: подтверждён'), findsOneWidget);
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
      expect(find.text('Direct-путь: не подтверждён'), findsOneWidget);
      client.value.credential = api.CredentialStatus(
        state: api.CredentialState.CREDENTIAL_STATE_EXPIRED,
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
      expect(find.text('Direct-путь: не подтверждён'), findsOneWidget);
      final connect = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Подключить'),
      );
      expect(connect.onPressed, isNull);
    },
  );
}
