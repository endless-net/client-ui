import 'dart:async';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:grpc/grpc.dart';

/// UI-owned synthetic wire fixture, never imported by production code.
/// It does not implement OS authentication, VPN, policy or runtime persistence.
class LoopbackContractServer extends api.ClientServiceBase {
  LoopbackContractServer({required this.requestId, required this.beforeAccept});
  final String requestId;
  final Future<void> Function() beforeAccept;
  final calls = <String>[];
  final violations = <String>[];
  final events = StreamController<api.WatchEventsResponse>();

  api.RuntimeInfo get runtime => api.RuntimeInfo(
    protocol: api.ClientContract.protocol,
    ipcVersion: api.ClientContract.version,
    contractSha256: api.ClientContract.sha256,
    instanceId: 'mock-runtime',
    callerAccess: api.Access.ACCESS_OWNER,
  );
  api.Status status(int revision, api.ConnectionPhase phase) =>
      api.Status()..mergeFromProto3Json({
        'metadata': {'instanceId': 'mock-runtime', 'revision': '$revision'},
        'activeProfileId': 'profile-a',
        'connectionPhase': phase.name,
      });

  void _check(bool condition, String message) {
    if (condition) return;
    violations.add(message);
    throw const GrpcError.failedPrecondition('Synthetic request mismatch');
  }

  void _record(ServiceCall call, String method) {
    calls.add(method);
    // Pairing metadata is mandatory after the bootstrap call.
    if (method == 'GetRuntimeInfo') return;
    for (final entry in api.ClientContract.metadata.entries) {
      _check(
        call.clientMetadata?[entry.key] == entry.value,
        'Pairing metadata: ${entry.key}',
      );
    }
  }

  @override
  Future<api.GetRuntimeInfoResponse> getRuntimeInfo(
    ServiceCall call,
    api.GetRuntimeInfoRequest request,
  ) async {
    _record(call, 'GetRuntimeInfo');
    _check(request.writeToBuffer().isEmpty, 'Nonempty bootstrap request');
    return api.GetRuntimeInfoResponse(runtime: runtime);
  }

  @override
  Stream<api.WatchEventsResponse> watchEvents(
    ServiceCall call,
    api.WatchEventsRequest request,
  ) async* {
    _record(call, 'WatchEvents');
    _check(request.writeToBuffer().isEmpty, 'Unexpected stream cursor');
    yield api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '1',
      'metadata': {'instanceId': 'mock-runtime', 'revision': '7'},
      'snapshot': {
        'runtime': runtime.toProto3Json(),
        'status': status(
          7,
          api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
        ).toProto3Json(),
      },
    });
    yield* events.stream;
  }

  api.Operation operation({required bool terminal}) => api.Operation()
    ..mergeFromProto3Json({
      'id': 'mock-operation',
      'requestId': requestId,
      'profileId': 'profile-a',
      'kind': 'OPERATION_KIND_CONNECT',
      'state': terminal
          ? 'OPERATION_STATE_SUCCEEDED'
          : 'OPERATION_STATE_PENDING',
      if (terminal) 'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
      if (terminal) 'change': {'changed': true},
    });

  @override
  Future<api.ConnectResponse> connect(
    ServiceCall call,
    api.ConnectRequest request,
  ) async {
    _record(call, 'Connect');
    _check(calls.where((v) => v == 'Connect').length == 1, 'Duplicate Connect');
    _check(request.profile.profileId == 'profile-a', 'Profile mismatch');
    _check(
      request.mutation.requestId == requestId &&
          request.mutation.expectedInstanceId == 'mock-runtime' &&
          request.mutation.expectedRevision.toInt() == 7,
      'Mutation context mismatch',
    );
    await beforeAccept();
    return api.ConnectResponse(operation: operation(terminal: false));
  }

  @override
  Future<api.GetOperationResponse> getOperation(
    ServiceCall call,
    api.GetOperationRequest request,
  ) async {
    _record(call, 'GetOperation');
    _check(
      request.requestId == requestId && request.operationId.isEmpty,
      'Recovery identity mismatch',
    );
    return api.GetOperationResponse(operation: operation(terminal: true));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    violations.add('Unexpected method ${invocation.memberName}');
    throw const GrpcError.unimplemented('Not part of the synthetic scenario');
  }
}
