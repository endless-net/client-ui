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
    this.openSettings,
  });
  final Future<ClientAutostartSetting> Function() read;
  final Future<ClientAutostartSetting> Function(bool) write;
  final ClientLocale locale;
  final bool enabled;
  final Future<bool> Function()? openSettings;
  @override
  State<ClientAutostartPanel> createState() => _AutostartState();
}

class _AutostartState extends State<ClientAutostartPanel> {
  bool _busy = false;
  bool _failed = false;
  bool _settingsFailed = false;
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
      _settingsFailed = false;
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

  Future<void> _openSettings() async {
    final open = widget.openSettings;
    if (!mounted ||
        _busy ||
        !widget.enabled ||
        open == null ||
        _setting != ClientAutostartSetting.requiresApproval) {
      return;
    }
    setState(() {
      _busy = true;
      _settingsFailed = false;
    });
    var opened = false;
    try {
      opened = await open();
    } catch (_) {
      /* Safe UI result below. */
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _settingsFailed = identical(open, widget.openSettings) && !opened;
    });
  }

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
                  ClientAutostartSetting.registered => text(
                    'User autostart entry registered. Windows startup permission is not checked; review it in Windows startup settings.',
                    'Запись автозапуска пользователя создана. Разрешение Windows не проверено; проверьте его в настройках автозагрузки Windows.',
                  ),
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
          if (_setting == ClientAutostartSetting.requiresApproval &&
              widget.openSettings != null)
            TextButton(
              key: const Key('ui-autostart-settings'),
              onPressed: _busy || !widget.enabled ? null : _openSettings,
              child: Text(
                text(
                  'Open Login Items settings',
                  'Открыть настройки объектов входа',
                ),
              ),
            ),
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
      if (_settingsFailed)
        Semantics(
          liveRegion: true,
          child: Text(
            text(
              'Could not request Login Items settings. Open them manually; then refresh the autostart status.',
              'Не удалось запросить открытие настроек объектов входа. Откройте их вручную, затем обновите состояние автозапуска.',
            ),
          ),
        ),
    ],
  );
}
