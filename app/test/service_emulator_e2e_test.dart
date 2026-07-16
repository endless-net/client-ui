import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endlessnet_tray/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/service_emulator.dart';

void main() {
  final executable = Platform.environment['ENDLESSNET_SERVICE_EMULATOR']
      ?.trim();
  final skipReason = !Platform.isWindows
      ? 'the service emulator uses Windows named pipes'
      : executable == null || executable.isEmpty
      ? 'set ENDLESSNET_SERVICE_EMULATOR to the emulator executable'
      : !File(executable).existsSync()
      ? 'ENDLESSNET_SERVICE_EMULATOR does not exist: $executable'
      : false;

  test(
    'UI bridge exercises the complete service contract over a named pipe',
    () async {
      final emulator = await ServiceEmulatorProcess.start(executable!);
      addTearDown(emulator.stop);
      final bridge = EndlessNetClientBridge(
        config: AppConfig.parse(['--ipc-pipe', emulator.pipe]),
        logger: AppLogger('', enabled: false),
      );

      var status = await bridge.status();
      expect(status['ipc_protocol'], 'endlessnet-client-ipc');
      expect(status['ipc_version'], 1);
      expect(status['state'], 'Connected');

      final networks = await bridge.networks();
      expect(networks['networks'], hasLength(2));
      final selected = await bridge.selectNetwork('net_staging');
      expect(selected['selected_network_id'], 'net_staging');

      status = await bridge.disconnect();
      expect(status['state'], 'Disconnected');
      expect(status['user_disconnected'], isTrue);
      status = await bridge.connect();
      expect(status['state'], 'Connected');

      final identity = await bridge.serverIdentity();
      final announcedKey = identity['announced_key_id'] as String;
      final trusted = await bridge.trustServer(announcedKey);
      expect(trusted['state'], 'Connected');

      final diagnostics = await bridge.diagnostics();
      expect(diagnostics['status'], isA<Map<String, dynamic>>());
      expect(diagnostics['recent_logs'], isNotEmpty);
      final logs = await bridge.recentLogs();
      expect(logs['logs'], isNotEmpty);

      status = await bridge.logout();
      expect(status['state'], 'NeedsEnrollment');
      status = await bridge.enroll(
        EnrollmentRequest(
          token: 'enj_emulator_e2e_secret',
          server: 'https://api.example.test',
          mode: 'workstation',
        ),
      );
      expect(status['state'], 'Connected');
      expect(status['enrolled'], isTrue);

      final interactions = await emulator.interactions();
      expect(
        interactions.map((entry) => '${entry['method']} ${entry['target']}'),
        containsAll(<String>[
          'GET /status',
          'GET /networks',
          'POST /network/select',
          'POST /disconnect',
          'POST /connect',
          'GET /server-identity',
          'POST /server-identity/trust',
          'GET /diagnostics',
          'GET /logs/recent',
          'POST /logout',
          'POST /enroll',
        ]),
      );
      final enroll = interactions.lastWhere(
        (entry) => entry['target'] == '/enroll',
      );
      expect(
        (enroll['request_body'] as Map<String, dynamic>)['join_token'],
        '<redacted>',
      );
      expect(
        jsonEncode(interactions),
        isNot(contains('enj_emulator_e2e_secret')),
      );
    },
    skip: skipReason != false,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'real UI buttons drive state transitions through the service emulator',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emulator = (await tester.runAsync(
        () => ServiceEmulatorProcess.start(executable!),
      ))!;
      addTearDown(emulator.stop);
      final config = AppConfig.parse(['--ipc-pipe', emulator.pipe]);
      final controller = EndlessNetController(
        config: config,
        bridge: EndlessNetClientBridge(
          config: config,
          logger: AppLogger('', enabled: false),
        ),
        logger: AppLogger('', enabled: false),
        desktopIntegrationEnabled: false,
      );
      addTearDown(controller.exitApp);
      await tester.runAsync(controller.initialize);

      await tester.pumpWidget(EndlessNetApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('100.64.0.10'), findsOneWidget);

      final disconnectButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Disconnect'),
      );
      await tester.runAsync(() async {
        disconnectButton.onPressed!();
        await _waitUntilIdle(controller);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Connect'), findsOneWidget);

      final connectButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Connect'),
      );
      await tester.runAsync(() async {
        connectButton.onPressed!();
        await _waitUntilIdle(controller);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Connected'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsOneWidget);

      final interactions = (await tester.runAsync(emulator.interactions))!;
      expect(
        interactions.map((entry) => entry['target']),
        containsAllInOrder(['/status', '/disconnect', '/connect']),
      );
    },
    skip: skipReason != false,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'scenario can inject a contract error and update observable state',
    () async {
      const scenario = <String, dynamic>{
        'schema_version': 1,
        'name': 'connect-failure',
        'routes': <Map<String, dynamic>>[
          <String, dynamic>{
            'method': 'POST',
            'path': '/connect',
            'repeat_last': true,
            'responses': <Map<String, dynamic>>[
              <String, dynamic>{
                'expect_body': <String, dynamic>{},
                'status': 503,
                'body': <String, dynamic>{
                  'ok': false,
                  'error_code': 'connect_failed',
                  'error': 'control plane unavailable',
                },
                'status_patch': <String, dynamic>{
                  'state': 'Degraded',
                  'control_state': 'offline_cache',
                },
              },
            ],
          },
        ],
      };
      final emulator = await ServiceEmulatorProcess.start(
        executable!,
        scenario: scenario,
      );
      addTearDown(emulator.stop);
      final bridge = EndlessNetClientBridge(
        config: AppConfig.parse(['--ipc-pipe', emulator.pipe]),
        logger: AppLogger('', enabled: false),
      );

      await expectLater(
        bridge.connect(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'control plane unavailable',
          ),
        ),
      );
      final status = await bridge.status();
      expect(status['state'], 'Degraded');
      expect(status['control_state'], 'offline_cache');
    },
    skip: skipReason != false,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _waitUntilIdle(EndlessNetController controller) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (controller.busy) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('UI controller did not complete its IPC action');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
