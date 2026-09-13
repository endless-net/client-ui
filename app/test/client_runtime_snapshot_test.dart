@Tags(['short'])
library;

import 'package:endlessnet/client_runtime_snapshot.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse snapshot() =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '1',
      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'ipcVersion': api.ClientContract.version,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': 'ACCESS_OWNER',
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'connectionPhase': 'CONNECTION_PHASE_CONNECTING',
          'currentOperations': [
            {
              'id': 'op-a',
              'profileId': 'inactive-profile',
              'kind': 'OPERATION_KIND_CONNECT',
              'state': 'OPERATION_STATE_RUNNING',
            },
          ],
        },
      },
    });

void main() {
  test(
    'US-01/03: first snapshot preserves phase and inactive operation kind',
    () {
      final event = snapshot();
      final value = ClientRuntimeSnapshot.fromEvent(event);
      expect(
        value.status.connectionPhase,
        api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
      );
      expect(
        value.status.currentOperations.single.profileId,
        'inactive-profile',
      );
      expect(
        value.status.currentOperations.single.kind,
        api.OperationKind.OPERATION_KIND_CONNECT,
      );
      event.snapshot.status.currentOperations.clear();
      expect(value.status.currentOperations, hasLength(1));
      expect(
        () => value.status.currentOperations.clear(),
        throwsUnsupportedError,
      );
      final context = value.mutationContext(
        '12345678-1234-1234-1234-123456789abc',
      );
      expect(context.expectedInstanceId, 'runtime-a');
      expect(context.expectedRevision.toString(), '7');
      expect(() => value.mutationContext(''), throwsFormatException);
    },
  );

  final invalid = <String, void Function(api.WatchEventsResponse)>{
    'missing initial snapshot': (e) => e.clearSnapshot(),
    'sequence gap': (e) => e.sequence += 1,
    'default zero identity': (e) => e.snapshot.runtime.clear(),
    'wrong digest': (e) => e.snapshot.runtime.contractSha256 = 'other',
    'wrong protocol': (e) => e.snapshot.runtime.protocol = 'other',
    'wrong version': (e) => e.snapshot.runtime.ipcVersion = 2,
    'missing caller': (e) => e.snapshot.runtime.clearCallerAccess(),
    'restart mismatch': (e) => e.metadata.instanceId = 'runtime-b',
    'missing status revision': (e) =>
        e.snapshot.status.metadata.clearRevision(),
    'unknown operation kind': (e) =>
        e.snapshot.status.currentOperations.single.clearKind(),
    'terminal current operation': (e) =>
        e.snapshot.status.currentOperations.single.state =
            api.OperationState.OPERATION_STATE_SUCCEEDED,
    'observer operation leak': (e) =>
        e.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER,
  };
  for (final entry in invalid.entries) {
    test('US-01/03: rejects ${entry.key}', () {
      final event = snapshot();
      entry.value(event);
      expect(
        () => ClientRuntimeSnapshot.fromEvent(event),
        throwsFormatException,
      );
    });
  }

  test('US-01/10: capability absence and policy denial are not supported', () {
    final event = snapshot();
    final capability = api.Capability.CAPABILITY_EXIT_NODE;
    expect(
      ClientRuntimeSnapshot.fromEvent(event).supports(capability),
      isFalse,
    );
    event.snapshot.runtime.capabilities.add(
      api.CapabilityStatus(
        capability: capability,
        restriction: api.Restriction(
          availability: api.Availability.AVAILABILITY_POLICY_BLOCKED,
        ),
      ),
    );
    expect(
      ClientRuntimeSnapshot.fromEvent(event).supports(capability),
      isFalse,
    );
    event.snapshot.runtime.capabilities.single.restriction.availability =
        api.Availability.AVAILABILITY_AVAILABLE;
    expect(ClientRuntimeSnapshot.fromEvent(event).supports(capability), isTrue);
  });
}
