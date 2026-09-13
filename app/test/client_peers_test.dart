import 'package:endlessnet/client_peers.dart';
import 'dart:io';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
  test(
    'US-04: peer session guards owner context and stops stale pagination',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'en-peer-session-',
      );
      final connection = fixtures.FakeConnection();
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => connection,
      );
      var calls = 0;
      api.ListPeersResponse response({
        String next = '',
        String revision = '7',
      }) => api.ListPeersResponse()
        ..mergeFromProto3Json({
          'page': {
            'metadata': {'instanceId': 'runtime-a', 'revision': revision},
            'nextPageToken': next,
          },
        });
      try {
        await session.connect();
        await expectLater(session.listPeers(), throwsStateError);
        connection.events.add(
          fixtures.snapshot()
            ..snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER
            ..snapshot.status.activeProfileId = 'profile-a',
        );
        await pumpEventQueue();
        await expectLater(session.listPeers(), throwsStateError);
        connection.events.add(fixtures.snapshot()..sequence += 1);
        await pumpEventQueue();
        await expectLater(session.listPeers(), throwsStateError);
        connection.events.add(
          fixtures.snapshot()
            ..sequence += 2
            ..snapshot.status.activeProfileId = 'profile-a',
        );
        await pumpEventQueue();
        connection.peers = (request) async {
          calls++;
          expect(request.profile.profileId, 'profile-a');
          expect(request.search, 'exact query');
          return response();
        };
        expect((await session.listPeers(search: 'exact query')).peers, isEmpty);
        expect(calls, 1);
        connection.peers = (_) async => response(revision: '6');
        await expectLater(session.listPeers(), throwsStateError);

        var sequence = 4;
        for (final domain in [
          api.Domain.DOMAIN_PEERS,
          api.Domain.DOMAIN_NETWORKS,
          api.Domain.DOMAIN_PROFILES,
        ]) {
          for (var repeat = 0; repeat < 2; repeat++) {
            calls = 0;
            connection.peers = (_) async {
              calls++;
              connection.events.add(
                api.WatchEventsResponse()..mergeFromProto3Json({
                  'sequence': '${sequence++}',
                  'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                  'invalidated': {'domain': domain.name},
                }),
              );
              await pumpEventQueue();
              return response(next: 'must-not-fetch');
            };
            await expectLater(session.listPeers(), throwsStateError);
            expect(calls, 1);
          }
        }
        for (final change in ['profile', 'network', 'owner']) {
          final initial = fixtures.snapshot()
            ..sequence += sequence++ - 1
            ..snapshot.status.activeProfileId = 'profile-a';
          connection.events.add(initial);
          await pumpEventQueue();
          calls = 0;
          connection.peers = (_) async {
            calls++;
            final changed = fixtures.snapshot()
              ..sequence += sequence++ - 1
              ..snapshot.status.activeProfileId = 'profile-a';
            if (change == 'profile') {
              changed.snapshot.status.activeProfileId = 'profile-b';
            } else if (change == 'network') {
            changed.snapshot.status.network = api.Network(id: 'network-b');
            } else {
              changed.snapshot.runtime.callerAccess =
                  api.Access.ACCESS_OBSERVER;
            }
            connection.events.add(changed);
            await pumpEventQueue();
            return response(next: 'must-not-fetch');
          };
          await expectLater(session.listPeers(), throwsStateError);
          expect(calls, 1);
        }
        expect(await session.journal.pending(), isEmpty);
      } finally {
        await session.close();
        await directory.delete(recursive: true);
      }
    },
  );
  revision(int value) =>
      (api.SnapshotMetadata()..mergeFromProto3Json({'revision': '$value'}))
          .revision;
  api.ListPeersResponse page(String id, {String next = ''}) =>
      api.ListPeersResponse(
        peers: id.isEmpty
            ? []
            : [
                api.Peer(
                  id: id,
                  hostname: 'synthetic',
                  selectedEndpoint: 'opaque-endpoint',
                  selectionReasonKey: 'path.unconfirmed',
                ),
              ],
        page: api.PageResponse(
          metadata: api.SnapshotMetadata(
            instanceId: 'runtime-a',
            revision: revision(7),
          ),
          nextPageToken: next,
        ),
        mapRevision: revision(11),
        targetMapRevision: revision(12),
      );

  test(
    'US-04: paginated peers retain exact query and immutable observed paths',
    () async {
      final pages = [page('peer-a', next: 'opaque/next'), page('peer-b')];
      var calls = 0;
      final catalog = await readClientPeers(
        (request) async {
          expect(request.isFrozen, isTrue);
          expect(request.profile.profileId, 'profile-a');
          expect(request.search, 'exact query');
          expect(request.page.pageSize, 100);
          expect(request.page.pageToken, calls == 0 ? '' : 'opaque/next');
          return pages[calls++];
        },
        instanceId: 'runtime-a',
        profileId: 'profile-a',
        search: 'exact query',
      );
      pages.first.peers.first.hostname = 'changed';
      expect(calls, 2);
      expect(catalog.peers.map((peer) => peer.id), ['peer-a', 'peer-b']);
      expect(catalog.peers.first.hostname, 'synthetic');
      expect(catalog.peers.first.selectedEndpoint, 'opaque-endpoint');
      expect(catalog.peers.first.isFrozen, isTrue);
      expect(catalog.metadata.isFrozen, isTrue);
      expect(catalog.mapRevision, revision(11));
      expect(catalog.targetMapRevision, revision(12));
      expect(() => catalog.peers.clear(), throwsUnsupportedError);
    },
  );

  test(
    'US-04: empty peer projection preserves every typed snapshot state',
    () async {
      for (final state in api.AgentSnapshotState.values) {
        final response = page('')..snapshotState = state;
        final catalog = await readClientPeers(
          (_) async => response,
          instanceId: 'runtime-a',
          profileId: 'profile-a',
        );
        expect(catalog.peers, isEmpty);
        expect(catalog.snapshotState, state);
      }
    },
  );

  test('US-04: inconsistent peer pages fail the entire projection', () async {
    for (final corrupt in <void Function(api.ListPeersResponse)>[
      (p) => p.clearPage(),
      (p) => p.page.clearMetadata(),
      (p) => p.page.metadata.instanceId = 'other-runtime',
      (p) => p.page.metadata.revision = revision(8),
      (p) => p.mapRevision = revision(13),
      (p) => p.targetMapRevision = revision(14),
      (p) => p.snapshotState = api.AgentSnapshotState.values.last,
      (p) => p.peers.first.id = 'peer-a',
      (p) => p.peers.first.id = '',
      (p) => p.page.nextPageToken = 'next',
      (p) =>
          p.peers.addAll(List.generate(100, (i) => api.Peer(id: 'extra-$i'))),
    ]) {
      var calls = 0;
      await expectLater(
        readClientPeers(
          (_) async {
            calls++;
            if (calls == 1) return page('peer-a', next: 'next');
            final response = page('peer-b');
            corrupt(response);
            return response;
          },
          instanceId: 'runtime-a',
          profileId: 'profile-a',
        ),
        throwsFormatException,
      );
      expect(calls, 2);
    }
  });

  test('US-04: invalid query context never contacts the producer', () async {
    for (final query in ['', 'я' * 129]) {
      await expectLater(
        readClientPeers(
          (_) async => throw StateError('Unexpected RPC'),
          instanceId: 'runtime-a',
          profileId: query.isEmpty ? '' : 'profile-a',
          search: query,
        ),
        throwsFormatException,
      );
    }
  });
}
