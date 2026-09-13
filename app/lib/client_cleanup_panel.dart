import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_locale.dart';
import 'client_state_controller.dart';

class ClientCleanupPanel extends StatefulWidget {
  const ClientCleanupPanel({
    super.key,
    required this.state,
    required this.logout,
    required this.forget,
    this.canElevate = false,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final Future<ClientOperation> Function(String profileId) logout;
  final Future<ClientOperation> Function(String profileId) forget;
  final bool canElevate;
  @override
  State<ClientCleanupPanel> createState() => _ClientCleanupPanelState();
}

enum _CleanupNotice { accepted, result, unknown }

class _ClientCleanupPanelState extends State<ClientCleanupPanel> {
  bool? _forget;
  bool Function()? _contextCurrent;
  int _confirmationSerial = 0;
  bool _busy = false;
  _CleanupNotice? _notice;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _noticeText(_CleanupNotice notice) => switch (notice) {
    _CleanupNotice.result => _text(
      'Cleanup result received. Recover it to inspect remote and local outcomes.',
      'Получен результат очистки. Восстановите его, чтобы проверить результат на сервере и локально.',
    ),
    _CleanupNotice.accepted => _text(
      'Cleanup accepted. Recover the operation; removal is not yet confirmed.',
      'Очистка принята. Восстановите операцию; удаление ещё не подтверждено.',
    ),
    _CleanupNotice.unknown => _text(
      'Cleanup could not be confirmed. Recover the intention. No other cleanup command was sent.',
      'Не удалось подтвердить очистку. Восстановите исходное намерение. Другая команда очистки не отправлялась.',
    ),
  };

  bool _allowed(bool forget) {
    final snapshot = widget.state.snapshot;
    return mounted &&
        !_busy &&
        widget.state.link == ClientLinkState.ready &&
        snapshot != null &&
        snapshot.status.activeProfileId.isNotEmpty &&
        (forget
            ? (snapshot.runtime.callerAccess ==
                      api.Access.ACCESS_ADMINISTRATOR ||
                  (snapshot.runtime.callerAccess == api.Access.ACCESS_OWNER &&
                      widget.canElevate))
            : snapshot.runtime.callerAccess != api.Access.ACCESS_OBSERVER) &&
        snapshot.supports(
          forget
              ? api.Capability.CAPABILITY_LOCAL_FORGET
              : api.Capability.CAPABILITY_LOGOUT,
        );
  }

  void _confirm(bool forget, bool Function() contextCurrent) {
    if (!_allowed(forget) || !contextCurrent()) return;
    setState(() {
      _forget = forget;
      _contextCurrent = contextCurrent;
      _confirmationSerial++;
      _notice = null;
    });
  }

  Future<void> _submit() async {
    final forget = _forget;
    final contextCurrent = _contextCurrent;
    if (forget == null ||
        contextCurrent == null ||
        !contextCurrent() ||
        !_allowed(forget)) {
      return;
    }
    final profileId = widget.state.snapshot!.status.activeProfileId;
    setState(() {
      _busy = true;
      _forget = null;
      _confirmationSerial++;
    });
    try {
      final operation = await (forget
          ? widget.forget(profileId)
          : widget.logout(profileId));
      if (!mounted || !contextCurrent()) return;
      setState(
        () => _notice = operation.terminal
            ? _CleanupNotice.result
            : _CleanupNotice.accepted,
      );
    } catch (_) {
      if (!mounted || !contextCurrent()) return;
      setState(() => _notice = _CleanupNotice.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final current = _contextCurrent?.call() ?? false;
      final state = widget.state;
      final snapshot = state.snapshot;
      final epoch = state.cacheEpoch;
      final profiles = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
      final session = state.domainEpoch(api.Domain.DOMAIN_SESSION);
      final serial = _confirmationSerial;
      bool contextCurrent() =>
          mounted &&
          identical(widget.state, state) &&
          identical(state.snapshot, snapshot) &&
          state.cacheEpoch == epoch &&
          state.domainEpoch(api.Domain.DOMAIN_PROFILES) == profiles &&
          state.domainEpoch(api.Domain.DOMAIN_SESSION) == session;
      bool actionCurrent() => contextCurrent() && serial == _confirmationSerial;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            children: [
              OutlinedButton(
                key: const Key('client-logout'),
                onPressed: _allowed(false)
                    ? () {
                        if (actionCurrent()) _confirm(false, contextCurrent);
                      }
                    : null,
                child: Text(_text('Log out', 'Выйти')),
              ),
              OutlinedButton(
                key: const Key('client-local-forget'),
                onPressed: _allowed(true)
                    ? () {
                        if (actionCurrent()) _confirm(true, contextCurrent);
                      }
                    : null,
                child: Text(
                  _text(
                    'Forget local enrollment',
                    'Удалить локальную регистрацию',
                  ),
                ),
              ),
            ],
          ),
          if (current && _forget != null) ...[
            if (_forget! &&
                widget.canElevate &&
                widget.state.snapshot!.runtime.callerAccess ==
                    api.Access.ACCESS_OWNER)
              Text(
                _text(
                  'Confirmation will open the system administrator approval prompt.',
                  'Подтверждение откроет системный запрос одобрения администратора.',
                ),
              ),
            Text(
              _forget!
                  ? _text(
                      'Remove local registration without confirmed remote cleanup? Remote registration may remain. Installation ownership is retained.',
                      'Удалить локальную регистрацию без подтверждённой очистки на сервере? Регистрация на сервере может сохраниться. Владелец установки не изменится.',
                    )
                  : _text(
                      'Log out the selected profile? Remote cleanup must be confirmed before local registration is removed.',
                      'Выйти из выбранного профиля? Очистка на сервере должна быть подтверждена до удаления локальной регистрации.',
                    ),
            ),
            Wrap(
              children: [
                TextButton(
                  key: const Key('cancel-client-cleanup'),
                  onPressed: () {
                    if (actionCurrent()) {
                      setState(() {
                        _forget = null;
                        _confirmationSerial++;
                      });
                    }
                  },
                  child: Text(_text('Cancel', 'Отмена')),
                ),
                TextButton(
                  key: const Key('confirm-client-cleanup'),
                  onPressed: _allowed(_forget!)
                      ? () {
                          if (actionCurrent()) _submit();
                        }
                      : null,
                  child: Text(_text('Confirm', 'Подтвердить')),
                ),
              ],
            ),
          ],
          if (current && _notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
        ],
      );
    },
  );
}
