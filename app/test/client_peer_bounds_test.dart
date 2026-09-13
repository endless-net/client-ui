@Tags(['short'])
library;

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet/client_peers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  api.ListPeersResponse page(int start, int count, String token) =>
      api.ListPeersResponse(
          peers: List.generate(count, (i) => api.Peer(id: 'peer-${start + i}')),
          page: api.PageResponse(
            nextPageToken: token,
            metadata: api.SnapshotMetadata(),
          ),
        )
        ..page.metadata.mergeFromProto3Json({
          'instanceId': 'runtime',
          'revision': '1',
        });

  test(
    'peer catalog rejects empty continuation and oversized opaque token',
    () async {
      for (final response in [
        page(0, 0, 'next'),
        page(0, 1, 'x' * 2049),
        page(0, 1, 'я' * 1025),
      ]) {
        var calls = 0;
        await expectLater(
          readClientPeers(
            (_) async {
              calls++;
              return response;
            },
            instanceId: 'runtime',
            profileId: 'profile',
          ),
          throwsFormatException,
        );
        expect(calls, 1);
      }
    },
  );

  test('peer catalog permits exact 4096 bound and rejects overflow', () async {
    for (final total in [4096, 4097]) {
      var offset = 0;
      var calls = 0;
      final result = readClientPeers(
        (request) async {
          expect(request.page.pageToken, offset == 0 ? '' : '$offset');
          calls++;
          final count = total - offset > 100 ? 100 : total - offset;
          final response = page(
            offset,
            count,
            offset + count < total ? '${offset + count}' : '',
          );
          offset += count;
          return response;
        },
        instanceId: 'runtime',
        profileId: 'profile',
      );
      if (total == 4096) {
        expect((await result).peers.length, 4096);
      } else {
        await expectLater(result, throwsFormatException);
      }
      expect(calls, 41);
    }
  });
}
