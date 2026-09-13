@Tags(['short'])
library;

import 'dart:convert';
import 'package:endlessnet/client_privileged_recovery.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  api.ForgetLocalEnrollmentRequest source() =>
      api.ForgetLocalEnrollmentRequest()..mergeFromProto3Json({
        'mutation': {
          'requestId': '5cf89bd1-11a0-4b31-955e-537aabff7a51',
          'expectedInstanceId': 'instance',
          'expectedRevision': '7',
        },
        'profile': {'profileId': 'profile'},
        'confirmed': true,
      });
  test('fixed arguments are immutable and retain exact context', () {
    final input = source();
    final request = ClientPrivilegedRecovery.forget(input);
    input.mutation.requestId = 'changed';
    expect(request.arguments, contains('5cf89bd1-11a0-4b31-955e-537aabff7a51'));
    expect(request.arguments, isNot(contains('--ipc-pipe')));
    expect(() => request.arguments.add('shell'), throwsUnsupportedError);
    expect(
      () => ClientPrivilegedRecovery.forget(source()..confirmed = false),
      throwsFormatException,
    );
  });
  test(
    'helper output must match request profile kind instance and revision',
    () {
      final request = ClientPrivilegedRecovery.forget(source());
      final valid = <String, dynamic>{
        'id': 'operation',
        'requestId': request.mutation.requestId,
        'profileId': 'profile',
        'kind': 'OPERATION_KIND_FORGET_LOCAL_ENROLLMENT',
        'state': 'OPERATION_STATE_PENDING',
        'metadata': {'instanceId': 'instance', 'revision': '8'},
      };
      expect(request.decodeResult(0, jsonEncode(valid)).terminal, false);
      for (final change in <Map<String, dynamic>>[
        {'requestId': 'other'},
        {'profileId': 'other'},
        {'kind': 'OPERATION_KIND_LOGOUT'},
        {
          'metadata': {'instanceId': 'other', 'revision': '8'},
        },
        {
          'metadata': {'instanceId': 'instance', 'revision': '6'},
        },
      ]) {
        expect(
          () => request.decodeResult(0, jsonEncode({...valid, ...change})),
          throwsFormatException,
        );
      }
      expect(() => request.decodeResult(0, ''), throwsFormatException);
      expect(
        () => request.decodeResult(
          1,
          '{"code":"ERROR_CODE_ADMINISTRATOR_REQUIRED"}',
        ),
        throwsA(isA<ClientPrivilegedFailure>()),
      );
      expect(
        () => request.decodeResult(1, 'private diagnostic'),
        throwsFormatException,
      );
    },
  );
}
