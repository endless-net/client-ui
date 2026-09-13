@Tags(['short'])
library;

import 'package:endlessnet/client_native_notifications.dart';
import 'package:endlessnet/client_notification_delivery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final result in ClientNotificationDeliveryResult.values) {
    test('native result $result and exact text-only channel shape', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'deliver');
        expect(call.arguments, {
          'title': 'EndlessNet',
          'body': 'Срок сессии истекает.',
        });
        return result.name;
      });
      expect(
        await deliverNativeClientNotification(
          'EndlessNet',
          'Срок сессии истекает.',
        ),
        result,
      );
    });
  }
  test('missing host implementation is unsupported, never success', () async {
    expect(
      await deliverNativeClientNotification('EndlessNet', 'Notice'),
      ClientNotificationDeliveryResult.unsupported,
    );
  });
  test(
    'native error is unavailable without returning private details',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'private',
          message: 'private endpoint',
        ),
      );
      expect(
        await deliverNativeClientNotification('EndlessNet', 'Notice'),
        ClientNotificationDeliveryResult.unavailable,
      );
    },
  );
  for (final malformed in [null, 'unexpected', 7]) {
    test('malformed native response $malformed fails closed', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => malformed);
      expect(
        await deliverNativeClientNotification('EndlessNet', 'Notice'),
        ClientNotificationDeliveryResult.failed,
      );
    });
  }
  test(
    'invalid or oversized UTF8 payload never crosses native channel',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return 'delivered';
      });
      for (final payload in [
        ('', 'Notice'),
        ('Other', 'Notice'),
        ('EndlessNet', ''),
        ('EndlessNet', 'bad\u0000body'),
        ('EndlessNet', 'я' * 1025),
      ]) {
        expect(
          await deliverNativeClientNotification(payload.$1, payload.$2),
          ClientNotificationDeliveryResult.failed,
        );
      }
      expect(calls, 0);
    },
  );
}
