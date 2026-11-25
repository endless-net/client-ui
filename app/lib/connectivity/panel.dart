import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:endlessnet_ui/endlessnet_ui.dart';

import 'controller.dart';

class ConnectivityPanel extends StatelessWidget {
  const ConnectivityPanel({
    super.key,
    required this.controller,
    this.reconnect,
    this.simple = false,
  });
  final ConnectivityController controller;
  final Future<void> Function()? reconnect;
  final bool simple;

  static String statusLabel(ConnectivityController c, api.Status? s) {
    if (c.link == ConnectivityLink.mismatch) {
      return 'Соединение: несовместимый локальный клиент';
    }
    if (!c.fresh) return 'Соединение: фактическое состояние неизвестно';
    if (!c.supported) return 'Соединение: функция недоступна в этом клиенте';
    if (c.loginRequired) return 'Соединение: требуется вход';
    if (c.retryScheduled) return 'Соединение: повтор подключения запланирован';
    if (s?.serviceState == api.ServiceState.SERVICE_STATE_POLICY_BLOCKED) {
      return 'Соединение: доступ заблокирован';
    }
    if (s?.serviceState == api.ServiceState.SERVICE_STATE_ERROR) {
      return 'Соединение: требуется устранить ошибку';
    }
    if (s?.controlState == api.ControlState.CONTROL_STATE_OFFLINE_CACHE) {
      return 'Соединение: сервер управления недоступен';
    }
    if (s?.serviceState == api.ServiceState.SERVICE_STATE_RECOVERING &&
        s?.connectionPhase == api.ConnectionPhase.CONNECTION_PHASE_CONNECTING) {
      return 'Соединение: подключение или восстановление выполняется';
    }
    final endpointUnconfirmed =
        s?.controlState == api.ControlState.CONTROL_STATE_DEGRADED &&
        (s?.failures.any(
              (f) =>
                  f.reasonKey ==
                  'client.connection.endpoint_refresh_unconfirmed',
            ) ??
            false);
    if (s?.serviceState == api.ServiceState.SERVICE_STATE_LOCAL_READY &&
        s?.connectionPhase ==
            api.ConnectionPhase.CONNECTION_PHASE_LOCAL_READY &&
        (s?.controlState == api.ControlState.CONTROL_STATE_READY ||
            endpointUnconfirmed) &&
        s?.peerCount == 0 &&
        (s?.mapRevision.toStringUnsigned() ?? '0') != '0' &&
        (s?.overlayAddresses.isNotEmpty ?? false) &&
        s?.agent.snapshotState ==
            api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT &&
        s?.agent.directPathCount == 0 &&
        s?.agent.relayPathCount == 0) {
      return 'Туннель готов';
    }
    return switch (s?.connectionPhase) {
      api.ConnectionPhase.CONNECTION_PHASE_UNSPECIFIED
          when s?.serviceState == api.ServiceState.SERVICE_STATE_RECOVERING =>
        'Соединение: служба восстанавливает состояние',
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTING =>
        'Соединение: подключение выполняется',
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTING =>
        'Соединение: отключение выполняется',
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTED =>
        s?.serviceState == api.ServiceState.SERVICE_STATE_CONNECTED &&
                (s?.controlState == api.ControlState.CONTROL_STATE_READY ||
                    endpointUnconfirmed)
            ? 'Туннель готов'
            : 'Соединение: ограничено',
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED =>
        'Соединение: отключено',
      _ => 'Соединение: фактическое состояние неизвестно',
    };
  }

  String _reason(api.Failure f) {
    if (f.reasonKey == 'client.connection.node_renewal_unresolved') {
      return 'Не подтверждён результат обновления доступа устройства. Вход пользователя не заменяет этот результат; требуется проверка владельцем сервиса.';
    }
    if (f.reasonKey == 'client.connection.registration_revoked') {
      return 'Регистрация устройства отозвана. Для возврата нужен новый авторизованный допуск; переподключение не восстанавливает прежнее право.';
    }
    if (f.reasonKey == 'client.connection.trust_required') {
      return 'Не удалось подтвердить подпись сервера. Проверьте адрес сервера и установленную версию EndlessNet; повтор подключения не принимает новый ключ.';
    }
    if (f.reasonKey == 'client.connection.checkpoint_unavailable') {
      return 'Не удалось прочитать или сохранить доверенную версию bootstrap на устройстве.';
    }
    if (f.reasonKey == 'client.connection.protocol_rejected') {
      return 'Сервер управления сообщил об ошибке протокола или конфигурации.';
    }
    if (f.reasonKey == 'client.connection.map_rejected') {
      return 'Карта сети отклонена при проверке.';
    }
    if (f.reasonKey == 'client.connection.configuration_invalid') {
      return 'Конфигурация подключения на устройстве некорректна.';
    }
    if (f.reasonKey == 'client.connection.endpoint_refresh_unconfirmed') {
      return 'Сервер не подтвердил обновление сетевого адреса устройства. Служба повторит запрос.';
    }
    if (f.reasonKey == 'client.connection.credential_rejected') {
      return 'Не удалось проверить учётные данные устройства.';
    }
    if (f.reasonKey == 'client.connection.credential_expired') {
      return 'Право устройства истекло или его срок неизвестен. Нажмите «Подключить»: служба проверит возможность продления для того же устройства. Если срок запроса истёк, повтор не гарантирует продление; требуется восстановить авторизованный вход.';
    }
    if (f.reasonKey == 'client.connection.login_required') {
      return 'Войдите снова, чтобы возобновить подключение. Регистрация устройства сохранена.';
    }
    if (f.reasonKey == 'client.connection.deadline') {
      return controller.retryScheduled
          ? 'Время предыдущей попытки истекло.'
          : 'Время подключения или восстановления истекло. Проверьте связь с сервером управления и повторите попытку.';
    }
    if (f.reasonKey == 'client.connection.cleanup_unconfirmed') {
      return 'Очистка сетевых ресурсов не подтверждена.';
    }
    if (f.reasonKey == 'client.connection.path_unconfirmed') {
      return 'Не удалось подтвердить сетевые параметры туннеля.';
    }
    if (f.reasonKey == 'client.connection.control_unavailable') {
      return 'Не удалось подтвердить результат через сервер управления.';
    }
    if (f.reasonKey == 'client.connection.discovery_unconfirmed') {
      return 'Локальное отключение завершено; уведомление сервера не подтверждено.';
    }
    if (f.reasonKey == 'client.connection.clock_unsafe') {
      return 'Безопасное время выполнения не подтверждено. Проверьте службу и часы устройства.';
    }
    return switch (f.code) {
      api.ErrorCode.ERROR_CODE_POLICY_BLOCKED => 'Разрешение отозвано, истекло или не подтверждено. Если регистрация отозвана, для возврата нужен новый авторизованный допуск. Повтор подключения не восстанавливает прежнее право.',
      api.ErrorCode.ERROR_CODE_PERMISSION_REQUIRED =>
        'Недостаточно локальных разрешений.',
      api.ErrorCode.ERROR_CODE_RESOURCE_CONFLICT =>
        'Обнаружен конфликт сетевых ресурсов.',
      api.ErrorCode.ERROR_CODE_APPLY_FAILED =>
        'Применение или очистка сетевых настроек не завершены.',
      api.ErrorCode.ERROR_CODE_DEADLINE_EXCEEDED =>
        'Время ожидания истекло. Проверьте текущее состояние.',
      api.ErrorCode.ERROR_CODE_STALE_STATE =>
        'Состояние изменилось. Показан результат повторного чтения.',
      api.ErrorCode.ERROR_CODE_OWNER_REQUIRED =>
        'Управление доступно владельцу локального клиента.',
      api.ErrorCode.ERROR_CODE_NEEDS_ENROLLMENT =>
        'Сначала зарегистрируйте устройство.',
      _ => 'Не удалось подтвердить результат. Обновите состояние.',
    };
  }

  String _actor(api.ActionOwner actor) => switch (actor) {
    api.ActionOwner.ACTION_OWNER_DEVICE_ADMINISTRATOR =>
      'Следующий шаг: обратитесь к администратору устройства.',
    api.ActionOwner.ACTION_OWNER_ACCESS_ADMINISTRATOR =>
      'Следующий шаг: обратитесь к администратору доступа.',
    api.ActionOwner.ACTION_OWNER_SUPPORT =>
      'Следующий шаг: обратитесь в поддержку.',
    _ => 'Следующий шаг: проверьте состояние перед повторной командой.',
  };

  Widget _transport(api.PeerTransportStatus peer, bool fresh) {
    // Render only the producer's public projection. Never echo raw diagnostics.
    final path = switch (peer.selectedPath) {
      api.PathKind.PATH_KIND_DIRECT => 'Direct',
      api.PathKind.PATH_KIND_RELAY => 'Relay',
      _ => null,
    };
    final engine = switch (peer.engine) {
      'wireguard' => 'WireGuard',
      'amneziawg' => 'AmneziaWG',
      _ => 'неизвестен',
    };
    final search = switch (peer.searchState) {
      api.TransportSearchState.TRANSPORT_SEARCH_STATE_SEARCHING =>
        'Поиск Direct выполняется',
      api.TransportSearchState.TRANSPORT_SEARCH_STATE_BACKOFF =>
        'Повторный поиск Direct запланирован',
      api.TransportSearchState.TRANSPORT_SEARCH_STATE_UNSUPPORTED =>
        'Для предложенного транспорта требуется обновление клиента',
      api.TransportSearchState.TRANSPORT_SEARCH_STATE_EXHAUSTED =>
        'Доступный Direct-вариант пока не найден',
      api.TransportSearchState.TRANSPORT_SEARCH_STATE_IDLE =>
        'Поиск Direct ожидает',
      _ => 'Состояние поиска Direct неизвестно',
    };
    // IDs/version strings are bounded labels, never interpreted configuration.
    String label(String value) =>
        RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(value)
        ? value
        : 'неизвестен';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Устройство: ${label(peer.peerId)}'),
        Text(
          fresh
              ? (path == null ? 'Нет подтверждённого пути' : 'Путь: $path')
              : (path == null
                    ? 'Состояние пути неизвестно'
                    : 'Последний известный путь: $path (не подтверждён)'),
        ),
        if (!simple) ...[
          Text('Транспорт: $engine; версия: ${label(peer.protocolVersion)}'),
          Text(
            'Профиль транспорта: ${label(peer.transportProfileId)}; ревизия: ${peer.transportProfileRevision.toStringUnsigned()}',
          ),
          Text(fresh ? search : 'Состояние поиска Direct устарело'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.hasDeviceContext) return const SizedBox.shrink();
      final s = c.snapshot;
      final applied =
          c.fresh &&
          s != null &&
          s.hasAgent() &&
          s.agent.mapRevision.toStringUnsigned() != '0';
      final disconnected =
          c.fresh &&
          s?.connectionPhase ==
              api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED;
      final failures = <api.Failure>[if (c.fresh) ...?s?.failures, ?c.failure]
          .where(
            (failure) =>
                failure.reasonKey != 'client.connection.retry_scheduled',
          );
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusLabel(c, s),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (c.busy) const LinearProgressIndicator(),
              if (!simple)
                Text(
                  'Намерение${c.fresh ? '' : ' (последнее известное)'}: ${switch (s?.intent.desiredState) {
                    api.DesiredState.DESIRED_STATE_CONNECTED => 'подключить',
                    api.DesiredState.DESIRED_STATE_DISCONNECTED => 'отключить',
                    _ => 'неизвестно',
                  }}',
                ),
              if (!simple)
                Text(
                  'Локальное применение: ${applied
                      ? 'подтверждено'
                      : disconnected
                      ? 'отключено'
                      : 'неизвестно'}',
                ),
              for (final peer
                  in s?.peerTransports ?? <api.PeerTransportStatus>[])
                _transport(peer, c.fresh),
              if (c.fresh && applied)
                for (final address in s.overlayAddresses)
                  SelectableText('Адрес EndlessNet: $address'),
              if (c.fresh &&
                  s?.controlState ==
                      api.ControlState.CONTROL_STATE_OFFLINE_CACHE)
                const Text(
                  'Новые соединения запрещены. Существующие потоки ограничены исходным сроком разрешения.',
                ),
              if (!simple &&
                  c.fresh &&
                  s?.credential.state ==
                      api.CredentialState.CREDENTIAL_STATE_EXPIRED)
                const Text(
                  'Учётные данные устройства истекли. Требуется восстановить право доступа.',
                ),
              if (!simple &&
                  c.fresh &&
                  s?.session.state == api.SessionState.SESSION_STATE_EXPIRED)
                const Text(
                  'Сеанс пользователя истёк. Для действий учётной записи войдите снова; это не продлевает право устройства.',
                ),
              if (c.link == ConnectivityLink.unavailable)
                Text(
                  c.readFailure?.problem == ConnectivityReadProblem.timeout
                      ? 'Истекло время чтения состояния локальной службы.'
                      : 'Не удалось прочитать состояние локальной службы.',
                ),
              if (c.uncertain)
                const Text(
                  'Ответ на команду не подтверждён. Фактическое состояние требует проверки.',
                ),
              if (reconnect != null &&
                  (c.link == ConnectivityLink.unavailable ||
                      c.link == ConnectivityLink.mismatch))
                TextButton(
                  onPressed: c.busy ? null : reconnect,
                  child: const Text('Переподключиться к локальному клиенту'),
                ),
              for (final failure in failures) ...[
                Text(_reason(failure)),
                if (!simple) Text(_actor(failure.actionOwner)),
              ],
              if (c.supported &&
                  c.restriction?.availability !=
                      api.Availability.AVAILABILITY_AVAILABLE)
                const Text(
                  'Управление соединением недоступно текущему пользователю.',
                ),
              if (!simple)
                const Text(
                  'Работа приложения второго устройства проверяется отдельно от сетевого пути.',
                ),
              Wrap(
                spacing: 8,
                children: [
                  EnButton(
                    enabled: c.canConnect,
                    onPressed: c.connect,
                    label: 'Подключить',
                  ),
                  EnButton(
                    kind: EnButtonKind.secondary,
                    enabled: c.canDisconnect,
                    onPressed: c.disconnect,
                    label: 'Отключить',
                  ),
                  EnButton(
                    kind: EnButtonKind.text,
                    enabled: !c.busy,
                    onPressed: c.refresh,
                    label: 'Обновить состояние',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
