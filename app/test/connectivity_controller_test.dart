import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/connectivity_client.dart';
import 'package:endlessnet_client_ui/connectivity/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

api.SnapshotMetadata metadata([String revision = '7']) =>
    api.SnapshotMetadata()
      ..mergeFromProto3Json({'instanceId': 'instance', 'revision': revision});
api.Profile profile([String id = 'profile']) =>
    api.Profile(id: id, controlOrigin: 'https://control.invalid');

api.Status disconnected() => api.Status(
  metadata: metadata(),
  activeProfileId: 'profile',
  nodeId: 'node',
  network: api.Network(id: 'network'),
  storedState: api.StoredStatePresence(nodeCredentialPresent: true),
  serviceState: api.ServiceState.SERVICE_STATE_DISCONNECTED,
  connectionPhase: api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
  intent: api.ConnectionIntent(
    desiredState: api.DesiredState.DESIRED_STATE_DISCONNECTED,
  ),
);

class ConnectivityFixture implements ConnectivityClient {
  api.RuntimeInfo runtime = api.RuntimeInfo(
    instanceId: 'instance',
    contractSha256: 'a' * 64,
    protocol: 'endlessnet-client-ipc',
    callerAccess: api.Access.ACCESS_OWNER,
    capabilities: [
      api.CapabilityStatus(
        capability: api.Capability.CAPABILITY_CONNECTION,
        restriction: api.Restriction(
          availability: api.Availability.AVAILABILITY_AVAILABLE,
        ),
      ),
    ],
  );
  api.Status value = disconnected();
  api.ConnectRequest? connected;
  api.DisconnectRequest? disconnectedRequest;
  Duration? connectTimeout, disconnectTimeout;
  int connects = 0, disconnects = 0, reads = 0;
  Object? readFailure, commandFailure;
  Completer<api.Status>? readGate;
  Completer<void>? commandGate;
  void Function()? onCommand;
  @override
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout) async => runtime;
  @override
  Future<api.Status> status(Duration timeout) async {
    reads++;
    if (readFailure != null) throw readFailure!;
    if (readGate != null) return readGate!.future;
    return api.Status.fromBuffer(value.writeToBuffer());
  }

  @override
  Future<void> connect(api.ConnectRequest request, Duration timeout) async {
    connects++;
    connected = request;
    connectTimeout = timeout;
    onCommand?.call();
    await commandGate?.future;
    if (commandFailure != null) throw commandFailure!;
  }

  @override
  Future<void> disconnect(
    api.DisconnectRequest request,
    Duration timeout,
  ) async {
    disconnects++;
    disconnectedRequest = request;
    disconnectTimeout = timeout;
    onCommand?.call();
    await commandGate?.future;
    if (commandFailure != null) throw commandFailure!;
  }
}

ConnectivityController controller(ConnectivityFixture client) =>
    ConnectivityController(
      client: client,
      expectedContractSha256: 'a' * 64,
      expectedInstanceId: 'instance',
      readTimeout: const Duration(seconds: 1),
      pollInterval: const Duration(seconds: 1),
      automaticPolling: false,
    );

void main() {
  test(
    'a buffered pre-resume reply cannot restore fresh state after suspend',
    () async {
      final client = ConnectivityFixture();
      final c = controller(client);
      addTearDown(c.dispose);
      await c.bind(profile());
      final oldGate = Completer<api.Status>();
      client.readGate = oldGate;
      final oldRead = c.refresh();
      await Future<void>.delayed(Duration.zero);
      final resumed = c.resume();
      expect(c.fresh, isFalse);
      client.readGate = null;
      client.value = disconnected()..metadata.revision += 1;
      oldGate.complete(
        disconnected()..serviceState = api.ServiceState.SERVICE_STATE_CONNECTED,
      );
      await oldRead;
      await resumed;
      expect(client.reads, 3);
      expect(c.snapshot!.metadata.revision.toStringUnsigned(), '8');
      expect(
        c.snapshot!.serviceState,
        api.ServiceState.SERVICE_STATE_DISCONNECTED,
      );
    },
  );

  test('timeout followed by unavailable reread keeps outcome unknown without a retry', () async {
    final client = ConnectivityFixture();
    final c = controller(client);
    addTearDown(c.dispose);
    await c.bind(profile());
    client.commandFailure = TimeoutException('synthetic-secret');
    client.onCommand = () {
      client.readFailure = StateError('synthetic-secret');
    };
    await c.connect();
    expect(c.uncertain, isTrue);
    expect(c.fresh, isFalse);
    expect(c.canConnect, isFalse);
    expect(c.link, ConnectivityLink.unavailable);
    expect(client.connects, 1);
  });
  test('resume invalidates the old snapshot until a fresh read and sends no command', () async {
    final client = ConnectivityFixture();
    final c = controller(client);
    addTearDown(c.dispose);
    await c.bind(profile());
    client.readGate = Completer<api.Status>();
    final resume = c.resume();
    expect(c.fresh, isFalse);
    expect(c.canConnect, isFalse);
    client.readGate!.complete(disconnected());
    await resume;
    expect(c.fresh, isTrue);
    expect(client.connects + client.disconnects, 0);
  });
  test('in-flight refresh revokes authority before mutation and duplicate clicks do not queue commands', () async {
    final client = ConnectivityFixture();
    final c = controller(client);

    await c.bind(profile());
    client.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
    client.readGate = Completer<api.Status>();
    final reading = c.refresh();
    await Future<void>.delayed(Duration.zero);
    final command = c.connect();
    client.readGate!.complete(disconnected());
    await reading;
    await command;
    expect(client.connects, 0);
    client.readGate = null;
    client.runtime.callerAccess = api.Access.ACCESS_OWNER;
    await c.refresh();
    client.commandGate = Completer<void>();
    final first = c.connect();
    await Future<void>.delayed(Duration.zero);
    await c.connect();
    expect(client.connects, 1);
    c.dispose();
    client.commandGate!.complete();
    await first;
    expect(client.disconnects, 0);
  });
  test('ACK is scheduling only, disconnect supersedes pending connect and uses current CAS', () async {
    final client = ConnectivityFixture();
    final c = controller(client);
    addTearDown(c.dispose);
    await c.bind(profile());
    expect(c.canConnect, isTrue);
    client.onCommand = () {
      client.value.metadata.revision += 1;
      client.value.intent.desiredState =
          api.DesiredState.DESIRED_STATE_CONNECTED;
      client.value.connectionPhase =
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTING;
      client.value.serviceState = api.ServiceState.SERVICE_STATE_RECOVERING;
    };
    await c.connect();
    expect(client.connects, 1);
    expect(client.connected!.async, isTrue);
    expect(client.connected!.mutation.expectedRevision.toStringUnsigned(), '7');
    expect(client.connected!.mutation.expectedInstanceId, 'instance');
    expect(client.connectTimeout, const Duration(seconds: 30));
    expect(
      c.snapshot!.connectionPhase,
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
    );
    expect(c.canConnect, isFalse);
    expect(c.canDisconnect, isTrue);
    client.onCommand = () {
      client.value = disconnected()..metadata.revision += 2;
    };
    await c.disconnect();
    expect(client.disconnectTimeout, const Duration(seconds: 10));
    expect(
      client.disconnectedRequest!.mutation.expectedRevision.toStringUnsigned(),
      '8',
    );
    expect(
      c.snapshot!.connectionPhase,
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
    );
    expect(c.canConnect, isTrue);
  });

  test(
    'lost ACK and stale replies reread once without retry or invented rollback',
    () async {
      for (final failure in [
        TimeoutException('synthetic-secret'),
        ClientCallFailure.fromGrpc(
          const grpc.GrpcError.aborted('synthetic-secret'),
          1024,
        ),
      ]) {
        final client = ConnectivityFixture()..commandFailure = failure;
        final c = controller(client);
        await c.bind(profile());
        client.onCommand = () {
          client.value.intent.desiredState =
              api.DesiredState.DESIRED_STATE_CONNECTED;
          client.value.connectionPhase =
              api.ConnectionPhase.CONNECTION_PHASE_UNSPECIFIED;
          client.value.serviceState = api.ServiceState.SERVICE_STATE_RECOVERING;
          client.value.metadata.revision += 1;
        };
        await c.connect();
        expect(client.connects, 1);
        expect(client.reads, 2);
        expect(
          c.snapshot!.intent.desiredState,
          api.DesiredState.DESIRED_STATE_CONNECTED,
        );
        expect(
          c.snapshot!.serviceState,
          api.ServiceState.SERVICE_STATE_RECOVERING,
        );
        c.dispose();
        expect(client.disconnects, 0);
      }
    },
  );

  test('older generation/profile response and disposed command cannot overwrite the new binding', () async {
    final client = ConnectivityFixture();
    final c = controller(client);
    await c.bind(profile());
    client.commandGate = Completer<void>();
    final old = c.connect();
    await Future<void>.delayed(Duration.zero);
    client.value = disconnected()..activeProfileId = 'other';
    await c.bind(profile('other'));
    client.commandGate!.complete();
    await old;
    expect(c.snapshot!.activeProfileId, 'other');
    expect(c.canConnect, isTrue);
    c.dispose();
    expect(client.disconnects, 0);
  });

  test('runtime identity, owner restrictions, and unsigned rollback fence commands', () async {
    final client = ConnectivityFixture();
    final c = controller(client);
    addTearDown(c.dispose);
    client.value.metadata = metadata('18446744073709551615');
    await c.bind(profile());
    expect(c.canConnect, isTrue);
    client.value.metadata = metadata('9223372036854775808');
    await c.refresh();
    expect(c.fresh, isFalse);
    expect(c.canConnect, isFalse);
    client.runtime.instanceId = 'other-instance';
    await c.refresh();
    expect(c.link, ConnectivityLink.mismatch);
    expect(c.snapshot, isNull);
    await c.connect();
    expect(client.connects, 0);
    client.runtime.instanceId = 'instance';
    client.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
    await c.bind(profile());
    expect(c.canConnect, isFalse);
  });
}
