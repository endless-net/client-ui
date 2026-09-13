@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_native_notifications.dart';
import 'package:endlessnet/client_notification_permission_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final permission in ClientNotificationPermission.values) {
    test('explicit native permission $permission sends no payload', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'requestPermission');
        expect(call.arguments, isNull);
        return permission.name;
      });
      expect(await requestNativeClientNotificationPermission(), permission);
    });
  }
  test('missing or failed permission adapter never reports granted', () async {
    expect(
      await requestNativeClientNotificationPermission(),
      ClientNotificationPermission.unsupported,
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'private'),
    );
    expect(
      await requestNativeClientNotificationPermission(),
      ClientNotificationPermission.unavailable,
    );
    messenger.setMockMethodCallHandler(channel, (_) async => 'unexpected');
    expect(
      await requestNativeClientNotificationPermission(),
      ClientNotificationPermission.unavailable,
    );
  });
  for (final permission in ClientNotificationPermission.values) {
    testWidgets('permission $permission is explicit, single-flight and localized', (
      tester,
    ) async {
      var requests = 0;
      final reply = Completer<ClientNotificationPermission>();
      Future<ClientNotificationPermission> request() {
        requests++;
        return reply.future;
      }

      Future<void> show(ClientLocale locale, {bool enabled = true}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientNotificationPermissionPanel(
                  request: request,
                  locale: locale,
                  enabled: enabled,
                ),
              ),
            ),
          );
      await show(ClientLocale.en);
      expect(requests, 0);
      final button = find.byKey(const Key('client-ui-notification-permission'));
      final stale = tester.widget<TextButton>(button).onPressed!;
      await tester.tap(button);
      await tester.pump();
      stale();
      expect(requests, 1);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await show(ClientLocale.ru);
      reply.complete(permission);
      await tester.pumpAndSettle();
      const ru = [
        'Разрешение получено. Включите уведомления или явно повторите доставку.',
        'В разрешении отказано. Проверьте настройки уведомлений системы.',
        'Эта сборка не поддерживает запрос разрешения на уведомления.',
        'Запрос разрешения на уведомления недоступен.',
      ];
      expect(find.text(ru[permission.index]), findsOneWidget);
      await show(ClientLocale.en, enabled: false);
      const en = [
        'Permission granted. Enable notifications or retry delivery explicitly.',
        'Permission denied. Review system notification settings.',
        'This host cannot request notification permission.',
        'Notification permission request is unavailable.',
      ];
      expect(find.text(en[permission.index]), findsOneWidget);
      stale();
      expect(requests, 1);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('late permission reply after disposal is ignored', (
    tester,
  ) async {
    final reply = Completer<ClientNotificationPermission>();
    await tester.pumpWidget(
      MaterialApp(
        home: ClientNotificationPermissionPanel(
          request: () => reply.future,
          locale: ClientLocale.en,
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('client-ui-notification-permission')),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    reply.complete(ClientNotificationPermission.granted);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
