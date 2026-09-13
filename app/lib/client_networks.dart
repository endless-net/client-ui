import 'dart:convert';

import 'package:endlessnet_client_api/client_api.dart' as api;

final class ClientNetworkCatalog {
  ClientNetworkCatalog._(
    this.profileId,
    this.networks,
    this.selectedNetworkId,
    this.metadata,
  );
  final String profileId;
  final List<api.Network> networks;
  final String selectedNetworkId;
  final api.SnapshotMetadata metadata;
}

/// Collect one profile's complete catalog. Any inconsistent page fails the
/// entire read; the caller still guards its own snapshot/domain epoch.
Future<ClientNetworkCatalog> readClientNetworks(
  Future<api.ListNetworksResponse> Function(api.ListNetworksRequest) read, {
  required String instanceId,
  required String profileId,
}) async {
  if (instanceId.isEmpty ||
      profileId.isEmpty ||
      utf8.encode(profileId).length > 256) {
    throw const FormatException('Network catalog requires runtime and profile');
  }
  final networks = <api.Network>[];
  final ids = <String>{};
  final tokens = <String>{};
  api.SnapshotMetadata? metadata;
  String? selected;
  var token = '';
  do {
    if (!tokens.add(token) || tokens.length > 4096) {
      throw const FormatException('Invalid network pagination');
    }
    final response = await read(
      api.ListNetworksRequest(
        profile: api.ProfileRef(profileId: profileId),
        page: api.PageRequest(pageSize: 100, pageToken: token),
      ),
    );
    final page = response.page;
    if (!response.hasPage() ||
        !page.hasMetadata() ||
        page.metadata.instanceId != instanceId ||
        page.metadata.revision <= 0 ||
        response.networks.length > 100 ||
        (metadata != null && metadata.revision != page.metadata.revision) ||
        (selected != null && selected != response.selectedNetworkId)) {
      throw const FormatException('Inconsistent network catalog context');
    }
    metadata ??= api.SnapshotMetadata.fromBuffer(page.metadata.writeToBuffer())
      ..freeze();
    selected ??= response.selectedNetworkId;
    for (final network in response.networks) {
      if (network.id.isEmpty ||
          utf8.encode(network.id).length > 256 ||
          !ids.add(network.id)) {
        throw const FormatException('Invalid network catalog entry');
      }
      networks.add(api.Network.fromBuffer(network.writeToBuffer())..freeze());
    }
    token = page.nextPageToken;
  } while (token.isNotEmpty);
  if (selected.isNotEmpty && !ids.contains(selected)) {
    throw const FormatException(
      'Selected network missing from complete catalog',
    );
  }
  return ClientNetworkCatalog._(
    profileId,
    List.unmodifiable(networks),
    selected,
    metadata,
  );
}
