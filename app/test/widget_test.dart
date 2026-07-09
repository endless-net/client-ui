import 'package:flutter_test/flutter_test.dart';

import 'package:endlessnet_tray/main.dart';
import 'package:endlessnet_tray/service_contract.dart';

void main() {
  test('parseEnrollment accepts EndlessNet deep links', () {
    final request = parseEnrollment(
      'endlessnet://enroll?join_token=enj_test_token&server=https%3A%2F%2Fapi.example.test&mode=server',
      '',
      'workstation',
    );

    expect(request.token, 'enj_test_token');
    expect(request.server, 'https://api.example.test');
    expect(request.mode, 'server');
  });

  test('parseEnrollment extracts pasted token text', () {
    final request = parseEnrollment(
      'connect with enr_pasted_secret now',
      'https://api.endlessnet.ru',
      '',
    );

    expect(request.token, 'enr_pasted_secret');
    expect(request.server, 'https://api.endlessnet.ru');
    expect(request.mode, 'workstation');
  });

  test('redactText removes enrollment tokens and credentials', () {
    final redacted = redactText(
      'token=enr_secret private_key: abc Bearer bearer-secret endlessnet://enroll?token=enj_secret',
    );

    expect(redacted, isNot(contains('enr_secret')));
    expect(redacted, isNot(contains('abc')));
    expect(redacted, isNot(contains('bearer-secret')));
    expect(redacted, isNot(contains('enj_secret')));
  });

  test('isDeviceEnrolled detects enrolled status markers', () {
    expect(isDeviceEnrolled(null), isFalse);
    expect(isDeviceEnrolled({'state': ServiceState.needsEnrollment}), isFalse);
    expect(
      isDeviceEnrolled({
        'state': ServiceState.connected,
        'account_id': 'acc_123',
        'agent': {'node_id': 'nod_123'},
      }),
      isTrue,
    );
    expect(
      isDeviceEnrolled({
        'state': ServiceState.disconnected,
        'agent': {'network_id': 'net_123', 'overlay_ip': '100.64.0.2'},
      }),
      isTrue,
    );
  });

  test('ServiceStatus exposes the service UI contract', () {
    final connected = ServiceStatus({
      'state': ServiceState.connected,
      'node_id': 'node-1',
    });
    expect(connected.connected, isTrue);
    expect(connected.deviceEnrolled, isTrue);
    expect(connected.userDisconnected, isFalse);

    final disconnected = ServiceStatus({
      'state': ServiceState.disconnected,
      'control_state': ControlState.disconnected,
      'user_disconnected': true,
      'node_id': 'node-1',
    });
    expect(disconnected.connected, isFalse);
    expect(disconnected.deviceEnrolled, isTrue);
    expect(disconnected.userDisconnected, isTrue);

    final needsEnrollment = ServiceStatus({
      'state': ServiceState.needsEnrollment,
      'control_state': ControlState.notRegistered,
      'node_id': 'stale-node-id',
    });
    expect(needsEnrollment.needsEnrollment, isTrue);
    expect(needsEnrollment.deviceEnrolled, isFalse);
  });
}
