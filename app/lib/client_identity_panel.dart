import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_locale.dart';

import 'client_state_controller.dart';

enum _IdentityNotice { readFailed, changed, received, unknown }

class ClientIdentityPanel extends StatelessWidget {
  const ClientIdentityPanel({
    super.key,
    required this.state,
    required this.load,
    required this.trust,
    this.canElevate = false,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final Future<api.GetServerIdentityResponse> Function() load;
  final Future<ClientOperation> Function(api.ServerIdentity identity) trust;
  final bool canElevate;
  final ClientLocale locale;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => _IdentityForm(
      key: ValueKey((
        state,
        state.cacheEpoch,
        state.domainEpoch(api.Domain.DOMAIN_SERVER_IDENTITY),
        state.domainEpoch(api.Domain.DOMAIN_PROFILES),
      )),
      panel: this,
    ),
  );
}

class _IdentityForm extends StatefulWidget {
  const _IdentityForm({super.key, required this.panel});
  final ClientIdentityPanel panel;
  @override
  State<_IdentityForm> createState() => _IdentityFormState();
}

class _IdentityFormState extends State<_IdentityForm> {
  api.ServerIdentity? _identity;
  bool _busy = false;
  bool _confirmed = false;
  _IdentityNotice? _notice;
  int _confirmationSerial = 0;
  String _text(String en, String ru) =>
      widget.panel.locale.text(en: en, ru: ru);
  String _noticeText(_IdentityNotice notice) => switch (notice) {
    _IdentityNotice.readFailed => _text(
      'Server identity could not be read.',
      'Не удалось прочитать сведения о подлинности сервера.',
    ),
    _IdentityNotice.changed => _text(
      'Server identity changed. Reload and compare again; no trust command was sent.',
      'Сведения о подлинности сервера изменились. Загрузите и сравните их снова; команда доверия не отправлена.',
    ),
    _IdentityNotice.received => _text(
      'Trust operation received. Recover its result; trust is not inferred from acceptance.',
      'Операция доверия получена. Восстановите её результат; принятие операции не означает установления доверия.',
    ),
    _IdentityNotice.unknown => _text(
      'Trust could not be confirmed. Check operation recovery before another attempt.',
      'Не удалось подтвердить доверие. Проверьте восстановление операции перед повторной попыткой.',
    ),
  };
  ClientStateController get state => widget.panel.state;
  late final (int, int, int) _boundContext;

  @override
  void initState() {
    super.initState();
    _boundContext = _context;
  }

  (int, int, int) get _context => (
    state.cacheEpoch,
    state.domainEpoch(api.Domain.DOMAIN_SERVER_IDENTITY),
    state.domainEpoch(api.Domain.DOMAIN_PROFILES),
  );
  bool get _readAllowed =>
      mounted &&
      _boundContext == _context &&
      state.link == ClientLinkState.ready &&
      state.snapshot != null &&
      state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER &&
      state.snapshot!.status.activeProfileId.isNotEmpty;
  bool get _trustAllowed =>
      _readAllowed &&
      (state.snapshot!.runtime.callerAccess ==
              api.Access.ACCESS_ADMINISTRATOR ||
          (state.snapshot!.runtime.callerAccess == api.Access.ACCESS_OWNER &&
              widget.panel.canElevate)) &&
      state.snapshot!.supports(api.Capability.CAPABILITY_IDENTITY_RECOVERY);

  api.ServerIdentity _validate(api.GetServerIdentityResponse response) {
    final snapshot = state.snapshot!;
    if (!response.hasIdentity() ||
        !response.hasMetadata() ||
        response.metadata.instanceId != snapshot.runtime.instanceId ||
        response.metadata.revision < snapshot.status.metadata.revision ||
        response.identity.profileId != snapshot.status.activeProfileId) {
      throw const FormatException('Invalid identity context');
    }
    return api.ServerIdentity.fromBuffer(response.identity.writeToBuffer())
      ..freeze();
  }

  Future<void> _load() async {
    if (_busy || !_readAllowed) return;
    final context = _context;
    setState(() {
      _busy = true;
      _identity = null;
      _confirmed = false;
      _confirmationSerial++;
      _notice = null;
    });
    try {
      final response = await widget.panel.load();
      if (!mounted || context != _context || !_readAllowed) return;
      final identity = _validate(response);
      setState(() => _identity = identity);
    } catch (_) {
      if (mounted && context == _context) {
        setState(() => _notice = _IdentityNotice.readFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trust() async {
    final shown = _identity;
    if (_busy ||
        !_confirmed ||
        !_trustAllowed ||
        shown == null ||
        shown.controlOrigin.isEmpty ||
        shown.announcedKeyId.isEmpty ||
        shown.announcementId.isEmpty) {
      return;
    }
    final context = _context;
    setState(() {
      _busy = true;
      _confirmed = false;
      _confirmationSerial++;
      _notice = null;
    });
    try {
      final response = await widget.panel.load();
      if (!mounted || context != _context || !_trustAllowed) return;
      final fresh = _validate(response);
      if (fresh.profileId != shown.profileId ||
          fresh.controlOrigin != shown.controlOrigin ||
          fresh.trustedKeyId != shown.trustedKeyId ||
          fresh.announcedKeyId != shown.announcedKeyId ||
          fresh.announcementId != shown.announcementId ||
          fresh.changed != shown.changed) {
        setState(() {
          _identity = null;
          _notice = _IdentityNotice.changed;
        });
        return;
      }
      await widget.panel.trust(shown);
      if (!mounted || context != _context) return;
      setState(() {
        _identity = null;
        _notice = _IdentityNotice.received;
      });
    } catch (_) {
      if (mounted && context == _context) {
        setState(() {
          _identity = null;
          _notice = _IdentityNotice.unknown;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    final snapshot = state.snapshot;
    final serial = _confirmationSerial;
    bool current() =>
        mounted &&
        identical(identity, _identity) &&
        identical(snapshot, state.snapshot) &&
        serial == _confirmationSerial;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const Key('load-client-identity'),
          onPressed: !_busy && _readAllowed
              ? () {
                  if (current()) _load();
                }
              : null,
          child: Text(
            _text('Inspect server identity', 'Проверить подлинность сервера'),
          ),
        ),
        if (_identity case final identity?) ...[
          Text(
            '${_text('Control origin', 'Адрес сервера управления')}: ${identity.controlOrigin}',
          ),
          Text(
            '${_text('Trusted key', 'Доверенный ключ')}: ${identity.trustedKeyId}',
          ),
          Text(
            '${_text('Announced key', 'Объявленный ключ')}: ${identity.announcedKeyId}',
          ),
          Text(
            '${_text('Announcement', 'Объявление')}: ${identity.announcementId}',
          ),
          if (_trustAllowed &&
              state.snapshot!.runtime.callerAccess == api.Access.ACCESS_OWNER)
            Text(
              _text(
                'Confirmation will open the system administrator approval prompt.',
                'Подтверждение откроет системный запрос одобрения администратора.',
              ),
            ),
          if (!_trustAllowed)
            Text(
              _text(
                'Trust requires administrator access and available identity recovery.',
                'Для доверия нужны права администратора и доступная функция восстановления подлинности.',
              ),
            ),
          CheckboxListTile(
            key: const Key('compare-client-identity'),
            title: Text(
              _text(
                'I independently verified this origin, key and announcement.',
                'Я независимо проверил адрес сервера, ключ и объявление.',
              ),
            ),
            value: _confirmed,
            onChanged: !_busy && _trustAllowed
                ? (value) {
                    if (!current() ||
                        _busy ||
                        !_trustAllowed ||
                        !identical(identity, _identity)) {
                      return;
                    }
                    setState(() {
                      _confirmed = value == true;
                      _confirmationSerial++;
                    });
                  }
                : null,
          ),
          TextButton(
            key: const Key('trust-client-identity'),
            onPressed:
                !_busy &&
                    _confirmed &&
                    _trustAllowed &&
                    identity.controlOrigin.isNotEmpty &&
                    identity.announcedKeyId.isNotEmpty &&
                    identity.announcementId.isNotEmpty
                ? () {
                    if (current()) _trust();
                  }
                : null,
            child: Text(
              _text('Confirm server trust', 'Подтвердить доверие серверу'),
            ),
          ),
        ],
        if (_notice != null)
          Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
      ],
    );
  }
}
