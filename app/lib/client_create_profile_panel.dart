import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_operation.dart';
import 'client_locale.dart';
import 'client_state_controller.dart';

/// Initial ownership is checked atomically by the producer, never inferred
/// from an observer's deliberately redacted snapshot.
class ClientCreateProfilePanel extends StatelessWidget {
  const ClientCreateProfilePanel({
    super.key,
    required this.state,
    required this.create,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final Future<ClientOperation> Function(String name, String origin) create;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final snapshot = state.snapshot;
      final epoch = state.cacheEpoch;
      final profilesEpoch = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
      return _CreateProfileForm(
        key: ValueKey((state, epoch)),
        enabled: state.link == ClientLinkState.ready && snapshot != null,
        isCurrent: () =>
            state.link == ClientLinkState.ready &&
            identical(state.snapshot, snapshot) &&
            state.cacheEpoch == epoch &&
            state.domainEpoch(api.Domain.DOMAIN_PROFILES) == profilesEpoch,
        locale: locale,
        create: create,
      );
    },
  );
}

class _CreateProfileForm extends StatefulWidget {
  const _CreateProfileForm({
    super.key,
    required this.enabled,
    required this.create,
    required this.isCurrent,
    required this.locale,
  });
  final bool Function() isCurrent;
  final ClientLocale locale;
  final bool enabled;
  final Future<ClientOperation> Function(String name, String origin) create;
  @override
  State<_CreateProfileForm> createState() => _CreateProfileFormState();
}

enum _CreateNotice { accepted, result, unknown }

class _CreateProfileFormState extends State<_CreateProfileForm> {
  final _name = TextEditingController();
  final _origin = TextEditingController();
  bool _busy = false;
  _CreateNotice? _notice;
  bool Function()? _noticeCurrent;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _noticeText(_CreateNotice notice) => switch (notice) {
    _CreateNotice.accepted => _text(
      'Creation accepted. Recover the operation to see its result.',
      'Создание профиля принято. Восстановите операцию, чтобы узнать результат.',
    ),
    _CreateNotice.result => _text(
      'Creation result received. Refresh profiles and runtime status.',
      'Получен результат создания профиля. Обновите профили и состояние клиента.',
    ),
    _CreateNotice.unknown => _text(
      'Profile creation could not be confirmed. Recover any pending operation before retrying.',
      'Не удалось подтвердить создание профиля. Восстановите незавершённую операцию перед повторной попыткой.',
    ),
  };
  bool get _valid {
    final name = _name.text.trim();
    final origin = Uri.tryParse(_origin.text.trim());
    return name.isNotEmpty &&
        utf8.encode(name).length <= 128 &&
        !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(_name.text) &&
        origin != null &&
        origin.scheme == 'https' &&
        origin.host.isNotEmpty &&
        origin.userInfo.isEmpty &&
        !origin.hasQuery &&
        !origin.hasFragment &&
        (origin.path.isEmpty || origin.path == '/');
  }

  Future<void> _submit() async {
    final isCurrent = widget.isCurrent;
    if (!mounted || !widget.enabled || !isCurrent() || _busy || !_valid) return;
    final name = _name.text.trim();
    final origin = _origin.text.trim();
    setState(() {
      _busy = true;
      _notice = null;
      _noticeCurrent = isCurrent;
    });
    try {
      final operation = await widget.create(name, origin);
      if (!mounted || !isCurrent()) return;
      setState(() {
        _name.clear();
        _origin.clear();
        _notice = operation.terminal
            ? _CreateNotice.result
            : _CreateNotice.accepted;
      });
    } catch (_) {
      if (!mounted || !isCurrent()) return;
      setState(() => _notice = _CreateNotice.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _origin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderedName = _name.text;
    final renderedOrigin = _origin.text;
    final isCurrent = widget.isCurrent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _text(
            'Create a profile. The service checks ownership; a fresh installation may assign you as owner.',
            'Создайте профиль. Служба проверяет права владельца; при первой настройке вы можете стать владельцем.',
          ),
        ),
        TextField(
          key: const Key('create-profile-name'),
          controller: _name,
          enabled: widget.enabled && !_busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _text('Profile name', 'Имя профиля'),
          ),
        ),
        TextField(
          key: const Key('create-profile-origin'),
          controller: _origin,
          enabled: widget.enabled && !_busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _text(
              'Control HTTPS origin',
              'HTTPS-адрес сервера управления',
            ),
          ),
        ),
        OutlinedButton(
          key: const Key('create-profile-submit'),
          onPressed: widget.enabled && !_busy && _valid
              ? () {
                  if (!mounted ||
                      !isCurrent() ||
                      _name.text != renderedName ||
                      _origin.text != renderedOrigin) {
                    return;
                  }
                  _submit();
                }
              : null,
          child: Text(_text('Create profile', 'Создать профиль')),
        ),
        if (_notice != null && (_noticeCurrent?.call() ?? false))
          Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
      ],
    );
  }
}
