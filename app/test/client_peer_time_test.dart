import 'package:endlessnet/client_peers.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  api.ListPeersResponse response() =>
      api.ListPeersResponse()..mergeFromProto3Json({
        'page': {
          'metadata': {'instanceId': 'runtime', 'revision': '1'},
        },
        'peers': [
          {
            'id': 'peer',
            'lastTransitionAt': '2026-01-01T00:00:00Z',
            'candidates': [
              {
                'checkedAt': '2026-01-01T00:00:00Z',
                'lastReachableAt': '2026-01-01T00:00:00Z',
                'rtt': '0.001s',
              },
            ],
          },
        ],
      });

  test('invalid peer timestamps and RTT fail before rendering', () async {
    for (final mutate in <void Function(api.Peer)>[
      (p) => p.lastTransitionAt.nanos = -1,
      (p) => p.lastTransitionAt.nanos = 1000000000,
      (p) => p.lastTransitionAt.seconds *= 1000,
      (p) => p.candidates.first.checkedAt.nanos = -1,
      (p) => p.candidates.first.lastReachableAt.seconds *= 1000,
      (p) => p.candidates.first.rtt.nanos = -1,
      (p) => p.candidates.first.rtt.nanos = 1000000000,
      (p) => p.candidates.first.rtt.seconds = p.lastTransitionAt.seconds * 1000,
    ]) {
      final page = response();
      mutate(page.peers.first);
      await expectLater(
        readClientPeers(
          (_) async => page,
          instanceId: 'runtime',
          profileId: 'profile',
        ),
        throwsFormatException,
      );
    }
  });

  test('valid and absent peer observations stay distinct', () async {
    for (final absent in [false, true]) {
      final page = response();
      if (absent) {
        page.peers.first.clearLastTransitionAt();
        page.peers.first.candidates.first
          ..clearCheckedAt()
          ..clearLastReachableAt()
          ..clearRtt();
      }
      final catalog = await readClientPeers(
        (_) async => page,
        instanceId: 'runtime',
        profileId: 'profile',
      );
      expect(catalog.peers.first.hasLastTransitionAt(), !absent);
      expect(catalog.peers.first.candidates.first.hasRtt(), !absent);
    }
  });
}
