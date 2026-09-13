import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_exit_nodes.dart';
import 'client_operation.dart';
import 'client_state_controller.dart';

class ClientExitPanel extends StatefulWidget {
  const ClientExitPanel({
    super.key,
    required this.state,
    required this.load,
    required this.select,
    required this.clear,
  });
  final ClientStateController state;
  final Future<ClientExitNodes> Function() load;
  final Future<ClientOperation> Function(
    String,
    String,
    api.ExitFamilyMode,
    api.LanAccess,
    void Function(),
  )
  select;
  final Future<ClientOperation> Function(String, void Function()) clear;
  @override
  State<ClientExitPanel> createState() => _ClientExitPanelState();
}

class _ClientExitPanelState extends State<ClientExitPanel> {
  ClientExitNodes? _view;
  String? _context;
  String? _node;
  api.ExitFamilyMode? _mode;
  api.LanAccess? _lan;
  bool _busy = false;
  bool _confirmClear = false;
  String? _notice;
  String get contextId =>
      '${widget.state.cacheEpoch}:'
      '${[api.Domain.DOMAIN_EXIT_NODE, api.Domain.DOMAIN_PROFILES, api.Domain.DOMAIN_NETWORKS, api.Domain.DOMAIN_PEERS].map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_EXIT_NODE);
  bool get current => allowed && _context == contextId;
  bool get editable =>
      current &&
      _view != null &&
      !_view!.status.control.locked &&
      _view!.status.control.mutation.availability ==
          api.Availability.AVAILABILITY_AVAILABLE;
  api.ExitNode? get selected {
    for (final node in _view?.nodes ?? <api.ExitNode>[]) {
      if (node.id == _node) return node;
    }
    return null;
  }

  bool get canSelect =>
      editable &&
      selected != null &&
      selected!.selection.availability ==
          api.Availability.AVAILABILITY_AVAILABLE &&
      selected!.allowedFamilyModes.contains(_mode) &&
      selected!.allowedLanAccess.contains(_lan);
  void _discard() {
    _view = null;
    _context = null;
    _node = null;
    _mode = null;
    _lan = null;
    _notice = null;
    _confirmClear = false;
  }

  void _changed() {
    if (_context != null && !current) setState(_discard);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientExitPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _discard();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _discard();
    super.dispose();
  }

  Future<void> _run({bool select = false, bool clear = false}) async {
    if (!allowed ||
        _busy ||
        (select && !canSelect) ||
        (clear && (!editable || !_confirmClear))) {
      return;
    }
    final context = contextId;
    final profile = widget.state.snapshot!.status.activeProfileId;
    final node = _node;
    final mode = _mode;
    final lan = _lan;
    void check() {
      if (!mounted || !current || context != _context) {
        throw StateError('Exit context changed');
      }
    }

    setState(() {
      _context = context;
      _busy = true;
      _notice = null;
      _confirmClear = false;
    });
    try {
      if (select || clear) {
        check();
        if (select) {
          await widget.select(profile, node!, mode!, lan!, check);
        } else {
          await widget.clear(profile, check);
        }
        check();
        setState(() {
          _view = null;
          _node = null;
          _mode = null;
          _lan = null;
          _notice =
              'Exit operation received. Recover its result and refresh both address families.';
        });
      } else {
        setState(() {
          _view = null;
          _node = null;
          _mode = null;
          _lan = null;
        });
        final view = await widget.load();
        check();
        if (view.status.profileId != profile ||
            view.status.metadata.instanceId !=
                widget.state.snapshot!.runtime.instanceId ||
            view.status.metadata.revision <
                widget.state.snapshot!.status.metadata.revision) {
          throw const FormatException('Stale exit-node projection');
        }
        setState(() => _view = view);
      }
    } catch (_) {
      if (!mounted || !current || context != _context) return;
      setState(() {
        _view = null;
        _node = null;
        _mode = null;
        _lan = null;
        _notice =
            'Exit request could not be confirmed. Recover pending operations before retrying.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final view = _view;
      final viewContext = _context;
      bool validView() =>
          current &&
          !_busy &&
          identical(view, _view) &&
          viewContext == _context;
      final node = selected;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('client-load-exits'),
            onPressed: allowed && !_busy ? () => _run() : null,
            child: const Text('Refresh exit nodes'),
          ),
          if (current && _notice != null) Text(_notice!),
          if (current && view != null) ...[
            Text(
              'Requested exit mode: ${view.status.requestedFamilyMode.name}',
            ),
            Text(
              'Exit apply: ${view.status.applyState.name}; failure: ${view.status.failure.code.name}',
            ),
            for (final entry in [
              ('IPv4', view.status.ipv4),
              ('IPv6', view.status.ipv6),
            ]) ...[
              Text(
                '${entry.$1}: requested ${entry.$2.hasRequestedExitNodeId() ? entry.$2.requestedExitNodeId : 'No exit'}; '
                'effective ${entry.$2.hasEffectiveExitNodeId() ? entry.$2.effectiveExitNodeId : 'No exit'}',
              ),
              Text(
                '${entry.$1}: ${entry.$2.applyState.name}; reported fail-closed: ${entry.$2.failClosed}; '
                'failure: ${entry.$2.failure.code.name}',
              ),
              if (!entry.$2.hasRequestedExitNodeId())
                Text(
                  'No exit is requested for ${entry.$1}; see effective state for current routing.',
                ),
            ],
            Text(
              'LAN requested: ${view.status.requestedLanAccess.name}; effective: ${view.status.effectiveLanAccess.name}',
            ),
            Text(
              'Exit control: ${view.status.control.mutation.availability.name}; locked: ${view.status.control.locked}; '
              'reason: ${view.status.control.mutation.reasonKey}; owner: ${view.status.control.mutation.actionOwner.name}',
            ),
            DropdownButton<String>(
              key: const Key('client-exit-node'),
              isExpanded: true,
              value: _node,
              hint: const Text('Choose exit node'),
              items: [
                for (final candidate in view.nodes)
                  DropdownMenuItem(
                    value: candidate.id,
                    enabled:
                        candidate.selection.availability ==
                        api.Availability.AVAILABILITY_AVAILABLE,
                    child: Text(
                      '${candidate.displayName}: ${candidate.selection.availability.name}',
                    ),
                  ),
              ],
              onChanged: editable && !_busy
                  ? (id) {
                      if (!validView() ||
                          !view.nodes.any(
                            (n) =>
                                n.id == id &&
                                n.selection.availability ==
                                    api.Availability.AVAILABILITY_AVAILABLE,
                          )) {
                        return;
                      }
                      setState(() {
                        _node = id;
                        _mode = null;
                        _lan = null;
                        _confirmClear = false;
                      });
                    }
                  : null,
            ),
            if (node != null) ...[
              DropdownButton<api.ExitFamilyMode>(
                key: const Key('client-exit-mode'),
                isExpanded: true,
                value: _mode,
                hint: const Text('Choose address families'),
                items: [
                  for (final mode in node.allowedFamilyModes)
                    DropdownMenuItem(value: mode, child: Text(mode.name)),
                ],
                onChanged: editable && !_busy
                    ? (mode) {
                        if (validView() &&
                            selected == node &&
                            node.allowedFamilyModes.contains(mode)) {
                          setState(() => _mode = mode);
                        }
                      }
                    : null,
              ),
              DropdownButton<api.LanAccess>(
                key: const Key('client-exit-lan'),
                isExpanded: true,
                value: _lan,
                hint: const Text('Choose LAN policy'),
                items: [
                  for (final lan in node.allowedLanAccess)
                    DropdownMenuItem(value: lan, child: Text(lan.name)),
                ],
                onChanged: editable && !_busy
                    ? (lan) {
                        if (validView() &&
                            selected == node &&
                            node.allowedLanAccess.contains(lan)) {
                          setState(() => _lan = lan);
                        }
                      }
                    : null,
              ),
            ],
            if (_mode == api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY)
              const Text('IPv6 will not be protected by this exit selection.'),
            if (_mode == api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY)
              const Text('IPv4 will not be protected by this exit selection.'),
            FilledButton(
              key: const Key('client-select-exit'),
              onPressed: canSelect && !_busy
                  ? () {
                      if (validView()) _run(select: true);
                    }
                  : null,
              child: const Text('Select exit node'),
            ),
            OutlinedButton(
              key: const Key('client-clear-exit'),
              onPressed: editable && !_busy
                  ? () {
                      if (validView()) setState(() => _confirmClear = true);
                    }
                  : null,
              child: const Text('Clear exit node'),
            ),
            if (_confirmClear) ...[
              const Text(
                'Clear both exit families and restore ordinary routing policy?',
              ),
              TextButton(
                key: const Key('client-cancel-clear-exit'),
                onPressed: !_busy
                    ? () {
                        if (validView()) setState(() => _confirmClear = false);
                      }
                    : null,
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('client-confirm-clear-exit'),
                onPressed: editable && !_busy
                    ? () {
                        if (validView()) _run(clear: true);
                      }
                    : null,
                child: const Text('Confirm clear'),
              ),
            ],
          ],
        ],
      );
    },
  );
}
