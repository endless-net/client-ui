import 'package:flutter/material.dart';
import 'client_locale.dart';
import 'client_notification_delivery.dart';

class ClientNotificationsPanel extends StatelessWidget {
  const ClientNotificationsPanel({
    super.key,
    required this.delivery,
    required this.supported,
    required this.locale,
    this.busy = false,
  });
  final ClientNotificationDelivery delivery;
  final bool supported;
  final ClientLocale locale;
  final bool busy;

  String text(String en, String ru) => locale.text(en: en, ru: ru);

  String resultText(
    ClientNotificationDeliveryResult result,
  ) => switch (result) {
    ClientNotificationDeliveryResult.delivered => text(
      'Notification handed to the system. Display depends on system settings.',
      'Уведомление передано системе. Показ зависит от настроек системы.',
    ),
    ClientNotificationDeliveryResult.permissionDenied => text(
      'Notification permission denied. Review system notification settings.',
      'Нет разрешения на уведомления. Проверьте настройки уведомлений системы.',
    ),
    ClientNotificationDeliveryResult.unsupported => text(
      'System notifications are not supported by this application host.',
      'Эта сборка приложения не поддерживает системные уведомления.',
    ),
    ClientNotificationDeliveryResult.unavailable => text(
      'System notification delivery is temporarily unavailable.',
      'Доставка системных уведомлений временно недоступна.',
    ),
    ClientNotificationDeliveryResult.failed => text(
      'The notification could not be delivered.',
      'Не удалось доставить уведомление.',
    ),
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: delivery,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const Key('client-ui-notifications'),
          title: Text(text('Deadline notifications', 'Уведомления о сроках')),
          subtitle: Text(
            text(
              'Session and device credential warnings. This choice applies to this run only.',
              'Предупреждения о сроках сессии и учётных данных устройства. Выбор действует только в этом запуске.',
            ),
          ),
          value: delivery.enabled,
          onChanged: !supported || busy
              ? null
              : (value) {
                  if (!busy) delivery.enabled = value;
                },
        ),
        if (!supported || delivery.result != null)
          Semantics(
            liveRegion: true,
            child: Text(
              resultText(
                !supported
                    ? ClientNotificationDeliveryResult.unsupported
                    : delivery.result!,
              ),
            ),
          ),
        if (supported &&
            delivery.enabled &&
            delivery.result != null &&
            delivery.result != ClientNotificationDeliveryResult.delivered)
          TextButton(
            key: const Key('client-ui-notifications-retry'),
            onPressed: busy ? null : delivery.retry,
            child: Text(
              text(
                'Retry notification delivery',
                'Повторить доставку уведомлений',
              ),
            ),
          ),
      ],
    ),
  );
}
