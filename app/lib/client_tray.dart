import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'client_operation.dart';
import 'client_locale.dart';
import 'client_tray_labels.dart';
import 'client_state_controller.dart';

enum _TrayNotice { completed, failed, accepted, unknown }

/// Native snapshot projection. Menu keys expire on every state change so a
/// click queued by the OS cannot act on a newly selected profile or caller.
class ClientTray extends ChangeNotifier {
  ClientTray({
    required this.state,
    required this.connect,
    required this.disconnect,
    ClientLocale locale = ClientLocale.en,
  }) : _locale = locale {
    state.addListener(_stateChanged);
  }
  final ClientStateController state;
  final Future<ClientOperation> Function() connect;
  final Future<ClientOperation> Function() disconnect;
  int _generation = 0;
  bool _connecting = false;
  bool _disconnecting = false;
  bool _enabled = true;
  bool _disposed = false;
  ClientLocale _locale;
  ClientLocale get locale => _locale;
  set locale(ClientLocale value) {
    if (_disposed || value == _locale) return;
    _locale = value;
    _changed();
  }

  String _text(String en, String ru) => _locale.text(en: en, ru: ru);
  _TrayNotice? _notice;
  String? get notice => switch (_notice) {
    null => null,
    _TrayNotice.completed => _text(
      'Command completed. Check runtime status.',
      'Команда выполнена. Проверьте состояние службы.',
    ),
    _TrayNotice.failed => _text(
      'Command failed. Check the operation result.',
      'Команда завершилась ошибкой. Проверьте результат операции.',
    ),
    _TrayNotice.accepted => _text(
      'Command accepted. Completion is not yet confirmed.',
      'Команда принята. Завершение ещё не подтверждено.',
    ),
    _TrayNotice.unknown => _text(
      'Command result is unknown. Recover the original intention before retrying.',
      'Результат команды неизвестен. Восстановите исходное намерение перед повтором.',
    ),
  };

  void _stateChanged() {
    _notice = null;
    _changed();
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _generation++;
    notifyListeners();
  }

  bool get _owner {
    final snapshot = state.snapshot;
    return _enabled &&
        state.link == ClientLinkState.ready &&
        snapshot != null &&
        snapshot.status.activeProfileId.isNotEmpty &&
        [
          api.Access.ACCESS_OWNER,
          api.Access.ACCESS_ADMINISTRATOR,
        ].contains(snapshot.runtime.callerAccess);
  }

  bool get canConnect {
    final snapshot = state.snapshot;
    return _owner &&
        !_connecting &&
        !_disconnecting &&
        snapshot != null &&
        snapshot.supports(api.Capability.CAPABILITY_CONNECTION) &&
        snapshot.status.connectionPhase ==
            api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED &&
        !{
          api.ServiceState.SERVICE_STATE_NEEDS_ENROLLMENT,
          api.ServiceState.SERVICE_STATE_NEEDS_APPROVAL,
          api.ServiceState.SERVICE_STATE_NEEDS_LOGIN,
          api.ServiceState.SERVICE_STATE_SERVER_IDENTITY_CHANGED,
          api.ServiceState.SERVICE_STATE_RECOVERING,
          api.ServiceState.SERVICE_STATE_RECOVERY_BLOCKED,
          api.ServiceState.SERVICE_STATE_POLICY_BLOCKED,
        }.contains(snapshot.status.serviceState);
  }

  // Stopping remains available during connect/recovery; producer enforces policy.
  bool get canDisconnect => _owner && !_disconnecting;

  String get status =>
      state.link == ClientLinkState.ready && state.snapshot != null
      ? clientTrayServiceLabel(state.snapshot!.status.serviceState, _locale)
      : clientLinkLabel(state.link, _locale);

  Menu get menu => Menu(
    items: [
      MenuItem(
        key: 'open',
        label: _text('Open EndlessNet', 'Открыть EndlessNet'),
      ),
      MenuItem(
        label: _text('Runtime: $status', 'Служба: $status'),
        disabled: true,
      ),
      MenuItem(
        key: 'connect:$_generation',
        label: _text('Connect', 'Подключить'),
        disabled: !canConnect,
      ),
      MenuItem(
        key: 'disconnect:$_generation',
        label: _text('Disconnect', 'Отключить'),
        disabled: !canDisconnect,
      ),
      MenuItem(key: 'exit', label: _text('Quit', 'Выход'), disabled: !_enabled),
    ],
  );

  Future<void> activate(String? key) async {
    final isConnect = key == 'connect:$_generation';
    final isDisconnect = key == 'disconnect:$_generation';
    if (_disposed ||
        (!isConnect && !isDisconnect) ||
        (isConnect ? !canConnect : !canDisconnect)) {
      return;
    }
    final epoch = state.contextEpoch;
    if (isConnect) {
      _connecting = true;
    } else {
      _disconnecting = true;
    }
    _notice = null;
    _changed();
    try {
      final operation = await (isConnect ? connect() : disconnect());
      if (_disposed || state.contextEpoch != epoch) return;
      _notice = operation.succeeded
          ? _TrayNotice.completed
          : operation.terminal
          ? _TrayNotice.failed
          : _TrayNotice.accepted;
    } catch (_) {
      if (_disposed || state.contextEpoch != epoch) return;
      _notice = _TrayNotice.unknown;
    } finally {
      if (isConnect) {
        _connecting = false;
      } else {
        _disconnecting = false;
      }
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_stateChanged);
    super.dispose();
  }
}
