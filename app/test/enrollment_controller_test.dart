import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:endlessnet_client_ui/client/enrollment_client.dart';
import 'package:endlessnet_client_ui/enrollment/controller.dart';

const requestId = '00000000-0000-4000-8000-000000000001';
final now = DateTime.utc(2026, 10, 30, 12);
api.Profile profile([String id = 'profile-A']) =>
    api.Profile(id: id, controlOrigin: 'https://control.example');
api.SnapshotMetadata metadata() =>
    api.SnapshotMetadata(instanceId: 'instance-A')
      ..revision = api.SnapshotMetadata().revision + 9007199254740993;
api.EnrollmentAttempt makeAttempt({
  String profileId = 'profile-A',
  api.EnrollmentPhase? phase,
}) => api.EnrollmentAttempt(
  attemptId: 'attempt-A',
  requestId: requestId,
  profileId: profileId,
  metadata: metadata(),
  createdAt: Timestamp.fromDateTime(now),
  deadline: Timestamp.fromDateTime(now.add(const Duration(minutes: 22))),
  phase: phase ?? api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN,
  certainty: api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_KNOWN,
  pollAfterSeconds: 1,
  browserAction: api.EnrollmentBrowserAction(
    verificationUrl:
        'https://control.example/api/v1/auth/native-login/transaction',
    expiresAt: Timestamp.fromDateTime(now.add(const Duration(minutes: 10))),
  ),
);

class MemoryCorrelation implements CorrelationStore {
  final records = <String, EnrollmentCorrelation>{};
  Completer<void>? pendingSave;
  bool failSave = false;
  @override
  Future<EnrollmentCorrelation?> read(
    String profileId,
    String controlOrigin,
  ) async => records[profileId];
  @override
  Future<void> save(EnrollmentCorrelation record) async {
    if (failSave) throw StateError('synthetic storage failure');
    await pendingSave?.future;
    records[record.profileId] = record;
  }
}

class FakeClient implements EnrollmentClient {
  Duration? attemptTimeout;
  int enrolls = 0;
  int lookups = 0;
  int pages = 0;
  int selects = 0;
  int cancels = 0;
  bool lostSelect = false;
  bool lostCancel = false;
  api.ListEnrollmentTargetsRequest? targetRequest;
  api.SelectEnrollmentTargetRequest? selected;
  api.CancelEnrollmentAttemptRequest? cancelled;
  api.ListEnrollmentTargetsResponse page = api.ListEnrollmentTargetsResponse(
    metadata: metadata(),
    page: api.PageResponse(metadata: metadata()),
  );
  Completer<api.ListEnrollmentTargetsResponse>? pendingPage;

  @override
  Future<api.GetServerIdentityResponse> serverIdentity(
    api.GetServerIdentityRequest request,
    Duration timeout,
  ) async => throw UnimplementedError('trust fixture required');
  @override
  Future<api.ChangeResult> trustIdentity(
    api.TrustServerIdentityRequest request,
    Duration timeout,
  ) async => throw UnimplementedError('trust fixture required');

  bool lostEnroll = false;
  ClientCallFailure? enrollFailure;
  ClientCallFailure? lookupFailure;
  String digest = 'a' * 64;
  api.Availability capability = api.Availability.AVAILABILITY_AVAILABLE;
  api.EnrollRequest? sent;
  api.GetEnrollmentAttemptRequest? lookup;
  api.EnrollmentAttempt value = makeAttempt();
  api.EnrollmentAttempt? selectResult;
  api.Status snapshot = api.Status(metadata: metadata());
  Completer<api.EnrollmentAttempt>? pendingLookup;
  @override
  Future<api.ListEnrollmentTargetsResponse> targets(
    api.ListEnrollmentTargetsRequest request,
    Duration timeout,
  ) async {
    pages++;
    targetRequest = request;
    if (pendingPage != null) return pendingPage!.future;
    return page;
  }

  @override
  Future<api.EnrollmentAttempt> select(
    api.SelectEnrollmentTargetRequest request,
    Duration timeout,
  ) async {
    selects++;
    selected = request;
    if (lostSelect) throw TimeoutException('lost select');
    if (selectResult != null) return selectResult!;
    return makeAttempt(phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING)
      ..accountId = request.accountId
      ..networkId = request.networkId
      ..metadata.revision = request.mutation.expectedRevision + 1;
  }

  @override
  Future<api.EnrollmentAttempt> cancel(
    api.CancelEnrollmentAttemptRequest request,
    Duration timeout,
  ) async {
    cancels++;
    cancelled = request;
    if (lostCancel) throw TimeoutException('lost cancel');
    return value;
  }

  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async =>
      api.RuntimeInfo(
        instanceId: 'instance-A',
        protocol: 'endlessnet-client-ipc',
        ipcVersion: 0,
        contractSha256: digest,
        callerAccess: api.Access.ACCESS_OWNER,
        capabilities: [
          api.CapabilityStatus(
            capability: api.Capability.CAPABILITY_ENROLLMENT,
            restriction: api.Restriction(
              availability: capability,
              reasonKey: capability == api.Availability.AVAILABILITY_AVAILABLE
                  ? ''
                  : 'client.owner.required',
              actionOwner: api.ActionOwner.ACTION_OWNER_USER,
            ),
          ),
        ],
      );
  @override
  Future<api.Status> status(Duration timeout) async => snapshot;
  @override
  Future<api.EnrollmentAttempt> enroll(
    api.EnrollRequest request,
    Duration timeout,
  ) async {
    enrolls++;
    sent = api.EnrollRequest.fromBuffer(request.writeToBuffer());
    if (enrollFailure != null) throw enrollFailure!;
    if (lostEnroll) throw TimeoutException('synthetic lost response');
    return value;
  }

  @override
  Future<api.EnrollmentAttempt> attempt(
    api.GetEnrollmentAttemptRequest request,
    Duration timeout,
  ) async {
    attemptTimeout = timeout;
    lookups++;
    lookup = request;
    if (lookupFailure != null) throw lookupFailure!;
    if (pendingLookup != null) return pendingLookup!.future;
    return value;
  }
}

EnrollmentController controller(FakeClient client, MemoryCorrelation store) =>
    EnrollmentController(
      client: client,
      store: store,
      expectedContractSha256: 'a' * 64,
      now: () => now,
      callTimeout: const Duration(seconds: 1),
      recoveryPollInterval: const Duration(seconds: 1),
      requestId: () => requestId,
      automaticPolling: false,
    );

api.EnrollmentTarget target(
  String account,
  String network, {
  bool allowed = true,
}) => api.EnrollmentTarget(
  accountId: account,
  networkId: network,
  restriction: api.Restriction(
    availability: allowed
        ? api.Availability.AVAILABILITY_AVAILABLE
        : api.Availability.AVAILABILITY_PERMISSION_REQUIRED,
  ),
);

EnrollmentController automaticController(
  FakeClient client,
  CorrelationStore store,
  DateTime Function() clock,
) => EnrollmentController(
  client: client,
  store: store,
  expectedContractSha256: 'a' * 64,
  now: clock,
  callTimeout: const Duration(seconds: 1),
  recoveryPollInterval: const Duration(seconds: 1),
  requestId: () => requestId,
);

void main() {
  testWidgets(
    'deadline timer does not begin another automatic read; explicit original lookup remains available',
    (tester) async {
      var clock = now;
      final client = FakeClient()
        ..value = makeAttempt()
        ..value.deadline = Timestamp.fromDateTime(
          now.add(const Duration(seconds: 1)),
        );
      final c = automaticController(client, MemoryCorrelation(), () => clock);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      clock = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(client.lookups, 0);
      expect(c.uncertain, isTrue);
      expect(c.canCancel, isFalse);
      await c.refresh();
      expect(client.lookups, 1);
      expect(client.lookup!.requestId, requestId);
      expect(client.enrolls, 1);
      c.dispose();
    },
  );

  testWidgets(
    'automatic read timeout is remaining budget and late response cannot extend recovery past total',
    (tester) async {
      var clock = now;
      final end = now.add(const Duration(milliseconds: 1500));
      final client = FakeClient()
        ..value = makeAttempt()
        ..value.deadline = Timestamp.fromDateTime(end);
      final store = MemoryCorrelation();
      var c = automaticController(client, store, () => clock);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.pendingLookup = Completer<api.EnrollmentAttempt>();
      clock = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(client.attemptTimeout, const Duration(milliseconds: 500));
      clock = end;
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.busy, isFalse);
      expect(c.uncertain, isTrue);
      expect(store.records['profile-A']!.recoveryDeadline, end);
      client.pendingLookup!.complete(
        makeAttempt(phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED),
      );
      await tester.pump();
      expect(c.registeredConfirmed, isFalse);
      c.dispose();
      client.pendingLookup = null;
      client.lookupFailure = ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-secret'),
        16384,
      );
      c = automaticController(client, store, () => clock);
      await c.bind(profile());
      final reads = client.lookups;
      clock = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, reads);
      expect(c.correlation!.recoveryDeadline, end);
      expect(client.enrolls, 1);
      c.dispose();
    },
  );

  test('same attempt cannot change original creation or total deadline, including nanoseconds', () async {
    for (final field in [
      'created-seconds',
      'created-nanos',
      'deadline-seconds',
      'deadline-nanos',
    ]) {
      final client = FakeClient()
        ..value = makeAttempt()
        ..value.deadline = Timestamp.fromDateTime(
          now.add(const Duration(minutes: 15)),
        );
      final c = controller(client, MemoryCorrelation());
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      final original = c.currentAttempt!.writeToBuffer();
      switch (field) {
        case 'created-seconds':
          client.value.createdAt.seconds += 1;
        case 'created-nanos':
          client.value.createdAt.nanos += 1;
        case 'deadline-seconds':
          client.value.deadline.seconds += 1;
        case 'deadline-nanos':
          client.value.deadline.nanos += 1;
      }
      await c.refresh();
      expect(c.link, EnrollmentLinkState.unavailable);
      expect(c.currentAttempt!.writeToBuffer(), original);
      expect(client.enrolls, 1);
      c.dispose();
    }
  });
  testWidgets(
    'earlier producer recovery bound is durable before restart and unavailable replies cannot replace it',
    (tester) async {
      var clock = now;
      final client = FakeClient()..lostEnroll = true;
      final store = MemoryCorrelation();
      var c = automaticController(client, store, () => clock);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(minutes: 2)),
      );
      client.value =
          makeAttempt(phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING)
            ..certainty = api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN
            ..recoveryDeadline = Timestamp.fromDateTime(
              now.add(const Duration(seconds: 2)),
            );
      await c.refresh();
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(seconds: 2)),
      );
      c.dispose();
      clock = now.add(const Duration(seconds: 3));
      client.lookupFailure = ClientCallFailure.fromGrpc(
        const grpc.GrpcError.unavailable('raw-secret'),
        16384,
      );
      c = automaticController(client, store, () => clock);
      await c.bind(profile());
      final reads = client.lookups;
      clock = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, reads);
      expect(
        c.correlation!.recoveryDeadline,
        now.add(const Duration(seconds: 2)),
      );
      expect(client.enrolls, 1);
      c.dispose();
    },
  );
  testWidgets(
    'confirmed pending approval keeps polling after historical recovery window but stops at approval expiry',
    (tester) async {
      var clock = now;
      final client = FakeClient()
        ..value = makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING,
        )
        ..value.certainty =
            api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN
        ..value.recoveryDeadline = Timestamp.fromDateTime(
          now.add(const Duration(seconds: 2)),
        );
      final store = MemoryCorrelation();
      final c = automaticController(client, store, () => clock);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(seconds: 2)),
      );
      client.value =
          makeAttempt(
              phase: api.EnrollmentPhase.ENROLLMENT_PHASE_PENDING_APPROVAL,
            )
            ..recoveryDeadline = Timestamp.fromDateTime(
              now.add(const Duration(seconds: 2)),
            )
            ..approvalExpiresAt = Timestamp.fromDateTime(
              now.add(const Duration(seconds: 6)),
            );
      clock = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      clock = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 2));
      final afterHistoricalRecovery = client.lookups;
      clock = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(client.lookups, greaterThan(afterHistoricalRecovery));
      expect(c.uncertain, isFalse);
      clock = now.add(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 3));
      final reads = client.lookups;
      clock = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, reads);
      expect(c.uncertain, isTrue);
      expect(c.canCancel, isFalse);
      expect(
        c.currentAttempt!.phase,
        api.EnrollmentPhase.ENROLLMENT_PHASE_PENDING_APPROVAL,
      );
      expect(client.enrolls, 1);
      c.dispose();
    },
  );

  testWidgets(
    'first local recovery window bounds uncertain replies and survives reopening without extension',
    (tester) async {
      var clock = now;
      final client = FakeClient()..lostEnroll = true;
      final store = MemoryCorrelation();
      var c = automaticController(client, store, () => clock);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      final first = store.records['profile-A']!.recoveryDeadline;
      client.value =
          makeAttempt(phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING)
            ..certainty = api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN
            ..recoveryDeadline = Timestamp.fromDateTime(
              now.add(const Duration(minutes: 10)),
            );
      await c.refresh();
      clock = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      final reads = client.lookups;
      clock = now.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, reads);
      expect(c.canCancel, isFalse);
      c.dispose();
      c = automaticController(client, store, () => clock);
      await c.bind(profile());
      final afterReopen = client.lookups;
      clock = now.add(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, afterReopen);
      expect(store.records['profile-A']!.recoveryDeadline, first);
      expect(client.lookup!.requestId, requestId);
      expect(client.enrolls, 1);
      c.dispose();
    },
  );

  testWidgets(
    'uncertain cancellation persists producer recovery boundary and keeps only bounded original reads',
    (tester) async {
      var clock = now;
      final client = FakeClient()
        ..value = makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED,
        )
        ..value.certainty =
            api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN
        ..value.recoveryDeadline = Timestamp.fromDateTime(
          now.add(const Duration(seconds: 2)),
        );
      final store = MemoryCorrelation();
      final c = automaticController(client, store, () => clock);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(c.uncertain, isTrue);
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(seconds: 2)),
      );
      clock = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(client.lookups, 1);
      clock = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      final reads = client.lookups;
      clock = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, reads);
      expect(client.enrolls, 1);
      expect(c.registeredConfirmed, isFalse);
      c.dispose();
    },
  );

  test('uncertain reply without valid persisted producer recovery deadline stays unknown', () async {
    for (final invalid in ['missing', 'before-created', 'after-total']) {
      final client = FakeClient()
        ..value = makeAttempt()
        ..value.certainty =
            api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN;
      if (invalid != 'missing') {
        client.value.recoveryDeadline = Timestamp.fromDateTime(
          invalid == 'before-created'
              ? now
              : now.add(const Duration(minutes: 23)),
        );
      }
      final store = MemoryCorrelation();
      final c = controller(client, store);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(c.link, EnrollmentLinkState.unavailable);
      expect(c.currentAttempt, isNull);
      expect(c.uncertain, isTrue);
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(minutes: 2)),
      );
      expect(client.enrolls, 1);
      c.dispose();
    }
  });

  testWidgets(
    'login and completing deadlines gate polling, browser and actions consistently',
    (tester) async {
      for (final login in [true, false]) {
        var clock = now;
        final client = FakeClient()
          ..value = makeAttempt(
            phase: login
                ? api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN
                : api.EnrollmentPhase.ENROLLMENT_PHASE_COMPLETING,
          );
        if (login) {
          client.value.loginExpiresAt = Timestamp.fromDateTime(
            now.add(const Duration(seconds: 2)),
          );
        } else {
          client.value.approvalExpiresAt = Timestamp.fromDateTime(
            now.add(const Duration(seconds: 2)),
          );
        }
        final c = automaticController(client, MemoryCorrelation(), () => clock);
        await c.bind(profile());
        await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
        clock = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(c.uncertain, isTrue);
        expect(c.canCancel, isFalse);
        expect(c.browserAction, isNull);
        final reads = client.lookups;
        clock = now.add(const Duration(minutes: 1));
        await tester.pump(const Duration(minutes: 1));
        expect(client.lookups, reads);
        expect(client.enrolls, 1);
        c.dispose();
      }
    },
  );
  test('disposed controller rejects new enrollment, selection, cancel, reads and browser action', () async {
    final newClient = FakeClient();
    final newStore = MemoryCorrelation();
    final idle = controller(newClient, newStore);
    await idle.bind(profile());
    expect(idle.canEnroll, isTrue);
    idle.dispose();
    expect(idle.canEnroll, isFalse);
    await idle.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    expect(newClient.enrolls, 0);
    expect(newStore.records, isEmpty);
    for (final phase in [
      api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
      api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN,
    ]) {
      final client = FakeClient()..value = makeAttempt(phase: phase);
      final c = controller(client, MemoryCorrelation());
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      if (phase == api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT) {
        client.page.targets.add(target('account-A', 'network-A'));
        await c.loadTargets();
        expect(c.canSelect('account-A', 'network-A'), isTrue);
      } else {
        expect(c.browserAction, isNotNull);
      }
      final pages = client.pages;
      c.dispose();
      expect(c.canCancel, isFalse);
      expect(c.canSelect('account-A', 'network-A'), isFalse);
      expect(c.browserAction, isNull);
      await c.selectTarget('account-A', 'network-A');
      await c.cancelAttempt();
      await c.loadTargets();
      await c.refresh();
      expect(client.selects, 0);
      expect(client.cancels, 0);
      expect(client.lookups, 0);
      expect(client.pages, pages);
    }
  });
  test('read-only refresh before Enroll refreshes availability without UUID or mutation and rejects rollback', () async {
    final client = FakeClient()
      ..capability = api.Availability.AVAILABILITY_PERMISSION_REQUIRED;
    final store = MemoryCorrelation();
    final c = controller(client, store);
    addTearDown(c.dispose);
    await c.bind(profile());
    expect(c.canEnroll, isFalse);
    client.capability = api.Availability.AVAILABILITY_AVAILABLE;
    client.snapshot.metadata.revision += 1;
    await c.refresh();
    expect(c.canEnroll, isTrue);
    expect(store.records, isEmpty);
    expect(client.enrolls, 0);
    client.snapshot.metadata.revision -= 1;
    await c.refresh();
    expect(c.canEnroll, isFalse);
    expect(c.link, EnrollmentLinkState.unavailable);
    expect(client.enrolls, 0);
  });
  ClientCallFailure refusal([int code = grpc.StatusCode.permissionDenied]) =>
      ClientCallFailure.fromGrpc(
        grpc.GrpcError.custom(code, 'raw-not-for-display', [
          api.Failure(
            code: api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
            reasonKey: 'client.owner.required',
            actionOwner: api.ActionOwner.ACTION_OWNER_USER,
          ),
        ]),
        16384,
      );

  test(
    'RPC refusal retains UUID without inventing domain denial or retry',
    () async {
      final client = FakeClient()..enrollFailure = refusal();
      final store = MemoryCorrelation();
      final c = controller(client, store);
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(c.callRejected, true);
      expect(c.uncertain, false);
      expect(c.reasonKey, 'client.owner.required');
      expect(c.failure!.actionOwner, api.ActionOwner.ACTION_OWNER_USER);
      c.failure!.reasonKey = 'changed';
      expect(c.reasonKey, 'client.owner.required');
      expect(c.currentAttempt, isNull);
      expect(c.browserAction, isNull);
      expect(c.registeredConfirmed, false);
      expect(store.records['profile-A']!.requestId, requestId);
      expect(store.records['profile-A']!.recoveryDeadline, isNull);
      await c.start('another', api.EnrollmentMode.ENROLLMENT_MODE_SERVER);
      expect(client.enrolls, 1);
    },
  );

  test(
    'unavailable stays unknown despite a permission Failure detail',
    () async {
      final client = FakeClient()
        ..enrollFailure = refusal(grpc.StatusCode.unavailable);
      final store = MemoryCorrelation();
      final c = controller(client, store);
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(c.uncertain, true);
      expect(c.callRejected, false);
      expect(c.failure, isNull);
      expect(c.reasonKey, 'ui.enrollment_uncertain');
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(minutes: 2)),
      );
      await c.refresh();
      expect(client.enrolls, 1);
      expect(client.lookup!.requestId, requestId);
      expect(c.uncertain, false);
    },
  );

  test(
    'refused refresh hides cached browser action until a successful read',
    () async {
      final client = FakeClient();
      final store = MemoryCorrelation();
      final c = controller(client, store);
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(c.browserAction, isNotNull);
      client.lookupFailure = refusal();
      await c.refresh();
      expect(c.callRejected, true);
      expect(c.browserAction, isNull);
      expect(
        c.currentAttempt!.phase,
        api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN,
      );
      client.lookupFailure = null;
      await c.refresh();
      expect(c.callRejected, false);
      expect(c.failure, isNull);
      expect(c.browserAction, isNotNull);
      expect(client.enrolls, 1);
    },
  );

  test(
    'selection reply for another account cannot replace the current attempt',
    () async {
      final client = FakeClient()
        ..value = makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
        )
        ..selectResult =
            (makeAttempt(
                phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING,
              )
              ..accountId = 'foreign-account'
              ..networkId = 'foreign-network');
      final c = controller(client, MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.page.targets.add(target('account-A', 'network-A'));
      await c.loadTargets();
      await c.selectTarget('account-A', 'network-A');
      expect(c.uncertain, true);
      expect(c.currentAttempt!.accountId, isEmpty);
      expect(c.registeredConfirmed, false);
      await c.refresh();
      expect(client.lookup!.requestId, requestId);
      expect(client.selects, 1);
    },
  );

  test(
    'explicit pages and selection use exact catalog revision and offered IDs',
    () async {
      final client = FakeClient()
        ..value = makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
        );
      final c = controller(client, MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.page.targets.add(target('account-A', 'network-A', allowed: false));
      client.page.page.nextPageToken = 'opaque-next';
      await c.loadTargets(pageSize: 1);
      expect(client.pages, 1); // No automatic pagination.
      expect(client.targetRequest!.profile.profileId, 'profile-A');
      expect(client.targetRequest!.attemptId, 'attempt-A');
      expect(c.canSelect('account-A', 'network-A'), false);
      await c.selectTarget('forged', 'network-A');
      expect(client.selects, 0);
      client.page = api.ListEnrollmentTargetsResponse(
        targets: [target('account-B', 'network-B')],
        metadata: metadata(),
        page: api.PageResponse(metadata: metadata()),
      );
      await c.loadTargets(pageSize: 1, next: true);
      expect(client.targetRequest!.page.pageToken, 'opaque-next');
      expect(c.targets.single.accountId, 'account-B');
      c.targets.single.accountId = 'foreign';
      expect(c.canSelect('account-B', 'network-B'), true);
      // A polling snapshot at the exact same revision preserves current page.
      await c.refresh();
      expect(c.canSelect('account-B', 'network-B'), true);
      await c.selectTarget('account-B', 'network-B');
      expect(
        client.selected!.mutation.expectedRevision.toStringUnsigned(),
        '9007199254740993',
      );
      expect(client.selected!.mutation.expectedInstanceId, 'instance-A');
      expect(client.selected!.attemptId, 'attempt-A');
      expect(c.currentAttempt!.accountId, 'account-B');
      expect(c.targets, isEmpty);
      expect(c.registeredConfirmed, false);
      await c.selectTarget('account-A', 'network-A');
      expect(client.selects, 1);
    },
  );

  test('changed next-page revision, duplicate IDs and foreign instance invalidate choices', () async {
    for (final kind in ['revision', 'duplicates', 'instance']) {
      final client = FakeClient()
        ..value = makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
        );
      final c = controller(client, MemoryCorrelation());
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.page.targets.add(target('account-A', 'network-A'));
      client.page.page.nextPageToken = 'next';
      await c.loadTargets(pageSize: 2);
      if (kind == 'revision') {
        client.page.metadata.revision += 1;
        client.page.page.metadata.revision += 1;
      } else if (kind == 'duplicates') {
        client.page.targets.add(target('account-A', 'network-A'));
      } else {
        client.page.metadata.instanceId = 'foreign';
      }
      await c.loadTargets(pageSize: 2, next: true);
      expect(c.targets, isEmpty, reason: kind);
      expect(c.canSelect('account-A', 'network-A'), false);
      expect(c.uncertain, true);
      expect(client.selects, 0);
      c.dispose();
    }
  });

  test(
    'lost Select and Cancel only recover original request; cancel is no revoke',
    () async {
      for (final select in [true, false]) {
        final client = FakeClient()
          ..value = makeAttempt(
            phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
          )
          ..lostSelect = true
          ..lostCancel = true;
        final store = MemoryCorrelation();
        final c = controller(client, store);
        await c.bind(profile());
        await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
        if (select) {
          client.page.targets.add(target('account-A', 'network-A'));
          await c.loadTargets();
          await c.selectTarget('account-A', 'network-A');
        } else {
          await c.cancelAttempt();
          expect(client.cancelled!.attemptId, 'attempt-A');
          expect(
            client.cancelled!.mutation.expectedRevision.toStringUnsigned(),
            '9007199254740993',
          );
        }
        expect(c.uncertain, true);
        expect(c.canCancel, false);
        expect(
          c.currentAttempt!.phase,
          api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
        );
        await c.cancelAttempt();
        await c.selectTarget('account-A', 'network-A');
        await c.refresh();
        expect(client.lookup!.requestId, requestId);
        expect(client.enrolls, 1);
        expect(client.selects, select ? 1 : 0);
        expect(client.cancels, select ? 0 : 1);
        expect(store.records['profile-A']!.requestId, requestId);
        c.dispose();
      }
    },
  );

  test(
    'cancel uses actual producer phase and never cancels a registered Node',
    () async {
      final client = FakeClient();
      final c = controller(client, MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.value = makeAttempt(
        phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED,
      );
      await c.cancelAttempt();
      expect(
        c.currentAttempt!.phase,
        api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED,
      );
      expect(c.registeredConfirmed, false);
      expect(c.canCancel, false);
      client.value =
          makeAttempt(phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED)
            ..accountId = 'account-A'
            ..networkId = 'network-A'
            ..nodeId = 'node-A';
      await c.refresh();
      await c.cancelAttempt();
      expect(client.cancels, 1);
    },
  );

  test(
    'late catalog after profile switch cannot display targets or mutate',
    () async {
      final client = FakeClient()
        ..value = makeAttempt(
          phase: api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT,
        );
      final c = controller(client, MemoryCorrelation());
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.pendingPage = Completer<api.ListEnrollmentTargetsResponse>();
      final work = c.loadTargets();
      await Future<void>.delayed(Duration.zero);
      await c.bind(profile('profile-B'));
      client.pendingPage!.complete(
        api.ListEnrollmentTargetsResponse(
          targets: [target('account-A', 'network-A')],
          metadata: metadata(),
          page: api.PageResponse(metadata: metadata()),
        ),
      );
      await work;
      expect(c.targets, isEmpty);
      expect(c.correlation, isNull);
      expect(client.selects, 0);
    },
  );

  test(
    'uint64 revision above signed range remains current without precision loss',
    () async {
      final client = FakeClient();
      final store = MemoryCorrelation();
      final c = controller(client, store);
      addTearDown(c.dispose);
      client.value = makeAttempt()
        ..metadata.revision = ~api.SnapshotMetadata().revision;
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(
        c.currentAttempt!.metadata.revision.toStringUnsigned(),
        '18446744073709551615',
      );
      expect(c.link, EnrollmentLinkState.available);
    },
  );

  testWidgets(
    'automatic polling stops at producer deadline without a mutation',
    (tester) async {
      var clock = now;
      final client = FakeClient();
      final store = MemoryCorrelation();
      client.value = makeAttempt()
        ..deadline = Timestamp.fromDateTime(now.add(const Duration(seconds: 2)))
        ..browserAction.expiresAt = Timestamp.fromDateTime(
          now.add(const Duration(seconds: 2)),
        );
      final c = EnrollmentController(
        client: client,
        store: store,
        expectedContractSha256: 'a' * 64,
        now: () => clock,
        callTimeout: const Duration(seconds: 1),
        recoveryPollInterval: const Duration(seconds: 1),
        requestId: () => requestId,
      );
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      clock = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(client.lookups, 1);
      clock = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      final reads = client.lookups;
      clock = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(client.lookups, reads);
      expect(client.enrolls, 1);
      expect(c.uncertain, true);
      expect(c.browserAction, isNull);
      c.dispose();
    },
  );

  test(
    'UUID is durable before Enroll and exact uint64 precondition survives',
    () async {
      final client = FakeClient();
      final store = MemoryCorrelation();
      final c = controller(client, store);
      addTearDown(c.dispose);
      await c.bind(profile());
      store.pendingSave = Completer<void>();
      final work = c.start(
        'host',
        api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.enrolls, 0);
      store.pendingSave!.complete();
      await work;
      expect(store.records['profile-A']!.requestId, requestId);
      expect(client.sent!.requestId, requestId);
      expect(
        client.sent!.mutation.expectedRevision.toString(),
        '9007199254740993',
      );
      expect(c.browserAction?.origin, 'https://control.example');
      expect(c.registeredConfirmed, false);
    },
  );

  test('persistence failure and contract mismatch never send Enroll', () async {
    final client = FakeClient();
    final store = MemoryCorrelation()..failSave = true;
    final c = controller(client, store);
    addTearDown(c.dispose);
    await c.bind(profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    expect(client.enrolls, 0);
    expect(c.reasonKey, 'ui.correlation_save_failed');
    client.digest = 'b' * 64;
    await c.bind(profile());
    expect(c.link, EnrollmentLinkState.mismatch);
    expect(c.canEnroll, false);
  });

  test(
    'lost Enroll/reopen reads original UUID and never repeats mutation',
    () async {
      final client = FakeClient()..lostEnroll = true;
      final store = MemoryCorrelation();
      final c = controller(client, store);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      expect(c.uncertain, true);
      expect(client.enrolls, 1);
      expect(
        store.records['profile-A']!.recoveryDeadline,
        now.add(const Duration(minutes: 2)),
      );
      c.dispose();
      final reopened = controller(client, store);
      addTearDown(reopened.dispose);
      await reopened.bind(profile());
      expect(client.lookup!.requestId, requestId);
      expect(client.enrolls, 1);
      expect(reopened.currentAttempt!.attemptId, 'attempt-A');
      await reopened.start(
        'different host',
        api.EnrollmentMode.ENROLLMENT_MODE_SERVER,
      );
      expect(client.enrolls, 1);
    },
  );

  test(
    'late old profile reply and foreign instance cannot replace screen',
    () async {
      final client = FakeClient()..lostEnroll = true;
      final store = MemoryCorrelation();
      final c = controller(client, store);
      addTearDown(c.dispose);
      await c.bind(profile());
      await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
      client.pendingLookup = Completer<api.EnrollmentAttempt>();
      final read = c.refresh();
      await Future<void>.delayed(Duration.zero);
      await c.bind(profile('profile-B'));
      client.pendingLookup!.complete(makeAttempt());
      await read;
      expect(c.currentAttempt, isNull);
      expect(c.correlation, isNull);
      client.pendingLookup = null;
      client.value = makeAttempt()..metadata.instanceId = 'old-instance';
      await c.bind(profile());
      expect(c.currentAttempt, isNull);
      expect(c.registeredConfirmed, false);
    },
  );

  test('registered requires current matching Node snapshot; URL cannot change origin', () async {
    final client = FakeClient();
    final store = MemoryCorrelation();
    final c = controller(client, store);
    addTearDown(c.dispose);
    client.value = makeAttempt()
      ..browserAction.verificationUrl = 'https://evil.example/login';
    await c.bind(profile());
    await c.start('host', api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION);
    expect(c.browserAction, isNull);
    client.value =
        makeAttempt(phase: api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED)
          ..accountId = 'account-A'
          ..networkId = 'network-A'
          ..nodeId = 'node-A';
    await c.refresh();
    expect(c.registeredConfirmed, false);
    client.snapshot = api.Status(
      metadata: metadata(),
      activeProfileId: 'profile-A',
      accountId: 'account-A',
      nodeId: 'node-A',
      network: api.Network(id: 'network-A'),
    );
    await c.refresh();
    expect(c.registeredConfirmed, true);
    // Consumers cannot mutate the controller's saved producer message.
    c.currentAttempt!.nodeId = 'foreign-node';
    expect(c.registeredConfirmed, true);
  });
}
