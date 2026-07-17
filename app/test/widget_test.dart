import 'package:flutter_test/flutter_test.dart';

import 'package:endlessnet/main.dart';
import 'package:endlessnet/service_contract.dart';

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

    final identityChanged = ServiceStatus({
      'state': ServiceState.degraded,
      'node_id': 'node-1',
      'agent': {'last_error': 'server map signing key changed'},
    });
    expect(identityChanged.serverIdentityChanged, isTrue);
  });

  test('ServiceStatus parses selected paths and relay fallback', () {
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
            'hostname': 'older-peer',
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
    expect(peerLabels(status.payload), contains('older-peer - Relay'));
  });

  test('ServiceDiagnostics parses STUN and PCP/NAT-PMP results', () {
    final diagnostics = ServiceDiagnostics({
      'agent_state': {
        'stun': {
          'ok': true,
          'results': [
            {
              'id': 'stun-1',
              'reachable': true,
              'mapped_address': '198.51.100.10:51820',
              'duration': 10000000,
            },
          ],
          'nat': {
            'classification': 'consistent_mapping',
            'total_endpoints': 1,
            'reachable_endpoints': 1,
          },
          'port_mappings': [
            {
              'protocol': 'nat_pmp',
              'ok': true,
              'mapped_endpoint': '198.51.100.10:51820',
              'lifetime_seconds': 120,
            },
          ],
        },
      },
    });

    expect(diagnostics.stun.classification, 'consistent_mapping');
    expect(diagnostics.stun.results.single.reachable, isTrue);
    expect(diagnostics.stun.portMappings.single.protocol, 'nat_pmp');
    expect(
      portMappingSummary(diagnostics.stun.portMappings),
      'NAT-PMP 198.51.100.10:51820',
    );
  });
}
