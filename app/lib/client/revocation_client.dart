import 'package:endlessnet_client_api/client_api.dart' as api;

abstract interface class RevocationClient {
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout);
  Future<api.Status> status(Duration timeout);
  Future<api.ListNodeRevocationTargetsResponse> revocationTargets(
    api.ListNodeRevocationTargetsRequest request,
    Duration timeout,
  );
  Future<api.NodeRevocationResult> revokeNode(
    api.RevokeNodeAccessRequest request,
    Duration timeout,
  );
  Future<api.NodeRevocationResult> nodeRevocation(
    api.GetNodeRevocationRequest request,
    Duration timeout,
  );
}
