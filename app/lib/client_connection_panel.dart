import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_locale.dart';
import 'client_operation.dart';
import 'client_operation_labels.dart';
import 'client_runtime_snapshot.dart';
import 'client_state_controller.dart';

enum _ClientAction { connect, disconnect, renewSession }

/// Shared primary UI surface. Platform/application wiring supplies journaled
/// actions; this widget knows no HTTP DTO, desktop pipe or private state path.
class ClientConnectionPanel extends StatefulWidget {
  const ClientConnectionPanel({
    super.key,
    required this.state,
    required this.connect,
    required this.disconnect,
    required this.renewSession,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final Future<ClientOperation> Function() connect;
  final Future<ClientOperation> Function() disconnect;
  final Future<ClientOperation> Function() renewSession;

  @override
  State<ClientConnectionPanel> createState() => _ClientConnectionPanelState();
}

class _ClientConnectionPanelState extends State<ClientConnectionPanel> {
  final _pending = <_ClientAction>{};
  bool get _connecting => _pending.contains(_ClientAction.connect);
  bool get _disconnecting => _pending.contains(_ClientAction.disconnect);
  _ConnectionNotice? _notice;
  int? _noticeEpoch;
  Object _binding = Object();

  @override
  void didUpdateWidget(covariant ClientConnectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      _binding = Object();
      _pending.clear();
      _notice = null;
      _noticeEpoch = null;
    }
  }

  Future<void> _run(
    _ClientAction action,
    ClientRuntimeSnapshot? displayedSnapshot,
  ) async {
    // A queued pointer/keyboard activation belongs to the projection that
    // enabled the button, never to a replacement profile/caller or status.
    if (!mounted ||
        displayedSnapshot == null ||
        widget.state.link != ClientLinkState.ready ||
        !identical(widget.state.snapshot, displayedSnapshot) ||
        _pending.contains(action) ||
        (action == _ClientAction.connect && _disconnecting)) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    final binding = _binding;
    setState(() {
      _pending.add(action);
      _notice = null;
      _noticeEpoch = epoch;
    });
    try {
      final operation = await switch (action) {
        _ClientAction.connect => widget.connect(),
        _ClientAction.disconnect => widget.disconnect(),
        _ClientAction.renewSession => widget.renewSession(),
      };
      if (!mounted ||
          !identical(binding, _binding) ||
          widget.state.cacheEpoch != epoch) {
        return;
      }
      setState(() {
        _notice = operation.succeeded
            ? _ConnectionNotice.completed
            : operation.terminal
            ? _ConnectionNotice.failed
            : _ConnectionNotice.accepted;
      });
    } catch (_) {
      if (!mounted ||
          !identical(binding, _binding) ||
          widget.state.cacheEpoch != epoch) {
        return;
      }
      // Raw transport/exception text can contain credentials or private URLs.
      setState(() => _notice = _ConnectionNotice.unknown);
    } finally {
      if (mounted && identical(binding, _binding)) {
        setState(() {
          _pending.remove(action);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final snapshot = widget.state.snapshot;
      final ready =
          widget.state.link == ClientLinkState.ready && snapshot != null;
      final owner =
          ready && snapshot.runtime.callerAccess != api.Access.ACCESS_OBSERVER;
      final profile = ready && snapshot.status.activeProfileId.isNotEmpty;
      final blocked =
          ready &&
          {
            api.ServiceState.SERVICE_STATE_NEEDS_ENROLLMENT,
            api.ServiceState.SERVICE_STATE_NEEDS_APPROVAL,
            api.ServiceState.SERVICE_STATE_NEEDS_LOGIN,
            api.ServiceState.SERVICE_STATE_SERVER_IDENTITY_CHANGED,
            api.ServiceState.SERVICE_STATE_RECOVERING,
            api.ServiceState.SERVICE_STATE_RECOVERY_BLOCKED,
            api.ServiceState.SERVICE_STATE_POLICY_BLOCKED,
          }.contains(snapshot.status.serviceState);
      final canConnect =
          owner &&
          profile &&
          !blocked &&
          !_connecting &&
          !_disconnecting &&
          snapshot.supports(api.Capability.CAPABILITY_CONNECTION) &&
          snapshot.status.connectionPhase ==
              api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED;
      final canRenew =
          owner &&
          profile &&
          !_pending.contains(_ClientAction.renewSession) &&
          snapshot.supports(api.Capability.CAPABILITY_SESSION_RENEWAL) &&
          snapshot.status.session.renewal.availability ==
              api.Availability.AVAILABILITY_AVAILABLE &&
          snapshot.status.session.state !=
              api.SessionState.SESSION_STATE_RENEWING;
      final connectedColor = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF36DC8C)
          : const Color(0xFF087F46);
      final connected =
          ready &&
          !blocked &&
          snapshot.status.connectionPhase ==
              api.ConnectionPhase.CONNECTION_PHASE_CONNECTED;
      final showDisconnect =
          _connecting ||
          _disconnecting ||
          (ready &&
              {
                api.ConnectionPhase.CONNECTION_PHASE_CONNECTED,
                api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
                api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTING,
              }.contains(snapshot.status.connectionPhase));
      final actions = <Widget>[
        FilledButton(
          key: const Key('client-connect'),
          onPressed: canConnect
              ? () => _run(_ClientAction.connect, snapshot)
              : null,
          child: Text(widget.locale.text(en: 'Connect', ru: 'Подключить')),
        ),
        FilledButton(
          key: const Key('client-disconnect'),
          // Disconnect stays available during connect, blocked recovery
          // and stale intent. The producer owns authorization/policy.
          onPressed: owner && profile && !_disconnecting
              ? () => _run(_ClientAction.disconnect, snapshot)
              : null,
          child: Text(widget.locale.text(en: 'Disconnect', ru: 'Отключить')),
        ),
        OutlinedButton(
          key: const Key('client-renew-session'),
          onPressed: canRenew
              ? () => _run(_ClientAction.renewSession, snapshot)
              : null,
          child: Text(
            widget.locale.text(en: 'Renew session', ru: 'Продлить сессию'),
          ),
        ),
      ];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                connected ? Icons.check_circle : Icons.power_settings_new,
                color: connected
                    ? connectedColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 32,
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _statusLabel(widget.state),
                  key: const Key('client-runtime-state'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: connected
                        ? connectedColor
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (profile) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hub_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          snapshot.status.network.name.isNotEmpty
                              ? snapshot.status.network.name
                              : widget.locale.text(
                                  en: 'No network selected',
                                  ru: 'Сеть не выбрана',
                                ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_connecting)
                Text(widget.locale.text(en: 'Submitting…', ru: 'Отправка…')),
              SizedBox(
                width: double.infinity,
                child: actions[showDisconnect ? 1 : 0],
              ),
              ExpansionTile(
                key: const Key('client-session-actions'),
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  widget.locale.text(
                    en: 'Session actions',
                    ru: 'Действия с сессией',
                  ),
                ),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [actions[showDisconnect ? 0 : 1], actions[2]],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (ready && !owner)
                Text(
                  widget.locale.text(
                    en: 'An installation owner is required to control this device.',
                    ru: 'Для управления устройством требуется владелец установки.',
                  ),
                ),
              if (owner && profile) ...[
                if (snapshot.status.hasPendingAction())
                  Text(
                    widget.locale.text(
                      en: 'Required action: ${clientRequiredActionLabel(snapshot.status.pendingAction.kind, locale: widget.locale)}',
                      ru: 'Необходимое действие: ${clientRequiredActionLabel(snapshot.status.pendingAction.kind, locale: widget.locale)}',
                    ),
                    key: const Key('client-status-required-action'),
                  ),
                if (snapshot.status.recovery.hasFailure())
                  Text(
                    widget.locale.text(
                      en: 'Recovery: ${clientFailureLabel(snapshot.status.recovery.failure.code, locale: widget.locale)}. Action owner: ${clientActionOwnerLabel(snapshot.status.recovery.failure.actionOwner, locale: widget.locale)}.',
                      ru: 'Восстановление: ${clientFailureLabel(snapshot.status.recovery.failure.code, locale: widget.locale)}. Ответственный за действие: ${clientActionOwnerLabel(snapshot.status.recovery.failure.actionOwner, locale: widget.locale)}.',
                    ),
                    key: const Key('client-status-recovery-failure'),
                  ),
                for (final failure in snapshot.status.failures)
                  Text(
                    widget.locale.text(
                      en: 'Runtime issue: ${clientFailureLabel(failure.code, locale: widget.locale)}. Action owner: ${clientActionOwnerLabel(failure.actionOwner, locale: widget.locale)}.',
                      ru: 'Проблема службы: ${clientFailureLabel(failure.code, locale: widget.locale)}. Ответственный за действие: ${clientActionOwnerLabel(failure.actionOwner, locale: widget.locale)}.',
                    ),
                  ),
                ExpansionTile(
                  key: const Key('client-connection-details'),
                  maintainState: true,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(
                    widget.locale.text(
                      en: 'Connection details',
                      ru: 'Сведения о подключении',
                    ),
                  ),
                  children: [
                    Text(
                      widget.locale.text(
                        en: 'Profile: ${snapshot.status.activeProfileId}',
                        ru: 'Профиль: ${snapshot.status.activeProfileId}',
                      ),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Account: ${_contextValue(snapshot.status.accountId)}',
                        ru: 'Учётная запись: ${_contextValue(snapshot.status.accountId)}',
                      ),
                      key: const Key('client-context-account'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Network: ${_contextValue(snapshot.status.network.name)}',
                        ru: 'Сеть: ${_contextValue(snapshot.status.network.name)}',
                      ),
                      key: const Key('client-context-network'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Network ID: ${_contextValue(snapshot.status.network.id)}',
                        ru: 'Идентификатор сети: ${_contextValue(snapshot.status.network.id)}',
                      ),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Device: ${_contextValue(snapshot.status.hostname)}',
                        ru: 'Устройство: ${_contextValue(snapshot.status.hostname)}',
                      ),
                      key: const Key('client-context-device'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Device ID: ${_contextValue(snapshot.status.nodeId)}',
                        ru: 'Идентификатор устройства: ${_contextValue(snapshot.status.nodeId)}',
                      ),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Session state: ${_sessionState(snapshot.status.session.state)}',
                        ru: 'Состояние сессии: ${_sessionState(snapshot.status.session.state)}',
                      ),
                      key: const Key('client-session-state'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Session expiry: ${snapshot.status.session.hasExpiresAt() ? _deadline(snapshot.status.session.expiresAt.seconds.toInt(), snapshot.status.session.expiresAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                        ru: 'Срок сессии: ${snapshot.status.session.hasExpiresAt() ? _deadline(snapshot.status.session.expiresAt.seconds.toInt(), snapshot.status.session.expiresAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                      ),
                      key: const Key('client-session-expiry'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Session warning: ${snapshot.status.session.hasWarningAt() ? _deadline(snapshot.status.session.warningAt.seconds.toInt(), snapshot.status.session.warningAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                        ru: 'Предупреждение о сессии: ${snapshot.status.session.hasWarningAt() ? _deadline(snapshot.status.session.warningAt.seconds.toInt(), snapshot.status.session.warningAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                      ),
                      key: const Key('client-session-warning'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Session renewal: ${_renewalStatus(snapshot)}',
                        ru: 'Продление сессии: ${_renewalStatus(snapshot)}',
                      ),
                      key: const Key('client-session-renewal-status'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Credential state: ${_credentialState(snapshot.status.credential.state)}',
                        ru: 'Состояние учётных данных: ${_credentialState(snapshot.status.credential.state)}',
                      ),
                      key: const Key('client-credential-state'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Credential expiry: ${snapshot.status.credential.hasExpiresAt() ? _deadline(snapshot.status.credential.expiresAt.seconds.toInt(), snapshot.status.credential.expiresAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                        ru: 'Срок учётных данных: ${snapshot.status.credential.hasExpiresAt() ? _deadline(snapshot.status.credential.expiresAt.seconds.toInt(), snapshot.status.credential.expiresAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                      ),
                      key: const Key('client-credential-expiry'),
                    ),
                    Text(
                      widget.locale.text(
                        en: 'Credential warning: ${snapshot.status.credential.hasWarningAt() ? _deadline(snapshot.status.credential.warningAt.seconds.toInt(), snapshot.status.credential.warningAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                        ru: 'Предупреждение об учётных данных: ${snapshot.status.credential.hasWarningAt() ? _deadline(snapshot.status.credential.warningAt.seconds.toInt(), snapshot.status.credential.warningAt.nanos) : widget.locale.text(en: 'Unknown', ru: 'Неизвестно')}',
                      ),
                      key: const Key('client-credential-warning'),
                    ),
                  ],
                ),
              ],
              if (_notice != null &&
                  ready &&
                  _noticeEpoch == widget.state.cacheEpoch)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    key: const Key('client-command-announcement'),
                    container: true,
                    liveRegion: true,
                    child: Text(_notice!.label(widget.locale)),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  String _contextValue(String value) => value.isEmpty
      ? widget.locale.text(en: 'Unknown', ru: 'Неизвестно')
      : value;

  String _renewalStatus(ClientRuntimeSnapshot snapshot) {
    if (!snapshot.supports(api.Capability.CAPABILITY_SESSION_RENEWAL)) {
      return widget.locale.text(
        en: 'Unavailable on this runtime',
        ru: 'Недоступно в этой службе',
      );
    }
    if (snapshot.status.session.state ==
        api.SessionState.SESSION_STATE_RENEWING) {
      return widget.locale.text(en: 'In progress', ru: 'Выполняется');
    }
    return switch (snapshot.status.session.renewal.availability) {
      api.Availability.AVAILABILITY_AVAILABLE => widget.locale.text(
        en: 'Available — choose Renew session',
        ru: 'Доступно — выберите «Продлить сессию»',
      ),
      api.Availability.AVAILABILITY_UNSUPPORTED => widget.locale.text(
        en: 'Not supported',
        ru: 'Не поддерживается',
      ),
      api.Availability.AVAILABILITY_POLICY_BLOCKED => widget.locale.text(
        en: 'Blocked by policy',
        ru: 'Заблокировано политикой',
      ),
      api.Availability.AVAILABILITY_PERMISSION_REQUIRED => widget.locale.text(
        en: 'Permission required',
        ru: 'Требуется разрешение',
      ),
      api.Availability.AVAILABILITY_TEMPORARILY_UNAVAILABLE =>
        widget.locale.text(
          en: 'Temporarily unavailable',
          ru: 'Временно недоступно',
        ),
      _ => widget.locale.text(en: 'Unknown', ru: 'Неизвестно'),
    };
  }

  String _sessionState(api.SessionState state) => switch (state) {
    api.SessionState.SESSION_STATE_NOT_AUTHENTICATED => widget.locale.text(
      en: 'Not authenticated',
      ru: 'Не выполнен вход',
    ),
    api.SessionState.SESSION_STATE_ACTIVE => widget.locale.text(
      en: 'Active',
      ru: 'Активна',
    ),
    api.SessionState.SESSION_STATE_EXPIRING => widget.locale.text(
      en: 'Expiring',
      ru: 'Истекает',
    ),
    api.SessionState.SESSION_STATE_EXPIRED => widget.locale.text(
      en: 'Expired',
      ru: 'Срок истёк',
    ),
    api.SessionState.SESSION_STATE_RENEWING => widget.locale.text(
      en: 'Renewing',
      ru: 'Продлевается',
    ),
    _ => widget.locale.text(en: 'Unknown', ru: 'Неизвестно'),
  };

  String _credentialState(api.CredentialState state) => switch (state) {
    api.CredentialState.CREDENTIAL_STATE_ABSENT => widget.locale.text(
      en: 'Absent',
      ru: 'Отсутствуют',
    ),
    api.CredentialState.CREDENTIAL_STATE_VALID => widget.locale.text(
      en: 'Valid',
      ru: 'Действительны',
    ),
    api.CredentialState.CREDENTIAL_STATE_EXPIRING => widget.locale.text(
      en: 'Expiring',
      ru: 'Истекает',
    ),
    api.CredentialState.CREDENTIAL_STATE_EXPIRED => widget.locale.text(
      en: 'Expired',
      ru: 'Срок истёк',
    ),
    api.CredentialState.CREDENTIAL_STATE_RENEWING => widget.locale.text(
      en: 'Renewing',
      ru: 'Продлевается',
    ),
    api.CredentialState.CREDENTIAL_STATE_BLOCKED => widget.locale.text(
      en: 'Blocked',
      ru: 'Заблокированы',
    ),
    _ => widget.locale.text(en: 'Unknown', ru: 'Неизвестно'),
  };

  // Display authoritative UTC deadlines independently. Never infer runtime state
  // from the UI clock or substitute one deadline for the other.
  String _deadline(int seconds, int nanos) {
    if (seconds < -62135596800 ||
        seconds > 253402300799 ||
        nanos < 0 ||
        nanos > 999999999) {
      return widget.locale.text(en: 'Unknown', ru: 'Неизвестно');
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      seconds * 1000000 + nanos ~/ 1000,
      isUtc: true,
    ).toIso8601String();
  }

  String _statusLabel(ClientStateController state) {
    if (state.invalidContract) {
      return widget.locale.text(
        en: 'Incompatible runtime. Repair or update the application.',
        ru: 'Несовместимая служба. Восстановите или обновите приложение.',
      );
    }
    final snapshot = state.snapshot;
    if (snapshot == null) {
      return state.link == ClientLinkState.awaitingSnapshot
          ? widget.locale.text(
              en: 'Waiting for runtime snapshot…',
              ru: 'Ожидание снимка состояния службы…',
            )
          : widget.locale.text(
              en: 'Runtime unavailable',
              ru: 'Служба недоступна',
            );
    }
    switch (snapshot.status.serviceState) {
      case api.ServiceState.SERVICE_STATE_NEEDS_ENROLLMENT:
        return widget.locale.text(
          en: 'Device enrollment required',
          ru: 'Требуется регистрация устройства',
        );
      case api.ServiceState.SERVICE_STATE_NEEDS_APPROVAL:
        return widget.locale.text(
          en: 'Waiting for approval',
          ru: 'Ожидание одобрения',
        );
      case api.ServiceState.SERVICE_STATE_NEEDS_LOGIN:
        return widget.locale.text(en: 'Login required', ru: 'Требуется вход');
      case api.ServiceState.SERVICE_STATE_SERVER_IDENTITY_CHANGED:
        return widget.locale.text(
          en: 'Server identity changed',
          ru: 'Идентичность сервера изменилась',
        );
      case api.ServiceState.SERVICE_STATE_RECOVERING:
        return widget.locale.text(en: 'Recovering', ru: 'Восстановление');
      case api.ServiceState.SERVICE_STATE_RECOVERY_BLOCKED:
        return widget.locale.text(
          en: 'Recovery blocked',
          ru: 'Восстановление заблокировано',
        );
      case api.ServiceState.SERVICE_STATE_POLICY_BLOCKED:
        return widget.locale.text(
          en: 'Blocked by policy',
          ru: 'Заблокировано политикой',
        );
      case api.ServiceState.SERVICE_STATE_ERROR:
        return widget.locale.text(en: 'Runtime error', ru: 'Ошибка службы');
      case api.ServiceState.SERVICE_STATE_DEGRADED:
        return snapshot.status.connectionPhase ==
                api.ConnectionPhase.CONNECTION_PHASE_CONNECTING
            ? widget.locale.text(en: 'Connecting', ru: 'Подключение')
            : widget.locale.text(en: 'Degraded', ru: 'Работа с ограничениями');
      default:
        break;
    }
    return switch (snapshot.status.connectionPhase) {
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTING => widget.locale.text(
        en: 'Connecting',
        ru: 'Подключение',
      ),
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTING => widget.locale.text(
        en: 'Disconnecting',
        ru: 'Отключение',
      ),
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTED => widget.locale.text(
        en: 'Connected',
        ru: 'Подключено',
      ),
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED => widget.locale.text(
        en: 'Disconnected',
        ru: 'Отключено',
      ),
      _ => widget.locale.text(
        en: 'Runtime state unknown',
        ru: 'Состояние службы неизвестно',
      ),
    };
  }
}

enum _ConnectionNotice {
  completed,
  failed,
  accepted,
  unknown;

  String label(ClientLocale locale) => switch (this) {
    _ConnectionNotice.completed => locale.text(
      en: 'Command completed. Runtime status is shown above.',
      ru: 'Команда завершена. Состояние службы показано выше.',
    ),
    _ConnectionNotice.failed => locale.text(
      en: 'Command did not complete successfully. Check runtime status.',
      ru: 'Команда не завершилась успешно. Проверьте состояние службы.',
    ),
    _ConnectionNotice.accepted => locale.text(
      en: 'Command accepted. Waiting for the runtime result.',
      ru: 'Команда принята. Ожидается результат службы.',
    ),
    _ConnectionNotice.unknown => locale.text(
      en: 'Command result is unknown. Recover the original operation before retrying.',
      ru: 'Результат команды неизвестен. Восстановите исходную операцию перед повтором.',
    ),
  };
}
