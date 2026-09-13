import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_networks.dart';
import 'client_operation.dart';
import 'client_state_controller.dart';

class ClientNetworksPanel extends StatefulWidget {
  const ClientNetworksPanel({
    super.key,
    required this.state,
    required this.load,
    required this.select,
  });
  final ClientStateController state;
  final Future<ClientNetworkCatalog> Function() load;
  final Future<ClientOperation> Function(String profileId, String networkId)
  select;
  @override
  State<ClientNetworksPanel> createState() => _ClientNetworksPanelState();
}

class _ClientNetworksPanelState extends State<ClientNetworksPanel> {
  ClientNetworkCatalog? _catalog;
  int? _epoch;
  int? _domain;
  bool _busy = false;
  String? _notice;
  bool get _owner =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty;
  bool get _current =>
      _owner &&
      _epoch == widget.state.cacheEpoch &&
      _domain == widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS);

  Future<void> _run([String? id]) async {
    if (_busy || !_owner) return;
    if (id != null &&
        (!_current ||
            _catalog == null ||
            !_catalog!.networks.any(
              (n) =>
                  n.id == id &&
                  id != _catalog!.selectedNetworkId &&
                  n.selection.availability ==
                      api.Availability.AVAILABILITY_AVAILABLE,
            ))) {
      return;
    }
    final profileId = widget.state.snapshot!.status.activeProfileId;
    setState(() {
      _epoch = widget.state.cacheEpoch;
      _domain = widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS);
      _busy = true;
      _notice = null;
      _catalog = null;
    });
    try {
      if (id == null) {
        final catalog = await widget.load();
        if (!mounted || !_current || catalog.profileId != profileId) return;
        setState(() => _catalog = catalog);
      } else {
        final operation = await widget.select(profileId, id);
        if (!mounted || !_current) return;
        setState(
          () => _notice = operation.terminal
              ? 'Network selection result received. Refresh runtime status.'
              : 'Network selection accepted. Recover the operation for its result.',
        );
      }
    } catch (_) {
      if (!mounted || !_current) return;
      setState(
        () => _notice =
            'Network request could not be confirmed. Recover any pending selection before retrying.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const Key('client-load-networks'),
          onPressed: _owner && !_busy ? () => _run() : null,
          child: const Text('Refresh networks'),
        ),
        if (_current && _notice != null) Text(_notice!),
        if (_current && _catalog != null) ...[
          if (_catalog!.networks.isEmpty) const Text('No networks'),
          for (final network in _catalog!.networks)
            ListTile(
              title: Text(network.name),
              subtitle: Text(network.id),
              trailing: network.id == _catalog!.selectedNetworkId
                  ? const Text('Selected')
                  : TextButton(
                      key: ValueKey('select-network-${network.id}'),
                      onPressed:
                          !_busy &&
                              network.selection.availability ==
                                  api.Availability.AVAILABILITY_AVAILABLE
                          ? () => _run(network.id)
                          : null,
                      child: const Text('Select'),
                    ),
            ),
        ],
      ],
    ),
  );
}
