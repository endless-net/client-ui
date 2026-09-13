@Tags(['short'])
library;

import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

// No transport: unexpected submission must fail rather than contact a daemon.
class NoCallsClient implements api.ClientServiceClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RPC');
}

void main() {
  const requestId = 'abcdef12-1234-4567-89ab-123456789abc';
  final commands = ClientMutations(NoCallsClient(), instanceId: 'runtime-a');
  test('Enroll: missing mutation context fails before transport', () async {
    await expectLater(
      commands.enroll(api.EnrollRequest()),
      throwsFormatException,
    );
  });
  test('Connect: missing mutation context fails before transport', () async {
    await expectLater(
      commands.connect(api.ConnectRequest()),
      throwsFormatException,
    );
  });
  test('Disconnect: missing mutation context fails before transport', () async {
    await expectLater(
      commands.disconnect(api.DisconnectRequest()),
      throwsFormatException,
    );
  });
  test(
    'TrustServerIdentity: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.trustServerIdentity(api.TrustServerIdentityRequest()),
        throwsFormatException,
      );
    },
  );
  test('Logout: missing mutation context fails before transport', () async {
    await expectLater(
      commands.logout(api.LogoutRequest()),
      throwsFormatException,
    );
  });
  test(
    'ForgetLocalEnrollment: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.forgetLocalEnrollment(api.ForgetLocalEnrollmentRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'SelectNetwork: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.selectNetwork(api.SelectNetworkRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'CreateDiagnosticsBundle: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.createDiagnosticsBundle(api.CreateDiagnosticsBundleRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'CreateProfile: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.createProfile(api.CreateProfileRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'SelectProfile: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.selectProfile(api.SelectProfileRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'RenameProfile: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.renameProfile(api.RenameProfileRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'RemoveProfile: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.removeProfile(api.RemoveProfileRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'RenewSession: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.renewSession(api.RenewSessionRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'SelectExitNode: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.selectExitNode(api.SelectExitNodeRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'ClearExitNode: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.clearExitNode(api.ClearExitNodeRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'SetPreferences: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.setPreferences(api.SetPreferencesRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'ResetPreferences: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.resetPreferences(api.ResetPreferencesRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'SetResourceEnabled: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.setResourceEnabled(api.SetResourceEnabledRequest()),
        throwsFormatException,
      );
    },
  );
  test(
    'NotifyLifecycle: missing mutation context fails before transport',
    () async {
      await expectLater(
        commands.notifyLifecycle(api.NotifyLifecycleRequest()),
        throwsFormatException,
      );
    },
  );

  api.Operation accepted() => api.Operation(
    id: 'operation-a',
    requestId: requestId,
    kind: api.OperationKind.OPERATION_KIND_CONNECT,
    state: api.OperationState.OPERATION_STATE_PENDING,
  );

  test('US-03: acceptance must match original request and operation kind', () {
    final response = accepted();
    final result = ClientMutations.validateAcceptance(
      response,
      requestId,
      api.OperationKind.OPERATION_KIND_CONNECT,
    );
    expect(result.succeeded, isFalse);
    expect(result.terminal, isFalse);
    response.requestId = 'another-request';
    expect(result.value.requestId, requestId);
    expect(
      () => ClientMutations.validateAcceptance(
        response,
        requestId,
        api.OperationKind.OPERATION_KIND_CONNECT,
      ),
      throwsFormatException,
    );
    expect(
      () => ClientMutations.validateAcceptance(
        accepted(),
        requestId,
        api.OperationKind.OPERATION_KIND_DISCONNECT,
      ),
      throwsFormatException,
    );
  });

  test(
    'UUID identity is case-insensitive; nil UUID never reaches transport',
    () async {
      final response = api.Operation(
        id: 'op',
        requestId: requestId,
        kind: api.OperationKind.OPERATION_KIND_CONNECT,
        state: api.OperationState.OPERATION_STATE_PENDING,
      );
      expect(
        ClientMutations.validateAcceptance(
          response,
          requestId.toUpperCase(),
          api.OperationKind.OPERATION_KIND_CONNECT,
        ).value.requestId,
        requestId,
      );
      await expectLater(
        commands.connect(
          api.ConnectRequest()..mergeFromProto3Json({
            'mutation': {
              'requestId': '00000000-0000-0000-0000-000000000000',
              'expectedInstanceId': 'runtime-a',
              'expectedRevision': '1',
            },
          }),
        ),
        throwsFormatException,
      );
      await expectLater(
        commands.recoverByRequestId(
          '00000000-0000-0000-0000-000000000000',
          api.OperationKind.OPERATION_KIND_CONNECT,
        ),
        throwsFormatException,
      );
    },
  );
}
