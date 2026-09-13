import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_peers.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/local_client_events.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_host.dart';

Map<String, Object> _page(int index, {bool drift = false}) => {
  'page': {
    'metadata': {
      'instanceId': 'runtime-a',
      'revision': drift && index == 2 ? '8' : '7',
    },
    if (index == 1) 'nextPageToken': 'opaque-next',
  },
  'snapshotState': 'AGENT_SNAPSHOT_STATE_PREVIOUS',
  'mapRevision': '11',
  'targetMapRevision': '12',
  'peers': [
    {'id': 'peer-$index', 'selectedPath': 'PATH_KIND_RELAY'},
  ],
};

void main() {
  final executable = Platform.environment['ENDLESSNET_TESTSERVER'];
  test(
    'US-04/14: producer guard denies direct observer peer RPC',
    () async {
      final host = await ScenarioHost.start(executable!, [
        {
          'method': 'GetRuntimeInfo',
          'request': {},
          'responses': [
            {
              'runtime': {
                'protocol': api.ClientContract.protocol,
                'contractSha256': api.ClientContract.sha256,
                'instanceId': 'runtime-a',
                'callerAccess': 'ACCESS_OBSERVER',
              },
            },
          ],
        },
        // No ListPeers expectation: authorization must reject before dispatch.
      ], observer: true);
      LocalClientEvents? connection;
      try {
        connection = await LocalClientEvents.open(endpoint: host.endpoint);
        await expectLater(
          connection.listPeers(
            api.ListPeersRequest(
              profile: api.ProfileRef(profileId: 'private-profile'),
              page: api.PageRequest(pageSize: 100),
            ),
          ),
          throwsA(
            predicate<Object>(
              (error) =>
                  failureFromLocalRPCError(error)?.code ==
                  api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
            ),
          ),
        );
        await connection.close();
        await host.verify();
      } finally {
        await connection?.close();
        await host.close();
      }
    },
    skip: executable == null
        ? 'Requires pinned producer host in desktop CI'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test(
    'US-04: process peer fixtures validate pagination and revision drift',
    () async {
      for (final drift in [false, true]) {
        var reads = 0;
        final result = readClientPeers(
          (_) async =>
              api.ListPeersResponse()
                ..mergeFromProto3Json(_page(++reads, drift: drift)),
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          search: ' exact query ',
        );
        if (drift) {
          await expectLater(result, throwsFormatException);
        } else {
          expect((await result).peers.map((peer) => peer.id), [
            'peer-1',
            'peer-2',
          ]);
        }
        expect(reads, 2);
      }
    },
  );

  for (final scenario in ['pages', 'revision-drift', 'observer']) {
    test(
      'US-04: producer peer catalog $scenario while events remain open',
      () async {
        final directory = await Directory.systemTemp.createTemp('en-peers-');
        addTearDown(() => directory.delete(recursive: true));
        final observer = scenario == 'observer';
        final runtime = {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': observer ? 'ACCESS_OBSERVER' : 'ACCESS_OWNER',
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
                    if (!observer) 'activeProfileId': 'profile-a',
                  },
                },
              },
            ],
          },
          if (!observer)
            for (var index = 1; index <= 2; index++)
              {
                'method': 'ListPeers',
                'request': {
                  'profile': {'profileId': 'profile-a'},
                  'search': ' exact query ',
                  'page': {
                    'pageSize': 100,
                    if (index == 2) 'pageToken': 'opaque-next',
                  },
                },
                'responses': [
                  _page(index, drift: scenario == 'revision-drift'),
                ],
              },
        ], observer: observer);
        final session = ClientSession(
          journal: ClientIntentJournal(directory),
          endpoint: host.endpoint,
        );
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
          final result = session.listPeers(search: ' exact query ');
          if (observer) {
            await expectLater(result, throwsStateError);
          } else if (scenario == 'revision-drift') {
            await expectLater(result, throwsFormatException);
          } else {
            final catalog = await result;
            expect(catalog.peers.map((peer) => peer.id), ['peer-1', 'peer-2']);
            expect(catalog.peers.every((peer) => peer.isFrozen), isTrue);
            expect(
              catalog.snapshotState,
              api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_PREVIOUS,
            );
            expect(catalog.mapRevision.toString(), '11');
            expect(catalog.targetMapRevision.toString(), '12');
          }
          expect(session.state.link, ClientLinkState.ready);
          expect(await session.journal.pending(), isEmpty);
          await session.close();
          // Exact script verification also rejects retries, mutations and probes.
          await host.verify();
        } finally {
          await session.close();
          await host.close();
        }
      },
      skip: executable == null
          ? 'Requires pinned producer host in desktop CI'
          : false,
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
