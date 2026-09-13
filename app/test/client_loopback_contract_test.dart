import 'dart:async';
import 'dart:io';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'support/loopback_contract_server.dart';

class _WireConnection implements ClientConnection {
  _WireConnection(this.channel, this.client, String instanceId)
    : mutations = ClientMutations(client, instanceId: instanceId);
  final ClientChannel channel;
  final api.ClientServiceClient client;
  @override
  final ClientMutations mutations;
  @override
  Stream<api.WatchEventsResponse> watch() =>
      client.watchEvents(api.WatchEventsRequest());
  @override
  Future<void> close() => channel.shutdown();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected connection method');
}

Future<void> _until(ClientStateController state, bool Function() ready) async {
  final result = Completer<void>();
  void changed() {
    if (ready() && !result.isCompleted) result.complete();
  }

  state.addListener(changed);
  try {
    changed();
    await result.future.timeout(const Duration(seconds: 8));
  } finally {
    state.removeListener(changed);
  }
}

void main() {
  test(
    'US-01/03 mobile-capable protobuf wire mock preserves durable intent',
    () async {
      const requestId = '11111111-1111-4111-8111-111111111111';
      final directory = await Directory.systemTemp.createTemp(
        'client-wire-mock-',
      );
      final journal = ClientIntentJournal(
        directory,
        requestIdFactory: () => requestId,
      );
      final fixture = LoopbackContractServer(
        requestId: requestId,
        beforeAccept: () async {
          final persisted = await ClientIntentJournal(directory).pending();
          expect(persisted.single.requestId, requestId);
          expect(
            persisted.single.kind,
            api.OperationKind.OPERATION_KIND_CONNECT,
          );
        },
      );
      final server = Server.create(services: [fixture]);
      ClientSession? session;
      try {
        // Test-only loopback TCP: never an alternate production connection path.
        await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
        session = ClientSession(
          journal: journal,
          open: () async {
            final channel = ClientChannel(
              '127.0.0.1',
              port: server.port!,
              options: const ChannelOptions(
                credentials: ChannelCredentials.insecure(),
              ),
            );
            final client = api.ClientServiceClient(
              channel,
              options: CallOptions(
                metadata: api.ClientContract.metadata,
                timeout: const Duration(seconds: 8),
              ),
            );
            try {
              final runtime = await bootstrapLocalClient(client);
              return _WireConnection(channel, client, runtime.instanceId);
            } catch (_) {
              await channel.shutdown();
              rethrow;
            }
          },
        );
        final active = session;
        await active.connect();
        await _until(
          active.state,
          () => active.state.link == ClientLinkState.ready,
        );
        final accepted = await active.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (commands, mutation) => commands.connect(
            api.ConnectRequest(
              mutation: mutation,
              profile: api.ProfileRef(profileId: 'profile-a'),
            ),
          ),
        );
        expect(accepted.terminal, isFalse);
        expect(
          active.state.snapshot!.status.connectionPhase,
          api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
        );
        final recovered = (await active.recoverPending()).single;
        expect(recovered.succeeded, isTrue);
        expect((await journal.pending()).single.requestId, requestId);
        expect(
          active.state.snapshot!.status.connectionPhase,
          api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
        );
        fixture.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '2',
            'metadata': {'instanceId': 'mock-runtime', 'revision': '8'},
            'statusChanged': fixture
                .status(8, api.ConnectionPhase.CONNECTION_PHASE_CONNECTED)
                .toProto3Json(),
          }),
        );
        await _until(
          active.state,
          () =>
              active.state.snapshot?.status.connectionPhase ==
              api.ConnectionPhase.CONNECTION_PHASE_CONNECTED,
        );
        await journal.acknowledge(recovered);
        expect(await journal.pending(), isEmpty);
        expect(fixture.calls, [
          'GetRuntimeInfo',
          'WatchEvents',
          'Connect',
          'GetOperation',
        ]);
        expect(fixture.violations, isEmpty);
      } finally {
        await session?.close();
        await fixture.events.close();
        await server.shutdown();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
