import 'package:endlessnet/client_peers.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
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
