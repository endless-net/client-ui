import 'dart:async';
import 'dart:typed_data';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/correlation_journal.dart';
import 'package:endlessnet_client_ui/client/session_login_client.dart';
import 'package:endlessnet_client_ui/client/session_login_correlation.dart';
import 'package:endlessnet_client_ui/session_login/controller.dart';
import 'package:endlessnet_client_ui/session_login/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'correlation_journal_test.dart' as journal;

const profileId = '0b6e11e3-3daa-4846-92ed-e07b6d8ce566';
const requestId = '00000000-0000-4000-8000-000000000001';
const nextId = '00000000-0000-4000-8000-000000000002';
const origin = 'https://api.endlessnet.ru';
final at = DateTime.utc(2026, 11, 16);
api.Profile profile() => api.Profile(id: profileId, controlOrigin: origin);
api.SnapshotMetadata metadata() => api.SnapshotMetadata(
  instanceId: 'instance',
  revision: api.SnapshotMetadata().revision + 4,
);
SessionLoginCorrelation correlation({
  String id = requestId,
  String node = 'original-node',
}) => SessionLoginCorrelation(
  profileId: profileId,
  controlOrigin: origin,
  nodeId: node,
  requestId: id,
);

final class Remote implements SessionLoginClient {
  int mutations = 0, reads = 0;
  int sessionReads = 0;
  bool failFreshSession = false;
  bool lose = false,
      missing = false,
      wrongDigest = false,
      foreign = false,
      administrator = false;
  String node = 'original-node';
  api.SessionLoginAttempt? current;
  final history = <String, api.SessionLoginAttempt>{};
  api.StartSessionLoginRequest? sent;
  api.Session state = api.Session(
    state: api.SessionState.SESSION_STATE_EXPIRED,
  );
  api.SessionLoginAttempt receipt(String id) => api.SessionLoginAttempt(
    requestId: id,
    attemptId: 'attempt',
    profileId: foreign ? 'foreign-profile' : profileId,
    phase: api.SessionLoginPhase.SESSION_LOGIN_PHASE_AWAITING_CONFIRMATION,
    metadata: metadata(),
    createdAt: Timestamp.fromDateTime(at),
    deadline: Timestamp.fromDateTime(at.add(const Duration(minutes: 10))),
    browserAction: api.SessionLoginBrowserAction(
      verificationUrl: 'https://admin.endlessnet.ru/native-login/confirmation',
      expiresAt: Timestamp.fromDateTime(at.add(const Duration(minutes: 5))),
    ),
    pollAfterSeconds: 2,
  );
  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async =>
      api.RuntimeInfo(
        instanceId: 'instance',
        contractSha256: wrongDigest ? '2' * 64 : '1' * 64,
        protocol: 'endlessnet-client-ipc',
        ipcVersion: 0,
        callerAccess: administrator
            ? api.Access.ACCESS_ADMINISTRATOR
            : api.Access.ACCESS_OWNER,
        capabilities: [
          api.CapabilityStatus(
            capability: api.Capability.CAPABILITY_SESSION_LOGIN,
            restriction: api.Restriction(
              availability: api.Availability.AVAILABILITY_AVAILABLE,
            ),
          ),
        ],
      );
  @override
  Future<api.Status> status(Duration timeout) async => api.Status(
    activeProfileId: profileId,
    nodeId: node,
    metadata: metadata(),
  );
  @override
  Future<api.GetSessionResponse> session(
    api.GetSessionRequest request,
    Duration timeout,
  ) async {
    reads++;
    sessionReads++;
    if (failFreshSession && sessionReads > 1) {
      throw ClientCallFailure.fromGrpc(const grpc.GrpcError.notFound(), 1024);
    }
    return api.GetSessionResponse(
      session: state,
      metadata: metadata(),
      loginAttempt: missing ? null : current,
    );
  }

  @override
  Future<api.SessionLoginAttempt> sessionLogin(
    api.GetSessionLoginRequest request,
    Duration timeout,
  ) async {
    reads++;
    final selected = current?.requestId == request.requestId
        ? current
        : history[request.requestId];
    if (missing || selected == null) {
      throw ClientCallFailure.fromGrpc(const grpc.GrpcError.notFound(), 1024);
    }
    return api.SessionLoginAttempt.fromBuffer(selected.writeToBuffer());
  }

  @override
  Future<api.SessionLoginAttempt> startSessionLogin(
    api.StartSessionLoginRequest request,
    Duration timeout,
  ) async {
    mutations++;
    sent = api.StartSessionLoginRequest.fromBuffer(request.writeToBuffer());
    current = receipt(request.requestId);
    if (lose) throw TimeoutException('lost ACK');
    return api.SessionLoginAttempt.fromBuffer(current!.writeToBuffer());
  }
}

final class Store implements SessionLoginCorrelationStore {
  SessionLoginCorrelation? value;
  bool fail = false;
  int saves = 0;
  @override
  Future<SessionLoginCorrelation?> readSessionLogin(
    String profile,
    String origin,
  ) async => value;
  @override
  Future<void> saveSessionLogin(SessionLoginCorrelation c) async {
    saves++;
    if (fail) throw StateError('flush unavailable');
    value = c;
  }
}

SessionLoginController controller(
  Remote remote,
  SessionLoginCorrelationStore store, {
  String id = requestId,
  DateTime Function()? now,
  bool automaticPolling = false,
}) => SessionLoginController(
  client: remote,
  store: store,
  expectedContractSha256: '1' * 64,
  expectedInstanceId: 'instance',
  timeout: const Duration(seconds: 2),
  now: now ?? () => at,
  requestId: () => id,
  automaticPolling: automaticPolling,
);

void main() {
  test('reopen selects newer current success after original deadline without a mutation', () async {
    final r = Remote();
    r.history[requestId] = r.receipt(requestId)
      ..phase = api.SessionLoginPhase.SESSION_LOGIN_PHASE_UNCERTAIN
      ..pollAfterSeconds = 0
      ..clearBrowserAction();
    r.current = r.receipt(nextId)
      ..attemptId = 'new-attempt'
      ..createdAt = Timestamp.fromDateTime(at.add(const Duration(minutes: 11)))
      ..deadline = Timestamp.fromDateTime(at.add(const Duration(minutes: 21)))
      ..phase = api.SessionLoginPhase.SESSION_LOGIN_PHASE_SUCCEEDED
      ..clearBrowserAction()
      ..pollAfterSeconds = 0
      ..session = api.Session(
        state: api.SessionState.SESSION_STATE_ACTIVE,
        expiresAt: Timestamp.fromDateTime(at.add(const Duration(hours: 1))),
      );
    r.state = r.current!.session;
    final s = Store()..value = correlation();
    final c = controller(r, s, now: () => at.add(const Duration(minutes: 12)));
    await c.bind(profile());
    expect(c.attempt!.requestId, nextId);
    expect(
      c.attempt!.phase,
      api.SessionLoginPhase.SESSION_LOGIN_PHASE_SUCCEEDED,
    );
    expect(s.value!.requestId, nextId);
    expect(r.mutations, 0);
    expect(c.canStart, isFalse);
    c.dispose();
  });
  test('foreign current, failed fresh read and failed journal save retain the original', () async {
    for (final failure in ['foreign', 'fresh-read', 'save']) {
      final foreignProfile = failure == 'foreign';
      final r = Remote();
      r.failFreshSession = failure == 'fresh-read';
      r.history[requestId] = r.receipt(requestId)
        ..phase = api.SessionLoginPhase.SESSION_LOGIN_PHASE_UNCERTAIN
        ..pollAfterSeconds = 0
        ..clearBrowserAction();
      r.current = r.receipt(nextId)
        ..createdAt = Timestamp.fromDateTime(
          at.add(const Duration(minutes: 11)),
        )
        ..deadline = Timestamp.fromDateTime(
          at.add(const Duration(minutes: 21)),
        );
      if (foreignProfile) r.current!.profileId = 'foreign-profile';
      final s = Store()
        ..value = correlation()
        ..fail = failure == 'save';
      final c = controller(
        r,
        s,
        now: () => at.add(const Duration(minutes: 12)),
      );
      await c.bind(profile());
      expect(s.value!.requestId, requestId);
      expect(c.browserAction, isNull);
      expect(c.canStart, isFalse);
      expect(r.mutations, 0);
      c.dispose();
    }
  });
  test('different current cannot replace a known request before its original deadline', () async {
    final r = Remote();
    r.history[requestId] = r.receipt(requestId);
    r.current = r.receipt(nextId)
      ..createdAt = Timestamp.fromDateTime(at.add(const Duration(minutes: 1)));
    final s = Store()..value = correlation();
    final c = controller(r, s, now: () => at.add(const Duration(minutes: 2)));
    await c.bind(profile());
    expect(c.attempt!.requestId, requestId);
    expect(s.value!.requestId, requestId);
    expect(r.mutations, 0);
    c.dispose();
  });
  test('current different request cannot replace an unknown locally persisted UUID', () async {
    final r = Remote()..current = Remote().receipt(nextId);
    final s = Store()..value = correlation();
    final c = controller(r, s, now: () => at.add(const Duration(hours: 1)));
    await c.bind(profile());
    expect(s.value!.requestId, requestId);
    expect(c.canRetryOriginal, isTrue);
    expect(c.attempt, isNull);
    expect(r.mutations, 0);
    c.dispose();
  });
  test(
    'lost Start ACK and UI reopen recover original without another mutation',
    () async {
      final r = Remote()..lose = true;
      final s = Store();
      final c = controller(r, s);
      await c.bind(profile());
      expect(r.mutations, 0);
      await c.start();
      expect(r.mutations, 1);
      expect(s.value!.requestId, requestId);
      expect(r.sent!.mutation.expectedInstanceId, 'instance');
      expect(c.browserAction, isNull);
      c.dispose();
      final reopened = controller(r, s, id: nextId);
      await reopened.bind(profile());
      expect(reopened.attempt!.requestId, requestId);
      expect(reopened.browserAction!.host, 'admin.endlessnet.ru');
      expect(reopened.canStart, isFalse);
      expect(r.mutations, 1);
      reopened.dispose();
    },
  );
  test('failed durable save prevents Start; journal append followed by lost flush recovers UUID', () async {
    final r = Remote();
    final s = Store()..fail = true;
    final c = controller(r, s);
    await c.bind(profile());
    await c.start();
    expect(r.mutations, 0);
    c.dispose();
    final io = journal.MemoryIO()..failFlush = true;
    final durable = JournalCorrelationStore(io, maxBytes: 8192);
    final interrupted = controller(r, durable);
    await interrupted.bind(profile());
    await interrupted.start();
    expect(r.mutations, 0);
    interrupted.dispose();
    final bytes = Uint8List.fromList(io.bytes);
    await durable.close();
    final reopened = JournalCorrelationStore(
      journal.MemoryIO()..bytes = bytes,
      maxBytes: 8192,
    );
    expect(
      (await reopened.readSessionLogin(profileId, origin))!.requestId,
      requestId,
    );
    final recovered = controller(r, reopened, id: nextId);
    await recovered.bind(profile());
    expect(recovered.canRetryOriginal, isTrue);
    await recovered.start(retryOriginal: true);
    expect(r.sent!.requestId, requestId);
    expect(r.mutations, 1);
    recovered.dispose();
    await reopened.close();
  });
  test(
    'missing saved request only retries explicitly with the same UUID',
    () async {
      final r = Remote()..missing = true;
      final s = Store()..value = correlation();
      final c = controller(r, s, id: nextId);
      await c.bind(profile());
      expect(c.canRetryOriginal, isTrue);
      expect(c.canStart, isFalse);
      expect(r.mutations, 0);
      await c.start(retryOriginal: true);
      expect(r.sent!.requestId, requestId);
      expect(s.value!.requestId, requestId);
      c.dispose();
    },
  );
  test(
    'wrong digest, foreign Node and administrator never start a login',
    () async {
      for (final r in [
        Remote()..wrongDigest = true,
        Remote()..node = 'different-node',
        Remote()..administrator = true,
      ]) {
        final s = Store()..value = correlation();
        final c = controller(r, s);
        await c.bind(profile());
        await c.start();
        expect(c.canStart, isFalse);
        expect(c.browserAction, isNull);
        expect(r.mutations, 0);
        c.dispose();
      }
    },
  );
  test('foreign attempt and changed original deadline fail closed', () async {
    final r = Remote()..foreign = true;
    final s = Store();
    final c = controller(r, s);
    await c.bind(profile());
    await c.start();
    expect(c.browserAction, isNull);
    r.current = r.receipt(requestId)..profileId = profileId;
    await c.refresh();
    expect(c.browserAction, isNotNull);
    r.current!.deadline = Timestamp.fromDateTime(
      at.add(const Duration(minutes: 9)),
    );
    await c.refresh();
    expect(c.browserAction, isNull);
    expect(c.canStart, isFalse);
    c.dispose();
  });
  test('browser origin/query/expiry are checked each time; only explicit new request after deadline', () async {
    var clock = at;
    final r = Remote()..current = Remote().receipt(requestId);
    final s = Store();
    final c = controller(r, s, id: nextId, now: () => clock);
    await c.bind(profile());
    expect(c.browserAction, isNotNull);
    for (final url in [
      'https://evil.example/x',
      'https://admin.endlessnet.ru/x?token=secret',
      'https://user@admin.endlessnet.ru/x',
    ]) {
      r.current!.browserAction.verificationUrl = url;
      await c.refresh();
      expect(c.browserAction, isNull);
    }
    clock = at.add(const Duration(minutes: 11));
    expect(c.browserAction, isNull);
    expect(c.canStart, isTrue);
    expect(r.mutations, 0);
    await c.start();
    expect(r.sent!.requestId, nextId);
    c.dispose();
  });
  test('session correlation shares journal without altering enrollment and rejects UUID rebinding', () async {
    final io = journal.MemoryIO();
    final s = JournalCorrelationStore(io, maxBytes: 8192);
    final enrollment = journal.record();
    await s.save(enrollment);
    await s.saveSessionLogin(correlation());
    await s.saveSessionLogin(correlation());
    expect(
      (await s.read(enrollment.profileId, enrollment.controlOrigin))!.requestId,
      enrollment.requestId,
    );
    expect((await s.readSessionLogin(profileId, origin))!.requestId, requestId);
    await expectLater(
      s.saveSessionLogin(correlation(node: 'foreign')),
      throwsA(isA<CorrelationStoreFailure>()),
    );
    await s.saveSessionLogin(correlation(id: nextId));
    await expectLater(
      s.saveSessionLogin(correlation()),
      throwsA(isA<CorrelationStoreFailure>()),
    );
    await s.close();
  });
  testWidgets(
    'the current session takes precedence over an earlier successful login',
    (tester) async {
      final r = Remote();
      r.current = r.receipt(requestId)
        ..phase = api.SessionLoginPhase.SESSION_LOGIN_PHASE_SUCCEEDED
        ..pollAfterSeconds = 0
        ..clearBrowserAction()
        ..session = api.Session(
          state: api.SessionState.SESSION_STATE_ACTIVE,
          expiresAt: Timestamp.fromDateTime(at.add(const Duration(hours: 1))),
        );
      r.state = r.current!.session;
      var clock = at;
      final c = controller(
        r,
        Store(),
        now: () => clock,
        automaticPolling: true,
      );
      await c.bind(profile());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionLoginPanel(
              controller: c,
              openBrowser: (_) async => true,
            ),
          ),
        ),
      );
      expect(find.text('Сессия пользователя действует.'), findsOneWidget);
      expect(find.text('Войти снова'), findsNothing);

      clock = at.add(const Duration(hours: 1));
      r.state = api.Session(
        state: api.SessionState.SESSION_STATE_EXPIRED,
        expiresAt: Timestamp.fromDateTime(clock),
      );
      await tester.pump(const Duration(hours: 1));
      await tester.pumpAndSettle();
      expect(find.text('Сессия пользователя действует.'), findsNothing);
      expect(
        find.text(
          'Срок текущей сессии истёк. Нажмите «Подключить», чтобы проверить автоматическое продление.',
        ),
        findsOneWidget,
      );
      expect(find.text('Войти снова'), findsOneWidget);
      expect(r.mutations, 0);
      c.dispose();
    },
  );
}
