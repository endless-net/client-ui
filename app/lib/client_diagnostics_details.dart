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
  Widget _section(
    String key,
    String title,
    List<List<String>> entries, {
    String? emptyText,
  }) => ExpansionTile(
    key: Key(key),
    title: Text('$title: ${entries.length}'),
    children: [
      if (entries.isEmpty)
        Text(
          emptyText ??
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
        'diagnostic-tunnel',
        _text('Tunnel details', 'Подробности туннеля'),
        [
          if (diagnostics.hasTunnel())
            [
              '${_text('Inspection OK', 'Проверка успешна')}: ${_bool(diagnostics.tunnel.ok)}',
              '${_text('Interface', 'Интерфейс')}: ${diagnostics.tunnel.interfaceName}',
              'MTU: ${diagnostics.tunnel.mtu}',
              '${_text('Listen port', 'Порт прослушивания')}: ${diagnostics.tunnel.listenPort}',
              '${_text('Failure', 'Ошибка')}: ${_failure(diagnostics.tunnel.failure)}',
              '${_text('Tunnel peers', 'Устройства туннеля')}: ${diagnostics.tunnel.peers.length}',
              for (final peer in diagnostics.tunnel.peers) ...[
                '${_text('Peer', 'Устройство')}: ${peer.peerId}',
                '${_text('Public key', 'Публичный ключ')}: ${peer.publicKey}',
                '${_text('Endpoint', 'Адрес подключения')}: ${peer.endpoint}',
                '${_text('Allowed IPs', 'Разрешённые IP')}: ${peer.allowedIps.join(', ')}',
                '${_text('Latest handshake', 'Последнее рукопожатие')}: ${peer.hasLatestHandshake() ? peer.latestHandshake.toProto3Json() : _text('Not reported', 'Не сообщается')}',
                '${_text('Received bytes', 'Получено байт')}: ${peer.receivedBytes}',
                '${_text('Transmitted bytes', 'Отправлено байт')}: ${peer.transmittedBytes}',
                '${_text('Keepalive', 'Поддержание соединения')}: ${peer.hasPersistentKeepalive() ? peer.persistentKeepalive.toProto3Json() : _text('Not reported', 'Не сообщается')}',
              ],
            ],
        ],
        emptyText: _text(
          'Tunnel inspection not reported.',
          'Проверка туннеля не предоставлена.',
        ),
      ),
      _section(
        'diagnostic-dns',
        _text('DNS details', 'Подробности DNS'),
        [
          if (diagnostics.hasDns())
            [
              '${_text('Search domain', 'Поисковый домен')}: ${diagnostics.dns.searchDomain}',
              'TTL: ${diagnostics.dns.hasTtl() ? diagnostics.dns.ttl.toProto3Json() : _text('Not reported', 'Не сообщается')}',
              '${_text('Servers', 'Серверы')}: ${diagnostics.dns.servers.join(', ')}',
              '${_text('Records', 'Записи')}: ${diagnostics.dns.records.length}',
              for (final record in diagnostics.dns.records) ...[
                '${_text('Node', 'Узел')}: ${record.nodeId}',
                '${_text('Hostname', 'Имя хоста')}: ${record.hostname}',
                '${_text('Label', 'Метка')}: ${record.label}',
                'FQDN: ${record.fqdn}',
                '${_text('Addresses', 'Адреса')}: ${record.addresses.join(', ')}',
              ],
            ],
        ],
        emptyText: _text(
          'DNS inspection not reported.',
          'Проверка DNS не предоставлена.',
        ),
      ),
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
