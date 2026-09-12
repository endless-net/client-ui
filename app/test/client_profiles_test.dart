import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

api.ListProfilesResponse page(
  String id, {
  String next = '',
  String revision = '7',
}) => api.ListProfilesResponse()
  ..mergeFromProto3Json({
    'activeProfileId': 'a',
    'profiles': [
      {'id': id, 'displayName': 'Profile $id', 'active': id == 'a'},
    ],
    'page': {
      'nextPageToken': next,
      'metadata': {'instanceId': 'runtime-a', 'revision': revision},
    },
  });

void main() {
  test(
    'US-08: complete catalog preserves opaque page tokens and freezes entries',
    () async {
      final requests = <String>[];
      final first = page('a', next: 'opaque-token');
      final catalog = await readClientProfiles((request) async {
        requests.add(request.page.pageToken);
        expect(request.page.pageSize, 100);
        return requests.length == 1 ? first : page('b');
      }, instanceId: 'runtime-a');
      expect(requests, ['', 'opaque-token']);
      first.profiles.first.displayName = 'changed';
      expect(catalog.profiles.first.displayName, 'Profile a');
      expect(catalog.activeProfileId, 'a');
      expect(() => catalog.profiles.clear(), throwsUnsupportedError);
      expect(() => catalog.profiles.first.clearId(), throwsUnsupportedError);
    },
  );
  for (final fault in [
    'revision',
    'duplicate',
    'token-loop',
    'active',
    'instance',
  ]) {
    test(
      'US-08: $fault rejects the catalog without partial publication',
      () async {
        var calls = 0;
        await expectLater(
          readClientProfiles((request) async {
            calls++;
            if (calls == 1) return page('a', next: 'token');
            final response = page(fault == 'duplicate' ? 'a' : 'b');
            if (fault == 'revision') response.page.metadata.revision += 1;
            if (fault == 'token-loop') response.page.nextPageToken = 'token';
            if (fault == 'active') response.activeProfileId = 'b';
            if (fault == 'instance') {
              response.page.metadata.instanceId = 'runtime-b';
            }
            return response;
          }, instanceId: 'runtime-a'),
          throwsFormatException,
        );
        expect(calls, 2);
      },
    );
  }
}
