@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_notification_delivery.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

api.WatchEventsResponse snapshot(
  int revision, {
  String profile = 'a',
  String account = 'account-a',
}) {
  final value = fixtures.snapshot(revision);
  value.snapshot.status.activeProfileId = profile;
  value.snapshot.status.accountId = account;
  value.snapshot.status.mergeFromProto3Json({
    'session': {'state': 'SESSION_STATE_EXPIRING'},
    'credential': {'state': 'CREDENTIAL_STATE_EXPIRING'},
  });
  return value;
}

void main() {
  late ClientStateController state;
  late StreamController<api.WatchEventsResponse> stream;
  late ClientNotificationDelivery delivery;
  late List<(String, String)> calls;
  late List<Completer<ClientNotificationDeliveryResult>> replies;
  setUp(() async {
    state = ClientStateController();
    stream = StreamController<api.WatchEventsResponse>();
    calls = [];
    replies = [];
    await state.attach(stream.stream);
    delivery = ClientNotificationDelivery(
      state: state,
      enabled: true,
      locale: ClientLocale.en,
      deliver: (title, body) {
        calls.add((title, body));
        final reply = Completer<ClientNotificationDeliveryResult>();
        replies.add(reply);
        return reply.future;
      },
    );
  });
  tearDown(() async {
    delivery.dispose();
    await state.detach();
    await stream.close();
    state.dispose();
    for (final reply in replies) {
      if (!reply.isCompleted) {
        reply.complete(ClientNotificationDeliveryResult.delivered);
      }
    }
    await pumpEventQueue();
  });
  Future<void> emit(int revision, {String profile = 'a'}) async {
    stream.add(snapshot(revision, profile: profile));
    await pumpEventQueue();
  }

  Future<void> complete(
    int index,
    ClientNotificationDeliveryResult value,
  ) async {
    replies[index].complete(value);
    await pumpEventQueue();
  }

  test(
    'blocked credentials deliver once and valid recovery permits next episode',
    () async {
      Future<void> credential(int revision, String value) async {
        final event = snapshot(revision);
        event.snapshot.status.mergeFromProto3Json({
          'session': {'state': 'SESSION_STATE_ACTIVE'},
          'credential': {'state': value},
        });
        stream.add(event);
        await pumpEventQueue();
      }

      await credential(1, 'CREDENTIAL_STATE_BLOCKED');
      expect(
        calls.single.$2,
        'Device credentials are blocked. Open EndlessNet to review the required action.',
      );
      await complete(0, ClientNotificationDeliveryResult.delivered);
      await credential(2, 'CREDENTIAL_STATE_BLOCKED');
      expect(calls.length, 1);
      await credential(3, 'CREDENTIAL_STATE_VALID');
      await credential(4, 'CREDENTIAL_STATE_BLOCKED');
      expect(calls.length, 2);
      expect(calls.last, calls.first);
    },
  );

  test(
    'one delivery in flight; latest locale used for next notice, no replay',
    () async {
      expect(calls, isEmpty);
      await emit(1);
      expect(calls.length, 1);
      delivery.locale = ClientLocale.ru;
      await emit(2);
      expect(calls.length, 1);
      await complete(0, ClientNotificationDeliveryResult.delivered);
      expect(calls.length, 2);
      expect(calls.first, (
        'EndlessNet',
        'Your session is expiring. Open EndlessNet to review renewal options.',
      ));
      expect(calls.last, (
        'EndlessNet',
        'Срок учётных данных устройства истекает. Откройте EndlessNet, чтобы проверить их состояние.',
      ));
      await complete(1, ClientNotificationDeliveryResult.delivered);
      await emit(3);
      delivery.retry();
      expect(calls.length, 2);
    },
  );
  for (final failure in ClientNotificationDeliveryResult.values.where(
    (value) => value != ClientNotificationDeliveryResult.delivered,
  )) {
    test('$failure stays distinct, no state-driven retry storm', () async {
      await emit(1);
      await complete(0, failure);
      expect(delivery.result, failure);
      await emit(2);
      await emit(3);
      expect(calls.length, 1);
      expect(delivery.result, failure);
      delivery.retry();
      expect(calls.length, 2);
      await complete(1, ClientNotificationDeliveryResult.delivered);
      expect(calls.length, 3);
    });
  }
  test('adapter exception becomes fixed failure and can be retried', () async {
    await emit(1);
    replies.first.completeError(StateError('private native error'));
    await pumpEventQueue();
    expect(delivery.result, ClientNotificationDeliveryResult.failed);
    delivery.retry();
    expect(calls.length, 2);
  });
  test(
    'disable invalidates pending completion and sends no queued credential',
    () async {
      await emit(1);
      delivery.enabled = false;
      await complete(0, ClientNotificationDeliveryResult.permissionDenied);
      expect(delivery.result, isNull);
      expect(calls.length, 1);
      delivery.enabled = true;
      expect(calls.length, 2);
      await complete(1, ClientNotificationDeliveryResult.delivered);
      expect(calls.length, 3);
    },
  );
  test(
    'profile ABA discards old completion without acknowledging new notice',
    () async {
      await emit(1);
      await emit(2, profile: 'b');
      await emit(3);
      expect(calls.length, 1);
      await complete(0, ClientNotificationDeliveryResult.permissionDenied);
      expect(delivery.result, isNull);
      expect(calls.length, 2);
      await complete(1, ClientNotificationDeliveryResult.delivered);
      expect(calls.length, 3);
    },
  );
  test(
    'reconnect retains delivered dedup but discards in-flight result',
    () async {
      await emit(1);
      await complete(0, ClientNotificationDeliveryResult.delivered);
      await state.detach();
      await stream.close();
      stream = StreamController<api.WatchEventsResponse>();
      await state.attach(stream.stream);
      await emit(1);
      await complete(1, ClientNotificationDeliveryResult.unavailable);
      expect(delivery.result, isNull);
      expect(calls.length, 3);
      expect(calls.last.$2, startsWith('Device credentials'));
      await complete(2, ClientNotificationDeliveryResult.delivered);
      await emit(2);
      expect(calls.length, 3);
    },
  );
  test('same profile with changed account invalidates old delivery', () async {
    await emit(1);
    stream.add(snapshot(2, account: 'account-b'));
    await pumpEventQueue();
    await complete(0, ClientNotificationDeliveryResult.permissionDenied);
    expect(delivery.result, isNull);
    expect(calls.length, 2);
    await complete(1, ClientNotificationDeliveryResult.delivered);
    expect(calls.length, 3);
  });
  test('dispose detaches listener and ignores late result', () async {
    await emit(1);
    delivery.dispose();
    await complete(0, ClientNotificationDeliveryResult.delivered);
    await emit(2);
    expect(calls.length, 1);
    // Replace disposed instance for the shared teardown.
    delivery = ClientNotificationDelivery(
      state: state,
      enabled: false,
      locale: ClientLocale.en,
      deliver: (_, _) async => throw StateError('disabled'),
    );
  });
}
