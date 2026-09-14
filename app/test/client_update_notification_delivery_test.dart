@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_notification_delivery.dart';
import 'package:endlessnet/client_update_notification_source.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;
import 'client_update_notifications_test.dart' as updates;

api.WatchEventsResponse snapshot(
  int sequence, {
  bool observer = false,
  bool expiring = false,
}) {
  final event = fixtures.snapshot(sequence);
  event.snapshot.runtime.build = updates.build();
  if (observer) {
    event.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
  }
  if (expiring) {
    event.snapshot.status.ensureSession().state =
        api.SessionState.SESSION_STATE_EXPIRING;
  }
  return event;
}

api.WatchEventsResponse invalidated(int sequence) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '$sequence',
      'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
      'invalidated': {'domain': 'DOMAIN_UPDATES'},
    });
void main() {
  late ClientStateController state;
  late StreamController<api.WatchEventsResponse> stream;
  late ClientNotificationDelivery delivery;
  late List<Completer<api.UpdateInfo>> reads;
  late List<String> bodies;
  late List<Completer<ClientNotificationDeliveryResult>> sends;
  setUp(() async {
    state = ClientStateController();
    stream = StreamController();
    await state.attach(stream.stream);
    reads = [];
    bodies = [];
    sends = [];
    delivery = ClientNotificationDelivery(
      state: state,
      uiBuild: updates.build(),
      enabled: false,
      locale: ClientLocale.en,
      now: () => updates.clock,
      loadUpdates: () {
        final c = Completer<api.UpdateInfo>();
        reads.add(c);
        return c.future;
      },
      deliver: (_, body) {
        bodies.add(body);
        final c = Completer<ClientNotificationDeliveryResult>();
        sends.add(c);
        return c.future;
      },
    );
  });
  tearDown(() async {
    delivery.dispose();
    await state.detach();
    await stream.close();
    state.dispose();
    for (final read in reads) {
      if (!read.isCompleted) read.complete(updates.projection());
    }
    for (final send in sends) {
      if (!send.isCompleted) {
        send.complete(ClientNotificationDeliveryResult.delivered);
      }
    }
    await pumpEventQueue();
  });
  Future<void> emit(api.WatchEventsResponse event) async {
    stream.add(event);
    await pumpEventQueue();
  }

  test(
    'opt-in gates discovery; only one serial deadline/update delivery',
    () async {
      await emit(snapshot(1, expiring: true));
      expect(reads, isEmpty);
      delivery.enabled = true;
      await pumpEventQueue();
      expect(reads, hasLength(1));
      expect(sends, hasLength(1));
      reads.single.complete(updates.projection());
      await pumpEventQueue();
      expect(sends, hasLength(1));
      sends.first.complete(ClientNotificationDeliveryResult.delivered);
      await pumpEventQueue();
      expect(sends, hasLength(2));
      expect(bodies.last, contains('verified update'));
      sends.last.complete(ClientNotificationDeliveryResult.delivered);
      await pumpEventQueue();
      await emit(snapshot(2));
      expect(reads, hasLength(1));
      expect(sends, hasLength(2));
    },
  );
  test(
    'latest invalidation wins without overlapping reads or stale delivery',
    () async {
      delivery.enabled = true;
      await emit(snapshot(1));
      await emit(invalidated(2));
      await emit(invalidated(3));
      expect(reads, hasLength(1));
      reads.first.complete(updates.projection());
      await pumpEventQueue();
      expect(sends, isEmpty);
      expect(reads, hasLength(2));
      reads.last.complete(updates.projection());
      await pumpEventQueue();
      expect(sends, hasLength(1));
    },
  );
  test('observer and disabled transitions discard pending discovery', () async {
    delivery.enabled = true;
    await emit(snapshot(1));
    await emit(snapshot(2, observer: true));
    reads.first.complete(updates.projection());
    await pumpEventQueue();
    expect(sends, isEmpty);
    await emit(snapshot(3));
    expect(reads, hasLength(2));
    delivery.enabled = false;
    reads.last.complete(updates.projection());
    await pumpEventQueue();
    expect(sends, isEmpty);
    expect(reads, hasLength(2));
  });
  test(
    'lookup failure has no automatic retry and explicit retry recovers',
    () async {
      delivery.enabled = true;
      await emit(snapshot(1));
      reads.first.completeError(StateError('private'));
      await pumpEventQueue();
      expect(delivery.updateLookupFailed, isTrue);
      await emit(snapshot(2));
      expect(reads, hasLength(1));
      delivery.retry();
      await pumpEventQueue();
      expect(reads, hasLength(2));
      reads.last.complete(updates.projection());
      await pumpEventQueue();
      expect(delivery.updateLookupFailed, isFalse);
      expect(sends, hasLength(1));
    },
  );
  test(
    'same verified release after invalidation is not re-delivered',
    () async {
      delivery.enabled = true;
      await emit(snapshot(1));
      reads.first.complete(updates.projection());
      await pumpEventQueue();
      sends.first.complete(ClientNotificationDeliveryResult.delivered);
      await pumpEventQueue();
      await emit(invalidated(2));
      reads.last.complete(updates.projection());
      await pumpEventQueue();
      expect(sends, hasLength(1));
    },
  );
  test(
    'failed delivery retries the validated notice without rediscovery',
    () async {
      delivery.enabled = true;
      await emit(snapshot(1));
      reads.first.complete(updates.projection());
      await pumpEventQueue();
      sends.first.complete(ClientNotificationDeliveryResult.failed);
      await pumpEventQueue();
      expect(delivery.result, ClientNotificationDeliveryResult.failed);
      delivery.locale = ClientLocale.ru;
      delivery.retry();
      await pumpEventQueue();
      expect(reads, hasLength(1));
      expect(sends, hasLength(2));
      expect(bodies.last, contains('проверенное обновление'));
    },
  );
  for (final refreshFirst in [false, true]) {
    test(
      'in-flight failure waits for explicit retry after refresh first=$refreshFirst',
      () async {
        delivery.enabled = true;
        await emit(snapshot(1));
        reads.first.complete(updates.projection());
        await pumpEventQueue();
        await emit(invalidated(2));
        if (refreshFirst) {
          reads.last.complete(updates.projection());
          await pumpEventQueue();
        }
        sends.first.complete(ClientNotificationDeliveryResult.failed);
        await pumpEventQueue();
        if (!refreshFirst) {
          reads.last.complete(updates.projection());
          await pumpEventQueue();
        }
        expect(sends, hasLength(1));
        expect(delivery.result, ClientNotificationDeliveryResult.failed);
        delivery.retry();
        await pumpEventQueue();
        expect(sends, hasLength(2));
      },
    );
    test(
      'in-flight success survives metadata refresh first=$refreshFirst',
      () async {
        delivery.enabled = true;
        await emit(snapshot(1));
        reads.first.complete(updates.projection());
        await pumpEventQueue();
        expect(sends, hasLength(1));
        await emit(invalidated(2));
        if (refreshFirst) {
          reads.last.complete(updates.projection());
          await pumpEventQueue();
        }
        sends.first.complete(ClientNotificationDeliveryResult.delivered);
        await pumpEventQueue();
        if (!refreshFirst) {
          reads.last.complete(updates.projection());
          await pumpEventQueue();
        }
        expect(sends, hasLength(1));
      },
    );
  }
  for (final outcome in [
    ClientNotificationDeliveryResult.delivered,
    ClientNotificationDeliveryResult.failed,
  ]) {
    test('old release $outcome does not suppress a newer release', () async {
      delivery.enabled = true;
      await emit(snapshot(1));
      reads.first.complete(updates.projection());
      await pumpEventQueue();
      await emit(invalidated(2));
      reads.last.complete(
        updates.projection()..available.releaseId = 'new-release',
      );
      await pumpEventQueue();
      sends.first.complete(outcome);
      await pumpEventQueue();
      expect(sends, hasLength(2));
    });
  }
  test('disable and re-enable revoke an outstanding success receipt', () async {
    delivery.enabled = true;
    await emit(snapshot(1));
    reads.first.complete(updates.projection());
    await pumpEventQueue();
    delivery.enabled = false;
    delivery.enabled = true;
    reads.last.complete(updates.projection());
    await pumpEventQueue();
    sends.first.complete(ClientNotificationDeliveryResult.delivered);
    await pumpEventQueue();
    expect(sends, hasLength(2));
  });
  test('metadata expiry withdraws notice without another read', () async {
    var now = updates.clock;
    var count = 0;
    final timedState = ClientStateController();
    final timedStream = StreamController<api.WatchEventsResponse>();
    await timedState.attach(timedStream.stream);
    final source = ClientUpdateNotificationSource(
      state: timedState,
      uiBuild: updates.build(),
      enabled: true,
      now: () => now,
      load: () async {
        count++;
        return updates.projection()
          ..available.mergeFromProto3Json({
            'expiresAt': '2026-09-14T00:00:01Z',
          });
      },
    );
    timedStream.add(snapshot(1));
    await pumpEventQueue();
    expect(source.notice, isNotNull);
    final old = source.notice!;
    final expired = Completer<void>();
    source.addListener(() {
      if (source.notice == null && !expired.isCompleted) expired.complete();
    });
    now = DateTime.utc(2026, 9, 14, 0, 0, 1);
    await expired.future.timeout(const Duration(seconds: 5));
    expect(source.notice, isNull);
    expect(source.acknowledge(old), isFalse);
    expect(count, 1);
    source.dispose();
    await timedState.detach();
    await timedStream.close();
    timedState.dispose();
  });
}
