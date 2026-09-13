import 'dart:convert';
import 'package:flutter/services.dart';
import 'client_notification_delivery.dart';

const _channel = MethodChannel('endlessnet/ui-notifications');

/// Host channel carries only fixed presentation text. No runtime RPC or CLI.
Future<ClientNotificationDeliveryResult> deliverNativeClientNotification(
  String title,
  String body,
) async {
  if (title != 'EndlessNet' ||
      body.isEmpty ||
      body.contains('\u0000') ||
      utf8.encode(body).length > 2048) {
    return ClientNotificationDeliveryResult.failed;
  }
  try {
    final result = await _channel.invokeMethod<String>('deliver', {
      'title': title,
      'body': body,
    });
    return switch (result) {
      'delivered' => ClientNotificationDeliveryResult.delivered,
      'permissionDenied' => ClientNotificationDeliveryResult.permissionDenied,
      'unsupported' => ClientNotificationDeliveryResult.unsupported,
      'unavailable' => ClientNotificationDeliveryResult.unavailable,
      _ => ClientNotificationDeliveryResult.failed,
    };
  } on MissingPluginException {
    return ClientNotificationDeliveryResult.unsupported;
  } on PlatformException {
    return ClientNotificationDeliveryResult.unavailable;
  } catch (_) {
    return ClientNotificationDeliveryResult.failed;
  }
}
