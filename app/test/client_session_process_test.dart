import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_host.dart';

Map<String, Object> recoveredOperation(Map<String, Object> accepted) => {
  ...accepted,
  'state': 'OPERATION_STATE_SUCCEEDED',
  'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
  'change': {'changed': true},
};

void main() {
  final executable = Platform.environment['ENDLESSNET_TESTSERVER'];
  test('US-03: process recovery fixture satisfies operation contract', () {
    final operation = ClientOperation.fromProto(
      api.Operation()..mergeFromProto3Json(
        recoveredOperation({
          'id': 'operation-a',
          'requestId': 'c06bd29f-7c77-4b27-943a-620081f313df',
          'kind': 'OPERATION_KIND_CONNECT',
          'state': 'OPERATION_STATE_PENDING',
        }),
      ),
    );
    expect(operation.succeeded, isTrue);
    expect(
      operation.value.continuity,
      api.ConnectionContinuity.CONNECTION_CONTINUITY_UNKNOWN,
    );
  });
  test(
    'US-01/03: live session submits and recovers while WatchEvents stays open',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'en-session-rpc-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const intent = PendingClientIntent(
        'c06bd29f-7c77-4b27-943a-620081f313df',
        api.OperationKind.OPERATION_KIND_CONNECT,
      );
      // Only UUID generation is deterministic. Preparation, persistence and
      // submission ordering are production code, not a pre-seeded outbox.
      final journal = ClientIntentJournal(
        directory,
        requestIdFactory: () => intent.requestId,
      );
      final runtime = {
        'protocol': api.ClientContract.protocol,
        'contractSha256': api.ClientContract.sha256,
        'instanceId': 'runtime-a',
        'callerAccess': 'ACCESS_OWNER',
      };
      final accepted = {
        'id': 'operation-a',
        'requestId': intent.requestId,
        'kind': 'OPERATION_KIND_CONNECT',
        'state': 'OPERATION_STATE_PENDING',
      };
      final host = await ScenarioHost.start(executable!, [
        {
          'method': 'GetRuntimeInfo',
          'request': {},
          'responses': [
            {'runtime': runtime},
          ],
        },
        {
          'method': 'WatchEvents',
          'request': {},
          'hold_open': true,
          'responses': [
            {
              'sequence': '1',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'snapshot': {
                'runtime': runtime,
                'status': {
                  'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                  'activeProfileId': 'profile-a',
                  'serviceState': 'SERVICE_STATE_DISCONNECTED',
                  'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
                },
              },
            },
          ],
        },
        {
          'method': 'Connect',
          'request': {
            'mutation': {
              'requestId': intent.requestId,
              'expectedInstanceId': 'runtime-a',
              'expectedRevision': '7',
            },
            'profile': {'profileId': 'profile-a'},
          },
          'responses': [
            {'operation': accepted},
          ],
        },
        {
          'method': 'GetOperation',
          'request': {'requestId': intent.requestId},
          'responses': [
            {'operation': recoveredOperation(accepted)},
          ],
        },
      ]);
      final session = ClientSession(journal: journal, endpoint: host.endpoint);
      try {
        final ready = Completer<void>();
        session.state.addListener(() {
          if (session.state.link == ClientLinkState.ready &&
              !ready.isCompleted) {
            ready.complete();
          }
        });
        await session.connect();
        await ready.future.timeout(const Duration(seconds: 10));
        final result = await session.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (commands, context) {
            return commands.connect(
              api.ConnectRequest(
                mutation: context,
                profile: api.ProfileRef(
                  profileId: session.state.snapshot!.status.activeProfileId,
                ),
              ),
            );
          },
        );
        expect(result.terminal, isFalse);
        expect(session.state.link, ClientLinkState.ready);
        // RPC acceptance must not synthesize connected state in the UI.
        expect(
          session.state.snapshot!.status.connectionPhase,
          api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
        );
        final recovered = await session.recoverPending();
        expect(recovered.single.succeeded, isTrue);
        expect(recovered.single.value.id, result.value.id);
        await journal.acknowledge(recovered.single);
        expect(await journal.pending(), isEmpty);
        await session.close();
        await host.verify();
      } finally {
        await session.close();
        await host.close();
      }
    },
    skip: executable == null
        ? 'Requires pinned held-open producer fixture in CI'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
