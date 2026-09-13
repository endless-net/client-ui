import 'dart:convert';

import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_state_controller.dart';

/// Initial ownership is checked atomically by the producer, never inferred
/// from an observer's deliberately redacted snapshot.
class ClientCreateProfilePanel extends StatelessWidget {
  const ClientCreateProfilePanel({
    super.key,
    required this.state,
    required this.create,
  });
  final ClientStateController state;
  final Future<ClientOperation> Function(String name, String origin) create;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => _CreateProfileForm(
      key: ValueKey(state.cacheEpoch),
      enabled: state.link == ClientLinkState.ready && state.snapshot != null,
      create: create,
    ),
  );
}

class _CreateProfileForm extends StatefulWidget {
  const _CreateProfileForm({
    super.key,
    required this.enabled,
    required this.create,
  });
  final bool enabled;
  final Future<ClientOperation> Function(String name, String origin) create;
  @override
  State<_CreateProfileForm> createState() => _CreateProfileFormState();
}

class _CreateProfileFormState extends State<_CreateProfileForm> {
  final _name = TextEditingController();
  final _origin = TextEditingController();
  bool _busy = false;
  String? _notice;
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
    if (!mounted || !widget.enabled || _busy || !_valid) return;
    final name = _name.text.trim();
    final origin = _origin.text.trim();
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final operation = await widget.create(name, origin);
      if (!mounted) return;
      setState(() {
        _name.clear();
        _origin.clear();
        _notice = operation.terminal
            ? 'Creation result received. Refresh profiles and runtime status.'
            : 'Creation accepted. Recover the operation to see its result.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _notice =
            'Profile creation could not be confirmed. Recover any pending operation before retrying.',
      );
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
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Create a profile. The service checks ownership; a fresh installation may assign you as owner.',
      ),
      TextField(
        key: const Key('create-profile-name'),
        controller: _name,
        enabled: widget.enabled && !_busy,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Profile name'),
      ),
      TextField(
        key: const Key('create-profile-origin'),
        controller: _origin,
        enabled: widget.enabled && !_busy,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Control HTTPS origin'),
      ),
      OutlinedButton(
        key: const Key('create-profile-submit'),
        onPressed: widget.enabled && !_busy && _valid ? _submit : null,
        child: const Text('Create profile'),
      ),
      if (_notice != null) Text(_notice!),
    ],
  );
}
