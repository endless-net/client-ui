@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_notification_delivery.dart';
import 'package:endlessnet/client_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
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
