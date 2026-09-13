@Tags(['short'])
library;

import 'dart:async';

import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse event(int sequence, Map<String, Object> payload) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '$sequence',
      'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
      ...payload,
    });

Map<String, Object> status(int revision, String profile) => {
  'metadata': {'instanceId': 'runtime-a', 'revision': '$revision'},
  'activeProfileId': profile,
  'connectionPhase': 'CONNECTION_PHASE_CONNECTING',
};

api.WatchEventsResponse snapshot() => event(1, {
  'snapshot': {
    'runtime': {
      'protocol': api.ClientContract.protocol,
      'contractSha256': api.ClientContract.sha256,
      'instanceId': 'runtime-a',
      'callerAccess': 'ACCESS_OWNER',
    },
    'status': status(1, 'profile-a'),
  },
});

void main() {
  late ClientStateController state;
  late StreamController<api.WatchEventsResponse> source;
  setUp(() async {
    state = ClientStateController();
    source = StreamController<api.WatchEventsResponse>();
    await state.attach(source.stream);
  });
  tearDown(() async {
    await state.detach();
    await source.close();
    state.dispose();
  });

  test(
    'US-01: no authoritative status before snapshot; EOF clears old state',
    () async {
      expect(state.link, ClientLinkState.awaitingSnapshot);
      expect(state.snapshot, isNull);
      source.add(snapshot());
      await pumpEventQueue();
      expect(state.link, ClientLinkState.ready);
      expect(
        state.snapshot!.status.connectionPhase,
        api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
      );
      await source.close();
      await pumpEventQueue();
      expect(state.link, ClientLinkState.unavailable);
      expect(state.snapshot, isNull);
      expect(state.operations, isEmpty);
    },
  );

  test(
    'US-04/08: profile switch clears scoped invalidations and advances cache epoch',
    () async {
      source.add(snapshot());
      source.add(
        event(2, {
          'invalidated': {'domain': 'DOMAIN_PEERS', 'profileId': 'profile-a'},
        }),
      );
      await pumpEventQueue();
      expect(
        state.invalidated,
        contains((api.Domain.DOMAIN_PEERS, 'profile-a')),
      );
      final epoch = state.cacheEpoch;
      source.add(event(3, {'statusChanged': status(3, 'profile-b')}));
      await pumpEventQueue();
      expect(state.snapshot!.status.activeProfileId, 'profile-b');
      expect(state.cacheEpoch, greaterThan(epoch));
      expect(state.invalidated, isEmpty);
    },
  );

  test(
    'US-03: typed operation and session updates preserve separate state',
    () async {
      source.add(snapshot());
      source.add(
        event(2, {
          'operationChanged': {
            'id': 'op',
            'kind': 'OPERATION_KIND_RENEW_SESSION',
            'profileId': 'inactive',
            'state': 'OPERATION_STATE_RUNNING',
          },
        }),
      );
      source.add(
        event(3, {
          'sessionChanged': {'state': 'SESSION_STATE_RENEWING'},
        }),
      );
      await pumpEventQueue();
      expect(state.operations['op']!.profileId, 'inactive');
      expect(
        state.snapshot!.status.session.state,
        api.SessionState.SESSION_STATE_RENEWING,
      );
      expect(state.snapshot!.status.hasCredential(), isFalse);
      expect(() => state.operations.clear(), throwsUnsupportedError);
    },
  );

  test(
    'US-01: malformed stream clears sensitive data and flags invalid contract',
    () async {
      source.add(snapshot());
      source.add(event(2, {}));
      await pumpEventQueue();
      expect(state.link, ClientLinkState.unavailable);
      expect(state.invalidContract, isTrue);
      expect(state.snapshot, isNull);
    },
  );

  test(
    'US-03: reconnect cannot receive late events from the old subscription',
    () async {
      source.add(snapshot());
      await pumpEventQueue();
      final replacement = StreamController<api.WatchEventsResponse>();
      await state.attach(replacement.stream);
      source.add(event(2, {'statusChanged': status(2, 'stale-profile')}));
      await pumpEventQueue();
      expect(state.snapshot, isNull);
      replacement.add(snapshot());
      await pumpEventQueue();
      expect(state.snapshot!.status.activeProfileId, 'profile-a');
      await state.detach();
      await replacement.close();
    },
  );
}
