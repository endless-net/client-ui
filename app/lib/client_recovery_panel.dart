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
    this.openBrowser,
    this.exportBundle,
  });
  final ClientStateController state;
  final Future<List<ClientOperation>> Function() recover;
  final Future<void> Function(ClientOperation) acknowledge;
  final Future<bool> Function(Uri)? openBrowser;

  /// Adapter chooses a native destination, re-reads via ClientSession and calls
  /// checkContext across every await. False means user cancellation, not success.
  final Future<bool> Function(String requestId, void Function() checkContext)?
  exportBundle;

  @override
  State<ClientRecoveryPanel> createState() => _ClientRecoveryPanelState();
}

class _ClientRecoveryPanelState extends State<ClientRecoveryPanel> {
  List<ClientOperation> _results = [];
  String? _notice;
  int? _epoch;
  bool _busy = false;

  bool get _owner =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;

  Future<void> _openBrowser(ClientOperation displayed) async {
    if (_busy ||
        !_owner ||
        _epoch != widget.state.cacheEpoch ||
        widget.openBrowser == null) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      // Re-read the operation immediately before using its sensitive action.
      // A displayed URL may have expired or been replaced since the last lookup.
      final results = await widget.recover();
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      final current = results.singleWhere(
        (op) =>
            op.value.id == displayed.value.id &&
            op.value.requestId == displayed.value.requestId,
      );
      setState(() => _results = List.unmodifiable(results));
      final value = current.value;
      if (value.state != api.OperationState.OPERATION_STATE_WAITING_FOR_USER ||
          value.userAction.kind != api.UserAction_Kind.KIND_OPEN_BROWSER) {
        throw StateError('Browser action is no longer pending');
      }
      final action = value.userAction;
      final uri = Uri.tryParse(action.browserUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw StateError('Invalid browser action');
      }
      if (action.hasExpiresAt()) {
        final deadline = action.expiresAt;
        if (deadline.seconds.toInt() < -62135596800 ||
            deadline.seconds.toInt() > 253402300799 ||
            deadline.nanos < 0 ||
            deadline.nanos >= 1000000000 ||
            !DateTime.fromMicrosecondsSinceEpoch(
              deadline.seconds.toInt() * 1000000 + deadline.nanos ~/ 1000,
              isUtc: true,
            ).isAfter(DateTime.now().toUtc())) {
          throw StateError('Browser action expired');
        }
      }
      // Producer validates the URL against trusted origin/provider policy.
      // No URL, token or launch exception is logged or placed in a notice.
      final opened = await widget.openBrowser!(uri);
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      setState(
        () => _notice = opened
            ? 'Browser opened. The operation is still pending; recover its result.'
            : 'Browser could not be opened. The operation is retained.',
      );
    } catch (_) {
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      setState(
        () => _notice =
            'Browser action could not be completed. Refresh the operation; no command was replayed.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(ClientOperation displayed) async {
    if (_busy ||
        !_owner ||
        _epoch != widget.state.cacheEpoch ||
        widget.exportBundle == null) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    void check() {
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) {
        throw StateError('Export context changed');
      }
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final results = await widget.recover();
      check();
      final current = results.singleWhere(
        (op) =>
            op.value.id == displayed.value.id &&
            op.value.requestId == displayed.value.requestId,
      );
      if (!current.succeeded ||
          current.value.kind !=
              api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE) {
        throw StateError('Bundle is not ready');
      }
      final saved = await widget.exportBundle!(current.value.requestId, check);
      check();
      setState(
        () => _notice = saved
            ? 'Verified bundle exported. The operation is retained.'
            : 'Export cancelled. The operation is retained.',
      );
    } catch (_) {
      if (mounted && _owner && epoch == widget.state.cacheEpoch) {
        setState(
          () =>
              _notice = 'Export could not complete. The operation is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(ClientOperation? acknowledgement) async {
    if (_busy || !_owner) return;
    if (acknowledgement != null &&
        (_epoch != widget.state.cacheEpoch ||
            !_results.contains(acknowledgement))) {
      return;
    }
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
      final renderedState = widget.state;
      final renderedEpoch = widget.state.cacheEpoch;
      bool current() =>
          mounted &&
          identical(widget.state, renderedState) &&
          widget.state.cacheEpoch == renderedEpoch;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(
            key: const Key('client-recover'),
            onPressed: _owner && !_busy
                ? () {
                    if (current()) _run(null);
                  }
                : null,
            child: const Text('Recover pending operations'),
          ),
          if (visible && _notice != null) Text(_notice!),
          if (visible)
            for (final operation in _results)
              ListTile(
                title: Text(operation.value.kind.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClientOperationDetails(operation: operation),
                    if (operation.succeeded &&
                        operation.value.kind ==
                            api
                                .OperationKind
                                .OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE)
                      widget.exportBundle == null
                          ? const Text(
                              'Native export adapter is not available.',
                            )
                          : TextButton(
                              key: ValueKey(
                                'export-${operation.value.requestId}',
                              ),
                              onPressed: !_busy
                                  ? () {
                                      if (current() &&
                                          _results.contains(operation)) {
                                        _export(operation);
                                      }
                                    }
                                  : null,
                              child: const Text('Export verified bundle'),
                            ),
                  ],
                ),
                trailing: operation.terminal
                    ? TextButton(
                        key: ValueKey('ack-${operation.value.requestId}'),
                        onPressed: !_busy
                            ? () {
                                if (current()) _run(operation);
                              }
                            : null,
                        child: const Text('Acknowledge result'),
                      )
                    : operation.value.userAction.kind ==
                              api.UserAction_Kind.KIND_OPEN_BROWSER &&
                          widget.openBrowser != null
                    ? TextButton(
                        key: ValueKey('browser-${operation.value.requestId}'),
                        onPressed: !_busy
                            ? () {
                                if (current() && _results.contains(operation)) {
                                  _openBrowser(operation);
                                }
                              }
                            : null,
                        child: const Text('Open browser'),
                      )
                    : const Text('Still pending'),
              ),
        ],
      );
    },
  );
}
