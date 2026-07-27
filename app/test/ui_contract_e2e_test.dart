import 'dart:io';

import 'package:endlessnet/main.dart';
import 'package:endlessnet/named_pipe_http.dart';
import 'package:endlessnet/service_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default links target the deployed admin console', () {
    final config = AppConfig.parse(const []);

    expect(config.adminURL, 'https://admin.endlessnet.ru/');
  });

  test('UI contract constants mirror the OpenAPI enum/path surface', () {
    final contract = _ipcContractFile();
    final openAPI = contract.readAsStringSync();

    expect(openAPI, contains('title: EndlessNet Client Local Service IPC'));
    expect(_contractPaths(openAPI), ServiceIPCPath.all.toSet());
    expect(_schemaEnum(openAPI, 'ServiceState'), ServiceState.all.toSet());
    expect(_schemaEnum(openAPI, 'ControlState'), ControlState.all.toSet());
    expect(
      _schemaEnum(openAPI, 'AgentSnapshotState'),
      AgentSnapshotState.all.toSet(),
    );
    expect(
      _schemaEnum(openAPI, 'DesiredState'),
      ConnectionIntentState.all.toSet(),
    );
    expect(_schemaProperties(openAPI, 'EnrollRequest'), {
      'enroll_token',
      'server',
      'mode',
      'hostname',
      'idempotency_key',
    });
    expect(_schemaProperties(openAPI, 'ServerIdentityResponse'), {
      'control_plane_url',
      'trusted_key_id',
      'announced_key_id',
      'changed',
    });
    expect(_schemaProperties(openAPI, 'DiagnosticsResponse'), {'diagnostics'});
    expect(_schemaProperties(openAPI, 'LogsRecentResponse'), {'logs'});
    expect(
      _schemaProperties(openAPI, 'StatusResponse'),
      containsAll({
        'state',
        'control_state',
        'desired_state',
        'user_disconnected',
        'account_id',
        'node_id',
        'hostname',
        'network_id',
        'network_name',
        'approval_url',
        'overlay_ip',
        'map_revision',
        'peer_count',
        'node_credential_present',
        'agent',
      }),
    );
    expect(
      _schemaProperties(openAPI, 'AgentStatus'),
      containsAll({
        'state_present',
        'snapshot_state',
        'target_map_revision',
        'generated_at',
        'stun_ok',
        'relay_ok',
        'selected_path_counts',
        'peers',
      }),
    );
    expect(
      _schemaProperties(openAPI, 'PeerPathStatus'),
      containsAll({
        'peer_id',
        'hostname',
        'selected_path',
        'selected_endpoint',
        'selection_reason',
        'last_transition_at',
        'direct',
        'relay',
        'candidates',
      }),
    );
    expect(
      _schemaProperties(openAPI, 'PathCandidateStatus'),
      containsAll({
        'type',
        'tier',
        'state',
        'endpoint',
        'relay_id',
        'protocol',
        'rtt_ms',
        'checked_at',
        'last_reachable_at',
        'consecutive_failures',
        'reason',
      }),
    );
    expect(
      _schemaProperties(openAPI, 'Diagnostics'),
      containsAll({'generated_at', 'status'}),
    );
    expect(
      _schemaProperties(openAPI, 'NetworksResponse'),
      containsAll({'networks', 'selected_network_id'}),
    );
    for (final header in const [
      ServiceIPCMetadata.protocolHeader,
      ServiceIPCMetadata.versionHeader,
      ServiceIPCMetadata.minimumVersionHeader,
    ]) {
      expect(openAPI, contains('name: $header'));
    }
    for (final removedProperty in const [
      'join_token',
      'server_url',
      'server_urls',
      'enrollment_pending',
      'enrollment_approval_url',
    ]) {
      expect(
        RegExp('^\\s+$removedProperty:', multiLine: true).hasMatch(openAPI),
        isFalse,
        reason: '$removedProperty must not remain in the strict IPC contract',
      );
    }
  });

  testWidgets('UI drives service commands through an OpenAPI-shaped fake', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bridge = ContractFakeBridge();
    final controller = EndlessNetController(
      config: AppConfig.parse(const [
        '--ipc-pipe',
        r'\\.\pipe\endlessnet-ui-e2e',
        '--admin-url',
        'https://admin.endlessnet.ru/',
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
    expect(find.text('peer-a - Direct'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Connectivity diagnostics'), findsOneWidget);
    expect(find.text('1 direct'), findsWidgets);
    expect(find.text('STUN reachable · relay available'), findsWidgets);
    expect(
      find.text('Selected: Direct via 192.168.1.42:51820'),
      findsOneWidget,
    );
    await tester.tap(find.text('peer-a').last);
    await tester.pumpAndSettle();
    expect(find.text('Local candidate'), findsOneWidget);
    expect(
      find.textContaining('authenticated direct path selected'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('diagnostics'));

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
  });

  testWidgets('connectivity UI fits the minimum desktop window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bridge = ContractFakeBridge();
    final controller = EndlessNetController(
      config: AppConfig.parse(const []),
      bridge: bridge,
      logger: AppLogger('', enabled: false),
      desktopIntegrationEnabled: false,
    );
    addTearDown(controller.exitApp);
    controller.statusPayload = bridge.statusPayload;

    await tester.pumpWidget(EndlessNetApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('EndlessNet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Connectivity diagnostics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connect this device enrolls as local owner without elevation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final launchRequests = <Uri>[];
    final messages = <String>[];
    final elevatedRequests = <EnrollmentRequest>[];
    final bridge = ContractFakeBridge();
    bridge.statusPayload = {'state': ServiceState.needsEnrollment};
    bridge.enrollmentPayloads.add({
      'state': ServiceState.needsApproval,
      'control_state': ControlState.pendingApproval,
      'enrollment_request_id': 'ner_ui_connect',
      'approval_url':
          'https://admin.endlessnet.ru/?enrollment_request=ner_ui_connect',
    });
    final controller = EndlessNetController(
      config: AppConfig.parse(const [
        '--connect-url',
        'https://admin.endlessnet.ru/connect/windows/',
      ]),
      bridge: bridge,
      logger: AppLogger('', enabled: false),
      desktopIntegrationEnabled: false,
      externalURLLauncher: (uri) async {
        launchRequests.add(uri);
        return true;
      },
      messagePresenter: (title, message) async {
        messages.add('$title: $message');
      },
      elevatedEnrollmentLauncher: (request) async {
        elevatedRequests.add(request);
        return true;
      },
      enrollmentElevationSupported: true,
      enrollmentPollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.exitApp);
    controller.statusPayload = {'state': ServiceState.needsEnrollment};

    await tester.pumpWidget(EndlessNetApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Connect this device'), findsOneWidget);
    await tester.tap(find.text('Connect this device'));
    await tester.pump();
    await tester.pump();

    expect(launchRequests, [
      Uri.parse(
        'https://admin.endlessnet.ru/?enrollment_request=ner_ui_connect',
      ),
    ]);
    expect(messages, isEmpty);
    expect(elevatedRequests, isEmpty);
    expect(bridge.enrollmentRequests, hasLength(1));
    expect(bridge.enrollmentRequests.single.token, isEmpty);
    expect(bridge.enrollmentRequests.single.server, isEmpty);
    expect(bridge.enrollmentRequests.single.mode, 'workstation');

    await tester.pump(const Duration(milliseconds: 11));
    bridge.statusPayload = _contractStatus(
      state: ServiceState.connected,
      desiredState: ConnectionIntentState.connected,
      userDisconnected: false,
    );
    await tester.pump(const Duration(milliseconds: 11));
    await tester.pumpAndSettle();

    expect(bridge.calls.where((call) => call == 'enroll'), hasLength(1));
    expect(bridge.calls.where((call) => call == 'status'), isNotEmpty);
    expect(find.text(ServiceState.connected), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  test(
    'cancelled UAC leaves the device unenrolled with a clear error',
    () async {
      final messages = <String>[];
      final bridge = ContractFakeBridge();
      bridge.statusPayload = {'state': ServiceState.needsEnrollment};
      bridge.enrollmentError = const ServiceIPCException(
        statusCode: 403,
        errorCode: 'owner_required',
        message: 'local owner or administrator is required',
      );
      final controller = EndlessNetController(
        config: AppConfig.parse(const []),
        bridge: bridge,
        logger: AppLogger('', enabled: false),
        desktopIntegrationEnabled: false,
        elevatedEnrollmentLauncher: (_) async => false,
        enrollmentElevationSupported: true,
        messagePresenter: (title, message) async {
          messages.add('$title: $message');
        },
      );
      addTearDown(controller.exitApp);
      controller.statusPayload = bridge.statusPayload;

      await controller.connectDevice();

      expect(controller.errorText, contains('Administrator approval'));
      expect(messages.single, contains('Administrator approval'));
      expect(bridge.enrollmentRequests, hasLength(1));
    },
  );

  test(
    'degraded connected intent is refreshed until service is ready',
    () async {
      final bridge = ContractFakeBridge();
      bridge.statusPayload = _contractStatus(
        state: ServiceState.degraded,
        controlState: ControlState.degraded,
        desiredState: ConnectionIntentState.connected,
        userDisconnected: false,
      );
      final controller = EndlessNetController(
        config: AppConfig.parse(const []),
        bridge: bridge,
        logger: AppLogger('', enabled: false),
        desktopIntegrationEnabled: false,
        connectionPollInterval: const Duration(milliseconds: 5),
        connectionPollTimeout: const Duration(seconds: 1),
      );
      addTearDown(controller.exitApp);

      await controller.refreshStatus();
      expect(controller.state, ServiceState.degraded);

      bridge.statusPayload = _contractStatus(
        state: ServiceState.connected,
        desiredState: ConnectionIntentState.connected,
        userDisconnected: false,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (!controller.connected && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(controller.connected, isTrue);
      final completedStatusCalls = bridge.calls
          .where((call) => call == 'status')
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        bridge.calls.where((call) => call == 'status').length,
        completedStatusCalls,
      );
    },
  );

  testWidgets('UI explicitly confirms server identity recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bridge = ContractFakeBridge(identityChanged: true);
    final controller = EndlessNetController(
      config: AppConfig.parse(const []),
      bridge: bridge,
      logger: AppLogger('', enabled: false),
      desktopIntegrationEnabled: false,
    );
    controller.statusPayload = bridge.statusPayload;

    await tester.pumpWidget(EndlessNetApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Server identity changed'), findsAtLeast(2));
    expect(find.textContaining('ed25519:new'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Trust and connect'));
    await tester.pumpAndSettle();

    expect(
      bridge.calls,
      containsAllInOrder(['server-identity', 'trust-server']),
    );
    expect(find.text(ServiceState.connected), findsOneWidget);
  });
}

File _ipcContractFile() {
  final configured = Platform.environment['ENDLESSNET_IPC_OPENAPI']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    if (!file.existsSync()) {
      throw StateError('ENDLESSNET_IPC_OPENAPI does not exist: $configured');
    }
    return file;
  }

  var current = Directory.current.absolute;
  while (true) {
    final candidate = File(
      '${current.path}${Platform.pathSeparator}contracts${Platform.pathSeparator}upstream${Platform.pathSeparator}client-ipc-v1.openapi.yaml',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'contracts/upstream/client-ipc-v1.openapi.yaml was not found above ${Directory.current.path}',
      );
    }
    current = parent;
  }
}

class ContractFakeBridge extends EndlessNetClientBridge {
  ContractFakeBridge({bool identityChanged = false})
    : super(
        config: AppConfig.parse(const []),
        logger: AppLogger('', enabled: false),
      ) {
    if (identityChanged) {
      statusPayload = _contractStatus(
        state: ServiceState.serverIdentityChanged,
        controlState: ControlState.serverIdentityChanged,
        desiredState: ConnectionIntentState.connected,
        userDisconnected: false,
      );
    }
  }

  final calls = <String>[];
  final enrollmentPayloads = <Map<String, dynamic>>[];
  final enrollmentRequests = <EnrollmentRequest>[];
  Object? enrollmentError;

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
  Future<Map<String, dynamic>> enroll(EnrollmentRequest request) async {
    calls.add('enroll');
    enrollmentRequests.add(request);
    if (enrollmentError case final error?) {
      throw error;
    }
    if (enrollmentPayloads.isNotEmpty) {
      statusPayload = enrollmentPayloads.removeAt(0);
    }
    return statusPayload;
  }

  @override
  Future<Map<String, dynamic>> serverIdentity() async {
    calls.add('server-identity');
    return {
      'control_plane_url': 'https://api.endlessnet.ru',
      'trusted_key_id': 'ed25519:old',
      'announced_key_id': 'ed25519:new',
      'changed': true,
    };
  }

  @override
  Future<Map<String, dynamic>> trustServer(String confirmedKeyID) async {
    calls.add('trust-server');
    expect(confirmedKeyID, 'ed25519:new');
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

  @override
  Future<Map<String, dynamic>> diagnostics() async {
    calls.add('diagnostics');
    return {
      'ipc_protocol': 'endlessnet-client-ipc',
      'ipc_version': 1,
      'ipc_min_supported_version': 1,
      'diagnostics': {
        'generated_at': '2026-07-17T12:00:00Z',
        'client': {
          'product': 'endlessnet-client',
          'version': 'ui-e2e',
          'commit': 'contract',
          'build_date': '2026-07-09T00:00:00Z',
          'target_os': 'windows',
          'target_arch': 'amd64',
        },
        'runtime': {
          'goos': 'windows',
          'goarch': 'amd64',
          'go_version': 'go1.25',
          'os': {'name': 'Windows'},
        },
        'status': statusPayload,
        'last_errors': <String>[],
        'config': {
          'map_signing_trust_present': true,
          'token_present': true,
          'identity_private_key_present': true,
          'private_key_present': true,
          'node_credential_present': true,
          'device_fingerprint_present': true,
          'cached_map_present': true,
        },
        'recent_logs': <Map<String, dynamic>>[],
        'interfaces': <Map<String, dynamic>>[],
        'route_conflict_count': 0,
        'route_conflicts': <Map<String, dynamic>>[],
      },
    };
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
    'ipc_negotiated_version': 1,
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
    'map_signing_trust_present': true,
    'token_present': true,
    'node_credential_present': true,
    'device_fingerprint_present': true,
    'identity_private_key_present': true,
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
      'state_present': true,
      'snapshot_state': 'current',
      'node_id': 'node_ui_e2e',
      'network_id': 'net_prod',
      'overlay_ip': '100.64.0.42',
      'stun_ok': true,
      'relay_ok': true,
      'selected_path_counts': {'direct': 1},
      'peers': [
        {
          'peer_id': 'node_peer_a',
          'hostname': 'peer-a',
          'selected_path': 'direct',
          'selected_endpoint': '192.168.1.42:51820',
          'selection_reason':
              'authenticated direct path selected after successful candidate probe',
          'direct': {
            'type': 'direct',
            'tier': 'lan_direct',
            'state': 'reachable',
            'endpoint': '192.168.1.42:51820',
            'rtt_ms': 4.2,
          },
          'relay': {
            'type': 'relay',
            'tier': 'relay',
            'state': 'reachable',
            'endpoint': 'relay.example.test:443',
          },
        },
      ],
    },
  };
}

Set<String> _contractPaths(String openAPI) {
  return RegExp(
    r'^  (/[^:]+):\r?$',
    multiLine: true,
  ).allMatches(openAPI).map((match) => match.group(1)!).toSet();
}

Set<String> _schemaEnum(String openAPI, String schema) {
  final block = _schemaBlock(openAPI, schema);
  return RegExp(
    r'^        - ([^\r\n]+)\r?$',
    multiLine: true,
  ).allMatches(block).map((match) => match.group(1)!).toSet();
}

Set<String> _schemaProperties(String openAPI, String schema) {
  final block = _schemaBlock(openAPI, schema);
  final properties = RegExp(
    r'^( +)properties:\r?$',
    multiLine: true,
  ).firstMatch(block);
  if (properties == null) {
    throw StateError('OpenAPI schema has no properties: $schema');
  }
  final indent = properties.group(1)!.length + 2;
  final prefix = ' ' * indent;
  return block
      .split(RegExp(r'\r?\n'))
      .map((line) {
        if (!line.startsWith(prefix) || line.startsWith('$prefix ')) {
          return null;
        }
        return RegExp(
          r'^([a-z][a-z0-9_]*):$',
        ).firstMatch(line.trim())?.group(1);
      })
      .whereType<String>()
      .toSet();
}

String _schemaBlock(String openAPI, String schema) {
  final start = openAPI.indexOf('    $schema:');
  if (start < 0) {
    throw StateError('OpenAPI schema was not found: $schema');
  }
  final nextSchema = RegExp(
    r'^    [A-Za-z][A-Za-z0-9]*:',
    multiLine: true,
  ).firstMatch(openAPI.substring(start + schema.length + 5));
  final end = nextSchema == null
      ? openAPI.length
      : start + schema.length + 5 + nextSchema.start;
  return openAPI.substring(start, end);
}
