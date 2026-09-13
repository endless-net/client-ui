import 'dart:async';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_state_controller.dart';

class ClientUpdatePanel extends StatefulWidget {
  const ClientUpdatePanel({
    super.key,
    required this.state,
    required this.uiBuild,
    required this.load,
  });
  final ClientStateController state;
  final api.BuildIdentity uiBuild;
  final Future<api.UpdateInfo> Function(api.BuildIdentity) load;
  @override
  State<ClientUpdatePanel> createState() => _ClientUpdatePanelState();
}

class _ClientUpdatePanelState extends State<ClientUpdatePanel> {
  api.UpdateInfo? _info;
  String? _context;
  String? _notice;
  bool _busy = false;
  Timer? _expiry;
  String get contextId =>
      '${widget.state.cacheEpoch}:${widget.state.domainEpoch(api.Domain.DOMAIN_UPDATES)}';
  bool get allowed =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;
  bool get current => allowed && _context == contextId;
  void _reset() {
    _expiry?.cancel();
    _expiry = null;
    _info = null;
    _context = null;
    _notice = null;
  }

  void _changed() {
    if (_context != null && !current) setState(_reset);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientUpdatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.uiBuild != widget.uiBuild) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _reset();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _reset();
    super.dispose();
  }

  Future<void> _load() async {
    if (!allowed || _busy) return;
    final context = contextId;
    final ui = api.BuildIdentity.fromBuffer(widget.uiBuild.writeToBuffer())
      ..freeze();
    setState(() {
      _reset();
      _context = context;
      _busy = true;
    });
    try {
      final result = await widget.load(ui);
      if (!mounted || !current || context != _context || widget.uiBuild != ui) {
        return;
      }
      if (result.metadata.instanceId !=
              widget.state.snapshot!.runtime.instanceId ||
          result.metadata.revision <
              widget.state.snapshot!.status.metadata.revision ||
          result.reportedUi != ui) {
        throw const FormatException('Stale update projection');
      }
      final info = api.UpdateInfo.fromBuffer(result.writeToBuffer())..freeze();
      if (info.hasAvailable()) {
        final remaining = info.available.expiresAt.toDateTime().difference(
          DateTime.now().toUtc(),
        );
        if (remaining <= Duration.zero) {
          throw const FormatException('Expired update projection');
        }
        _expiry = Timer(remaining, () {
          if (mounted && current && identical(_info, info)) {
            setState(() {
              _info = null;
              _notice = 'Update metadata expired. Check again.';
            });
          }
        });
      }
      setState(() => _info = info);
    } catch (_) {
      if (mounted && current && context == _context) {
        setState(() => _notice = 'Update information could not be confirmed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String identity(api.BuildIdentity value) =>
      '${value.version.isEmpty ? 'Unknown' : value.version}; commit ${value.commit.isEmpty ? 'Unknown' : value.commit}; built ${value.buildDate.isEmpty ? 'Unknown' : value.buildDate}; ${value.platform.name}/${value.architecture}';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final info = current ? _info : null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('UI build: ${identity(widget.uiBuild)}'),
          if (widget.state.snapshot != null)
            Text(
              'Runtime build: ${identity(widget.state.snapshot!.runtime.build)}',
            ),
          OutlinedButton(
            key: const Key('client-check-updates'),
            onPressed: allowed && !_busy ? _load : null,
            child: const Text('Check updates'),
          ),
          if (current && _notice != null) Text(_notice!),
          if (info != null) ...[
            Text('Update source: ${info.state.name}'),
            Text(
              'Installed pair: ${info.installedPair.state.name}; ${info.installedPair.reasonKey}',
            ),
            Text(
              'Discovery: ${info.discovery.availability.name}; ${info.discovery.reasonKey}; ${info.discovery.actionOwner.name}',
            ),
            if (info.hasAvailable()) ...[
              Text(
                'Release: ${info.available.releaseId}; ${info.available.classification.name}',
              ),
              Text(
                'Offered runtime: ${identity(info.available.runtime)}; paired UI: ${info.available.pairedUiVersion}',
              ),
              Text(
                'Distribution: ${info.available.channel.name}; pair: ${info.available.compatibility.state.name}',
              ),
              Text(
                'Verified until: ${info.available.expiresAt.toDateTime().toUtc().toIso8601String()}',
              ),
              const Text(
                'Installation and its outcome belong to the distribution provider. This notice does not install or disconnect.',
              ),
            ],
          ],
        ],
      );
    },
  );
}
