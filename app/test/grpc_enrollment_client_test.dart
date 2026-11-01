import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/grpc_enrollment_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:grpc/service_api.dart' as wire;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart';

// Generated SDK поверх memory channel, не TCP/Windows transport acceptance.
class MemoryChannel implements wire.ClientChannel {
  int calls = 0;
  Duration? timeout;
  Map<String, String>? metadata;
  String? path;
  List<int>? requestBytes;
  bool waitForDeadline = false;
  grpc.ClientCall<dynamic, dynamic>? active;
  late Future<List<int>> Function(String, List<int>) respond;
  @override
  grpc.ClientCall<Q, R> createCall<Q, R>(
    wire.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
  ) {
    calls++;
    timeout = options.timeout;
    metadata = options.metadata;
    path = method.path;
    if (waitForDeadline) {
      final call = grpc.ClientCall<Q, R>(method, requests, options);
      active = call;
      return call;
    }
    return MemoryCall<Q, R>(
      requests.asyncMap((request) async {
        final bytes = method.requestSerializer(request);
        requestBytes = bytes;
        return method.responseDeserializer(await respond(method.path, bytes));
      }),
      options,
    );
  }

  @override
  Future<void> shutdown() async {}
  @override
  Future<void> terminate() async {
    await active?.cancel();
  }

  @override
  Stream<grpc.ConnectionState> get onConnectionStateChanged =>
      const Stream.empty();
}

class MemoryCall<Q, R> implements grpc.ClientCall<Q, R> {
  MemoryCall(this.response, this.options);
  @override
  final Stream<R> response;
  @override
  final grpc.CallOptions options;
  @override
  Future<Map<String, String>> get headers async => {};
  @override
  Future<Map<String, String>> get trailers async => {};
  @override
  Future<void> cancel() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

api.Failure ownerFailure() => api.Failure(
  code: api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
  reasonKey: 'client.owner.required',
  actionOwner: api.ActionOwner.ACTION_OWNER_USER,
);
Any packed(api.Failure value) => Any(
  typeUrl: 'type.googleapis.com/client.v0.Failure',
  value: value.writeToBuffer(),
);

void main() {
  test('identity SDK methods preserve confirmation and never infer trust from acknowledgement', () async {
    final channel = MemoryChannel();
    channel.respond = (path, bytes) async {
      if (path.endsWith('/GetServerIdentity')) {
        return api.GetServerIdentityResponse(
          identity: api.ServerIdentity(
            profileId: 'profile',
            controlOrigin: 'https://control.example',
            announcedKeyId: 'key',
            announcementId: 'announcement',
            changed: true,
          ),
          metadata: api.SnapshotMetadata(instanceId: 'instance'),
        ).writeToBuffer();
      }
      return api.TrustServerIdentityResponse(
        change: api.ChangeResult(changed: false),
      ).writeToBuffer();
    };
    final adapter = GrpcEnrollmentClient(
      api.ClientServiceClient(channel),
      maxFailureBytes: 16384,
    );
    const timeout = Duration(seconds: 2);
    final observed = await adapter.serverIdentity(
      api.GetServerIdentityRequest(
        profile: api.ProfileRef(profileId: 'profile'),
      ),
      timeout,
    );
    expect(channel.path, '/client.v0.ClientService/GetServerIdentity');
    expect(observed.identity.announcementId, 'announcement');
    final request = api.TrustServerIdentityRequest(
      profile: api.ProfileRef(profileId: 'profile'),
      mutation: api.MutationContext(expectedInstanceId: 'instance')
        ..expectedRevision = ~api.SnapshotMetadata().revision,
      confirmedControlOrigin: observed.identity.controlOrigin,
      confirmedKeyId: observed.identity.announcedKeyId,
      confirmedAnnouncementId: observed.identity.announcementId,
    );
    expect((await adapter.trustIdentity(request, timeout)).changed, false);
    expect(channel.path, '/client.v0.ClientService/TrustServerIdentity');
    expect(channel.requestBytes, request.writeToBuffer());
    expect(channel.timeout, timeout);
    expect(channel.metadata, isEmpty);
    expect(channel.calls, 2);
  });
  test(
    'generated SDK carries exact request and deadline with no caller claims',
    () async {
      final channel = MemoryChannel();
      channel.respond = (path, bytes) async {
        if (path.endsWith('/GetRuntimeInfo')) {
          return api.GetRuntimeInfoResponse(
            runtime: api.RuntimeInfo(instanceId: 'fixture'),
          ).writeToBuffer();
        }
        if (path.endsWith('/GetStatus')) {
          return api.GetStatusResponse(
            status: api.Status(activeProfileId: 'profile-A'),
          ).writeToBuffer();
        }
        if (path.endsWith('/Enroll')) {
          return api.EnrollResponse(
            attempt: api.EnrollmentAttempt(requestId: 'original'),
          ).writeToBuffer();
        }
        return api.GetEnrollmentAttemptResponse(
          attempt: api.EnrollmentAttempt(requestId: 'original'),
        ).writeToBuffer();
      };
      final adapter = GrpcEnrollmentClient(
        api.ClientServiceClient(channel),
        maxFailureBytes: 16384,
      );
      const timeout = Duration(seconds: 2);
      expect((await adapter.runtimeInfo(timeout)).instanceId, 'fixture');
      expect((await adapter.status(timeout)).activeProfileId, 'profile-A');
      final request = api.EnrollRequest(
        requestId: 'original',
        hostname: 'host',
        profile: api.ProfileRef(profileId: 'profile-A'),
      );
      await adapter.enroll(request, timeout);
      expect(
        api.EnrollRequest.fromBuffer(channel.requestBytes!).requestId,
        request.requestId,
      );
      expect(channel.path, '/client.v0.ClientService/Enroll');
      await adapter.attempt(
        api.GetEnrollmentAttemptRequest(requestId: 'original'),
        timeout,
      );
      expect(
        api.GetEnrollmentAttemptRequest.fromBuffer(channel.requestBytes!)
            .requestId,
        'original',
      );
      expect(channel.timeout, timeout);
      expect(channel.metadata, isEmpty);
      expect(channel.calls, 4);
    },
  );

  test(
    'target/select/cancel use generated RPCs and preserve mutation binding',
    () async {
      final channel = MemoryChannel();
      channel.respond = (path, bytes) async {
        if (path.endsWith('/ListEnrollmentTargets')) {
          return api.ListEnrollmentTargetsResponse(
            targets: [
              api.EnrollmentTarget(accountId: 'account', networkId: 'network'),
            ],
            metadata: api.SnapshotMetadata(instanceId: 'instance'),
            page: api.PageResponse(
              metadata: api.SnapshotMetadata(instanceId: 'instance'),
              nextPageToken: 'opaque-returned',
            ),
          ).writeToBuffer();
        }
        if (path.endsWith('/SelectEnrollmentTarget')) {
          return api.SelectEnrollmentTargetResponse(
            attempt: api.EnrollmentAttempt(attemptId: 'attempt'),
          ).writeToBuffer();
        }
        return api.CancelEnrollmentAttemptResponse(
          attempt: api.EnrollmentAttempt(attemptId: 'attempt'),
        ).writeToBuffer();
      };
      final adapter = GrpcEnrollmentClient(
        api.ClientServiceClient(channel),
        maxFailureBytes: 16384,
      );
      const timeout = Duration(seconds: 2);
      final page = await adapter.targets(
        api.ListEnrollmentTargetsRequest(
          profile: api.ProfileRef(profileId: 'profile'),
          attemptId: 'attempt',
          page: api.PageRequest(pageSize: 5, pageToken: 'opaque-sent'),
        ),
        timeout,
      );
      expect(channel.path, '/client.v0.ClientService/ListEnrollmentTargets');
      final sent = api.ListEnrollmentTargetsRequest.fromBuffer(
        channel.requestBytes!,
      );
      expect(sent.page.pageToken, 'opaque-sent');
      expect(sent.page.pageSize, 5);
      expect(page.page.nextPageToken, 'opaque-returned');
      final mutation = api.MutationContext(expectedInstanceId: 'instance')
        ..expectedRevision = ~api.SnapshotMetadata().revision;
      final select = api.SelectEnrollmentTargetRequest(
        mutation: mutation,
        profile: api.ProfileRef(profileId: 'profile'),
        attemptId: 'attempt',
        accountId: 'account',
        networkId: 'network',
      );
      expect((await adapter.select(select, timeout)).attemptId, 'attempt');
      expect(channel.path, '/client.v0.ClientService/SelectEnrollmentTarget');
      expect(channel.requestBytes, select.writeToBuffer());
      final cancel = api.CancelEnrollmentAttemptRequest(
        mutation: mutation,
        profile: api.ProfileRef(profileId: 'profile'),
        attemptId: 'attempt',
      );
      expect((await adapter.cancel(cancel, timeout)).attemptId, 'attempt');
      expect(channel.path, '/client.v0.ClientService/CancelEnrollmentAttempt');
      expect(channel.requestBytes, cancel.writeToBuffer());
      expect(channel.timeout, timeout);
      expect(channel.metadata, isEmpty);
      expect(channel.calls, 3);
    },
  );

  test(
    'real grpc ClientCall deadline cancels in memory without a retry',
    () async {
      final channel = MemoryChannel()..waitForDeadline = true;
      final adapter = GrpcEnrollmentClient(
        api.ClientServiceClient(channel),
        maxFailureBytes: 16384,
      );
      try {
        await adapter.enroll(
          api.EnrollRequest(requestId: 'original'),
          const Duration(milliseconds: 20),
        );
        fail('deadline did not terminate the call');
      } on ClientCallFailure catch (error) {
        expect(error.transportCode, grpc.StatusCode.deadlineExceeded);
        expect(error.definiteRejection, false);
      }
      expect(channel.active!.isCancelled, true);
      expect(channel.calls, 1);
    },
  );

  test('typed Failure is decoded and raw diagnostics discarded', () async {
    const secret = 'must-not-escape-raw-diagnostics';
    final channel = MemoryChannel();
    channel.respond = (_, _) async => throw grpc.GrpcError.custom(
      grpc.StatusCode.permissionDenied,
      secret,
      [packed(ownerFailure())],
      null,
      {'secret': secret},
    );
    final adapter = GrpcEnrollmentClient(
      api.ClientServiceClient(channel),
      maxFailureBytes: 16384,
    );
    try {
      await adapter.enroll(
        api.EnrollRequest(requestId: 'original'),
        const Duration(seconds: 1),
      );
      fail('owner denial missing');
    } on ClientCallFailure catch (error) {
      expect(error.definiteRejection, true);
      expect(error.reasonKey, 'client.owner.required');
      expect(error.failure!.actionOwner, api.ActionOwner.ACTION_OWNER_USER);
      expect(error.toString().contains(secret), false);
      error.failure!.reasonKey = 'changed';
      expect(error.reasonKey, 'client.owner.required');
    }
    expect(channel.calls, 1);
    final ambiguous = ClientCallFailure.fromGrpc(
      grpc.GrpcError.custom(grpc.StatusCode.unavailable, secret, [
        packed(ownerFailure()),
      ]),
      16384,
    );
    expect(ambiguous.definiteRejection, false);
    final duplicate = ClientCallFailure.fromGrpc(
      grpc.GrpcError.custom(grpc.StatusCode.permissionDenied, secret, [
        packed(ownerFailure()),
        packed(ownerFailure()),
      ]),
      16384,
    );
    expect(duplicate.failure, isNull);
  });

  test(
    'missing producer result is unknown and timeout bounds send no call',
    () async {
      final channel = MemoryChannel()
        ..respond = (_, _) async => api.EnrollResponse().writeToBuffer();
      final adapter = GrpcEnrollmentClient(
        api.ClientServiceClient(channel),
        maxFailureBytes: 16384,
      );
      for (final timeout in [Duration.zero, const Duration(seconds: 31)]) {
        await expectLater(
          adapter.enroll(api.EnrollRequest(), timeout),
          throwsArgumentError,
        );
      }
      expect(channel.calls, 0);
      await expectLater(
        adapter.enroll(api.EnrollRequest(), const Duration(seconds: 1)),
        throwsA(
          isA<ClientCallFailure>()
              .having((e) => e.transportCode, 'code', grpc.StatusCode.dataLoss)
              .having((e) => e.definiteRejection, 'definite', false),
        ),
      );
      expect(channel.calls, 1);
    },
  );

  test('oversized direct duplicate cannot select the smaller Failure', () {
    final oversized = ownerFailure()..fieldPaths.add('x' * 200);
    final error = ClientCallFailure.fromGrpc(
      grpc.GrpcError.custom(grpc.StatusCode.permissionDenied, null, [
        ownerFailure(),
        oversized,
      ]),
      128,
    );
    expect(error.failure, isNull);
    expect(error.reasonKey, 'ui.permission_required');
  });

  test('malformed or oversized details never become raw UI reason', () {
    for (final detail in [
      Any(typeUrl: 'type.googleapis.com/client.v0.Failure', value: [255]),
      packed(
        api.Failure(
          code: api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
          reasonKey: 'secret with spaces',
        ),
      ),
      packed(ownerFailure()),
    ]) {
      final error = ClientCallFailure.fromGrpc(
        grpc.GrpcError.custom(grpc.StatusCode.permissionDenied, 'raw-secret', [
          detail,
        ]),
        1,
      );
      expect(error.failure, isNull);
      expect(error.reasonKey, 'ui.permission_required');
    }
  });
}
