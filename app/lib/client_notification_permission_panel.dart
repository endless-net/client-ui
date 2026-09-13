import 'package:flutter/material.dart';
import 'client_locale.dart';
import 'client_native_notifications.dart';

class ClientNotificationPermissionPanel extends StatefulWidget {
  const ClientNotificationPermissionPanel({
    super.key,
    required this.request,
    required this.locale,
    this.enabled = true,
  });
  final Future<ClientNotificationPermission> Function() request;
  final ClientLocale locale;
  final bool enabled;
  @override
  State<ClientNotificationPermissionPanel> createState() => _PermissionState();
}

class _PermissionState extends State<ClientNotificationPermissionPanel> {
  bool _busy = false;
  ClientNotificationPermission? _result;
  Future<void> _request() async {
    if (_busy || !mounted || !widget.enabled) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final request = widget.request;
    ClientNotificationPermission result;
    try {
      result = await request();
    } catch (_) {
      result = ClientNotificationPermission.unavailable;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = identical(request, widget.request) ? result : null;
    });
  }

  String text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextButton(
        key: const Key('client-ui-notification-permission'),
        onPressed: _busy || !widget.enabled ? null : _request,
        child: Text(
          text(
            'Request system notification permission',
            'Запросить разрешение системы на уведомления',
          ),
        ),
      ),
      if (_result != null)
        Semantics(
          liveRegion: true,
          child: Text(switch (_result!) {
            ClientNotificationPermission.granted => text(
              'Permission granted. Enable notifications or retry delivery explicitly.',
              'Разрешение получено. Включите уведомления или явно повторите доставку.',
            ),
            ClientNotificationPermission.denied => text(
              'Permission denied. Review system notification settings.',
              'В разрешении отказано. Проверьте настройки уведомлений системы.',
            ),
            ClientNotificationPermission.unsupported => text(
              'This host cannot request notification permission.',
              'Эта сборка не поддерживает запрос разрешения на уведомления.',
            ),
            ClientNotificationPermission.unavailable => text(
              'Notification permission request is unavailable.',
              'Запрос разрешения на уведомления недоступен.',
            ),
          }),
        ),
    ],
  );
}
