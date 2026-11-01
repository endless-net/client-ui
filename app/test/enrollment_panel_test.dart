import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/enrollment/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

// Share only fixture definitions; the other entrypoint's main is not executed.
import 'enrollment_controller_test.dart' as fixture;

void main() {
  testWidgets(
    'completing is shown as finishing registration without claiming success',
    (tester) async {
      final client = fixture.FakeClient()
        ..value = fixture.makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_COMPLETING,
        );
      final c = fixture.controller(client, fixture.MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentPanel(controller: c, now: () => fixture.now),
          ),
        ),
      );
      expect(find.text('Завершение регистрации'), findsOneWidget);
      expect(find.text('Устройство зарегистрировано'), findsNothing);
      expect(find.text('Состояние требует проверки'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'permission restriction explains disabled start without claiming owner',
    (tester) async {
      final client = fixture.FakeClient()
        ..capability = api.Availability.AVAILABILITY_PERMISSION_REQUIRED;
      final c = fixture.controller(client, fixture.MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentPanel(controller: c, now: () => fixture.now),
          ),
        ),
      );
      expect(
        find.text('Действие доступно владельцу локального клиента.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Начать вход'),
      );
      expect(button.onPressed, isNull);
      expect(client.enrolls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('countdown uses producer expiry and dispose stops view timer', (
    tester,
  ) async {
    var clock = fixture.now;
    final client = fixture.FakeClient();
    final c = fixture.controller(client, fixture.MemoryCorrelation());
    await c.bind(fixture.profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    client.value =
        fixture.makeAttempt(
            phase: api.EnrollmentPhase.ENROLLMENT_PHASE_PENDING_APPROVAL,
          )
          ..approvalExpiresAt = Timestamp.fromDateTime(
            clock.add(const Duration(seconds: 2)),
          );
    await c.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrollmentPanel(controller: c, now: () => clock),
        ),
      ),
    );
    expect(find.text('Время ожидания одобрения: 0:02'), findsOneWidget);
    clock = clock.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Время ожидания одобрения: 0:01'), findsOneWidget);
    expect(find.text('Устройство зарегистрировано'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser failure is safe and bound to the current profile', (
    tester,
  ) async {
    final client = fixture.FakeClient();
    final c = fixture.controller(client, fixture.MemoryCorrelation());
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrollmentPanel(
            controller: c,
            now: () => fixture.now,
            openBrowser: (_) async => throw StateError('launcher-raw-secret'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть вход в браузере'));
    await tester.pump();
    expect(find.textContaining('Не удалось открыть браузер.'), findsOneWidget);
    expect(find.textContaining('launcher-raw-secret'), findsNothing);
    await c.bind(fixture.profile('profile-B'));
    await tester.pump();
    expect(find.textContaining('Не удалось открыть браузер.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'browser opens only by explicit click; completion is not enrollment',
    (tester) async {
      final client = fixture.FakeClient();
      final c = fixture.controller(client, fixture.MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentPanel(
              controller: c,
              now: () => fixture.now,
              openBrowser: (url) async {
                opened.add(url);
                return true;
              },
            ),
          ),
        ),
      );
      expect(opened, isEmpty);
      expect(find.text('Ожидание входа'), findsOneWidget);
      await tester.tap(find.text('Открыть вход в браузере'));
      await tester.pump();
      expect(opened.single.origin, 'https://control.example');
      expect(find.text('Устройство зарегистрировано'), findsNothing);
      expect(client.enrolls, 1);
      client.value = fixture.makeAttempt()
        ..browserAction.expiresAt = Timestamp.fromDateTime(fixture.now);
      await c.refresh();
      await tester.pump();
      expect(find.text('Открыть вход в браузере'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pending, denied, expired, cancelled and unknown remain distinct',
    (tester) async {
      final client = fixture.FakeClient();
      final c = fixture.controller(client, fixture.MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EnrollmentPanel(controller: c, now: () => fixture.now),
          ),
        ),
      );
      for (final state in <api.EnrollmentPhase, String>{
        api.EnrollmentPhase.ENROLLMENT_PHASE_PENDING_APPROVAL:
            'Ожидание одобрения',
        api.EnrollmentPhase.ENROLLMENT_PHASE_DENIED: 'Регистрация отклонена',
        api.EnrollmentPhase.ENROLLMENT_PHASE_EXPIRED: 'Время попытки истекло',
        api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED: 'Ожидание отменено',
      }.entries) {
        client.value = fixture.makeAttempt(phase: state.key)
          ..restriction = api.Restriction(
            actionOwner: api.ActionOwner.ACTION_OWNER_ACCESS_ADMINISTRATOR,
            reasonKey: 'unrecognized-raw-diagnostic',
          );
        await c.refresh();
        await tester.pump();
        expect(find.text(state.value), findsOneWidget);
        expect(
          find.text('Обратитесь к администратору доступа.'),
          findsOneWidget,
        );
        expect(find.text('unrecognized-raw-diagnostic'), findsNothing);
        expect(find.text('Устройство зарегистрировано'), findsNothing);
      }
      client.value = fixture.makeAttempt()
        ..certainty = api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN;
      await c.refresh();
      await tester.pump();
      expect(find.text('Исход регистрации пока неизвестен'), findsOneWidget);
      expect(find.text('Открыть вход в браузере'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('registered display requires current matching Node snapshot', (
    tester,
  ) async {
    final client = fixture.FakeClient();
    final c = fixture.controller(client, fixture.MemoryCorrelation());
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    client.value =
        fixture.makeAttempt(
            phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED,
          )
          ..accountId = 'account-A'
          ..networkId = 'network-A'
          ..nodeId = 'node-A';
    await c.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrollmentPanel(controller: c, now: () => fixture.now),
        ),
      ),
    );
    expect(find.text('Регистрация требует подтверждения'), findsOneWidget);
    expect(find.text('Устройство: node-A'), findsNothing);
    client.snapshot = api.Status(
      metadata: fixture.metadata(),
      activeProfileId: 'profile-A',
      accountId: 'account-A',
      nodeId: 'node-A',
      network: api.Network(id: 'network-A'),
    );
    await c.refresh();
    await tester.pump();
    expect(find.text('Устройство зарегистрировано'), findsOneWidget);
    expect(find.text('Устройство: node-A'), findsOneWidget);
    expect(find.text('Аккаунт: account-A'), findsOneWidget);
    expect(find.text('Сеть: network-A'), findsOneWidget);
    expect(find.text('Отменить ожидание'), findsNothing);
    expect(
      find.textContaining('Доступность сетевых ресурсов проверяется отдельно.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lost response offers lookup and never offers a second Enroll', (
    tester,
  ) async {
    final client = fixture.FakeClient()..lostEnroll = true;
    final c = fixture.controller(client, fixture.MemoryCorrelation());
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrollmentPanel(controller: c, now: () => fixture.now),
        ),
      ),
    );
    expect(find.text('Начать вход'), findsNothing);
    expect(find.text('Исход регистрации пока неизвестен'), findsOneWidget);
    await tester.tap(find.text('Проверить исходную попытку'));
    await tester.pump();
    expect(client.lookup!.requestId, fixture.requestId);
    expect(client.enrolls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('catalog is explicit and denied target cannot be selected', (
    tester,
  ) async {
    final client = fixture.FakeClient()
      ..value = fixture.makeAttempt(
        phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
      );
    client.page.targets.addAll([
      api.EnrollmentTarget(
        accountId: 'account-A',
        networkId: 'network-A',
        restriction: api.Restriction(
          availability: api.Availability.AVAILABILITY_PERMISSION_REQUIRED,
        ),
      ),
      api.EnrollmentTarget(
        accountId: 'account-B',
        networkId: 'network-B',
        restriction: api.Restriction(
          availability: api.Availability.AVAILABILITY_AVAILABLE,
        ),
      ),
    ]);
    final c = fixture.controller(client, fixture.MemoryCorrelation());
    addTearDown(c.dispose);
    await c.bind(fixture.profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrollmentPanel(controller: c, now: () => fixture.now),
        ),
      ),
    );
    expect(client.pages, 0);
    await tester.tap(find.text('Загрузить доступные аккаунты и сети'));
    await tester.pump();
    expect(client.pages, 1);
    final choices = tester
        .widgetList<TextButton>(find.widgetWithText(TextButton, 'Выбрать'))
        .toList();
    expect(choices[0].onPressed, isNull);
    expect(choices[1].onPressed, isNotNull);
    await tester.ensureVisible(find.text('Выбрать').last);
    await tester.tap(find.text('Выбрать').last);
    await tester.pump();
    expect(client.selects, 1);
    expect(client.selected!.accountId, 'account-B');
    expect(find.text('Регистрация устройства'), findsOneWidget);
    expect(find.text('Устройство зарегистрировано'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
