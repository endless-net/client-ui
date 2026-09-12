import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_state_controller.dart';

/// Shared primary UI surface. Platform/application wiring supplies journaled
/// actions; this widget knows no HTTP DTO, desktop pipe or private state path.
class ClientConnectionPanel extends StatefulWidget {
  const ClientConnectionPanel({
    super.key,
    required this.state,
    required this.connect,
    required this.disconnect,
  });
  final ClientStateController state;
  final Future<ClientOperation> Function() connect;
  final Future<ClientOperation> Function() disconnect;

  @override
  State<ClientConnectionPanel> createState() => _ClientConnectionPanelState();
}

class _ClientConnectionPanelState extends State<ClientConnectionPanel> {
  bool _connecting = false;
  bool _disconnecting = false;
  String? _notice;
  int? _noticeEpoch;

  Future<void> _run(bool connect) async {
    final epoch = widget.state.cacheEpoch;
    setState(() {
      if (connect) {
        _connecting = true;
      } else {
        _disconnecting = true;
      }
      _notice = null;
      _noticeEpoch = epoch;
    });
    try {
      final operation = await (connect
          ? widget.connect()
          : widget.disconnect());
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
          if (connect) {
            _connecting = false;
          } else {
            _disconnecting = false;
          }
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('client-connect'),
                    onPressed: canConnect ? () => _run(true) : null,
                    child: Text(_connecting ? 'Submitting…' : 'Connect'),
                  ),
                  OutlinedButton(
                    key: const Key('client-disconnect'),
                    // Disconnect stays available during connect, blocked recovery
                    // and stale intent. The producer owns authorization/policy.
                    onPressed: owner && profile && !_disconnecting
                        ? () => _run(false)
                        : null,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
              if (_notice != null &&
                  ready &&
                  _noticeEpoch == widget.state.cacheEpoch)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_notice!),
                ),
            ],
          ),
        ),
      );
    },
  );
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
