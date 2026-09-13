@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_notification_delivery.dart';
import 'package:endlessnet/client_notifications_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_notification_delivery_test.dart' as fixtures;

void main() {
  for (final locale in ClientLocale.values) {
    for (final outcome in ClientNotificationDeliveryResult.values) {
      testWidgets('explicit toggle and $outcome in $locale', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        var calls = 0;
        final delivery = ClientNotificationDelivery(
          state: state,
          locale: locale,
          enabled: false,
          deliver: (_, _) async {
            calls++;
            return outcome;
          },
        );
        Future<void> show(ClientLocale language, {bool supported = true}) =>
            tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: ClientNotificationsPanel(
                      delivery: delivery,
                      supported: supported,
                      locale: language,
                    ),
                  ),
                ),
              ),
            );
        await show(locale);
        stream.add(fixtures.snapshot(1));
        await tester.pumpAndSettle();
        expect(calls, 0);
        await tester.tap(find.byKey(const Key('client-ui-notifications')));
        await tester.pumpAndSettle();
        expect(
          calls,
          outcome == ClientNotificationDeliveryResult.delivered ? 2 : 1,
        );
        const en = [
          'Notification handed to the system. Display depends on system settings.',
          'Notification permission denied. Review system notification settings.',
          'System notifications are not supported by this application host.',
          'System notification delivery is temporarily unavailable.',
          'The notification could not be delivered.',
        ];
        const ru = [
          'Уведомление передано системе. Показ зависит от настроек системы.',
          'Нет разрешения на уведомления. Проверьте настройки уведомлений системы.',
          'Эта сборка приложения не поддерживает системные уведомления.',
          'Доставка системных уведомлений временно недоступна.',
          'Не удалось доставить уведомление.',
        ];
        expect(
          find.text((locale == ClientLocale.en ? en : ru)[outcome.index]),
          findsOneWidget,
        );
        final before = calls;
        await show(
          locale == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        );
        await tester.pumpAndSettle();
        expect(calls, before);
        expect(
          find.text((locale == ClientLocale.en ? ru : en)[outcome.index]),
          findsOneWidget,
        );
        if (outcome != ClientNotificationDeliveryResult.delivered) {
          await tester.tap(
            find.byKey(const Key('client-ui-notifications-retry')),
          );
          await tester.pumpAndSettle();
          expect(calls, before + 1);
        }
        await tester.tap(find.byKey(const Key('client-ui-notifications')));
        await tester.pumpAndSettle();
        expect(delivery.enabled, isFalse);
        expect(
          find.byKey(const Key('client-ui-notifications-retry')),
          findsNothing,
        );
        await show(locale, supported: false);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        delivery.dispose();
        await tester.runAsync(() async {
          await state.detach();
          await stream.close();
          state.dispose();
        });
      });
    }
  }
}
