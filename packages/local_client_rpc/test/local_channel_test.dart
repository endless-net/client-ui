import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' hide Platform;
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

void main() {
  test('only local desktop endpoints are accepted', () {
    for (final os in ['windows', 'linux', 'macos']) {
      for (final endpoint in [
        'http://localhost:8765',
        'relative',
        r'\\remote\pipe\service',
        '/tmp/null\u0000.sock',
      ]) {
        expect(
          () => validateLocalEndpoint(endpoint, operatingSystem: os),
          throwsArgumentError,
        );
      }
      expect(validateLocalEndpoint(null, operatingSystem: os), isNotEmpty);
    }
    for (final os in ['android', 'ios']) {
      expect(
        () => validateLocalEndpoint(null, operatingSystem: os),
        throwsUnsupportedError,
      );
    }
  });

  final host = Platform.environment['ENDLESSNET_TESTSERVER'];
  test(
    'Go/Dart local bootstrap, unary, streaming and typed rejection',
    () async {
      final directory = await Directory.systemTemp.createTemp('en-dart-');
      final socketDirectory = Platform.isWindows
          ? directory
          : await Directory('/tmp').createTemp('en-dart-');
      final endpoint = Platform.isWindows
          ? r'\\.\pipe\en-dart-' +
                DateTime.now().microsecondsSinceEpoch.toString()
          : '${socketDirectory.path}/rpc.sock';
      final script = File('${directory.path}/scenario.json');
      await script.writeAsString(
        jsonEncode({
          'steps': [
            {
              'method': 'GetRuntimeInfo',
              'request': {},
              'responses': [
                {
                  'runtime': {
                    'protocol': ClientContract.protocol,
                    'ipcVersion': ClientContract.version,
                    'contractSha256': ClientContract.sha256,
                    'instanceId': 'test-instance',
                  },
                },
              ],
            },
            {
              'method': 'GetStatus',
              'request': {},
              'responses': [
                {
                  'status': {
                    'connectionPhase': 'CONNECTION_PHASE_CONNECTING',
                    'currentOperations': [
                      {
                        'id': 'op',
                        'profileId': 'inactive',
                        'kind': 'OPERATION_KIND_RENEW_SESSION',
                        'state': 'OPERATION_STATE_RUNNING',
                      },
                    ],
                  },
                },
              ],
            },
            {
              'method': 'WatchEvents',
              'request': {},
              'responses': [
                {
                  'sequence': '1',
                  'snapshot': {
                    'runtime': {'instanceId': 'test-instance'},
                  },
                },
                {
                  'sequence': '2',
                  'operationChanged': {
                    'id': 'op',
                    'kind': 'OPERATION_KIND_RENEW_SESSION',
                    'state': 'OPERATION_STATE_RUNNING',
                  },
                },
              ],
            },
            {
              'method': 'GetStatus',
              'request': {},
              'failure': {
                'rpc_code': 'unavailable',
                'detail': {'code': 'ERROR_CODE_UNAVAILABLE', 'retryable': true},
              },
            },
          ],
        }),
      );
      final process = await Process.start(host!, [
        '--script',
        script.path,
        '--endpoint',
        endpoint,
        '--access',
        'owner',
      ]);
      final stderr = process.stderr.transform(utf8.decoder).join();
      final output = StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      LocalClientChannel? channel;
      try {
        expect(
          await output.moveNext().timeout(const Duration(seconds: 10)),
          isTrue,
        );
        final ready = jsonDecode(output.current) as Map<String, dynamic>;
        expect(ready['event'], 'ready');
        expect(ready['contract_sha256'], ClientContract.sha256);
        channel = LocalClientChannel(endpoint: endpoint);
        final client = localServiceClient(channel);
        expect(
          (await bootstrapLocalClient(client)).instanceId,
          'test-instance',
        );
        final status = await client.getStatus(GetStatusRequest());
        expect(
          status.status.connectionPhase,
          ConnectionPhase.CONNECTION_PHASE_CONNECTING,
        );
        expect(
          status.status.currentOperations.single.kind,
          OperationKind.OPERATION_KIND_RENEW_SESSION,
        );
        final events = await client.watchEvents(WatchEventsRequest()).toList();
        expect(events.length, 2);
        expect(events.first.snapshot.runtime.instanceId, 'test-instance');
        expect(
          events.last.operationChanged.kind,
          OperationKind.OPERATION_KIND_RENEW_SESSION,
        );
        await expectLater(
          client.getStatus(GetStatusRequest()),
          throwsA(
            isA<GrpcError>().having(
              (e) => e.code,
              'code',
              StatusCode.unavailable,
            ),
          ),
        );
        await channel.shutdown();
        channel = null;
        process.stdin.writeln('verify');
        await process.stdin.flush();
        expect(
          await output.moveNext().timeout(const Duration(seconds: 10)),
          isTrue,
        );
        expect((jsonDecode(output.current) as Map)['event'], 'verified');
        expect(
          await process.exitCode.timeout(const Duration(seconds: 10)),
          0,
          reason: await stderr,
        );
      } finally {
        await channel?.terminate();
        process.kill();
        await process.exitCode;
        await output.cancel();
        await script.delete();
        await directory.delete();
        if (socketDirectory.path != directory.path)
          await socketDirectory.delete();
      }
    },
    skip: host == null
        ? 'Go/Dart local integration runs in the three-platform CI job'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
