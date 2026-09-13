import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_state_controller.dart';
import 'client_support_info.dart';

class ClientSupportPanel extends StatefulWidget {
  const ClientSupportPanel({
    super.key,
    required this.state,
    required this.load,
    required this.openBrowser,
  });
  final ClientStateController state;
  final Future<api.SupportInfo> Function() load;
  final Future<bool> Function(Uri, void Function()) openBrowser;
  @override
  State<ClientSupportPanel> createState() => _ClientSupportPanelState();
}

class _ClientSupportPanelState extends State<ClientSupportPanel> {
  api.SupportInfo? _info;
  String? _context;
  String? _notice;
  bool _busy = false;
  bool _help = false;
  String get contextId =>
      '${widget.state.cacheEpoch}:${widget.state.domainEpoch(api.Domain.DOMAIN_SUPPORT)}';
  bool get allowed =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null;
  bool get current => allowed && _context == contextId;
  void _reset() {
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
  void didUpdateWidget(covariant ClientSupportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
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

  String link(api.SupportInfo info, String key) => switch (key) {
    'documentation' => info.documentationUrl,
    'support' => info.supportUrl,
    'privacy' => info.privacyUrl,
    'license' => info.licenseUrl,
    _ => '',
  };
  Future<void> _run([String? key]) async {
    if (!allowed || _busy || (key != null && (!current || _info == null))) {
      return;
    }
    final original = key == null ? null : link(_info!, key);
    if (original == '') return;
    final context = contextId;
    final build = widget.state.snapshot!.runtime.build;
    void check() {
      if (!mounted || !current || context != _context) {
        throw StateError('Support context changed');
      }
    }

    setState(() {
      _context = context;
      _busy = true;
      _notice = null;
      if (key == null) _info = null;
    });
    try {
      final loaded = await widget.load();
      check();
      final info = await readClientSupportInfo(
        installedRuntime: build,
        get: (_) async => api.GetSupportInfoResponse(info: loaded),
        checkContext: check,
      );
      check();
      if (key != null) {
        final destination = link(info, key);
        if (destination != original || destination.isEmpty) {
          throw StateError('Support destination changed');
        }
        check();
        final opened = await widget.openBrowser(Uri.parse(destination), check);
        check();
        if (!opened) throw StateError('Browser did not confirm opening');
      }
      setState(() => _info = info);
    } catch (_) {
      if (mounted && current && context == _context) {
        setState(() {
          _info = null;
          _notice =
              'Support information could not be confirmed. Refresh before opening a link.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final info = current ? _info : null;
      final viewContext = _context;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const Key('client-offline-help'),
            onPressed: () => setState(() => _help = !_help),
            child: const Text('Offline help'),
          ),
          if (_help)
            const Text(
              'Built-in help: Reconnect runtime if its status is unavailable. '
              'An accepted operation is not a completed result: recover pending operations before retrying. '
              'Logout and Forget local enrollment are different actions. Never share enrollment tokens or private keys. '
              'Use explicit diagnostics export when requesting support; inspect the file before sharing.',
            ),
          OutlinedButton(
            key: const Key('client-load-support'),
            onPressed: allowed && !_busy ? () => _run() : null,
            child: const Text('Refresh support information'),
          ),
          if (current && _notice != null) Text(_notice!),
          if (info != null) ...[
            Text('Product: ${info.productName}'),
            if (info.offlineHelpKey.isNotEmpty)
              const Text(
                'The runtime-requested offline topic is not bundled. Built-in help remains available.',
              ),
            for (final key in [
              'documentation',
              'support',
              'privacy',
              'license',
            ])
              if (link(info, key).isNotEmpty)
                OutlinedButton(
                  key: Key('client-support-$key'),
                  onPressed: !_busy
                      ? () {
                          if (current &&
                              identical(info, _info) &&
                              viewContext == _context) {
                            _run(key);
                          }
                        }
                      : null,
                  child: Text('Open $key'),
                ),
          ],
        ],
      );
    },
  );
}
