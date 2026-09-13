@Tags(['short'])
library;

import 'dart:async';
import 'dart:io';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

class _NoRpc implements api.ClientServiceClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RPC');
}

class _Connection implements ClientConnection {
  final events = StreamController<api.WatchEventsResponse>();
  bool closed = false;
  @override
  final mutations = ClientMutations(_NoRpc(), instanceId: 'runtime-a');
  @override
  Stream<api.WatchEventsResponse> watch() => events.stream;
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected read');
}

api.WatchEventsResponse _snapshot({required bool identityReady}) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '1',
      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': 'ACCESS_OWNER',
          'capabilities': [
            if (identityReady)
              {
                'capability': 'CAPABILITY_IDENTITY_RECOVERY',
                'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
              },
          ],
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'activeProfileId': 'profile-a',
        },
      },
    });

void main() {
  test(
    'US-01/03 stale readiness requires fresh bootstrap without intent replay',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'client-stale-readiness-',
      );
      final first = _Connection();
      final second = _Connection();
      var opens = 0;
      var submits = 0;
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => ++opens == 1 ? first : second,
      );
      try {
        await session.connect();
        first.events.add(_snapshot(identityReady: true));
        await pumpEventQueue();
        expect(
          session.state.snapshot!.supports(
            api.Capability.CAPABILITY_IDENTITY_RECOVERY,
          ),
          isTrue,
        );
        final result = await session.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (_, context) async {
            submits++;
            return ClientOperation.fromProto(
              api.Operation(
                id: 'op-a',
                requestId: context.requestId,
                kind: api.OperationKind.OPERATION_KIND_CONNECT,
                state: api.OperationState.OPERATION_STATE_PENDING,
              ),
            );
          },
        );
        first.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '2',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'failure': {
              'code': 'ERROR_CODE_STALE_STATE',
              'reasonKey': 'synthetic-private-reason',
            },
          }),
        );
        await pumpEventQueue();
        expect(session.state.link, ClientLinkState.unavailable);
        expect(session.state.snapshot, isNull);
        expect(session.state.operations, isEmpty);
        expect(
          session.state.failure!.code,
          api.ErrorCode.ERROR_CODE_STALE_STATE,
        );
        expect(session.state.invalidContract, isFalse);
        expect(opens, 1); // No implicit reconnect or mutation from the failure.
        expect(
          (await session.journal.pending()).single.requestId,
          result.value.requestId,
        );
        await session.connect();
        expect(first.closed, isTrue);
        expect(opens, 2);
        expect(session.state.link, ClientLinkState.awaitingSnapshot);
        expect(session.state.snapshot, isNull);
        second.events.add(_snapshot(identityReady: false));
        await pumpEventQueue();
        expect(session.state.link, ClientLinkState.ready);
        expect(
          session.state.snapshot!.supports(
            api.Capability.CAPABILITY_IDENTITY_RECOVERY,
          ),
          isFalse,
        );
        await expectLater(
          session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
            _,
            context,
          ) async {
            submits++;
            throw StateError('Must recover original intention');
          }),
          throwsStateError,
        );
        expect(submits, 1);
        expect(
          (await ClientIntentJournal(directory).pending()).single.requestId,
          result.value.requestId,
        );
      } finally {
        await session.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
