import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_operation_details.dart';
import 'client_state_controller.dart';

/// Lookup and explicit acknowledgement only: this surface never replays work.
class ClientRecoveryPanel extends StatefulWidget {
  const ClientRecoveryPanel({
    super.key,
    required this.state,
    required this.recover,
    required this.acknowledge,
  });
  final ClientStateController state;
  final Future<List<ClientOperation>> Function() recover;
  final Future<void> Function(ClientOperation) acknowledge;

  @override
  State<ClientRecoveryPanel> createState() => _ClientRecoveryPanelState();
}

class _ClientRecoveryPanelState extends State<ClientRecoveryPanel> {
  List<ClientOperation> _results = [];
  String? _notice;
  int? _epoch;
  bool _busy = false;

  bool get _owner =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;

  Future<void> _run(ClientOperation? acknowledgement) async {
    if (_busy || !_owner) return;
    final epoch = widget.state.cacheEpoch;
    setState(() {
      _busy = true;
      if (_epoch != epoch) _results = [];
      _epoch = epoch;
      _notice = null;
    });
    try {
      if (acknowledgement == null) {
        final results = await widget.recover();
        if (!mounted || widget.state.cacheEpoch != epoch || !_owner) return;
        setState(() {
          _results = List.unmodifiable(results);
          if (results.isEmpty) _notice = 'No pending intentions.';
        });
      } else {
        if (!acknowledgement.terminal) return;
        await widget.acknowledge(acknowledgement);
        if (!mounted || widget.state.cacheEpoch != epoch || !_owner) return;
        setState(() {
          _results = _results
              .where(
                (op) => op.value.requestId != acknowledgement.value.requestId,
              )
              .toList();
          _notice = 'Result acknowledged. No command was replayed.';
        });
      }
    } catch (_) {
      if (!mounted || widget.state.cacheEpoch != epoch || !_owner) return;
      setState(
        () => _notice =
            'Recovery could not complete. Pending intentions are retained.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final visible = _owner && _epoch == widget.state.cacheEpoch;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(
            key: const Key('client-recover'),
            onPressed: _owner && !_busy ? () => _run(null) : null,
            child: const Text('Recover pending operations'),
          ),
          if (visible && _notice != null) Text(_notice!),
          if (visible)
            for (final operation in _results)
              ListTile(
                title: Text(operation.value.kind.name),
                subtitle: ClientOperationDetails(operation: operation),
                trailing: operation.terminal
                    ? TextButton(
                        key: ValueKey('ack-${operation.value.requestId}'),
                        onPressed: !_busy ? () => _run(operation) : null,
                        child: const Text('Acknowledge result'),
                      )
                    : const Text('Still pending'),
              ),
        ],
      );
    },
  );
}
