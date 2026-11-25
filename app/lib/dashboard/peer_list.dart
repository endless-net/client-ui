import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import '../client/call_failure.dart';
import '../client/connectivity_client.dart';

class NetworkPeerList extends StatefulWidget {
  const NetworkPeerList({
    super.key,
    required this.client,
    required this.timeout,
    required this.status,
  });

  final PeerClient client;
  final Duration timeout;
  final api.Status status;

  @override
  State<NetworkPeerList> createState() => _NetworkPeerListState();
}

class _NetworkPeerListState extends State<NetworkPeerList> {
  final _peers = <api.Peer>[];
  var _nextPage = '';
  var _loading = true;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(''));
  }

  Future<void> _load(String token) async {
    final snapshot = widget.status;
    try {
      final response = await widget.client
          .listPeers(
            api.ListPeersRequest(
              profile: api.ProfileRef(profileId: snapshot.activeProfileId),
              page: api.PageRequest(pageToken: token),
            ),
            widget.timeout,
          )
          .timeout(widget.timeout);
      if (!mounted) return;
      if (response.snapshotState !=
              api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT ||
          response.mapRevision != snapshot.agent.mapRevision ||
          response.targetMapRevision != snapshot.agent.targetMapRevision ||
          response.page.metadata.instanceId != snapshot.metadata.instanceId ||
          BigInt.parse(response.page.metadata.revision.toStringUnsigned())
                  .compareTo(
                    BigInt.parse(snapshot.metadata.revision.toStringUnsigned()),
                  ) <
              0 ||
          (token.isNotEmpty && response.page.nextPageToken == token)) {
        throw ClientCallFailure.protocol();
      }
      setState(() {
        _peers.addAll(response.peers);
        _nextPage = response.page.nextPageToken;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _peers.clear();
        _nextPage = '';
        _loading = false;
        _failed = true;
      });
    }
  }

  void _request(String token) {
    setState(() {
      _failed = false;
      _loading = true;
    });
    unawaited(_load(token));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Устройства активной сети EndlessNet',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      for (final peer in _peers)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(peer.hostname.isEmpty ? peer.id : peer.hostname),
            subtitle: peer.overlayAddresses.isEmpty
                ? null
                : Text(peer.overlayAddresses.join(', ')),
          ),
        ),
      if (_loading)
        const LinearProgressIndicator()
      else if (_failed) ...[
        const Text('Не удалось получить список устройств сети.'),
        TextButton(
          onPressed: () => _request(''),
          child: const Text('Повторить'),
        ),
      ] else if (_peers.isEmpty)
        const Text('Вам пока недоступны другие устройства в этой сети.')
      else if (_nextPage.isNotEmpty)
        TextButton(
          onPressed: () => _request(_nextPage),
          child: const Text('Показать ещё'),
        ),
    ],
  );
}
