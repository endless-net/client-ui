import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet/client_privileged_recovery.dart';
import 'package:endlessnet/client_privileged_session.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'client_session_test.dart' as fixtures;

class LookupOnlyClient implements api.ClientServiceClient {
  int calls = 0;
  String profile = 'profile-a';
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #getOperation) {
      throw StateError('Mutation replayed');
    }
    calls++;
    final request =
        invocation.positionalArguments.single as api.GetOperationRequest;
    return ImmediateResponse<api.GetOperationResponse>(
      api.GetOperationResponse()..mergeFromProto3Json({
        'operation': {
          'id': 'operation',
          'requestId': request.requestId,
          'kind': 'OPERATION_KIND_FORGET_LOCAL_ENROLLMENT',
          'profileId': profile,
          'state': 'OPERATION_STATE_PENDING',
          'metadata': {'instanceId': 'runtime-a', 'revision': '8'},
        },
      }),
    );
  }
}

class ImmediateResponse<T> implements ResponseFuture<T> {
  ImmediateResponse(T value) : _value = Future.value(value);
  final Future<T> _value;
  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) =>
      _value.then(onValue, onError: onError);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected response API');
}

void main() {
  for (final scenario in ['exited', 'unconfirmed', 'canceled', 'mismatch']) {
    test('elevation $scenario uses retained lookup without replay', () async {
      final directory = await Directory.systemTemp.createTemp('en-elevation-');
      final rpc = LookupOnlyClient();
      final connection = fixtures.FakeConnection()
        ..mutations = ClientMutations(rpc, instanceId: 'runtime-a');
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => connection,
      );
      try {
        await session.connect();
        connection.events.add(
          fixtures.snapshot()..snapshot.status.activeProfileId = 'profile-a',
        );
        await pumpEventQueue();
        var launches = 0;
        const kind = api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT;
        Future<void> submit() async {
          final result = await session.submitPrivilegedViaLookup(
            kind,
            (mutation) => ClientPrivilegedRecovery.forget(
              api.ForgetLocalEnrollmentRequest(
                mutation: mutation,
                profile: api.ProfileRef(profileId: 'profile-a'),
                confirmed: true,
              ),
            ),
            (request) async {
              launches++;
              expect(
                (await session.journal.pending()).single.requestId,
                request.mutation.requestId,
              );
              if (scenario == 'mismatch') rpc.profile = 'other';
              return scenario == 'canceled'
                  ? ClientElevationOutcome.canceled
                  : scenario == 'unconfirmed'
                  ? ClientElevationOutcome.unconfirmed
                  : ClientElevationOutcome.exited;
            },
          );
          expect(result.terminal, false);
        }

        if (scenario == 'canceled') {
          await expectLater(submit(), throwsStateError);
        } else if (scenario == 'mismatch') {
          await expectLater(submit(), throwsFormatException);
        } else {
          await submit();
        }
        expect(rpc.calls, scenario == 'canceled' ? 0 : 1);
        expect(await session.journal.pending(), hasLength(1));
        await expectLater(submit(), throwsStateError);
        expect(launches, 1);
      } finally {
        await session.close();
        await directory.delete(recursive: true);
      }
    });
  }
}
