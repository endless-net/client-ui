@Tags(['short'])
library;

import 'dart:io';
import 'dart:async';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_notification_delivery.dart';
import 'package:endlessnet/client_notifications_panel.dart';
import 'package:endlessnet/client_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
  for (final quit in [false, true]) {
    testWidgets('notification writes are ordered; quit=$quit', (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-notification-order-'),
      ))!;
      final connection = fixtures.FakeConnection();
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => connection,
      );
      final pending = Completer<void>();
      final writes = <bool>[];
      var exits = 0;
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          desktopIntegration: false,
          deliverNotification: (_, _) async =>
              ClientNotificationDeliveryResult.delivered,
          saveNotifications: (value) async {
            writes.add(value);
            if (writes.length == 1) await pending.future;
          },
          onExit: () async {
            exits++;
          },
        ),
      );
      await tester.pumpAndSettle();
      final snapshot = fixtures.snapshot();
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(snapshot);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-settings')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('client-ui-notifications'));
      final oldChoice = tester.widget<SwitchListTile>(toggle).onChanged!;
      oldChoice(true);
      await tester.pumpAndSettle();
      expect(writes, [true]);
      if (quit) {
        late Future<void> quitting;
        await tester.runAsync(() async {
          final action = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Quit'))
              .onPressed!;
          quitting = (action as Future<void> Function())();
        });
        await tester.pumpAndSettle();
        expect(exits, 0);
        oldChoice(false);
        expect(writes, [true]);
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        pending.complete();
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => quitting.timeout(const Duration(seconds: 5)),
        );
        expect(exits, 1);
      } else {
        tester.widget<SwitchListTile>(toggle).onChanged!(false);
        await tester.pumpAndSettle();
        expect(writes, [true]);
        pending.completeError(StateError('old private error'));
        await tester.pumpAndSettle();
        expect(writes, [true, false]);
        expect(
          tester
              .widget<ClientNotificationsPanel>(
                find.byType(ClientNotificationsPanel),
              )
              .storageFailed,
          isFalse,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await session.close();
        await connection.events.close();
        await directory.delete(recursive: true);
      });
    });
  }
  for (final fail in [false, true]) {
    testWidgets('restored preference and explicit save failure=$fail', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-notification-save-'),
      ))!;
      final connection = fixtures.FakeConnection();
      final saved = <bool>[];
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => connection,
      );
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          desktopIntegration: false,
          initialNotifications: true,
          notificationReadFailed: fail,
          saveNotifications: (value) async {
            saved.add(value);
            if (fail) throw StateError('private storage path');
          },
          deliverNotification: (_, _) async =>
              ClientNotificationDeliveryResult.delivered,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-settings')));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      ClientNotificationsPanel panel() =>
          tester.widget(find.byType(ClientNotificationsPanel));
      expect(panel().delivery.enabled, isTrue);
      expect(panel().persistent, isTrue);
      expect(panel().storageFailed, fail);
      await tester.tap(find.byKey(const ValueKey('page-settings')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('client-ui-notifications'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(saved, [false]);
      expect(panel().delivery.enabled, isFalse);
      expect(panel().storageFailed, fail);
      expect(find.textContaining('private storage'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await session.close();
        await connection.events.close();
        await directory.delete(recursive: true);
      });
    });
  }
  testWidgets(
    'shell binds explicit notification choice without runtime mutation',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-notifications-'),
      ))!;
      final connection = fixtures.FakeConnection();
      final journal = ClientIntentJournal(directory);
      var opens = 0;
      var deliveries = 0;
      final session = ClientSession(
        journal: journal,
        open: () async {
          opens++;
          return connection;
        },
      );
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          desktopIntegration: false,
          deliverNotification: (title, body) async {
            deliveries++;
            expect(title, 'EndlessNet');
            expect(body, startsWith('Your session'));
            return ClientNotificationDeliveryResult.permissionDenied;
          },
        ),
      );
      await tester.pumpAndSettle();
      final value = fixtures.snapshot();
      value.snapshot.status.activeProfileId = 'a';
      value.snapshot.status.mergeFromProto3Json({
        'session': {'state': 'SESSION_STATE_EXPIRING'},
      });
      connection.events.add(value);
      await tester.pumpAndSettle();
      expect(deliveries, 0);
      await tester.tap(find.byKey(const ValueKey('page-settings')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('client-ui-notifications'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(deliveries, 1);
      expect(
        find.text(
          'Notification permission denied. Review system notification settings.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('client-ui-notifications-retry')));
      await tester.pumpAndSettle();
      expect(deliveries, 2);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect((await tester.runAsync(journal.pending))!, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await session.close();
        await connection.events.close();
        await directory.delete(recursive: true);
      });
    },
  );
}
