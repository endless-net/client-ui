import 'package:endlessnet/client_event_stream.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse event(int sequence, Map<String, Object> payload) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '$sequence',
      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      ...payload,
    });

api.WatchEventsResponse snapshot(int sequence) => event(sequence, {
  'snapshot': {
    'runtime': {
      'protocol': api.ClientContract.protocol,
      'contractSha256': api.ClientContract.sha256,
      'instanceId': 'runtime-a',
      'callerAccess': 'ACCESS_OWNER',
    },
    'status': {
      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
    },
  },
});

void main() {
  test(
    'US-01: capability refresh snapshot is accepted after first event',
    () async {
      await expectLater(
        validateClientEvents(Stream.fromIterable([snapshot(1), snapshot(2)])),
        emitsInOrder([
          isA<api.WatchEventsResponse>(),
          isA<api.WatchEventsResponse>(),
          emitsError(isA<ClientEventStreamEnded>()),
          emitsDone,
        ]),
      );
    },
  );

  final invalid = <String, api.WatchEventsResponse Function()>{
    'repeated sequence': () => snapshot(1),
    'different runtime': () => snapshot(2)..metadata.instanceId = 'runtime-b',
    'revision regression': () => snapshot(2)..metadata.revision -= 1,
    'empty event': () => event(2, {}),
    'unknown invalidation': () => event(2, {'invalidated': {}}),
    'missing failure code': () => event(2, {'failure': {}}),
    'missing operation kind': () => event(2, {
      'operationChanged': {
        'id': 'operation-a',
        'state': 'OPERATION_STATE_RUNNING',
      },
    }),
    'full status lacks metadata': () => event(2, {'statusChanged': {}}),
  };
  for (final entry in invalid.entries) {
    test('US-01/03: stream rejects ${entry.key}', () async {
      await expectLater(
        validateClientEvents(
          Stream.fromIterable([snapshot(1), entry.value(), snapshot(3)]),
        ),
        emitsInOrder([
          isA<api.WatchEventsResponse>(),
          emitsError(isA<FormatException>()),
          emitsDone,
        ]),
      );
    });
  }

  test(
    'US-03: overflow preserves typed failure and stops the subscription',
    () async {
      await expectLater(
        validateClientEvents(
          Stream.fromIterable([
            snapshot(1),
            event(2, {
              'failure': {
                'code': 'ERROR_CODE_LIMIT_EXCEEDED',
                'retryable': true,
              },
            }),
          ]),
        ),
        emitsInOrder([
          isA<api.WatchEventsResponse>(),
          emitsError(
            isA<ClientEventFailure>()
                .having(
                  (e) => e.failure.code,
                  'code',
                  api.ErrorCode.ERROR_CODE_LIMIT_EXCEEDED,
                )
                .having((e) => e.failure.retryable, 'retryable', isTrue),
          ),
          emitsDone,
        ]),
      );
    },
  );

  test('US-01: observer session disclosure fails closed', () async {
    final first = snapshot(1);
    first.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
    await expectLater(
      validateClientEvents(
        Stream.fromIterable([
          first,
          event(2, {'sessionChanged': {}}),
        ]),
      ),
      emitsInOrder([
        isA<api.WatchEventsResponse>(),
        emitsError(isA<FormatException>()),
        emitsDone,
      ]),
    );
  });

  test(
    'US-03: new subscription starts at one and never inherits old cursor',
    () async {
      for (var attempt = 0; attempt < 2; attempt++) {
        final value = await validateClientEvents(
          Stream.value(snapshot(1)),
        ).first;
        expect(value.sequence.toString(), '1');
        expect(() => value.clearSnapshot(), throwsUnsupportedError);
      }
    },
  );
}
