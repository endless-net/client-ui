import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_host.dart';

// Reserve a real persisted ID before serializing the exact producer script.
// Only preparation timing is controlled; storage and session code are real.
final class ScriptJournal extends ClientIntentJournal {
  ScriptJournal(super.directory);
  PendingClientIntent? reserved;
  @override
  Future<PendingClientIntent> prepare(api.OperationKind kind) async {
    final intent = reserved;
    if (intent == null) return super.prepare(kind);
    reserved = null;
    expect(intent.kind, kind);
    return intent;
  }
}

void main() {
  final executable = Platform.environment['ENDLESSNET_TESTSERVER'];
  test(
    'US-01/03: live session submits and recovers while WatchEvents stays open',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'en-session-rpc-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final journal = ScriptJournal(directory);
      final intent = await journal.prepare(
        api.OperationKind.OPERATION_KIND_CONNECT,
      );
      journal.reserved = intent;
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
            {
              'operation': {
                ...accepted,
                'state': 'OPERATION_STATE_SUCCEEDED',
                'change': {'changed': true},
              },
            },
          ],
        },
      ]);
      final session = ClientSession(journal: journal, endpoint: host.endpoint);
      try {
        final ready = Completer<void>();
        session.state.addListener(() {
          if (session.state.link == ClientLinkState.ready && !ready.isCompleted) {
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
