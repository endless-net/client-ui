import 'dart:async';
import 'package:flutter/material.dart';
import 'client_autostart_setting.dart';
import 'client_locale.dart';

class ClientAutostartPanel extends StatefulWidget {
  const ClientAutostartPanel({
    super.key,
    required this.read,
    required this.write,
    required this.locale,
    this.enabled = true,
  });
  final Future<ClientAutostartSetting> Function() read;
  final Future<ClientAutostartSetting> Function(bool) write;
  final ClientLocale locale;
  final bool enabled;
  @override
  State<ClientAutostartPanel> createState() => _AutostartState();
}

class _AutostartState extends State<ClientAutostartPanel> {
  bool _busy = false;
  bool _failed = false;
  ClientAutostartSetting? _setting;
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run([bool? value]) async {
    if (!mounted ||
        _busy ||
        (!widget.enabled && value != null) ||
        ((_failed || _setting == ClientAutostartSetting.unsupported) &&
            value != null)) {
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = value == null
          ? await widget.read()
          : await widget.write(value);
      if (mounted) setState(() => _setting = result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _setting = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text('Start UI at sign-in', 'Запускать интерфейс при входе')),
      Text(
        text(
          'Controls this user’s desktop entry only. Does not change the runtime connection intent or system policy.',
          'Управляет только записью текущего пользователя. Не меняет намерение подключения службы или системную политику.',
        ),
      ),
      Semantics(
        liveRegion: true,
        child: Text(
          _failed
              ? text(
                  'Autostart could not be read or changed. An unrecognized entry is never overwritten.',
                  'Не удалось прочитать или изменить автозапуск. Неизвестная запись не перезаписывается.',
                )
              : switch (_setting) {
                  ClientAutostartSetting.enabled => text(
                    'User autostart entry enabled.',
                    'Автозапуск пользователя включён.',
                  ),
                  ClientAutostartSetting.disabled => text(
                    'User autostart entry disabled.',
                    'Автозапуск пользователя выключен.',
                  ),
                  ClientAutostartSetting.notConfigured => text(
                    'No user autostart entry. System-wide policy is not evaluated.',
                    'Пользовательская запись отсутствует. Системная политика не проверялась.',
                  ),
                  ClientAutostartSetting.requiresApproval => text(
                    'Autostart requires your approval in system Login Items settings.',
                    'Для автозапуска требуется ваше одобрение в системных настройках объектов входа.',
                  ),
                  ClientAutostartSetting.unsupported => text(
                    'UI autostart is not supported on this operating system version.',
                    'Эта версия операционной системы не поддерживает автозапуск интерфейса.',
                  ),
                  null => text('Reading autostart…', 'Чтение автозапуска…'),
                },
        ),
      ),
      Wrap(
        children: [
          TextButton(
            key: const Key('ui-autostart-read'),
            onPressed: _busy || !widget.enabled ? null : () => _run(),
            child: Text(text('Refresh', 'Обновить')),
          ),
          TextButton(
            key: const Key('ui-autostart-enable'),
            onPressed:
                _busy ||
                    !widget.enabled ||
                    _failed ||
                    _setting == ClientAutostartSetting.unsupported
                ? null
                : () => _run(true),
            child: Text(text('Enable', 'Включить')),
          ),
          TextButton(
            key: const Key('ui-autostart-disable'),
            onPressed:
                _busy ||
                    !widget.enabled ||
                    _failed ||
                    _setting == ClientAutostartSetting.unsupported
                ? null
                : () => _run(false),
            child: Text(text('Disable', 'Выключить')),
          ),
        ],
      ),
    ],
  );
}
