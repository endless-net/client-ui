import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_operation.dart';

/// Typed command boundary. The caller persists the request UUID before invoking
/// a method. No automatic retry or UUID replacement happens here; timeout leaves
/// acceptance unknown and must be resolved by recoverByRequestId.
final class ClientMutations {
  ClientMutations(this._client, {required this.instanceId});

  final api.ClientServiceClient _client;
  final String instanceId;

  void _validate(api.MutationContext mutation) {
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(mutation.requestId) ||
        instanceId.isEmpty ||
        mutation.expectedInstanceId != instanceId ||
        mutation.expectedRevision <= 0) {
      throw const FormatException(
        'Invalid mutation identity or snapshot context',
      );
    }
  }

  static ClientOperation validateAcceptance(
    api.Operation operation,
    String requestId,
    api.OperationKind kind,
  ) {
    final result = ClientOperation.fromProto(operation);
    if (result.value.requestId != requestId || result.value.kind != kind) {
      throw const FormatException(
        'Operation does not match submitted intention',
      );
    }
    return result;
  }

  Future<ClientOperation> recoverByRequestId(
    String requestId,
    api.OperationKind kind,
  ) async {
    final response = await _client.getOperation(
      api.GetOperationRequest(requestId: requestId),
    );
    return validateAcceptance(response.operation, requestId, kind);
  }

  Future<ClientOperation> enroll(api.EnrollRequest request) async {
    final copy = api.EnrollRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.enroll(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_ENROLL,
    );
  }

  Future<ClientOperation> connect(api.ConnectRequest request) async {
    final copy = api.ConnectRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.connect(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_CONNECT,
    );
  }

  Future<ClientOperation> disconnect(api.DisconnectRequest request) async {
    final copy = api.DisconnectRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.disconnect(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_DISCONNECT,
    );
  }

  Future<ClientOperation> trustServerIdentity(
    api.TrustServerIdentityRequest request,
  ) async {
    final copy = api.TrustServerIdentityRequest.fromBuffer(
      request.writeToBuffer(),
    )..freeze();
    _validate(copy.mutation);
    final response = await _client.trustServerIdentity(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
    );
  }

  Future<ClientOperation> logout(api.LogoutRequest request) async {
    final copy = api.LogoutRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.logout(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_LOGOUT,
    );
  }

  Future<ClientOperation> forgetLocalEnrollment(
    api.ForgetLocalEnrollmentRequest request,
  ) async {
    final copy = api.ForgetLocalEnrollmentRequest.fromBuffer(
      request.writeToBuffer(),
    )..freeze();
    _validate(copy.mutation);
    final response = await _client.forgetLocalEnrollment(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
    );
  }

  Future<ClientOperation> selectNetwork(
    api.SelectNetworkRequest request,
  ) async {
    final copy = api.SelectNetworkRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.selectNetwork(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_SELECT_NETWORK,
    );
  }

  Future<ClientOperation> createDiagnosticsBundle(
    api.CreateDiagnosticsBundleRequest request,
  ) async {
    final copy = api.CreateDiagnosticsBundleRequest.fromBuffer(
      request.writeToBuffer(),
    )..freeze();
    _validate(copy.mutation);
    final response = await _client.createDiagnosticsBundle(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
    );
  }

  Future<ClientOperation> createProfile(
    api.CreateProfileRequest request,
  ) async {
    final copy = api.CreateProfileRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.createProfile(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_CREATE_PROFILE,
    );
  }

  Future<ClientOperation> selectProfile(
    api.SelectProfileRequest request,
  ) async {
    final copy = api.SelectProfileRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.selectProfile(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_SELECT_PROFILE,
    );
  }

  Future<ClientOperation> renameProfile(
    api.RenameProfileRequest request,
  ) async {
    final copy = api.RenameProfileRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.renameProfile(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_RENAME_PROFILE,
    );
  }

  Future<ClientOperation> removeProfile(
    api.RemoveProfileRequest request,
  ) async {
    final copy = api.RemoveProfileRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.removeProfile(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_REMOVE_PROFILE,
    );
  }

  Future<ClientOperation> renewSession(api.RenewSessionRequest request) async {
    final copy = api.RenewSessionRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.renewSession(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_RENEW_SESSION,
    );
  }

  Future<ClientOperation> selectExitNode(
    api.SelectExitNodeRequest request,
  ) async {
    final copy = api.SelectExitNodeRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.selectExitNode(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
    );
  }

  Future<ClientOperation> clearExitNode(
    api.ClearExitNodeRequest request,
  ) async {
    final copy = api.ClearExitNodeRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.clearExitNode(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
    );
  }

  Future<ClientOperation> setPreferences(
    api.SetPreferencesRequest request,
  ) async {
    final copy = api.SetPreferencesRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.setPreferences(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_SET_PREFERENCES,
    );
  }

  Future<ClientOperation> resetPreferences(
    api.ResetPreferencesRequest request,
  ) async {
    final copy = api.ResetPreferencesRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.resetPreferences(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_RESET_PREFERENCES,
    );
  }

  Future<ClientOperation> setResourceEnabled(
    api.SetResourceEnabledRequest request,
  ) async {
    final copy = api.SetResourceEnabledRequest.fromBuffer(
      request.writeToBuffer(),
    )..freeze();
    _validate(copy.mutation);
    final response = await _client.setResourceEnabled(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_SET_RESOURCE_ENABLED,
    );
  }

  Future<ClientOperation> notifyLifecycle(
    api.NotifyLifecycleRequest request,
  ) async {
    final copy = api.NotifyLifecycleRequest.fromBuffer(request.writeToBuffer())
      ..freeze();
    _validate(copy.mutation);
    final response = await _client.notifyLifecycle(copy);
    return validateAcceptance(
      response.operation,
      copy.mutation.requestId,
      api.OperationKind.OPERATION_KIND_NOTIFY_LIFECYCLE,
    );
  }
}
