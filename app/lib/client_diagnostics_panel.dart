import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_state_controller.dart';
import 'client_operation.dart';

/// Local summary only. Never serialize the full message into logs/clipboard:
/// diagnostics can contain addresses, pending browser actions and log entries.
class ClientDiagnosticsPanel extends StatefulWidget {
  const ClientDiagnosticsPanel({
    super.key,
    required this.state,
    required this.load,
    required this.createBundle,
    this.loadLogs,
  });
  final ClientStateController state;
  final Future<api.Diagnostics> Function() load;
  final Future<ClientOperation> Function(String profileId) createBundle;
  final Future<List<api.LogEntry>> Function()? loadLogs;
  @override
  State<ClientDiagnosticsPanel> createState() => _ClientDiagnosticsPanelState();
}

class _ClientDiagnosticsPanelState extends State<ClientDiagnosticsPanel> {
  api.Diagnostics? _preview;
  List<api.LogEntry>? _logs;
  String? _context;
  String? _notice;
  bool _busy = false;
  bool _confirmBundle = false;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_clearInvalidatedPreview);
  }

  @override
  void didUpdateWidget(covariant ClientDiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_clearInvalidatedPreview);
      widget.state.addListener(_clearInvalidatedPreview);
      _clearPreview();
    }
  }

  void _clearPreview() {
    _preview = null;
    _logs = null;
    _notice = null;
    _confirmBundle = false;
    _context = null;
  }

  void _clearInvalidatedPreview() {
    if (_context != null && (_context != contextId || !allowed)) {
      // Drop the message itself, not just its rendered summary. It can contain
      // log entries or browser actions belonging to the former caller/profile.
      setState(_clearPreview);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_clearInvalidatedPreview);
    _clearPreview();
    super.dispose();
  }

  String get contextId =>
      '${widget.state.cacheEpoch}:${api.Domain.values.map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_DIAGNOSTICS);

  Future<void> _loadLogs() async {
    if (!allowed || _busy || widget.loadLogs == null) return;
    final context = contextId;
    setState(() {
      _context = context;
      _logs = null;
      _notice = null;
      _busy = true;
    });
    try {
      final logs = await widget.loadLogs!();
      if (!mounted || _context != context || contextId != context || !allowed) {
        return;
      }
      setState(() => _logs = logs);
    } catch (_) {
      if (mounted && _context == context && contextId == context && allowed) {
        setState(
          () => _notice =
              'Logs could not be read. Refresh to start a new snapshot.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (!allowed || _busy) return;
    final context = contextId;
    setState(() {
      _context = context;
      _busy = true;
      _preview = null;
      _notice = null;
      _confirmBundle = false;
    });
    try {
      final preview = await widget.load();
      if (!mounted || context != _context || context != contextId || !allowed) {
        return;
      }
      final snapshot = widget.state.snapshot!;
      if (!preview.hasMetadata() ||
          preview.metadata.instanceId != snapshot.runtime.instanceId ||
          preview.metadata.revision < snapshot.status.metadata.revision) {
        throw const FormatException('Invalid diagnostics context');
      }
      setState(
        () =>
            _preview = api.Diagnostics.fromBuffer(preview.writeToBuffer())
              ..freeze(),
      );
    } catch (_) {
      if (mounted && context == _context && context == contextId) {
        setState(() => _notice = 'Diagnostics could not be read.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!allowed ||
        _busy ||
        !_confirmBundle ||
        _preview == null ||
        _context != contextId) {
      return;
    }
    final context = contextId;
    final profileId = widget.state.snapshot!.status.activeProfileId;
    setState(() {
      _busy = true;
      _confirmBundle = false;
      _notice = null;
    });
    try {
      final operation = await widget.createBundle(profileId);
      if (!mounted || context != _context || context != contextId || !allowed) {
        return;
      }
      setState(
        () => _notice = operation.succeeded
            ? 'Bundle operation succeeded. Recover its handle before verified download; nothing was exported.'
            : 'Bundle operation received. Recover its result; archive readiness is not confirmed.',
      );
    } catch (_) {
      if (mounted && context == _context && context == contextId) {
        setState(
          () => _notice =
              'Bundle creation could not be confirmed. Recover the intention before another attempt.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final preview = allowed && _context == contextId ? _preview : null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.loadLogs != null)
            OutlinedButton(
              key: const Key('load-client-logs'),
              onPressed: allowed && !_busy ? _loadLogs : null,
              child: const Text('Read recent logs'),
            ),
          if (allowed && _context == contextId && _logs != null) ...[
            const Text(
              'Recent local log window — not a complete history. Nothing uploaded.',
            ),
            if (_logs!.isEmpty) const Text('No recent log entries.'),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: _logs!.length,
                itemBuilder: (context, index) {
                  final entry = _logs![index];
                  return Text(
                    '${entry.timestamp.toDateTime().toUtc().toIso8601String()} ${entry.message}',
                  );
                },
              ),
            ),
          ],
          OutlinedButton(
            key: const Key('load-client-diagnostics'),
            onPressed: allowed && !_busy ? _load : null,
            child: const Text('Inspect diagnostics'),
          ),
          if (preview != null) ...[
            const Text(
              'Local diagnostics summary — no data copied or uploaded.',
            ),
            Text('OS: ${preview.osName} ${preview.osVersion}'),
            Text('Go: ${preview.goVersion}'),
            Text(
              'Interfaces: ${preview.interfaces.length}; routes: ${preview.routes.length}; peers: ${preview.peers.length}',
            ),
            Text(
              'Route conflicts: ${preview.routeConflicts.length}; failures: ${preview.failures.length}',
            ),
            if (preview.truncated)
              const Text(
                'Diagnostics are truncated; this is not a complete report.',
              ),
            if (preview.hasStatus())
              Text('Connection phase: ${preview.status.connectionPhase.name}'),
            const Text(
              'Detailed inspection and archive export are not yet available.',
            ),
            OutlinedButton(
              key: const Key('create-client-bundle'),
              onPressed: !_busy
                  ? () {
                      if (!allowed || _context != contextId) return;
                      setState(() => _confirmBundle = true);
                    }
                  : null,
              child: const Text('Create diagnostics archive'),
            ),
            if (_confirmBundle) ...[
              const Text(
                'Create a local redacted diagnostics archive? This does not upload or export it.',
              ),
              Wrap(
                children: [
                  TextButton(
                    key: const Key('cancel-client-bundle'),
                    onPressed: () => setState(() => _confirmBundle = false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    key: const Key('confirm-client-bundle'),
                    onPressed: !_busy ? _create : null,
                    child: const Text('Confirm archive creation'),
                  ),
                ],
              ),
            ],
          ],
          if (_context == contextId && allowed && _notice != null)
            Text(_notice!),
        ],
      );
    },
  );
}
