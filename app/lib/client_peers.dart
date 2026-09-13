import 'dart:convert';

import 'package:endlessnet_client_api/client_api.dart' as api;

final class ClientPeerCatalog {
  ClientPeerCatalog._(
    this.profileId,
    this.search,
    this.peers,
    this.metadata,
    this.snapshotState,
    this._projection,
  );

  final String profileId;
  final String search;
  final List<api.Peer> peers;
  final api.SnapshotMetadata metadata;
  final api.AgentSnapshotState snapshotState;
  final api.ListPeersResponse _projection;
  // Keep the SDK's exact integer types without a direct dependency on its
  // implementation package. These expression getters infer their SDK types.
  // ignore: strict_top_level_inference
  get mapRevision => _projection.mapRevision;
  // ignore: strict_top_level_inference
  get targetMapRevision => _projection.targetMapRevision;
}

/// One immutable, producer-filtered projection. Addresses and path health are
/// observations, never instructions to probe a peer or infer reachability.
Future<ClientPeerCatalog> readClientPeers(
  Future<api.ListPeersResponse> Function(api.ListPeersRequest) read, {
  required String instanceId,
  required String profileId,
  String search = '',
}) async {
  if (instanceId.isEmpty ||
      profileId.isEmpty ||
      utf8.encode(profileId).length > 256 ||
      utf8.encode(search).length > 256) {
    throw const FormatException('Invalid peer catalog context');
  }
  final peers = <api.Peer>[];
  final ids = <String>{};
  final tokens = <String>{};
  api.ListPeersResponse? first;
  var token = '';
  do {
    if (!tokens.add(token) || tokens.length > 4096) {
      throw const FormatException('Invalid peer pagination');
    }
    final response = api.ListPeersResponse.fromBuffer(
      (await read(
        api.ListPeersRequest(
          profile: api.ProfileRef(profileId: profileId),
          page: api.PageRequest(pageSize: 100, pageToken: token),
          search: search,
        )..freeze(),
      )).writeToBuffer(),
    )..freeze();
    if (!response.hasPage() ||
        !response.page.hasMetadata() ||
        response.page.metadata.instanceId != instanceId ||
        response.page.metadata.revision <= 0 ||
        response.peers.length > 100 ||
        peers.length + response.peers.length > 4096 ||
        utf8.encode(response.page.nextPageToken).length > 2048 ||
        (response.peers.isEmpty && response.page.nextPageToken.isNotEmpty) ||
        (first != null &&
            (first.page.metadata.revision != response.page.metadata.revision ||
                first.snapshotState != response.snapshotState ||
                first.mapRevision != response.mapRevision ||
                first.targetMapRevision != response.targetMapRevision))) {
      throw const FormatException('Inconsistent peer catalog projection');
    }
    first ??= response;
    for (final peer in response.peers) {
      if (peer.id.isEmpty ||
          utf8.encode(peer.id).length > 256 ||
          !ids.add(peer.id)) {
        throw const FormatException('Invalid peer catalog entry');
      }
      peers.add(peer);
    }
    token = response.page.nextPageToken;
  } while (token.isNotEmpty);
  return ClientPeerCatalog._(
    profileId,
    search,
    List.unmodifiable(peers),
    first.page.metadata,
    first.snapshotState,
    first,
  );
}
