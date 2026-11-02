import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:grpc/grpc.dart' as grpc;

import 'call_failure.dart';
import 'connectivity_client.dart';
import 'enrollment_client.dart';
import 'revocation_client.dart';

// Generated SDK получает уже OS-authenticated pipe channel. Здесь нет TCP,
// channel credentials, server SDK, retry interceptor или transport fallback.
final class GrpcEnrollmentClient
    implements EnrollmentClient, ConnectivityClient, RevocationClient {
  GrpcEnrollmentClient(this._client, {required this.maxFailureBytes}) {
    if (maxFailureBytes <= 0 || maxFailureBytes > 65536) {
      throw ArgumentError('failure budget');
    }
  }
  final api.ClientServiceClient _client;
  final int maxFailureBytes;

  @override
  Future<api.ListNodeRevocationTargetsResponse> revocationTargets(
    api.ListNodeRevocationTargetsRequest request,
    Duration timeout,
  ) => _invoke(
    () => _client.listNodeRevocationTargets(
      api.ListNodeRevocationTargetsRequest.fromBuffer(request.writeToBuffer()),
      options: _options(timeout),
    ),
  );
  @override
  Future<api.NodeRevocationResult> revokeNode(
    api.RevokeNodeAccessRequest request,
    Duration timeout,
  ) async {
    final r = await _invoke(
      () => _client.revokeNodeAccess(
        api.RevokeNodeAccessRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!r.hasResult()) {
      throw ClientCallFailure.protocol();
    }
    return api.NodeRevocationResult.fromBuffer(r.result.writeToBuffer());
  }

  @override
  Future<api.NodeRevocationResult> nodeRevocation(
    api.GetNodeRevocationRequest request,
    Duration timeout,
  ) async {
    final r = await _invoke(
      () => _client.getNodeRevocation(
        api.GetNodeRevocationRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!r.hasResult()) {
      throw ClientCallFailure.protocol();
    }
    return api.NodeRevocationResult.fromBuffer(r.result.writeToBuffer());
  }

  grpc.CallOptions _options(Duration timeout) {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw ArgumentError('Client RPC timeout');
    }
    return grpc.CallOptions(timeout: timeout);
  }

  Future<T> _invoke<T>(grpc.ResponseFuture<T> Function() operation) async {
    try {
      return await operation();
    } on grpc.GrpcError catch (error) {
      throw ClientCallFailure.fromGrpc(error, maxFailureBytes);
    }
  }

  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async {
    final response = await _invoke(
      () => _client.getRuntimeInfo(
        api.GetRuntimeInfoRequest(),
        options: _options(timeout),
      ),
    );
    if (!response.hasRuntime()) throw ClientCallFailure.protocol();
    return api.RuntimeInfo.fromBuffer(response.runtime.writeToBuffer());
  }

  @override
  Future<api.Status> status(Duration timeout) async {
    final response = await _invoke(
      () =>
          _client.getStatus(api.GetStatusRequest(), options: _options(timeout)),
    );
    if (!response.hasStatus()) throw ClientCallFailure.protocol();
    return api.Status.fromBuffer(response.status.writeToBuffer());
  }

  @override
  Future<void> connect(api.ConnectRequest request, Duration timeout) async {
    await _invoke(
      () => _client.connect(
        api.ConnectRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
  }

  @override
  Future<void> disconnect(
    api.DisconnectRequest request,
    Duration timeout,
  ) async {
    await _invoke(
      () => _client.disconnect(
        api.DisconnectRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
  }

  @override
  Future<api.EnrollmentAttempt> enroll(
    api.EnrollRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.enroll(
        api.EnrollRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasAttempt()) throw ClientCallFailure.protocol();
    return api.EnrollmentAttempt.fromBuffer(response.attempt.writeToBuffer());
  }

  @override
  Future<api.EnrollmentAttempt> attempt(
    api.GetEnrollmentAttemptRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.getEnrollmentAttempt(
        api.GetEnrollmentAttemptRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasAttempt()) throw ClientCallFailure.protocol();
    return api.EnrollmentAttempt.fromBuffer(response.attempt.writeToBuffer());
  }

  @override
  Future<api.ListEnrollmentTargetsResponse> targets(
    api.ListEnrollmentTargetsRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.listEnrollmentTargets(
        api.ListEnrollmentTargetsRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasMetadata() ||
        !response.hasPage() ||
        !response.page.hasMetadata()) {
      throw ClientCallFailure.protocol();
    }
    return api.ListEnrollmentTargetsResponse.fromBuffer(
      response.writeToBuffer(),
    );
  }

  @override
  Future<api.EnrollmentAttempt> select(
    api.SelectEnrollmentTargetRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.selectEnrollmentTarget(
        api.SelectEnrollmentTargetRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasAttempt()) throw ClientCallFailure.protocol();
    return api.EnrollmentAttempt.fromBuffer(response.attempt.writeToBuffer());
  }

  @override
  Future<api.EnrollmentAttempt> cancel(
    api.CancelEnrollmentAttemptRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.cancelEnrollmentAttempt(
        api.CancelEnrollmentAttemptRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasAttempt()) throw ClientCallFailure.protocol();
    return api.EnrollmentAttempt.fromBuffer(response.attempt.writeToBuffer());
  }

  @override
  Future<api.GetServerIdentityResponse> serverIdentity(
    api.GetServerIdentityRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.getServerIdentity(
        api.GetServerIdentityRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasIdentity() || !response.hasMetadata()) {
      throw ClientCallFailure.protocol();
    }
    return api.GetServerIdentityResponse.fromBuffer(response.writeToBuffer());
  }

  @override
  Future<api.ChangeResult> trustIdentity(
    api.TrustServerIdentityRequest request,
    Duration timeout,
  ) async {
    final response = await _invoke(
      () => _client.trustServerIdentity(
        api.TrustServerIdentityRequest.fromBuffer(request.writeToBuffer()),
        options: _options(timeout),
      ),
    );
    if (!response.hasChange()) throw ClientCallFailure.protocol();
    return api.ChangeResult.fromBuffer(response.change.writeToBuffer());
  }
}
