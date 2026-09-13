import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:grpc/grpc.dart';

/// Strict, single-call UI wire fixture. Scripted envelopes are not runtime
/// business effects, authorization, protected IPC, or OS acceptance evidence.
class MutationWireServer extends api.ClientServiceBase {
  MutationWireServer({
    required this.method,
    required this.requestBytes,
    required this.response,
  });
  final String method;
  final List<int> requestBytes;
  final api.Operation response;
  final calls = <String>[];
  final violations = <String>[];

  api.Operation _accept(ServiceCall call, String name, List<int> bytes) {
    calls.add(name);
    if (name != method || calls.length != 1) {
      violations.add('Unexpected or duplicate mutation');
    }
    if (bytes.length != requestBytes.length ||
        Iterable<int>.generate(
          bytes.length,
        ).any((i) => bytes[i] != requestBytes[i])) {
      violations.add('Request payload changed');
    }
    for (final entry in api.ClientContract.metadata.entries) {
      if (call.clientMetadata?[entry.key] != entry.value) {
        violations.add('Pairing metadata mismatch');
      }
    }
    if (violations.isNotEmpty) {
      throw const GrpcError.failedPrecondition('Synthetic fixture mismatch');
    }
    return response;
  }

  @override
  Future<api.EnrollResponse> enroll(
    ServiceCall call,
    api.EnrollRequest request,
  ) async => api.EnrollResponse(
    operation: _accept(call, 'Enroll', request.writeToBuffer()),
  );

  @override
  Future<api.ConnectResponse> connect(
    ServiceCall call,
    api.ConnectRequest request,
  ) async => api.ConnectResponse(
    operation: _accept(call, 'Connect', request.writeToBuffer()),
  );

  @override
  Future<api.DisconnectResponse> disconnect(
    ServiceCall call,
    api.DisconnectRequest request,
  ) async => api.DisconnectResponse(
    operation: _accept(call, 'Disconnect', request.writeToBuffer()),
  );

  @override
  Future<api.TrustServerIdentityResponse> trustServerIdentity(
    ServiceCall call,
    api.TrustServerIdentityRequest request,
  ) async => api.TrustServerIdentityResponse(
    operation: _accept(call, 'TrustServerIdentity', request.writeToBuffer()),
  );

  @override
  Future<api.LogoutResponse> logout(
    ServiceCall call,
    api.LogoutRequest request,
  ) async => api.LogoutResponse(
    operation: _accept(call, 'Logout', request.writeToBuffer()),
  );

  @override
  Future<api.ForgetLocalEnrollmentResponse> forgetLocalEnrollment(
    ServiceCall call,
    api.ForgetLocalEnrollmentRequest request,
  ) async => api.ForgetLocalEnrollmentResponse(
    operation: _accept(call, 'ForgetLocalEnrollment', request.writeToBuffer()),
  );

  @override
  Future<api.SelectNetworkResponse> selectNetwork(
    ServiceCall call,
    api.SelectNetworkRequest request,
  ) async => api.SelectNetworkResponse(
    operation: _accept(call, 'SelectNetwork', request.writeToBuffer()),
  );

  @override
  Future<api.CreateDiagnosticsBundleResponse> createDiagnosticsBundle(
    ServiceCall call,
    api.CreateDiagnosticsBundleRequest request,
  ) async => api.CreateDiagnosticsBundleResponse(
    operation: _accept(
      call,
      'CreateDiagnosticsBundle',
      request.writeToBuffer(),
    ),
  );

  @override
  Future<api.CreateProfileResponse> createProfile(
    ServiceCall call,
    api.CreateProfileRequest request,
  ) async => api.CreateProfileResponse(
    operation: _accept(call, 'CreateProfile', request.writeToBuffer()),
  );

  @override
  Future<api.SelectProfileResponse> selectProfile(
    ServiceCall call,
    api.SelectProfileRequest request,
  ) async => api.SelectProfileResponse(
    operation: _accept(call, 'SelectProfile', request.writeToBuffer()),
  );

  @override
  Future<api.RenameProfileResponse> renameProfile(
    ServiceCall call,
    api.RenameProfileRequest request,
  ) async => api.RenameProfileResponse(
    operation: _accept(call, 'RenameProfile', request.writeToBuffer()),
  );

  @override
  Future<api.RemoveProfileResponse> removeProfile(
    ServiceCall call,
    api.RemoveProfileRequest request,
  ) async => api.RemoveProfileResponse(
    operation: _accept(call, 'RemoveProfile', request.writeToBuffer()),
  );

  @override
  Future<api.RenewSessionResponse> renewSession(
    ServiceCall call,
    api.RenewSessionRequest request,
  ) async => api.RenewSessionResponse(
    operation: _accept(call, 'RenewSession', request.writeToBuffer()),
  );

  @override
  Future<api.SelectExitNodeResponse> selectExitNode(
    ServiceCall call,
    api.SelectExitNodeRequest request,
  ) async => api.SelectExitNodeResponse(
    operation: _accept(call, 'SelectExitNode', request.writeToBuffer()),
  );

  @override
  Future<api.ClearExitNodeResponse> clearExitNode(
    ServiceCall call,
    api.ClearExitNodeRequest request,
  ) async => api.ClearExitNodeResponse(
    operation: _accept(call, 'ClearExitNode', request.writeToBuffer()),
  );

  @override
  Future<api.SetPreferencesResponse> setPreferences(
    ServiceCall call,
    api.SetPreferencesRequest request,
  ) async => api.SetPreferencesResponse(
    operation: _accept(call, 'SetPreferences', request.writeToBuffer()),
  );

  @override
  Future<api.ResetPreferencesResponse> resetPreferences(
    ServiceCall call,
    api.ResetPreferencesRequest request,
  ) async => api.ResetPreferencesResponse(
    operation: _accept(call, 'ResetPreferences', request.writeToBuffer()),
  );

  @override
  Future<api.SetResourceEnabledResponse> setResourceEnabled(
    ServiceCall call,
    api.SetResourceEnabledRequest request,
  ) async => api.SetResourceEnabledResponse(
    operation: _accept(call, 'SetResourceEnabled', request.writeToBuffer()),
  );

  @override
  Future<api.NotifyLifecycleResponse> notifyLifecycle(
    ServiceCall call,
    api.NotifyLifecycleRequest request,
  ) async => api.NotifyLifecycleResponse(
    operation: _accept(call, 'NotifyLifecycle', request.writeToBuffer()),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    violations.add('Unexpected RPC');
    throw const GrpcError.unimplemented('Outside synthetic mutation scenario');
  }
}
