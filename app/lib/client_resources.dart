import 'dart:convert';
import 'package:endlessnet_client_api/client_api.dart' as api;

final class ClientResourceCatalog {
  ClientResourceCatalog._(
    this.profileId,
    this.search,
    this.kinds,
    this.resources,
    this.metadata,
  );
  final String profileId;
  final String search;
  final List<api.ResourceKind> kinds;
  final List<api.Resource> resources;
  final api.SnapshotMetadata metadata;
}

/// Search and authorization belong to the producer. This reader never probes
/// targets or resolves overlap IDs, which may be outside the filtered result.
Future<ClientResourceCatalog> readClientResources(
  Future<api.ListResourcesResponse> Function(api.ListResourcesRequest) read, {
  required String instanceId,
  required String profileId,
  String search = '',
  List<api.ResourceKind> kinds = const [],
  required void Function() checkContext,
}) async {
  final filter = List<api.ResourceKind>.unmodifiable(kinds);
  const targets = {
    api.ResourceKind.RESOURCE_KIND_HOST: api.Resource_Target.host,
    api.ResourceKind.RESOURCE_KIND_SUBNET: api.Resource_Target.subnet,
    api.ResourceKind.RESOURCE_KIND_SERVICE: api.Resource_Target.service,
    api.ResourceKind.RESOURCE_KIND_APPLICATION: api.Resource_Target.application,
  };
  bool id(String value) => value.isNotEmpty && utf8.encode(value).length <= 256;
  if (instanceId.isEmpty ||
      !id(profileId) ||
      utf8.encode(search).length > 256 ||
      filter.toSet().length != filter.length ||
      filter.any((kind) => !targets.containsKey(kind))) {
    throw const FormatException('Invalid resource query');
  }
  final resources = <api.Resource>[];
  final ids = <String>{};
  final tokens = <String>{};
  api.SnapshotMetadata? metadata;
  var token = '';
  do {
    if (!tokens.add(token) || tokens.length > 4096) {
      throw const FormatException('Invalid resource pagination');
    }
    checkContext();
    final response = await read(
      api.ListResourcesRequest(
        profile: api.ProfileRef(profileId: profileId),
        search: search,
        kinds: filter,
        page: api.PageRequest(pageSize: 100, pageToken: token),
      )..freeze(),
    );
    checkContext();
    final page = response.page;
    if (!response.hasPage() ||
        !page.hasMetadata() ||
        page.metadata.instanceId != instanceId ||
        page.metadata.revision <= 0 ||
        (metadata != null && page.metadata.revision != metadata.revision) ||
        response.resources.length > 100) {
      throw const FormatException('Inconsistent resource catalog context');
    }
    metadata ??= api.SnapshotMetadata.fromBuffer(page.metadata.writeToBuffer())
      ..freeze();
    for (final resource in response.resources) {
      if (!id(resource.id) ||
          !ids.add(resource.id) ||
          !id(resource.networkId) ||
          resource.displayName.isEmpty ||
          utf8.encode(resource.displayName).length > 128 ||
          !targets.containsKey(resource.kind) ||
          resource.whichTarget() != targets[resource.kind] ||
          (filter.isNotEmpty && !filter.contains(resource.kind)) ||
          resource.overlappingResourceIds.any((value) => !id(value))) {
        throw const FormatException('Invalid resource catalog entry');
      }
      resources.add(
        api.Resource.fromBuffer(resource.writeToBuffer())..freeze(),
      );
    }
    token = page.nextPageToken;
  } while (token.isNotEmpty);
  checkContext();
  return ClientResourceCatalog._(
    profileId,
    search,
    filter,
    List.unmodifiable(resources),
    metadata,
  );
}
