import 'dart:io';

import 'package:endlessnet/client_event_stream.dart';
import 'package:endlessnet/local_client_events.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_host.dart';

void main() {
  final executable = Platform.environment['ENDLESSNET_TESTSERVER'];
  test(
    'US-01/03: Go host → local gRPC → validated snapshot and reconnect',
    () async {
      final runtime = {
        'protocol': api.ClientContract.protocol,
        'ipcVersion': api.ClientContract.version,
        'contractSha256': api.ClientContract.sha256,
        'instanceId': 'runtime-a',
        'callerAccess': 'ACCESS_OWNER',
      };
      const requestId = '12345678-1234-1234-1234-123456789abc';
      final connectRequest = {
        'mutation': {
          'requestId': requestId,
          'expectedInstanceId': 'runtime-a',
          'expectedRevision': '8',
        },
        'profile': {'profileId': 'active'},
      };
      final accepted = {
        'id': 'connect-operation',
        'requestId': requestId,
        'kind': 'OPERATION_KIND_CONNECT',
        'state': 'OPERATION_STATE_PENDING',
      };
      final host = await ScenarioHost.start(executable!, [
        {
          'method': 'GetRuntimeInfo',
          'request': {},
          'responses': [
            {'runtime': runtime},
          ],
        },
        for (final revision in [7, 8])
          {
            'method': 'WatchEvents',
            'request': {},
            'responses': [
              {
                'sequence': '1',
                'metadata': {
                  'instanceId': 'runtime-a',
                  'revision': '$revision',
                },
                'snapshot': {
                  'runtime': runtime,
                  'status': {
                    'metadata': {
                      'instanceId': 'runtime-a',
                      'revision': '$revision',
                    },
                    'connectionPhase': 'CONNECTION_PHASE_CONNECTING',
                    'currentOperations': [
                      {
                        'id': 'op',
                        'profileId': 'inactive',
                        'kind': 'OPERATION_KIND_CONNECT',
                        'state': 'OPERATION_STATE_RUNNING',
                      },
                    ],
                  },
                },
              },
              {
                'sequence': '2',
                'metadata': {
                  'instanceId': 'runtime-a',
                  'revision': '$revision',
                },
                'failure': {
                  'code': 'ERROR_CODE_LIMIT_EXCEEDED',
                  'retryable': true,
                },
              },
            ],
          },
        {
          'method': 'Connect',
          'request': connectRequest,
          'responses': [
            {'operation': accepted},
          ],
        },
        {
          'method': 'GetOperation',
          'request': {'requestId': requestId},
          'responses': [
            {'operation': accepted},
          ],
        },
      ]);
      LocalClientEvents? source;
      try {
        source = await LocalClientEvents.open(endpoint: host.endpoint);
        for (final revision in [7, 8]) {
          await expectLater(
            source.watch(),
            emitsInOrder([
              isA<api.WatchEventsResponse>()
                  .having(
                    (e) => e.snapshot.status.connectionPhase,
                    'phase',
                    api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
                  )
                  .having(
                    (e) => e.metadata.revision.toString(),
                    'revision',
                    '$revision',
                  )
                  .having(
                    (e) => e.snapshot.status.currentOperations.single.kind,
                    'kind',
                    api.OperationKind.OPERATION_KIND_CONNECT,
                  ),
              emitsError(
                isA<ClientEventFailure>().having(
                  (e) => e.failure.code,
                  'code',
                  api.ErrorCode.ERROR_CODE_LIMIT_EXCEEDED,
                ),
              ),
              emitsDone,
            ]),
          );
        }
        final request = api.ConnectRequest()
          ..mergeFromProto3Json(connectRequest);
        final operation = await source.mutations.connect(request);
        expect(operation.terminal, isFalse);
        expect(operation.succeeded, isFalse);
        final recovered = await source.mutations.recoverByRequestId(
          requestId,
          api.OperationKind.OPERATION_KIND_CONNECT,
        );
        expect(recovered.value.id, operation.value.id);
        await source.close();
        await host.verify();
      } finally {
        await source?.close();
        await host.close();
      }
    },
    skip: executable == null
        ? 'Requires pinned producer testserver in CI'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
