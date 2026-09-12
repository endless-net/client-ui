import 'dart:convert';

import 'package:endlessnet_client_api/client_api.dart' as api;

final class ClientProfileCatalog {
  ClientProfileCatalog._(this.profiles, this.activeProfileId, this.metadata);
  final List<api.Profile> profiles;
  final String activeProfileId;
  final api.SnapshotMetadata metadata;
}

/// A complete, single-revision catalog. Never publishes a partial list or
/// retries stale tokens. The session must additionally guard caller/cache epoch.
Future<ClientProfileCatalog> readClientProfiles(
  Future<api.ListProfilesResponse> Function(api.ListProfilesRequest) read, {
  required String instanceId,
}) async {
  final profiles = <api.Profile>[];
  final ids = <String>{};
  final tokens = <String>{};
  api.SnapshotMetadata? metadata;
  String? active;
  var token = '';
  do {
    if (!tokens.add(token) || tokens.length > 4096) {
      throw const FormatException('Invalid profile pagination');
    }
    final response = await read(
      api.ListProfilesRequest(
        page: api.PageRequest(pageSize: 100, pageToken: token),
      ),
    );
    final page = response.page;
    if (!response.hasPage() ||
        !page.hasMetadata() ||
        instanceId.isEmpty ||
        page.metadata.instanceId != instanceId ||
        page.metadata.revision <= 0 ||
        response.profiles.length > 100 ||
        (metadata != null && page.metadata.revision != metadata.revision) ||
        (active != null && response.activeProfileId != active)) {
      throw const FormatException('Inconsistent profile catalog context');
    }
    metadata ??= api.SnapshotMetadata.fromBuffer(page.metadata.writeToBuffer())
      ..freeze();
    active ??= response.activeProfileId;
    for (final profile in response.profiles) {
      if (profile.id.isEmpty ||
          utf8.encode(profile.id).length > 256 ||
          !ids.add(profile.id) ||
          profile.displayName.isEmpty ||
          utf8.encode(profile.displayName).length > 128 ||
          profile.active != (profile.id == active)) {
        throw const FormatException('Invalid profile catalog entry');
      }
      profiles.add(api.Profile.fromBuffer(profile.writeToBuffer())..freeze());
    }
    token = page.nextPageToken;
  } while (token.isNotEmpty);
  if (active.isNotEmpty && !ids.contains(active)) {
    throw const FormatException('Missing active profile in complete catalog');
  }
  return ClientProfileCatalog._(List.unmodifiable(profiles), active, metadata);
}
