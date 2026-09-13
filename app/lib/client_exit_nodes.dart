import 'dart:convert';
import 'package:endlessnet_client_api/client_api.dart' as api;

final class ClientExitNodes {
  ClientExitNodes._(this.nodes, this.status);
  final List<api.ExitNode> nodes;
  final api.ExitNodeStatus status;
}

/// One catalog/status revision. No selection, automatic downgrade, retry or
/// fallback is performed, and neither family is synthesized from aggregate data.
Future<ClientExitNodes> readClientExitNodes({
  required String instanceId,
  required String profileId,
  required Future<api.ListExitNodesResponse> Function(api.ListExitNodesRequest)
  list,
  required Future<api.GetExitNodeResponse> Function(api.GetExitNodeRequest) get,
  required void Function() checkContext,
}) async {
  bool id(String value) => value.isNotEmpty && utf8.encode(value).length <= 256;
  if (instanceId.isEmpty || !id(profileId)) {
    throw const FormatException('Invalid exit-node context');
  }
  final nodes = <api.ExitNode>[];
  final ids = <String>{};
  final tokens = <String>{};
  api.SnapshotMetadata? metadata;
  var token = '';
  do {
    if (!tokens.add(token) || tokens.length > 4096) {
      throw const FormatException('Invalid exit-node pagination');
    }
    checkContext();
    final response = await list(
      api.ListExitNodesRequest(
        profile: api.ProfileRef(profileId: profileId),
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
        response.exitNodes.length > 100) {
      throw const FormatException('Inconsistent exit-node catalog');
    }
    metadata ??= api.SnapshotMetadata.fromBuffer(page.metadata.writeToBuffer())
      ..freeze();
    for (final node in response.exitNodes) {
      if (!id(node.id) ||
          !ids.add(node.id) ||
          node.displayName.isEmpty ||
          utf8.encode(node.displayName).length > 128 ||
          !id(node.peerId) ||
          node.allowedFamilyModes.any(
            (mode) =>
                mode == api.ExitFamilyMode.EXIT_FAMILY_MODE_UNSPECIFIED ||
                mode == api.ExitFamilyMode.EXIT_FAMILY_MODE_NONE,
          ) ||
          node.allowedFamilyModes.toSet().length !=
              node.allowedFamilyModes.length ||
          node.allowedLanAccess.any(
            (access) => access == api.LanAccess.LAN_ACCESS_UNSPECIFIED,
          ) ||
          node.allowedLanAccess.toSet().length !=
              node.allowedLanAccess.length) {
        throw const FormatException('Invalid exit-node entry');
      }
      nodes.add(api.ExitNode.fromBuffer(node.writeToBuffer())..freeze());
    }
    token = page.nextPageToken;
  } while (token.isNotEmpty);
  checkContext();
  final response = await get(
    api.GetExitNodeRequest(profile: api.ProfileRef(profileId: profileId)),
  );
  checkContext();
  final status = response.status;
  if (!response.hasStatus() ||
      !status.hasMetadata() ||
      status.metadata.instanceId != instanceId ||
      status.metadata.revision != metadata.revision ||
      status.profileId != profileId ||
      !status.hasIpv4() ||
      !status.hasIpv6() ||
      status.requestedFamilyMode ==
          api.ExitFamilyMode.EXIT_FAMILY_MODE_UNSPECIFIED ||
      status.applyState == api.ApplyState.APPLY_STATE_UNSPECIFIED ||
      (status.hasRequestedExitNodeId() && !id(status.requestedExitNodeId)) ||
      (status.hasEffectiveExitNodeId() && !id(status.effectiveExitNodeId))) {
    throw const FormatException('Invalid exit-node status');
  }
  for (final family in [status.ipv4, status.ipv6]) {
    if (family.applyState == api.ApplyState.APPLY_STATE_UNSPECIFIED ||
        (family.hasRequestedExitNodeId() && !id(family.requestedExitNodeId)) ||
        (family.hasEffectiveExitNodeId() && !id(family.effectiveExitNodeId)) ||
        (family.applyState == api.ApplyState.APPLY_STATE_FAILED &&
            (!family.hasFailure() ||
                family.failure.code == api.ErrorCode.ERROR_CODE_UNSPECIFIED))) {
      throw const FormatException('Invalid exit address-family status');
    }
  }
  if (status.applyState == api.ApplyState.APPLY_STATE_FAILED &&
      (!status.hasFailure() ||
          status.failure.code == api.ErrorCode.ERROR_CODE_UNSPECIFIED)) {
    throw const FormatException('Exit apply failure lacks typed reason');
  }
  // A missing selected catalog entry can be valid after path loss or policy
  // changes. Keep authoritative status; never substitute a different node.
  return ClientExitNodes._(
    List.unmodifiable(nodes),
    api.ExitNodeStatus.fromBuffer(status.writeToBuffer())..freeze(),
  );
}
