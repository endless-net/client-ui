import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
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
  });
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
        key: ValueKey(state.cacheEpoch),
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
  });
  final String profileId;
  final EnrollProfile enroll;
  @override
  State<_EnrollmentForm> createState() => _EnrollmentFormState();
}

class _EnrollmentFormState extends State<_EnrollmentForm> {
  final _hostname = TextEditingController();
  final _token = TextEditingController();
  var _mode = api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION;
  bool _useToken = false;
  bool _busy = false;
  String? _notice;
  bool get _enabled => widget.profileId.isNotEmpty && !_busy;

  Future<void> _submit() async {
    if (!_enabled ||
        _hostname.text.trim().isEmpty ||
        (_useToken && _token.text.trim().isEmpty)) {
      return;
    }
    final token = _useToken ? _token.text.trim() : null;
    final hostname = _hostname.text.trim();
    setState(() {
      _busy = true;
      _notice = null;
      _token.clear();
    });
    try {
      final operation = await widget.enroll(
        widget.profileId,
        _mode,
        hostname,
        token,
      );
      if (!mounted) return;
      setState(
        () => _notice = operation.terminal
            ? 'Enrollment result received. Refresh runtime status.'
            : 'Enrollment accepted. Recover the operation for required actions and its result.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _notice =
            'Enrollment could not be confirmed. Recover the intention before retrying.',
      );
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
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Enroll the selected profile'),
      TextField(
        key: const Key('enroll-hostname'),
        controller: _hostname,
        enabled: _enabled,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Device hostname'),
      ),
      DropdownButton<api.EnrollmentMode>(
        key: const Key('enroll-mode'),
        value: _mode,
        items: [
          for (final mode in api.EnrollmentMode.values.where(
            (m) => m != api.EnrollmentMode.ENROLLMENT_MODE_UNSPECIFIED,
          ))
            DropdownMenuItem(value: mode, child: Text(mode.name)),
        ],
        onChanged: _enabled ? (mode) => setState(() => _mode = mode!) : null,
      ),
      SwitchListTile(
        key: const Key('enroll-use-token'),
        title: const Text('Use enrollment token instead of browser login'),
        value: _useToken,
        onChanged: _enabled
            ? (value) => setState(() {
                _useToken = value;
                _token.clear();
              })
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
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Enrollment token'),
        ),
      OutlinedButton(
        key: const Key('enroll-submit'),
        onPressed:
            _enabled &&
                _hostname.text.trim().isNotEmpty &&
                (!_useToken || _token.text.trim().isNotEmpty)
            ? _submit
            : null,
        child: const Text('Enroll profile'),
      ),
      if (_notice != null) Text(_notice!),
    ],
  );
}
