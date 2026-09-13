import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
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
  });
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
  String? _notice;
  int? _noticeEpoch;

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
      if (!mounted || widget.state.cacheEpoch != epoch) return;
      setState(() {
        _notice = operation.succeeded
            ? 'Command completed. Runtime status is shown above.'
            : operation.terminal
            ? 'Command did not complete successfully. Check runtime status.'
            : 'Command accepted. Waiting for the runtime result.';
      });
    } catch (_) {
      if (!mounted || widget.state.cacheEpoch != epoch) return;
      // Raw transport/exception text can contain credentials or private URLs.
      setState(
        () => _notice =
            'Command result is unknown. Recover the original operation before retrying.',
      );
    } finally {
      if (mounted) {
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  _statusLabel(widget.state),
                  key: const Key('client-runtime-state'),
                ),
              ),
              if (ready && !owner)
                const Text(
                  'An installation owner is required to control this device.',
                ),
              if (owner && profile)
                Text('Profile: ${snapshot.status.activeProfileId}'),
              if (owner && profile) ...[
                Text(
                  'Account: ${_contextValue(snapshot.status.accountId)}',
                  key: const Key('client-context-account'),
                ),
                Text(
                  'Network: ${_contextValue(snapshot.status.network.name)}',
                  key: const Key('client-context-network'),
                ),
                Text(
                  'Network ID: ${_contextValue(snapshot.status.network.id)}',
                ),
                Text(
                  'Device: ${_contextValue(snapshot.status.hostname)}',
                  key: const Key('client-context-device'),
                ),
                Text('Device ID: ${_contextValue(snapshot.status.nodeId)}'),
                Text(
                  'Session expiry: ${snapshot.status.session.hasExpiresAt() ? _deadline(snapshot.status.session.expiresAt.seconds.toInt(), snapshot.status.session.expiresAt.nanos) : 'Unknown'}',
                  key: const Key('client-session-expiry'),
                ),
                Text(
                  'Credential expiry: ${snapshot.status.credential.hasExpiresAt() ? _deadline(snapshot.status.credential.expiresAt.seconds.toInt(), snapshot.status.credential.expiresAt.nanos) : 'Unknown'}',
                  key: const Key('client-credential-expiry'),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('client-connect'),
                    onPressed: canConnect
                        ? () => _run(_ClientAction.connect, snapshot)
                        : null,
                    child: Text(_connecting ? 'Submitting…' : 'Connect'),
                  ),
                  OutlinedButton(
                    key: const Key('client-disconnect'),
                    // Disconnect stays available during connect, blocked recovery
                    // and stale intent. The producer owns authorization/policy.
                    onPressed: owner && profile && !_disconnecting
                        ? () => _run(_ClientAction.disconnect, snapshot)
                        : null,
                    child: const Text('Disconnect'),
                  ),
                  OutlinedButton(
                    key: const Key('client-renew-session'),
                    onPressed: canRenew
                        ? () => _run(_ClientAction.renewSession, snapshot)
                        : null,
                    child: const Text('Renew session'),
                  ),
                ],
              ),
              if (_notice != null &&
                  ready &&
                  _noticeEpoch == widget.state.cacheEpoch)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    key: const Key('client-command-announcement'),
                    container: true,
                    liveRegion: true,
                    child: Text(_notice!),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String _contextValue(String value) => value.isEmpty ? 'Unknown' : value;

// Display authoritative UTC deadlines independently. Never infer runtime state
// from the UI clock or substitute one deadline for the other.
String _deadline(int seconds, int nanos) {
  if (seconds < -62135596800 ||
      seconds > 253402300799 ||
      nanos < 0 ||
      nanos > 999999999) {
    return 'Unknown';
  }
  return DateTime.fromMicrosecondsSinceEpoch(
    seconds * 1000000 + nanos ~/ 1000,
    isUtc: true,
  ).toIso8601String();
}

String _statusLabel(ClientStateController state) {
  if (state.invalidContract) {
    return 'Incompatible runtime. Repair or update the application.';
  }
  final snapshot = state.snapshot;
  if (snapshot == null) {
    return state.link == ClientLinkState.awaitingSnapshot
        ? 'Waiting for runtime snapshot…'
        : 'Runtime unavailable';
  }
  switch (snapshot.status.serviceState) {
    case api.ServiceState.SERVICE_STATE_NEEDS_ENROLLMENT:
      return 'Device enrollment required';
    case api.ServiceState.SERVICE_STATE_NEEDS_APPROVAL:
      return 'Waiting for approval';
    case api.ServiceState.SERVICE_STATE_NEEDS_LOGIN:
      return 'Login required';
    case api.ServiceState.SERVICE_STATE_SERVER_IDENTITY_CHANGED:
      return 'Server identity changed';
    case api.ServiceState.SERVICE_STATE_RECOVERING:
      return 'Recovering';
    case api.ServiceState.SERVICE_STATE_RECOVERY_BLOCKED:
      return 'Recovery blocked';
    case api.ServiceState.SERVICE_STATE_POLICY_BLOCKED:
      return 'Blocked by policy';
    case api.ServiceState.SERVICE_STATE_ERROR:
      return 'Runtime error';
    case api.ServiceState.SERVICE_STATE_DEGRADED:
      return snapshot.status.connectionPhase ==
              api.ConnectionPhase.CONNECTION_PHASE_CONNECTING
          ? 'Connecting'
          : 'Degraded';
    default:
      break;
  }
  return switch (snapshot.status.connectionPhase) {
    api.ConnectionPhase.CONNECTION_PHASE_CONNECTING => 'Connecting',
    api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTING => 'Disconnecting',
    api.ConnectionPhase.CONNECTION_PHASE_CONNECTED => 'Connected',
    api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED => 'Disconnected',
    _ => 'Runtime state unknown',
  };
}
