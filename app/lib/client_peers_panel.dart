import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_peers.dart';
import 'client_state_controller.dart';

class ClientPeersPanel extends StatefulWidget {
  const ClientPeersPanel({super.key, required this.state, required this.load});
  final ClientStateController state;
  final Future<ClientPeerCatalog> Function(String search) load;

  @override
  State<ClientPeersPanel> createState() => _ClientPeersPanelState();
}

class _ClientPeersPanelState extends State<ClientPeersPanel> {
  final _search = TextEditingController();
  ClientPeerCatalog? _catalog;
  String? _notice;
  late String _context;
  var _serial = 0;
  var _busy = false;

  bool get _allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty;

  String get _key =>
      '${widget.state.cacheEpoch}:$_allowed:'
      '${widget.state.domainEpoch(api.Domain.DOMAIN_PEERS)}:'
      '${widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS)}:'
      '${widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES)}';

  void _reset() {
    _serial++;
    _catalog = null;
    _notice = null;
    _busy = false;
  }

  void _changed() {
    if (_context == _key) return;
    setState(() {
      _context = _key;
      _reset();
      _search.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _context = _key;
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientPeersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _context = _key;
      _reset();
      _search.clear();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed || _busy) return;
    final key = _key;
    final query = _search.text;
    final serial = ++_serial;
    setState(() {
      _busy = true;
      _catalog = null;
      _notice = null;
    });
    bool current() =>
        mounted &&
        _allowed &&
        key == _key &&
        serial == _serial &&
        query == _search.text;
    try {
      final result = await widget.load(query);
      if (!current()) return;
      final snapshot = widget.state.snapshot!;
      if (result.search != query ||
          result.profileId != snapshot.status.activeProfileId ||
          result.metadata.instanceId != snapshot.runtime.instanceId ||
          result.metadata.revision < snapshot.status.metadata.revision) {
        throw StateError('Stale peer catalog');
      }
      setState(() => _catalog = result);
    } catch (_) {
      if (current()) {
        setState(
          () => _notice =
              'Peer information could not be confirmed. Refresh to try again.',
        );
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Peers'),
      TextField(
        key: const Key('client-peer-search'),
        controller: _search,
        enabled: _allowed,
        decoration: const InputDecoration(labelText: 'Search peers'),
        onChanged: (_) => setState(_reset),
      ),
      OutlinedButton(
        key: const Key('client-load-peers'),
        onPressed: _allowed && !_busy ? _load : null,
        child: Text(_busy ? 'Loading peers…' : 'Refresh peers'),
      ),
      if (_notice != null) Text(_notice!),
      if (_catalog case final catalog?) ...[
        Text('Snapshot: ${catalog.snapshotState.name}'),
        Text(
          'Applied map: ${catalog.mapRevision}; target map: ${catalog.targetMapRevision}',
        ),
        const Text('Runtime observations; this screen does not probe peers.'),
        if (catalog.peers.isEmpty) const Text('No peers in this response.'),
        for (final peer in catalog.peers)
          ExpansionTile(
            key: ValueKey('client-peer-${peer.id}'),
            title: Text(peer.hostname.isEmpty ? peer.id : peer.hostname),
            subtitle: Text(
              'ID: ${peer.id}\nSelected path: ${peer.selectedPath.name}',
            ),
            children: [
              Text('Overlay addresses: ${peer.overlayAddresses.join(', ')}'),
              Text(
                'Selected endpoint: ${peer.selectedEndpoint.isEmpty ? 'not reported' : peer.selectedEndpoint}',
              ),
              Text(
                'Selection reason: ${peer.selectionReasonKey.isEmpty ? 'not reported' : peer.selectionReasonKey}',
              ),
              Text(
                'Last transition: ${peer.hasLastTransitionAt() ? peer.lastTransitionAt.toProto3Json() : 'not reported'}',
              ),
              if (peer.candidates.isEmpty)
                const Text('No path candidates reported.'),
              for (final candidate in peer.candidates)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Candidate: ${candidate.kind.name}; ${candidate.health.name}\n'
                    'Endpoint: ${candidate.endpoint}; relay: ${candidate.relayId}\n'
                    'Protocol: ${candidate.protocol}; tier: ${candidate.tier}; priority: ${candidate.priority}\n'
                    'RTT: ${candidate.hasRtt() ? candidate.rtt.toProto3Json() : 'not reported'}\n'
                    'Checked: ${candidate.hasCheckedAt() ? candidate.checkedAt.toProto3Json() : 'not reported'}\n'
                    'Last reachable: ${candidate.hasLastReachableAt() ? candidate.lastReachableAt.toProto3Json() : 'not reported'}\n'
                    'Consecutive failures: ${candidate.consecutiveFailures}; reason: ${candidate.reasonKey}',
                  ),
                ),
            ],
          ),
      ],
    ],
  );
}
