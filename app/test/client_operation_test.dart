@Tags(['short'])
library;

import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Separate test vectors for every producer mutation kind. A new kind requires
  // an explicit consumer decision; it cannot silently inherit generic success.
  final outcomes = <String, Map<String, Object>>{
    'ENROLL': {
      'enrollment': {'profileId': 'profile', 'nodeId': 'node'},
    },
    'CONNECT': {
      'change': {'changed': true},
    },
    'DISCONNECT': {
      'change': {'changed': false},
    },
    'TRUST_SERVER_IDENTITY': {'change': {}},
    'LOGOUT': {
      'cleanup': {'outcome': 'CLEANUP_OUTCOME_REMOTE_CONFIRMED'},
    },
    'FORGET_LOCAL_ENROLLMENT': {
      'cleanup': {'outcome': 'CLEANUP_OUTCOME_REMOTE_UNCONFIRMED'},
    },
    'SELECT_NETWORK': {
      'selection': {'selectedId': 'network'},
    },
    'CREATE_DIAGNOSTICS_BUNDLE': {
      'bundle': {'bundleId': 'bundle'},
    },
    'CREATE_PROFILE': {
      'selection': {'selectedId': 'profile'},
    },
    'SELECT_PROFILE': {
      'selection': {'selectedId': 'profile'},
    },
    'RENAME_PROFILE': {'change': {}},
    'REMOVE_PROFILE': {'change': {}},
    'RENEW_SESSION': {'renewal': {}},
    'SELECT_EXIT_NODE': {
      'selection': {'selectedId': 'exit'},
    },
    'CLEAR_EXIT_NODE': {'selection': {}},
    'SET_PREFERENCES': {'change': {}},
    'RESET_PREFERENCES': {'change': {}},
    'SET_RESOURCE_ENABLED': {'change': {}},
    'NOTIFY_LIFECYCLE': {'change': {}},
  };

  api.Operation operation(
    String kind,
    String state, [
    Map<String, Object> fields = const {},
  ]) => api.Operation()
    ..mergeFromProto3Json({
      'id': 'operation-a',
      'kind': 'OPERATION_KIND_$kind',
      'state': 'OPERATION_STATE_$state',
      if (state == 'SUCCEEDED') 'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
      ...fields,
    });

  test(
    'consumer vectors cover the complete generated operation vocabulary',
    () {
      expect(
        outcomes.keys.map((k) => 'OPERATION_KIND_$k').toSet(),
        api.OperationKind.values
            .where((k) => k.value != 0)
            .map((k) => k.name)
            .toSet(),
      );
    },
  );
  for (final entry in outcomes.entries) {
    test(
      '${entry.key}: accepted is not completed; success requires typed outcome',
      () {
        final pending = ClientOperation.fromProto(
          operation(entry.key, 'PENDING'),
        );
        expect(pending.terminal, isFalse);
        expect(pending.succeeded, isFalse);
        final success = ClientOperation.fromProto(
          operation(entry.key, 'SUCCEEDED', entry.value),
        );
        expect(success.terminal, isTrue);
        expect(success.succeeded, isTrue);
        expect(() => success.value.clearKind(), throwsUnsupportedError);
        expect(
          () => ClientOperation.fromProto(operation(entry.key, 'SUCCEEDED')),
          throwsFormatException,
        );
        expect(
          () => ClientOperation.fromProto(
            operation(entry.key, 'RUNNING', entry.value),
          ),
          throwsFormatException,
        );
        expect(
          () => ClientOperation.fromProto(
            operation(entry.key, 'SUCCEEDED', {
              'failure': {'code': 'ERROR_CODE_UNAVAILABLE'},
            }),
          ),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'waiting requires a typed user action; failure and cancellation require Failure',
    () {
      expect(
        () =>
            ClientOperation.fromProto(operation('ENROLL', 'WAITING_FOR_USER')),
        throwsFormatException,
      );
      expect(
        ClientOperation.fromProto(
          operation('ENROLL', 'WAITING_FOR_USER', {
            'userAction': {'kind': 'KIND_WAIT_FOR_APPROVAL'},
          }),
        ).terminal,
        isFalse,
      );
      for (final state in ['FAILED', 'CANCELLED']) {
        expect(
          () => ClientOperation.fromProto(operation('CONNECT', state)),
          throwsFormatException,
        );
        final value = ClientOperation.fromProto(
          operation('CONNECT', state, {
            'failure': {'code': 'ERROR_CODE_UNAVAILABLE', 'retryable': true},
          }),
        );
        expect(value.terminal, isTrue);
        expect(value.succeeded, isFalse);
        expect(value.value.failure.retryable, isTrue);
      }
    },
  );

  test('kind-specific result and nonempty selection are mandatory', () {
    expect(
      () => ClientOperation.fromProto(
        operation('CONNECT', 'SUCCEEDED', {
          'selection': {'selectedId': 'network'},
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => ClientOperation.fromProto(
        operation('SELECT_NETWORK', 'SUCCEEDED', {'selection': {}}),
      ),
      throwsFormatException,
    );
  });

  test(
    'success requires continuity and nonwaiting states reject user actions',
    () {
      final missing = operation('CONNECT', 'SUCCEEDED', {'change': {}})
        ..clearContinuity();
      expect(() => ClientOperation.fromProto(missing), throwsFormatException);
      for (final state in [
        'PENDING',
        'RUNNING',
        'SUCCEEDED',
        'FAILED',
        'CANCELLED',
      ]) {
        final value = operation('CONNECT', state, {
          if (state == 'SUCCEEDED') 'change': {},
          if (state == 'FAILED' || state == 'CANCELLED')
            'failure': {'code': 'ERROR_CODE_CANCELLED'},
          'userAction': {'kind': 'KIND_WAIT_FOR_APPROVAL'},
        });
        expect(() => ClientOperation.fromProto(value), throwsFormatException);
      }
    },
  );
}
