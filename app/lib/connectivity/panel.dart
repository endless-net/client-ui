import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'controller.dart';

class ConnectivityPanel extends StatelessWidget {
  const ConnectivityPanel({
    super.key,
    required this.controller,
    this.reconnect,
  });
  final ConnectivityController controller;
  final Future<void> Function()? reconnect;

  String _state(ConnectivityController c, api.Status? s) {
    if (c.link == ConnectivityLink.mismatch) {
      return 'Соединение: несовместимый локальный клиент';
    }
    if (!c.fresh) return 'Соединение: фактическое состояние неизвестно';
    if (!c.supported) return 'Соединение: функция недоступна в этом клиенте';
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
    return switch (s?.connectionPhase) {
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTING =>
        'Соединение: подключение выполняется',
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTING =>
        'Соединение: отключение выполняется',
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTED =>
        s?.serviceState == api.ServiceState.SERVICE_STATE_CONNECTED
            ? 'Соединение: подключено'
            : 'Соединение: ограничено',
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED =>
        'Соединение: отключено',
      _ => 'Соединение: фактическое состояние неизвестно',
    };
  }

  String _reason(api.Failure f) {
    if (f.reasonKey == 'client.connection.registration_revoked') {
      return 'Регистрация устройства отозвана. Для возврата нужен новый авторизованный допуск; переподключение не восстанавливает прежнее право.';
    }
    if (f.reasonKey == 'client.connection.trust_required') {
      return 'Доверенная подпись сервера изменилась или не подтверждена. Проверьте сервер и подтвердите доверие отдельно; повтор подключения не подтверждает новую подпись.';
    }
    if (f.reasonKey == 'client.connection.credential_expired') {
      return 'Право устройства истекло или его срок неизвестен. Выполните авторизованное продление учётных данных устройства; вход в учётную запись не продлевает это право.';
    }
    if (f.reasonKey == 'client.connection.deadline') {
      return 'Попытка подключения или восстановления завершена: бюджет 30 секунд исчерпан. Проверьте сеть и разрешённый Direct-путь, затем повторите подключение.';
    }
    if (f.reasonKey == 'client.connection.cleanup_unconfirmed') {
      return 'Очистка сетевых ресурсов не подтверждена.';
    }
    if (f.reasonKey == 'client.connection.path_unconfirmed') {
      return 'Direct-путь до второго устройства не подтверждён.';
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
      final path =
          c.fresh &&
          s?.serviceState == api.ServiceState.SERVICE_STATE_CONNECTED &&
          (s?.agent.directPathCount ?? 0) > 0 &&
          !(s?.agent.connectionPaused ?? true);
      final failures = <api.Failure>[...?s?.failures, ?c.failure];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _state(c, s),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (c.busy) const LinearProgressIndicator(),
              Text(
                'Намерение${c.fresh ? '' : ' (последнее известное)'}: ${switch (s?.intent.desiredState) {
                  api.DesiredState.DESIRED_STATE_CONNECTED => 'подключить',
                  api.DesiredState.DESIRED_STATE_DISCONNECTED => 'отключить',
                  _ => 'неизвестно',
                }}',
              ),
              Text(
                'Локальное применение: ${applied
                    ? 'подтверждено'
                    : disconnected
                    ? 'отключено'
                    : 'неизвестно'}',
              ),
              Text('Direct-путь: ${path ? 'подтверждён' : 'не подтверждён'}'),
              if (c.fresh && applied)
                for (final address in s.overlayAddresses)
                  SelectableText('Адрес EndlessNet: $address'),
              if (c.fresh &&
                  s?.controlState ==
                      api.ControlState.CONTROL_STATE_OFFLINE_CACHE)
                const Text(
                  'Новые соединения запрещены. Существующие потоки ограничены исходным сроком разрешения.',
                ),
              if (c.fresh &&
                  s?.credential.state ==
                      api.CredentialState.CREDENTIAL_STATE_EXPIRED)
                const Text(
                  'Учётные данные устройства истекли. Требуется восстановить право доступа.',
                ),
              if (c.fresh &&
                  s?.session.state == api.SessionState.SESSION_STATE_EXPIRED)
                const Text(
                  'Сеанс пользователя истёк. Для действий учётной записи войдите снова; это не продлевает право устройства.',
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
                Text(_actor(failure.actionOwner)),
              ],
              if (c.supported &&
                  c.restriction?.availability !=
                      api.Availability.AVAILABILITY_AVAILABLE)
                const Text(
                  'Управление соединением недоступно текущему пользователю.',
                ),
              const Text(
                'Работа приложения второго устройства проверяется отдельно от сетевого пути.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: c.canConnect ? c.connect : null,
                    child: const Text('Подключить'),
                  ),
                  OutlinedButton(
                    onPressed: c.canDisconnect ? c.disconnect : null,
                    child: const Text('Отключить'),
                  ),
                  TextButton(
                    onPressed: c.busy ? null : c.refresh,
                    child: const Text('Обновить состояние'),
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
