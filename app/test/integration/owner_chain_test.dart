import 'dart:convert';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/contract_identity.dart';
import 'package:endlessnet_client_ui/client/correlation_journal.dart';
import 'package:endlessnet_client_ui/client/windows_correlation_store.dart';
import 'package:endlessnet_client_ui/client/windows_pipe.dart';
import 'package:endlessnet_client_ui/client/windows_pipe_config.dart';
import 'package:endlessnet_client_ui/enrollment/controller.dart';
import 'package:endlessnet_client_ui/enrollment/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = 'real Windows Client owner chain';

Future<void> _until(
  EnrollmentController controller,
  bool Function() ready,
) async {
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) {
      fail('Owner-chain UI deadline: ${controller.reasonKey}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await controller.refresh();
  }
}

Future<void> _browser(String address, Uri verification) async {
  final endpoint = Uri.parse('http://$address/simulate-login');
  expect(endpoint.host, '127.0.0.1');
  expect(endpoint.hasPort, isTrue);
  expect(endpoint.port, greaterThan(0));
  // Widget tests replace HttpClient with a 400 responder. Only this isolated
  // browser-controller port uses a bounded raw socket; UI APIs still use pipe.
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    endpoint.port,
    timeout: const Duration(seconds: 3),
  );
  try {
    final body = utf8.encode(
      jsonEncode({'verification_url': verification.toString()}),
    );
    socket.add(
      utf8.encode(
        'POST /simulate-login HTTP/1.1\r\nHost: ${endpoint.authority}\r\n'
        'Content-Type: application/json\r\nContent-Length: ${body.length}\r\n'
        'Connection: close\r\n\r\n',
      ),
    );
    socket.add(body);
    await socket.flush();
    final response = await socket
        .fold<List<int>>([], (bytes, chunk) {
          if (bytes.length + chunk.length > 4096) {
            throw StateError('Browser controller response bound');
          }
          return bytes..addAll(chunk);
        })
        .timeout(const Duration(seconds: 15));
    expect(
      ascii.decode(response).split('\r\n').first,
      startsWith('HTTP/1.1 204 '),
    );
  } finally {
    socket.destroy();
  }
}

void main() {
  final inputPath = Platform.environment['ENDLESSNET_UI_OWNER_CHAIN_FIXTURE'];
  testWidgets(
    _name,
    (tester) async {
      WindowsEnrollmentConnection? connection;
      JournalCorrelationStore? journal;
      EnrollmentController? controller;
      Map<String, Object?>? outcome;
      var cycle = -1;
      late Map<String, dynamic> input;
      try {
        await tester.runAsync(() async {
          final file = File(inputPath!);
          expect(file.isAbsolute, isTrue);
          expect(await file.length(), lessThanOrEqualTo(65536));
          input = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          cycle = input['cycle'] as int;
          expect(cycle, anyOf(0, 1));
          expect(input['origin'], 'https://public.invalid');
          expect(input['digest'], clientContractSha256);
          final temp = '${Directory.systemTemp.absolute.path}\\'.toLowerCase();
          for (final key in ['journal', 'result']) {
            expect(
              File(input[key] as String).absolute.path.toLowerCase(),
              startsWith(temp),
            );
          }
          connection = await connectWindowsEnrollment(
            config: WindowsPipeConfig(
              instanceId: input['instance'] as String,
              serverSid: input['sid'] as String,
              nativeLibraryPath: input['library'] as String,
              connectTimeout: const Duration(seconds: 3),
              writeTimeout: const Duration(seconds: 3),
              maxPendingWriteBytes: 262144,
            ),
            expectedContractSha256: clientContractSha256,
            maxFailureBytes: 16384,
          );
          journal = await openWindowsCorrelationStore(
            File(input['journal'] as String),
            maxBytes: 65536,
          );
          final c = EnrollmentController(
            client: connection!.client,
            store: journal!,
            expectedContractSha256: clientContractSha256,
            now: DateTime.now,
            callTimeout: const Duration(seconds: 3),
            recoveryPollInterval: const Duration(seconds: 1),
            automaticPolling: false,
          );
          controller = c;
          await c.bind(
            api.Profile(
              id: input['profile'] as String,
              controlOrigin: input['origin'] as String,
            ),
          );
          expect(c.link, EnrollmentLinkState.available, reason: c.reasonKey);
          if (cycle == 0) {
            expect(c.canEnroll, isTrue);
            await c.start(
              'owner-chain-ui-device',
              api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
            );
            expect(c.correlation?.requestId, isNotEmpty);
            await _until(c, () => c.browserAction != null);
            await _browser(
              input['browser_simulator'] as String,
              c.browserAction!,
            );
            await _until(c, () => c.canLoadTargets);
            await c.loadTargets();
            expect(c.targets, hasLength(1));
            expect(c.canSelect('account', 'network'), isTrue);
            await c.selectTarget('account', 'network');
            await _until(c, () => c.uncertain);
            expect(c.link, EnrollmentLinkState.available);
            expect(c.registeredConfirmed, isFalse);
            expect(
              c.currentAttempt?.certainty,
              api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN,
            );
          } else {
            expect(c.canEnroll, isFalse);
            await _until(c, () => c.registeredConfirmed);
            expect(c.currentAttempt!.accountId, 'account');
            expect(c.currentAttempt!.networkId, 'network');
            expect(c.currentAttempt!.nodeId, isNotEmpty);
          }
          outcome = {
            'request_id': c.correlation!.requestId,
            'attempt_id': c.currentAttempt!.attemptId,
            'node_id': c.currentAttempt!.nodeId,
            'registered': c.registeredConfirmed,
          };
        });
        if (outcome == null) {
          return; // runAsync has already reported its failure.
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EnrollmentPanel(controller: controller!, now: DateTime.now),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text('Устройство зарегистрировано'),
          cycle == 1 ? findsOneWidget : findsNothing,
        );
        if (cycle == 0) {
          expect(
            find.text('Исход регистрации пока неизвестен'),
            findsOneWidget,
          );
        }
        await tester.runAsync(() async {
          await File(input['result'] as String)
              .writeAsString(jsonEncode(outcome), flush: true);
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller?.dispose();
        await tester.runAsync(() async {
          try {
            await connection?.close();
          } finally {
            await journal?.close();
          }
        });
      }
    },
    skip: !Platform.isWindows || inputPath == null,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
