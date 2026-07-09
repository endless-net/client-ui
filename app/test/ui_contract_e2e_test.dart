import 'dart:io';

import 'package:endlessnet_tray/main.dart';
import 'package:endlessnet_tray/service_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray UI contract constants mirror the OpenAPI enum/path surface', () {
    final contractPath = Platform.environment['ENDLESSNET_IPC_OPENAPI'];
    expect(contractPath, isNotNull);
    final openAPI = File(contractPath!).readAsStringSync();

    expect(openAPI, contains('title: EndlessNet Client Local Service IPC'));
    for (final path in const [
      ServiceIPCPath.status,
      ServiceIPCPath.events,
      ServiceIPCPath.enroll,
      ServiceIPCPath.connect,
      ServiceIPCPath.disconnect,
      ServiceIPCPath.logout,
      ServiceIPCPath.networks,
      ServiceIPCPath.selectNetwork,
      ServiceIPCPath.diagnostics,
      ServiceIPCPath.recentLogs,
    ]) {
      expect(openAPI, contains('  $path:'));
    }

    for (final state in const [
      ServiceState.connected,
      ServiceState.disconnected,
      ServiceState.connecting,
      ServiceState.updating,
      ServiceState.degraded,
      ServiceState.error,
      ServiceState.needsEnrollment,
      ServiceState.needsApproval,
    ]) {
      expect(openAPI, contains('        - $state'));
    }

    for (final state in const [
      ControlState.connecting,
      ControlState.updating,
      ControlState.syncing,
      ControlState.needsApproval,
      ControlState.approvalRequired,
      ControlState.pendingApproval,
      ControlState.degraded,
      ControlState.offlineCache,
      ControlState.ready,
      ControlState.registered,
      ControlState.cacheInvalid,
      ControlState.error,
      ControlState.notRegistered,
      ControlState.disconnected,
    ]) {
      expect(openAPI, contains('        - $state'));
    }

    for (final state in const [
      ConnectionIntentState.connected,
      ConnectionIntentState.disconnected,
    ]) {
      expect(openAPI, contains('        - $state'));
    }
  });

  testWidgets(
    'tray UI drives service commands through an OpenAPI-shaped fake',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bridge = ContractFakeBridge();
      final controller = EndlessNetController(
        config: AppConfig.parse(const [
          '--ipc-pipe',
          r'\\.\pipe\endlessnet-ui-e2e',
          '--connect-url',
          'https://endlessnet.ru/admin/connect/windows',
          '--admin-url',
          'https://endlessnet.ru/admin/',
        ]),
        bridge: bridge,
        logger: AppLogger('', enabled: false),
        desktopIntegrationEnabled: false,
      );
      controller.statusPayload = bridge.statusPayload;

      await tester.pumpWidget(EndlessNetApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('EndlessNet'), findsOneWidget);
      expect(find.text(ServiceState.connected), findsOneWidget);
      expect(find.text('100.64.0.42'), findsOneWidget);
      expect(find.text('prod'), findsOneWidget);
      expect(find.text('peer-a - direct'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(bridge.calls, contains('disconnect'));
      expect(find.text(ServiceState.disconnected), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(bridge.calls, contains('connect'));
      expect(find.text(ServiceState.connected), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    },
  );
}

class ContractFakeBridge extends EndlessNetClientBridge {
  ContractFakeBridge()
    : super(
        config: AppConfig.parse(const []),
        logger: AppLogger('', enabled: false),
      );

  final calls = <String>[];

  Map<String, dynamic> statusPayload = _contractStatus(
    state: ServiceState.connected,
    desiredState: ConnectionIntentState.connected,
    userDisconnected: false,
  );

  @override
  Future<Map<String, dynamic>> status() async {
    calls.add('status');
    return statusPayload;
  }

  @override
  Future<Map<String, dynamic>> connect() async {
    calls.add('connect');
    statusPayload = _contractStatus(
      state: ServiceState.connected,
      desiredState: ConnectionIntentState.connected,
      userDisconnected: false,
    );
    return statusPayload;
  }

  @override
  Future<Map<String, dynamic>> disconnect() async {
    calls.add('disconnect');
    statusPayload = _contractStatus(
      state: ServiceState.disconnected,
      controlState: ControlState.disconnected,
      desiredState: ConnectionIntentState.disconnected,
      userDisconnected: true,
    );
    return statusPayload;
  }
}

Map<String, dynamic> _contractStatus({
  required String state,
  String controlState = ControlState.ready,
  required String desiredState,
  required bool userDisconnected,
}) {
  return {
    'ipc_protocol': 'endlessnet-client-ipc',
    'ipc_version': 1,
    'ipc_min_supported_version': 1,
    'service_version': 'ui-e2e',
    'service_commit': 'contract',
    'service_build_date': '2026-07-09T00:00:00Z',
    'state': state,
    'control_state': controlState,
    'desired_state': desiredState,
    'user_disconnected': userDisconnected,
    'connection_intent': {
      'desired_state': desiredState,
      'reason': userDisconnected ? 'user_disconnect' : 'user_connect',
      'updated_at': '2026-07-09T00:00:00Z',
    },
    'cached_map_present': true,
    'cached_map_valid': true,
    'node_credential_present': true,
    'private_key_present': true,
    'account_id': 'acc_ui_e2e',
    'node_id': 'node_ui_e2e',
    'hostname': 'win-ui-e2e',
    'network_id': 'net_prod',
    'network_name': 'prod',
    'overlay_ip': '100.64.0.42',
    'map_revision': 7,
    'peer_count': 1,
    'agent': {
      'node_id': 'node_ui_e2e',
      'network_id': 'net_prod',
      'overlay_ip': '100.64.0.42',
      'peers': [
        {
          'peer_id': 'node_peer_a',
          'hostname': 'peer-a',
          'selected_path': 'direct',
        },
      ],
    },
  };
}
