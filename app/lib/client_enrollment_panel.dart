import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_locale.dart';
import 'client_state_controller.dart';

typedef EnrollProfile =
    Future<ClientOperation> Function(
      String profileId,
      api.EnrollmentMode mode,
      String hostname,
      String? token,
    );

class ClientEnrollmentPanel extends StatelessWidget {
  const ClientEnrollmentPanel({
    super.key,
    required this.state,
    required this.enroll,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final EnrollProfile enroll;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final snapshot = state.snapshot;
      final enabled =
          state.link == ClientLinkState.ready &&
          snapshot != null &&
          snapshot.runtime.callerAccess != api.Access.ACCESS_OBSERVER &&
          snapshot.status.activeProfileId.isNotEmpty &&
          snapshot.supports(api.Capability.CAPABILITY_ENROLLMENT);
      return _EnrollmentForm(
        key: ValueKey((
          state,
          state.cacheEpoch,
          state.domainEpoch(api.Domain.DOMAIN_PROFILES),
          state.domainEpoch(api.Domain.DOMAIN_SESSION),
        )),
        locale: locale,
        isCurrent: () =>
            identical(state.snapshot, snapshot) &&
            state.link == ClientLinkState.ready,
        profileId: enabled ? snapshot.status.activeProfileId : '',
        enroll: enroll,
      );
    },
  );
}

class _EnrollmentForm extends StatefulWidget {
  const _EnrollmentForm({
    super.key,
    required this.profileId,
    required this.enroll,
    required this.locale,
    required this.isCurrent,
  });
  final ClientLocale locale;
  final bool Function() isCurrent;
  final String profileId;
  final EnrollProfile enroll;
  @override
  State<_EnrollmentForm> createState() => _EnrollmentFormState();
}

enum _EnrollmentNotice { accepted, result, unknown }

String enrollmentModeLabel(api.EnrollmentMode mode, ClientLocale locale) =>
    switch (mode) {
      api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION => locale.text(
        en: 'Workstation',
        ru: 'Рабочая станция',
      ),
      api.EnrollmentMode.ENROLLMENT_MODE_SERVER => locale.text(
        en: 'Server',
        ru: 'Сервер',
      ),
      api.EnrollmentMode.ENROLLMENT_MODE_SUBNET_ROUTER => locale.text(
        en: 'Subnet router',
        ru: 'Маршрутизатор подсети',
      ),
      api.EnrollmentMode.ENROLLMENT_MODE_INTERACTIVE => locale.text(
        en: 'Interactive',
        ru: 'Интерактивный',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указан'),
    };

class _EnrollmentFormState extends State<_EnrollmentForm> {
  final _hostname = TextEditingController();
  final _token = TextEditingController();
  var _mode = api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION;
  bool _useToken = false;
  bool _busy = false;
  _EnrollmentNotice? _notice;
  bool Function()? _noticeCurrent;
  int _inputSerial = 0;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _noticeText(_EnrollmentNotice notice) => switch (notice) {
    _EnrollmentNotice.result => _text(
      'Enrollment result received. Refresh runtime status.',
      'Получен результат регистрации. Обновите состояние клиента.',
    ),
    _EnrollmentNotice.accepted => _text(
      'Enrollment accepted. Recover the operation for required actions and its result.',
      'Регистрация принята. Восстановите операцию, чтобы узнать необходимые действия и результат.',
    ),
    _EnrollmentNotice.unknown => _text(
      'Enrollment could not be confirmed. Recover the intention before retrying.',
      'Не удалось подтвердить регистрацию. Восстановите исходное намерение перед повторной попыткой.',
    ),
  };
  bool get _enabled => mounted && widget.profileId.isNotEmpty && !_busy;

  Future<void> _submit() async {
    final isCurrent = widget.isCurrent;
    if (!_enabled ||
        !isCurrent() ||
        _hostname.text.trim().isEmpty ||
        (_useToken && _token.text.trim().isEmpty)) {
      return;
    }
    final token = _useToken ? _token.text.trim() : null;
    final hostname = _hostname.text.trim();
    setState(() {
      _busy = true;
      _notice = null;
      _noticeCurrent = isCurrent;
      _inputSerial++;
      _token.clear();
    });
    try {
      final operation = await widget.enroll(
        widget.profileId,
        _mode,
        hostname,
        token,
      );
      if (!mounted || !isCurrent()) return;
      setState(
        () => _notice = operation.terminal
            ? _EnrollmentNotice.result
            : _EnrollmentNotice.accepted,
      );
    } catch (_) {
      if (!mounted || !isCurrent()) return;
      setState(() => _notice = _EnrollmentNotice.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _hostname.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serial = _inputSerial;
    final isCurrent = widget.isCurrent;
    bool current() => mounted && isCurrent() && serial == _inputSerial;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _text(
            'Enroll the selected profile',
            'Зарегистрировать выбранный профиль',
          ),
        ),
        TextField(
          key: const Key('enroll-hostname'),
          controller: _hostname,
          enabled: _enabled,
          onChanged: (_) => setState(() {
            _inputSerial++;
          }),
          decoration: InputDecoration(
            labelText: _text('Device hostname', 'Имя устройства'),
          ),
        ),
        DropdownButton<api.EnrollmentMode>(
          itemHeight: null,
          isExpanded: true,
          key: const Key('enroll-mode'),
          value: _mode,
          items: [
            for (final mode in api.EnrollmentMode.values.where(
              (m) => m != api.EnrollmentMode.ENROLLMENT_MODE_UNSPECIFIED,
            ))
              DropdownMenuItem(
                value: mode,
                child: Text(enrollmentModeLabel(mode, widget.locale)),
              ),
          ],
          onChanged: _enabled
              ? (mode) {
                  if (!current() ||
                      mode == null ||
                      mode == api.EnrollmentMode.ENROLLMENT_MODE_UNSPECIFIED) {
                    return;
                  }
                  setState(() {
                    _mode = mode;
                    _inputSerial++;
                  });
                }
              : null,
        ),
        SwitchListTile(
          key: const Key('enroll-use-token'),
          title: Text(
            _text(
              'Use enrollment token instead of browser login',
              'Использовать токен регистрации вместо входа через браузер',
            ),
          ),
          value: _useToken,
          onChanged: _enabled
              ? (value) {
                  if (!current()) return;
                  setState(() {
                    _useToken = value;
                    _token.clear();
                    _inputSerial++;
                  });
                }
              : null,
        ),
        if (_useToken)
          TextField(
            key: const Key('enroll-token'),
            controller: _token,
            enabled: _enabled,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {
              _inputSerial++;
            }),
            decoration: InputDecoration(
              labelText: _text('Enrollment token', 'Токен регистрации'),
            ),
          ),
        OutlinedButton(
          key: const Key('enroll-submit'),
          onPressed:
              _enabled &&
                  _hostname.text.trim().isNotEmpty &&
                  (!_useToken || _token.text.trim().isNotEmpty)
              ? () {
                  if (current()) _submit();
                }
              : null,
          child: Text(_text('Enroll profile', 'Зарегистрировать профиль')),
        ),
        if (_notice != null && (_noticeCurrent?.call() ?? false))
          Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
      ],
    );
  }
}
