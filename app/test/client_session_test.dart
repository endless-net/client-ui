import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

class NoCallsClient implements api.ClientServiceClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RPC');
}

class FakeConnection implements ClientConnection {
  Future<ClientProfileCatalog> Function()? profiles;
  @override
  Future<ClientProfileCatalog> listProfiles() => profiles!();
  final events = StreamController<api.WatchEventsResponse>();
  bool closed = false;
  @override
  final mutations = ClientMutations(NoCallsClient(), instanceId: 'runtime-a');
  @override
  Stream<api.WatchEventsResponse> watch() => events.stream;
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

class FailedWatchConnection extends FakeConnection {
  int closeCalls = 0;
  @override
  Stream<api.WatchEventsResponse> watch() =>
      throw const FormatException('Synthetic watch setup failure');
  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    // No subscription was created. Do not await an unlistened controller.
    unawaited(events.close());
  }
}

api.WatchEventsResponse snapshot() =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '1',
      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': 'ACCESS_OWNER',
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        },
      },
    });

ClientOperation accepted(api.MutationContext context) =>
    ClientOperation.fromProto(
      api.Operation(
        id: 'operation-a',
        requestId: context.requestId,
        kind: api.OperationKind.OPERATION_KIND_CONNECT,
        state: api.OperationState.OPERATION_STATE_PENDING,
      ),
    );

void main() {
  late Directory directory;
  late FakeConnection connection;
  late ClientSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('en-session-');
    connection = FakeConnection();
    session = ClientSession(
      journal: ClientIntentJournal(directory),
      open: () async => connection,
    );
    await session.connect();
  });
  tearDown(() async {
    await session.close();
    await directory.delete(recursive: true);
  });

  test(
    'US-03: acceptance snapshot refresh does not invalidate RPC result',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      final cacheEpoch = session.state.cacheEpoch;
      final contextEpoch = session.state.contextEpoch;
      final result = await session.submit(
        api.OperationKind.OPERATION_KIND_CONNECT,
        (_, context) async {
          final refresh = snapshot()..sequence += 1;
          refresh.metadata.revision += 1;
          refresh.snapshot.status.metadata.revision += 1;
          connection.events.add(refresh);
          await pumpEventQueue();
          return accepted(context);
        },
      );
      expect(result.value.kind, api.OperationKind.OPERATION_KIND_CONNECT);
      expect(session.state.cacheEpoch, greaterThan(cacheEpoch));
      expect(session.state.contextEpoch, contextEpoch);
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-03: real profile change still makes in-flight result recoverable',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          final changed = snapshot()..sequence += 1;
          changed.metadata.revision += 1;
          changed.snapshot.status.metadata.revision += 1;
          changed.snapshot.status.activeProfileId = 'different-profile';
          connection.events.add(changed);
          await pumpEventQueue();
          return accepted(context);
        }),
        throwsStateError,
      );
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-08: catalog requires snapshot and rejects a late caller-context result',
    () async {
      var calls = 0;
      final result = Completer<ClientProfileCatalog>();
      connection.profiles = () {
        calls++;
        return result.future;
      };
      await expectLater(session.listProfiles(), throwsStateError);
      expect(calls, 0);
      connection.events.add(snapshot());
      await pumpEventQueue();
      final query = session.listProfiles();
      final rejection = expectLater(query, throwsStateError);
      final observer = snapshot()..sequence += 1;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await pumpEventQueue();
      result.complete(
        await readClientProfiles(
          (_) async => api.ListProfilesResponse()
            ..mergeFromProto3Json({
              'page': {
                'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              },
            }),
          instanceId: 'runtime-a',
        ),
      );
      await rejection;
      expect(calls, 1);
      await expectLater(session.listProfiles(), throwsStateError);
      expect(calls, 1);
    },
  );

  test(
    'US-08: owner receives a complete current catalog, never an older revision',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      var revision = '7';
      connection.profiles = () => readClientProfiles(
        (_) async => api.ListProfilesResponse()
          ..mergeFromProto3Json({
            'page': {
              'metadata': {'instanceId': 'runtime-a', 'revision': revision},
            },
          }),
        instanceId: 'runtime-a',
      );
      expect((await session.listProfiles()).profiles, isEmpty);
      revision = '6';
      await expectLater(session.listProfiles(), throwsStateError);
    },
  );

  test(
    'US-01: failed watch releases bootstrapped channel before retry',
    () async {
      await session.close();
      final failed = FailedWatchConnection();
      final replacement = FakeConnection();
      var attempts = 0;
      session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => attempts++ == 0 ? failed : replacement,
      );
      await expectLater(session.connect(), throwsFormatException);
      await pumpEventQueue();
      expect(failed.closeCalls, 1);
      expect(session.state.link, ClientLinkState.unavailable);
      expect(session.state.snapshot, isNull);
      await session.connect();
      replacement.events.add(snapshot());
      await pumpEventQueue();
      expect(failed.closeCalls, 1);
      expect(session.state.link, ClientLinkState.ready);
      expect(replacement.closed, isFalse);
    },
  );

  test(
    'US-01/03: bootstrap alone cannot submit; snapshot context is journaled before send',
    () async {
      await expectLater(
        session.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (_, context) async => accepted(context),
        ),
        throwsStateError,
      );
      expect(await session.journal.pending(), isEmpty);
      connection.events.add(snapshot());
      await pumpEventQueue();
      final result = await session.submit(
        api.OperationKind.OPERATION_KIND_CONNECT,
        (_, context) async {
          expect(context.expectedInstanceId, 'runtime-a');
          expect(context.expectedRevision.toString(), '7');
          expect(
            (await ClientIntentJournal(directory).pending()).single.requestId,
            context.requestId,
          );
          return accepted(context);
        },
      );
      expect(result.terminal, isFalse);
      expect(await session.journal.pending(), hasLength(1));
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          fail('Accepted work must be recovered, not submitted again');
        }),
        throwsStateError,
      );
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-03: transport timeout preserves request identity without resubmitting',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      var calls = 0;
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          calls++;
          throw TimeoutException('synthetic');
        }),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
      expect(await session.journal.pending(), hasLength(1));
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          calls++;
          return accepted(context);
        }),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test(
    'US-03: overlapping submissions do not allocate a second intention',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      final release = Completer<void>();
      final first = session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
        _,
        context,
      ) async {
        await release.future;
        return accepted(context);
      });
      await expectLater(
        session.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (_, context) async => accepted(context),
        ),
        throwsStateError,
      );
      release.complete();
      await first;
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-03: late acceptance after stream loss is not shown in the current context',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          await connection.events.close();
          await pumpEventQueue();
          return accepted(context);
        }),
        throwsStateError,
      );
      expect(session.state.link, ClientLinkState.unavailable);
      expect(await session.journal.pending(), hasLength(1));
    },
  );
}
