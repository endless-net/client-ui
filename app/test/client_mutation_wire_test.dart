import 'dart:io';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'support/mutation_wire_server.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';

class _Vector {
  _Vector(this.name, this.kind, this.bytes, this.submit, this.clear);
  final String name;
  final api.OperationKind kind;
  final List<int> bytes;
  final Future<ClientOperation> Function(ClientMutations) submit;
  final void Function() clear;
}

Map<String, dynamic> _payload(
  Map<String, dynamic> fields, {
  bool profile = true,
}) => {
  'mutation': {
    'requestId': _requestId,
    'expectedInstanceId': 'wire-runtime',
    'expectedRevision': '7',
  },
  if (profile) 'profile': {'profileId': 'profile-a'},
  ...fields,
};

List<_Vector> _vectors() {
  final enroll = api.EnrollRequest()
    ..mergeFromProto3Json(
      _payload({
        "mode": "ENROLLMENT_MODE_WORKSTATION",
        "hostname": "synthetic-host",
        "enrollmentToken": "synthetic-not-a-secret",
      }),
    );
  final connect = api.ConnectRequest()..mergeFromProto3Json(_payload({}));
  final disconnect = api.DisconnectRequest()..mergeFromProto3Json(_payload({}));
  final trustServerIdentity = api.TrustServerIdentityRequest()
    ..mergeFromProto3Json(
      _payload({
        "confirmedControlOrigin": "https://control.example.test",
        "confirmedKeyId": "key-a",
        "confirmedAnnouncementId": "announcement-a",
      }),
    );
  final logout = api.LogoutRequest()..mergeFromProto3Json(_payload({}));
  final forgetLocalEnrollment = api.ForgetLocalEnrollmentRequest()
    ..mergeFromProto3Json(_payload({"confirmed": true}));
  final selectNetwork = api.SelectNetworkRequest()
    ..mergeFromProto3Json(_payload({"networkId": "network-a"}));
  final createDiagnosticsBundle = api.CreateDiagnosticsBundleRequest()
    ..mergeFromProto3Json(_payload({}));
  final createProfile = api.CreateProfileRequest()
    ..mergeFromProto3Json(
      _payload({
        "displayName": "Синтетический профиль",
        "controlOrigin": "https://control.example.test",
      }, profile: false),
    );
  final selectProfile = api.SelectProfileRequest()
    ..mergeFromProto3Json(_payload({}));
  final renameProfile = api.RenameProfileRequest()
    ..mergeFromProto3Json(_payload({"displayName": "Renamed профиль"}));
  final removeProfile = api.RemoveProfileRequest()
    ..mergeFromProto3Json(_payload({}));
  final renewSession = api.RenewSessionRequest()
    ..mergeFromProto3Json(_payload({}));
  final selectExitNode = api.SelectExitNodeRequest()
    ..mergeFromProto3Json(
      _payload({
        "exitNodeId": "exit-a",
        "lanAccess": "LAN_ACCESS_BLOCK",
        "familyMode": "EXIT_FAMILY_MODE_IPV4_ONLY",
      }),
    );
  final clearExitNode = api.ClearExitNodeRequest()
    ..mergeFromProto3Json(_payload({}));
  final setPreferences = api.SetPreferencesRequest()
    ..mergeFromProto3Json(
      _payload({
        "patch": {"allowInbound": false, "acceptDns": true},
      }),
    );
  final resetPreferences = api.ResetPreferencesRequest()
    ..mergeFromProto3Json(
      _payload({
        "keys": ["PREFERENCE_KEY_ALLOW_INBOUND", "PREFERENCE_KEY_ACCEPT_DNS"],
      }),
    );
  final setResourceEnabled = api.SetResourceEnabledRequest()
    ..mergeFromProto3Json(
      _payload({"resourceId": "resource-a", "enabled": true}),
    );
  final notifyLifecycle = api.NotifyLifecycleRequest()
    ..mergeFromProto3Json(_payload({"event": "LIFECYCLE_EVENT_UI_QUIT"}));
  return [
    _Vector(
      'Enroll',
      api.OperationKind.OPERATION_KIND_ENROLL,
      enroll.writeToBuffer(),
      (c) => c.enroll(enroll),
      enroll.clear,
    ),
    _Vector(
      'Connect',
      api.OperationKind.OPERATION_KIND_CONNECT,
      connect.writeToBuffer(),
      (c) => c.connect(connect),
      connect.clear,
    ),
    _Vector(
      'Disconnect',
      api.OperationKind.OPERATION_KIND_DISCONNECT,
      disconnect.writeToBuffer(),
      (c) => c.disconnect(disconnect),
      disconnect.clear,
    ),
    _Vector(
      'TrustServerIdentity',
      api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
      trustServerIdentity.writeToBuffer(),
      (c) => c.trustServerIdentity(trustServerIdentity),
      trustServerIdentity.clear,
    ),
    _Vector(
      'Logout',
      api.OperationKind.OPERATION_KIND_LOGOUT,
      logout.writeToBuffer(),
      (c) => c.logout(logout),
      logout.clear,
    ),
    _Vector(
      'ForgetLocalEnrollment',
      api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
      forgetLocalEnrollment.writeToBuffer(),
      (c) => c.forgetLocalEnrollment(forgetLocalEnrollment),
      forgetLocalEnrollment.clear,
    ),
    _Vector(
      'SelectNetwork',
      api.OperationKind.OPERATION_KIND_SELECT_NETWORK,
      selectNetwork.writeToBuffer(),
      (c) => c.selectNetwork(selectNetwork),
      selectNetwork.clear,
    ),
    _Vector(
      'CreateDiagnosticsBundle',
      api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
      createDiagnosticsBundle.writeToBuffer(),
      (c) => c.createDiagnosticsBundle(createDiagnosticsBundle),
      createDiagnosticsBundle.clear,
    ),
    _Vector(
      'CreateProfile',
      api.OperationKind.OPERATION_KIND_CREATE_PROFILE,
      createProfile.writeToBuffer(),
      (c) => c.createProfile(createProfile),
      createProfile.clear,
    ),
    _Vector(
      'SelectProfile',
      api.OperationKind.OPERATION_KIND_SELECT_PROFILE,
      selectProfile.writeToBuffer(),
      (c) => c.selectProfile(selectProfile),
      selectProfile.clear,
    ),
    _Vector(
      'RenameProfile',
      api.OperationKind.OPERATION_KIND_RENAME_PROFILE,
      renameProfile.writeToBuffer(),
      (c) => c.renameProfile(renameProfile),
      renameProfile.clear,
    ),
    _Vector(
      'RemoveProfile',
      api.OperationKind.OPERATION_KIND_REMOVE_PROFILE,
      removeProfile.writeToBuffer(),
      (c) => c.removeProfile(removeProfile),
      removeProfile.clear,
    ),
    _Vector(
      'RenewSession',
      api.OperationKind.OPERATION_KIND_RENEW_SESSION,
      renewSession.writeToBuffer(),
      (c) => c.renewSession(renewSession),
      renewSession.clear,
    ),
    _Vector(
      'SelectExitNode',
      api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
      selectExitNode.writeToBuffer(),
      (c) => c.selectExitNode(selectExitNode),
      selectExitNode.clear,
    ),
    _Vector(
      'ClearExitNode',
      api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
      clearExitNode.writeToBuffer(),
      (c) => c.clearExitNode(clearExitNode),
      clearExitNode.clear,
    ),
    _Vector(
      'SetPreferences',
      api.OperationKind.OPERATION_KIND_SET_PREFERENCES,
      setPreferences.writeToBuffer(),
      (c) => c.setPreferences(setPreferences),
      setPreferences.clear,
    ),
    _Vector(
      'ResetPreferences',
      api.OperationKind.OPERATION_KIND_RESET_PREFERENCES,
      resetPreferences.writeToBuffer(),
      (c) => c.resetPreferences(resetPreferences),
      resetPreferences.clear,
    ),
    _Vector(
      'SetResourceEnabled',
      api.OperationKind.OPERATION_KIND_SET_RESOURCE_ENABLED,
      setResourceEnabled.writeToBuffer(),
      (c) => c.setResourceEnabled(setResourceEnabled),
      setResourceEnabled.clear,
    ),
    _Vector(
      'NotifyLifecycle',
      api.OperationKind.OPERATION_KIND_NOTIFY_LIFECYCLE,
      notifyLifecycle.writeToBuffer(),
      (c) => c.notifyLifecycle(notifyLifecycle),
      notifyLifecycle.clear,
    ),
  ];
}

void main() {
  test('wire vectors cover every concrete mutation kind', () {
    expect(
      _vectors().map((v) => v.kind).toSet(),
      api.OperationKind.values
          .where((kind) => kind != api.OperationKind.OPERATION_KIND_UNSPECIFIED)
          .toSet(),
    );
    expect(_vectors().map((v) => v.kind).toSet().length, _vectors().length);
  });

  for (final mode in ['accepted', 'wrong request', 'wrong kind']) {
    for (final vector in _vectors()) {
      test('protobuf mutation ${vector.name}: $mode', () async {
        final response = api.Operation(
          id: 'operation-a',
          requestId: mode == 'wrong request'
              ? '22222222-2222-4222-8222-222222222222'
              : _requestId,
          profileId: 'profile-a',
          kind: mode == 'wrong kind'
              ? (vector.kind == api.OperationKind.OPERATION_KIND_CONNECT
                    ? api.OperationKind.OPERATION_KIND_DISCONNECT
                    : api.OperationKind.OPERATION_KIND_CONNECT)
              : vector.kind,
          state: api.OperationState.OPERATION_STATE_PENDING,
        );
        final fixture = MutationWireServer(
          method: vector.name,
          requestBytes: vector.bytes,
          response: response,
        );
        final server = Server.create(services: [fixture]);
        await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
        final channel = ClientChannel(
          '127.0.0.1',
          port: server.port!,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
          ),
        );
        try {
          final commands = ClientMutations(
            api.ClientServiceClient(
              channel,
              options: CallOptions(
                metadata: api.ClientContract.metadata,
                timeout: const Duration(seconds: 8),
              ),
            ),
            instanceId: 'wire-runtime',
          );
          final pending = vector.submit(commands);
          // Caller changes after invocation must not alter the submitted intent.
          vector.clear();
          if (mode == 'accepted') {
            final result = await pending;
            expect(result.value.writeToBuffer(), response.writeToBuffer());
            expect(result.terminal, isFalse);
          } else {
            await expectLater(pending, throwsFormatException);
          }
          expect(fixture.calls, [vector.name]); // No replay after rejection.
          expect(fixture.violations, isEmpty);
        } finally {
          await channel.shutdown();
          await server.shutdown();
        }
      }, timeout: const Timeout(Duration(seconds: 20)));
    }
  }
}
