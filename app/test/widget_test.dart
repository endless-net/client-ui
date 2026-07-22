import 'package:flutter_test/flutter_test.dart';

import 'package:endlessnet/main.dart';
import 'package:endlessnet/named_pipe_http.dart';
import 'package:endlessnet/service_contract.dart';

void main() {
  test('AppConfig recognizes the elevated enrollment worker', () {
    final config = AppConfig.parse(const ['--elevated-enroll']);

    expect(config.elevatedEnrollment, isTrue);
    expect(config.enrollText, isEmpty);
    expect(config.server, isEmpty);
  });

  test('interactive enrollment leaves the optional server unset', () {
    final request = parseEnrollment('endlessnet://enroll', '', 'workstation');

    expect(request.token, isEmpty);
    expect(request.server, isEmpty);
  });

  test('elevated enrollment omits an unset optional server', () {
    final config = AppConfig.parse(const []);
    final arguments = elevatedEnrollmentArguments(
      config,
      EnrollmentRequest(token: '', server: '', mode: 'workstation'),
    );

    expect(arguments, isNot(contains('--server')));
  });

  test('elevated enrollment preserves the protected pipe and request', () {
    final config = AppConfig.parse(const [
      '--pipe',
      r'\\.\pipe\endlessnet-test',
      '--debug',
      '--debug-log-dir',
      r'C:\Users\tester\EndlessNet Logs',
    ]);
    final arguments = elevatedEnrollmentArguments(
      config,
      EnrollmentRequest(
        token: 'enr_secret',
        server: 'https://api.example.test',
        mode: 'workstation',
      ),
    );

    expect(arguments.first, '--elevated-enroll');
    expect(arguments, containsAllInOrder(['--pipe', config.pipe]));
    expect(
      arguments,
      containsAllInOrder(['--server', 'https://api.example.test']),
    );
    expect(arguments, containsAllInOrder(['--enroll', 'enr_secret']));
    expect(
      arguments,
      containsAllInOrder(['--debug-log-dir', config.debugLogDir]),
    );
  });

  test('Windows elevation arguments are quoted for ShellExecute', () {
    expect(quoteWindowsCommandLineArgument('plain'), 'plain');
    expect(
      quoteWindowsCommandLineArgument(
        r'C:\Program Files\EndlessNet\endlessnet.exe',
      ),
      r'"C:\Program Files\EndlessNet\endlessnet.exe"',
    );
  });

  test('only owner policy errors trigger administrator elevation', () {
    expect(
      requiresAdministratorElevation(
        const ServiceIPCException(
          statusCode: 403,
          errorCode: 'owner_required',
          message: 'owner required',
        ),
      ),
      isTrue,
    );
    expect(
      requiresAdministratorElevation(
        const ServiceIPCException(
          statusCode: 403,
          errorCode: 'administrator_required',
          message: 'administrator required',
        ),
      ),
      isTrue,
    );
    expect(
      requiresAdministratorElevation(
        const ServiceIPCException(
          statusCode: 400,
          errorCode: 'enrollment_failed',
          message: 'enrollment failed',
        ),
      ),
      isFalse,
    );
  });

  test('parseEnrollment accepts EndlessNet deep links', () {
    final request = parseEnrollment(
      'endlessnet://enroll?enroll_token=enr_test_token&server=https%3A%2F%2Fapi.example.test&mode=server',
      '',
      'workstation',
    );

    expect(request.token, 'enr_test_token');
    expect(request.server, 'https://api.example.test');
    expect(request.mode, 'server');
  });

  test(
    'parseEnrollment accepts no-token interactive EndlessNet deep links',
    () {
      final request = parseEnrollment(
        'endlessnet://enroll?server=https%3A%2F%2Fapi.example.test&mode=server',
        '',
        'workstation',
      );

      expect(request.token, '');
      expect(request.server, 'https://api.example.test');
      expect(request.mode, 'server');
    },
  );

  test('parseEnrollment does not accept legacy token query aliases', () {
    final request = parseEnrollment(
      'endlessnet://enroll?join_token=enr_legacy&server=https%3A%2F%2Fapi.example.test',
      '',
      'workstation',
    );

    expect(request.token, isEmpty);
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
      'token=enr_secret private_key: abc Bearer bearer-secret endlessnet://enroll?enroll_token=enr_url_secret',
    );

    expect(redacted, isNot(contains('enr_secret')));
    expect(redacted, isNot(contains('abc')));
    expect(redacted, isNot(contains('bearer-secret')));
    expect(redacted, isNot(contains('enr_url_secret')));
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
        'node_credential_present': true,
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

    final identityChanged = ServiceStatus({
      'state': ServiceState.serverIdentityChanged,
      'node_id': 'node-1',
    });
    expect(identityChanged.serverIdentityChanged, isTrue);
  });

  test('ServiceStatus parses strict peer path diagnostics', () {
    final status = ServiceStatus({
      'agent': {
        'state_present': true,
        'stun_ok': true,
        'relay_ok': true,
        'selected_path_counts': {'direct': 1, 'relay': 1},
        'peers': [
          {
            'peer_id': 'peer-direct',
            'hostname': 'peer-a',
            'selected_path': 'direct',
            'selected_endpoint': '192.168.1.20:51820',
            'direct': {
              'type': 'direct',
              'state': 'reachable',
              'endpoint': '192.168.1.20:51820',
            },
            'relay': {'type': 'relay', 'state': 'standby'},
            'candidates': [
              {
                'type': 'direct',
                'tier': 'lan_direct',
                'state': 'reachable',
                'endpoint': '192.168.1.20:51820',
                'rtt_ms': 4.5,
              },
            ],
          },
          {
            'peer_id': 'peer-relay',
            'hostname': 'relay-peer',
            'selected_path': 'relay',
            'selection_reason':
                'relay-first path established while direct candidates are probed',
            'direct': {'type': 'direct', 'state': 'untested'},
            'relay': {
              'type': 'relay',
              'state': 'reachable',
              'endpoint': 'relay.example.test:443',
            },
          },
        ],
      },
    });

    expect(status.peerPaths, hasLength(2));
    expect(status.peerPaths.first.candidates.single.rttMS, 4.5);
    expect(status.peerPaths.last.selectedPath, 'relay');
    expect(selectedPathsLabel(status.agent), '1 direct · 1 relay');
    expect(peerLabels(status.payload), contains('relay-peer - Relay'));
  });

  test('ServiceDiagnostics reads status from the strict response envelope', () {
    final diagnostics = ServiceDiagnostics({
      'diagnostics': {
        'generated_at': '2026-07-21T12:00:00Z',
        'status': {
          'state': ServiceState.connected,
          'agent': {
            'state_present': true,
            'stun_ok': true,
            'relay_ok': true,
            'selected_path_counts': {'direct': 1},
            'peers': <Map<String, dynamic>>[],
          },
        },
      },
    });

    expect(diagnostics.generatedAt, '2026-07-21T12:00:00Z');
    expect(diagnostics.status.connected, isTrue);
    expect(
      discoveryHealthLabel(diagnostics.agent),
      'STUN reachable · relay available',
    );
  });
}
