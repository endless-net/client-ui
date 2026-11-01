import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/enrollment/server_trust_controller.dart';
import 'package:endlessnet_client_ui/enrollment/server_trust_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'enrollment_controller_test.dart' as fixture;
import 'server_trust_controller_test.dart' as trust;

Widget root(ServerTrustController c, {Future<void> Function()? onConfirmed}) =>
    MaterialApp(
      home: Scaffold(
        body: ServerTrustPanel(controller: c, onConfirmed: onConfirmed),
      ),
    );

void main() {
  testWidgets(
    'OWNER sees announcement but no enabled privileged confirmation',
    (tester) async {
      final client = trust.TrustClient()..access = api.Access.ACCESS_OWNER;
      final c = trust.trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await tester.pumpWidget(root(c));
      expect(
        find.textContaining(
          'Подтверждение доступно администратору устройства.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Проверить и подтвердить сервер'),
      );
      expect(button.onPressed, isNull);
      expect(client.trusts, 0);
      expect(client.reads, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'explicit dialog shows exact fields; cancel sends nothing and success re-reads',
    (tester) async {
      final client = trust.TrustClient();
      final c = trust.trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      var callbacks = 0;
      await tester.pumpWidget(
        root(
          c,
          onConfirmed: () async {
            callbacks++;
          },
        ),
      );
      expect(client.trusts, 0);
      await tester.tap(find.text('Проверить и подтвердить сервер'));
      await tester.pumpAndSettle();
      expect(find.text('Подтвердить объявление сервера?'), findsOneWidget);
      expect(find.text('Профиль: profile-A'), findsOneWidget);
      final fields = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data)
          .toList();
      expect(fields, contains('Объявленный ключ: announced-key'));
      expect(fields, contains('Объявление: announcement-A'));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(client.trusts, 0);
      await tester.tap(find.text('Проверить и подтвердить сервер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить это объявление'));
      await tester.pumpAndSettle();
      expect(client.trusts, 1);
      expect(client.reads, 2);
      expect(callbacks, 1);
      expect(
        find.text('Текущее объявление принято локальным клиентом.'),
        findsOneWidget,
      );
      expect(client.enrolls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'profile switch while dialog is open invalidates displayed confirmation',
    (tester) async {
      final client = trust.TrustClient();
      final c = trust.trustController(client);
      addTearDown(c.dispose);
      await c.bind(fixture.profile());
      await tester.pumpWidget(root(c));
      await tester.tap(find.text('Проверить и подтвердить сервер'));
      await tester.pumpAndSettle();
      client.identity = trust.announcement(profile: 'profile-B');
      await c.bind(fixture.profile('profile-B'));
      await tester.tap(find.text('Подтвердить это объявление'));
      await tester.pumpAndSettle();
      expect(client.trusts, 0);
      expect(c.canConfirm, false);
      expect(
        find.textContaining('Объявление или состояние изменилось.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'replacing controller while dialog is open sends no old mutation',
    (tester) async {
      final oldClient = trust.TrustClient();
      final oldController = trust.trustController(oldClient);
      final newClient = trust.TrustClient();
      final newController = trust.trustController(newClient);
      addTearDown(oldController.dispose);
      addTearDown(newController.dispose);
      await oldController.bind(fixture.profile());
      await newController.bind(fixture.profile());
      await tester.pumpWidget(root(oldController));
      await tester.tap(find.text('Проверить и подтвердить сервер'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(root(newController));
      await tester.tap(find.text('Подтвердить это объявление'));
      await tester.pumpAndSettle();
      expect(oldClient.trusts, 0);
      expect(newClient.trusts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
