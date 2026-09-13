import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';

final class RevocationConnection implements ClientConnection {
  final events = StreamController<api.WatchEventsResponse>();
  int calls = 0;
  bool closed = false;
  @override
  Stream<api.WatchEventsResponse> watch() => events.stream;
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected command or recovery');
  }
}

api.WatchEventsResponse baseline({bool observer = false}) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '1',
      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': observer ? 'ACCESS_OBSERVER' : 'ACCESS_OWNER',
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          if (!observer) 'activeProfileId': 'profile-a',
          if (!observer) 'accountId': 'private-account',
        },
      },
    });

void main() {
  test(
    'US-03: revoked stream clears private state but retains intentions',
    () async {
      final directory = await Directory.systemTemp.createTemp('en-revocation-');
      final first = RevocationConnection();
      final second = RevocationConnection();
      var opens = 0;
      final journal = ClientIntentJournal(
        directory,
        requestIdFactory: () => '12345678-1234-4234-8234-123456789abc',
      );
      final intent = await journal.prepare(
        api.OperationKind.OPERATION_KIND_CONNECT,
      );
      final session = ClientSession(
        journal: journal,
        open: () async => opens++ == 0 ? first : second,
      );
      try {
        await session.connect();
        first.events.add(baseline());
        await pumpEventQueue();
        expect(session.state.snapshot!.status.accountId, 'private-account');
        final epoch = session.state.contextEpoch;
        final failure = api.Failure(
          code: api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
        );
        first.events.addError(
          GrpcError.permissionDenied('private transport detail', [failure]),
        );
        await pumpEventQueue();
        expect(session.state.link, ClientLinkState.unavailable);
        expect(session.state.snapshot, isNull);
        expect(session.state.operations, isEmpty);
        expect(session.state.invalidated, isEmpty);
        expect(session.state.contextEpoch, greaterThan(epoch));
        expect(
          session.state.failure!.code,
          api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
        );
        failure.code = api.ErrorCode.ERROR_CODE_INTERNAL;
        expect(
          session.state.failure!.code,
          api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
        );
        expect((await journal.pending()).single.requestId, intent.requestId);
        await expectLater(session.recoverPending(), throwsStateError);
        expect(first.calls, 0);
        expect(opens, 1); // No automatic reconnect/replay on permission denial.

        await session.connect();
        expect(first.closed, isTrue);
        expect(session.state.link, ClientLinkState.awaitingSnapshot);
        expect(session.state.failure, isNull);
        second.events.add(baseline(observer: true));
        await pumpEventQueue();
        expect(session.state.link, ClientLinkState.ready);
        expect(
          session.state.snapshot!.runtime.callerAccess,
          api.Access.ACCESS_OBSERVER,
        );
        expect(session.state.snapshot!.status.accountId, isEmpty);
        await expectLater(session.recoverPending(), throwsStateError);
        expect(second.calls, 0);
        expect((await journal.pending()).single.requestId, intent.requestId);
      } finally {
        await session.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('transport text cannot masquerade as typed owner failure', () async {
    final controller = ClientStateController();
    final source = StreamController<api.WatchEventsResponse>();
    try {
      await controller.attach(source.stream);
      source.add(baseline());
      await pumpEventQueue();
      source.addError(
        const GrpcError.permissionDenied(
          'ERROR_CODE_OWNER_REQUIRED private detail',
        ),
      );
      await pumpEventQueue();
      expect(controller.link, ClientLinkState.unavailable);
      expect(controller.snapshot, isNull);
      expect(controller.failure, isNull);
    } finally {
      controller.dispose();
      await source.close();
    }
  });
}
