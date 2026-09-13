import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_state_controller.dart';

class ClientIdentityPanel extends StatelessWidget {
  const ClientIdentityPanel({
    super.key,
    required this.state,
    required this.load,
    required this.trust,
  });
  final ClientStateController state;
  final Future<api.GetServerIdentityResponse> Function() load;
  final Future<ClientOperation> Function(api.ServerIdentity identity) trust;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => _IdentityForm(
      key: ValueKey((
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
  String? _notice;
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
      _boundContext == _context &&
      state.link == ClientLinkState.ready &&
      state.snapshot != null &&
      state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER &&
      state.snapshot!.status.activeProfileId.isNotEmpty;
  bool get _trustAllowed =>
      _readAllowed &&
      state.snapshot!.runtime.callerAccess == api.Access.ACCESS_ADMINISTRATOR &&
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
      _notice = null;
    });
    try {
      final response = await widget.panel.load();
      if (!mounted || context != _context || !_readAllowed) return;
      final identity = _validate(response);
      setState(() => _identity = identity);
    } catch (_) {
      if (mounted && context == _context) {
        setState(() => _notice = 'Server identity could not be read.');
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
          _notice =
              'Server identity changed. Reload and compare again; no trust command was sent.';
        });
        return;
      }
      await widget.panel.trust(shown);
      if (!mounted || context != _context) return;
      setState(() {
        _identity = null;
        _notice =
            'Trust operation received. Recover its result; trust is not inferred from acceptance.';
      });
    } catch (_) {
      if (mounted && context == _context) {
        setState(() {
          _identity = null;
          _notice =
              'Trust could not be confirmed. Check operation recovery before another attempt.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton(
        key: const Key('load-client-identity'),
        onPressed: !_busy && _readAllowed ? _load : null,
        child: const Text('Inspect server identity'),
      ),
      if (_identity case final identity?) ...[
        Text('Control origin: ${identity.controlOrigin}'),
        Text('Trusted key: ${identity.trustedKeyId}'),
        Text('Announced key: ${identity.announcedKeyId}'),
        Text('Announcement: ${identity.announcementId}'),
        if (!_trustAllowed)
          const Text(
            'Trust requires administrator access and available identity recovery.',
          ),
        CheckboxListTile(
          key: const Key('compare-client-identity'),
          title: const Text(
            'I independently verified this origin, key and announcement.',
          ),
          value: _confirmed,
          onChanged: !_busy && _trustAllowed
              ? (value) => setState(() => _confirmed = value == true)
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
              ? _trust
              : null,
          child: const Text('Confirm server trust'),
        ),
      ],
      if (_notice != null) Text(_notice!),
    ],
  );
}
