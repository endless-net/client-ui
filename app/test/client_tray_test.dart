@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_tray.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse snapshot(
  int sequence, {
  String access = 'ACCESS_OWNER',
  String profile = 'profile-a',
  bool capability = true,
  String service = 'SERVICE_STATE_DISCONNECTED',
}) => api.WatchEventsResponse()
  ..mergeFromProto3Json({
    'sequence': '$sequence',
    'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
    'snapshot': {
      'runtime': {
        'protocol': api.ClientContract.protocol,
        'contractSha256': api.ClientContract.sha256,
        'instanceId': 'runtime-a',
        'callerAccess': access,
        'capabilities': [
          if (capability)
            {
              'capability': 'CAPABILITY_CONNECTION',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
        ],
      },
      'status': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
        'activeProfileId': profile,
        'serviceState': service,
        'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
      },
    },
  });

ClientOperation pending(api.OperationKind kind) => ClientOperation.fromProto(
  api.Operation(
    id: 'operation',
    requestId: 'request',
    kind: kind,
    state: api.OperationState.OPERATION_STATE_PENDING,
  ),
);

void main() {
  late ClientStateController state;
  late StreamController<api.WatchEventsResponse> events;
  late ClientTray tray;
  late Completer<ClientOperation> connection;
  var connects = 0;
  var disconnects = 0;
  setUp(() async {
    state = ClientStateController();
    events = StreamController<api.WatchEventsResponse>();
    connection = Completer<ClientOperation>();
    connects = 0;
    disconnects = 0;
    tray = ClientTray(
      state: state,
      connect: () {
        connects++;
        return connection.future;
      },
      disconnect: () async {
        disconnects++;
        return pending(api.OperationKind.OPERATION_KIND_DISCONNECT);
      },
    );
    await state.attach(events.stream);
  });
  tearDown(() async {
    tray.dispose();
    await state.detach();
    await events.close();
    state.dispose();
  });
  String? key(String label) =>
      tray.menu.items!.singleWhere((item) => item.label == label).key;
  Future<void> receive(api.WatchEventsResponse event) async {
    events.add(event);
    await pumpEventQueue();
  }

  test(
    'tray rejects unavailable capability observer and stale profile menu',
    () async {
      expect(tray.canConnect, false);
      expect(tray.canDisconnect, false);
      await receive(snapshot(1));
      final oldKey = key('Connect');
      expect(tray.canConnect, true);
      await receive(snapshot(2, profile: 'profile-b'));
      await tray.activate(oldKey);
      expect(connects, 0);
      await receive(snapshot(3, access: 'ACCESS_OBSERVER'));
      await tray.activate(key('Connect'));
      await tray.activate(key('Disconnect'));
      expect(connects, 0);
      expect(disconnects, 0);
      await receive(snapshot(4, capability: false));
      expect(tray.canConnect, false);
      expect(tray.canDisconnect, true);
      await receive(snapshot(5, service: 'SERVICE_STATE_RECOVERING'));
      expect(tray.canConnect, false);
      expect(tray.canDisconnect, true);
      await state.detach();
      expect(tray.canDisconnect, false);
    },
  );

  test(
    'tray serializes connect but allows disconnect without claiming completion',
    () async {
      await receive(snapshot(1));
      final connectKey = key('Connect');
      final work = tray.activate(connectKey);
      await tray.activate(connectKey);
      expect(connects, 1);
      expect(tray.canConnect, false);
      expect(tray.canDisconnect, true);
      await tray.activate(key('Disconnect'));
      expect(disconnects, 1);
      expect(tray.notice, contains('Completion is not yet confirmed'));
      connection.complete(pending(api.OperationKind.OPERATION_KIND_CONNECT));
      await work;
      expect(tray.notice, contains('accepted'));
    },
  );

  test('tray suppresses stale outcomes and sanitizes errors', () async {
    await receive(snapshot(1));
    final work = tray.activate(key('Connect'));
    await receive(snapshot(2, profile: 'profile-b'));
    connection.complete(pending(api.OperationKind.OPERATION_KIND_CONNECT));
    await work;
    expect(tray.notice, isNull);
    connection = Completer<ClientOperation>();
    final failed = tray.activate(key('Connect'));
    connection.completeError(StateError('private credentials diagnostic'));
    await failed;
    expect(tray.notice, contains('Recover the original intention'));
    expect(tray.notice, isNot(contains('private')));
    tray.enabled = false;
    await tray.activate(key('Disconnect'));
    expect(disconnects, 0);
  });
}
