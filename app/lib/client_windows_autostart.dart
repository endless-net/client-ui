import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'client_locale.dart';

/// Fixed OS-owned settings destination, never derived from runtime data.
Future<bool> openWindowsClientAutostartSettings({
  Future<bool> Function(Uri)? launch,
}) => (launch ?? _launch)(Uri.parse('ms-settings:startupapps'));

Future<bool> _launch(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class ClientWindowsAutostartPanel extends StatefulWidget {
  const ClientWindowsAutostartPanel({
    super.key,
    required this.openSettings,
    required this.locale,
    this.enabled = true,
  });
  final Future<bool> Function() openSettings;
  final ClientLocale locale;
  final bool enabled;
  @override
  State<ClientWindowsAutostartPanel> createState() => _WindowsAutostartState();
}

class _WindowsAutostartState extends State<ClientWindowsAutostartPanel> {
  bool _busy = false;
  bool? _opened;
  Future<void> _open() async {
    if (!mounted || _busy || !widget.enabled) return;
    final open = widget.openSettings;
    setState(() {
      _busy = true;
      _opened = null;
    });
    bool opened;
    try {
      opened = await open();
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _opened = identical(open, widget.openSettings) ? opened : null;
    });
  }

  String text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text('Start UI at sign-in', 'Запускать интерфейс при входе')),
      Text(
        text(
          'After enabling UI autostart, manage EndlessNet in Windows Startup apps settings. Its current startup permission is not checked here. This does not change the runtime connection intent.',
          'После включения автозапуска интерфейса управляйте EndlessNet в настройках автозагрузки Windows. Текущее разрешение автозапуска здесь не проверяется. Это не меняет намерение подключения службы.',
        ),
      ),
      TextButton(
        key: const Key('ui-windows-autostart-settings'),
        onPressed: _busy || !widget.enabled ? null : _open,
        child: Text(
          text(
            'Open Windows startup settings',
            'Открыть настройки автозагрузки Windows',
          ),
        ),
      ),
      if (_opened != null)
        Semantics(
          liveRegion: true,
          child: Text(
            _opened!
                ? text(
                    'Settings launch requested. Review EndlessNet there; no startup change is confirmed by this app.',
                    'Запрошено открытие настроек. Проверьте там EndlessNet; приложение не подтверждает изменение автозапуска.',
                  )
                : text(
                    'Could not open startup settings. Open Windows Settings → Apps → Startup manually.',
                    'Не удалось открыть настройки автозагрузки. Откройте вручную Параметры Windows → Приложения → Автозагрузка.',
                  ),
          ),
        ),
    ],
  );
}
