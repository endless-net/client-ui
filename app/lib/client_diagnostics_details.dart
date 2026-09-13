import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_locale.dart';
import 'client_operation_labels.dart';

/// Explicit projection of inspection data. Never render the whole protobuf:
/// Status can contain browser actions. Failures use only typed code/retryability.
class ClientDiagnosticsDetails extends StatelessWidget {
  const ClientDiagnosticsDetails({
    super.key,
    required this.diagnostics,
    required this.locale,
  });
  final api.Diagnostics diagnostics;
  final ClientLocale locale;
  String _text(String en, String ru) => locale.text(en: en, ru: ru);
  String _bool(bool value) => value ? _text('Yes', 'Да') : _text('No', 'Нет');
  String _failure(api.Failure failure) =>
      failure.code == api.ErrorCode.ERROR_CODE_UNSPECIFIED
      ? _text('Not reported', 'Не сообщена')
      : clientFailureLabel(failure.code, locale: locale);
  Widget _section(String key, String title, List<List<String>> entries) =>
      ExpansionTile(
        key: Key(key),
        title: Text('$title: ${entries.length}'),
        children: [
          if (entries.isEmpty)
            Text(
              _text(
                'No entries in this snapshot.',
                'В этом снимке нет записей.',
              ),
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final line in entry) Text(line)],
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _section(
        'diagnostic-interfaces',
        _text('Interface details', 'Подробности интерфейсов'),
        [
          for (final item in diagnostics.interfaces)
            [
              '${_text('Name', 'Имя')}: ${item.name}',
              '${_text('Index', 'Индекс')}: ${item.index}; MTU: ${item.mtu}',
              '${_text('Addresses', 'Адреса')}: ${item.addresses.join(', ')}',
              '${_text('Prefixes', 'Префиксы')}: ${item.prefixes.join(', ')}',
              '${_text('Flags', 'Флаги')}: ${item.flags.join(', ')}',
              '${_text('Failure', 'Ошибка')}: ${_failure(item.failure)}',
            ],
        ],
      ),
      _section(
        'diagnostic-routes',
        _text('Route details', 'Подробности маршрутов'),
        [
          for (final item in diagnostics.routes)
            [
              '${_text('Target', 'Назначение')}: ${item.target}',
              '${_text('Interface', 'Интерфейс')}: ${item.interfaceName}',
              '${_text('Uses interface', 'Использует интерфейс')}: ${_bool(item.usesInterface)}',
              '${_text('Peer', 'Устройство')}: ${item.peerId}',
              '${_text('Failure', 'Ошибка')}: ${_failure(item.failure)}',
            ],
        ],
      ),
      _section(
        'diagnostic-conflicts',
        _text('Conflict details', 'Подробности конфликтов'),
        [
          for (final item in diagnostics.routeConflicts)
            [
              '${_text('Overlay CIDR', 'CIDR оверлея')}: ${item.overlayCidr}',
              '${_text('Local prefix', 'Локальный префикс')}: ${item.localPrefix}',
              '${_text('Interface', 'Интерфейс')}: ${item.interfaceName}',
              '${_text('Reason code', 'Код причины')}: ${item.reasonKey}',
            ],
        ],
      ),
      _section(
        'diagnostic-failures',
        _text('Failure details', 'Подробности ошибок'),
        [
          for (final item in diagnostics.failures)
            [
              _failure(item),
              '${_text('Retryable', 'Возможен повтор')}: ${_bool(item.retryable)}',
            ],
        ],
      ),
    ],
  );
}
