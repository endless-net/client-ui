import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ClientIntentJournal journal;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('en-intent-');
    journal = ClientIntentJournal(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  ClientOperation operation(
    PendingClientIntent intent, {
    bool terminal = false,
  }) => ClientOperation.fromProto(
    api.Operation(
      id: 'operation-a',
      requestId: intent.requestId,
      kind: intent.kind,
      continuity: api.ConnectionContinuity.CONNECTION_CONTINUITY_UNKNOWN,
      state: terminal
          ? api.OperationState.OPERATION_STATE_SUCCEEDED
          : api.OperationState.OPERATION_STATE_PENDING,
      change: terminal ? api.ChangeResult(changed: true) : null,
    ),
  );

  test(
    'US-03: full outbox reserves a durable Disconnect without evicting work',
    () async {
      // Seed the real admission boundary without O(n squared) prepare reads.
      for (var offset = 0; offset < 4096; offset += 64) {
        await Future.wait([
          for (var index = offset; index < offset + 64; index++)
            File.fromUri(
              directory.uri.resolve(
                '12345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}.json',
              ),
            ).writeAsString(
              jsonEncode({
                'request_id':
                    '12345678-1234-4234-8234-${index.toRadixString(16).padLeft(12, '0')}',
                'kind': api.OperationKind.OPERATION_KIND_CONNECT.value,
              }),
            ),
        ]);
      }
      // Two command kinds compete for the final ordinary slot. A failed
      // admission must not poison the queue or consume Disconnect's reserve.
      await File.fromUri(
        directory.uri.resolve('12345678-1234-4234-8234-000000000fff.json'),
      ).delete();
      final competing = await Future.wait<Object>([
        for (final kind in [
          api.OperationKind.OPERATION_KIND_CONNECT,
          api.OperationKind.OPERATION_KIND_RENEW_SESSION,
        ])
          journal
              .prepare(kind)
              .then<Object>(
                (intent) => intent,
                onError: (Object error) => error,
              ),
      ]);
      expect(competing.whereType<PendingClientIntent>(), hasLength(1));
      expect(competing.whereType<StateError>(), hasLength(1));
      expect(await journal.pending(), hasLength(4096));
      await expectLater(
        journal.prepare(api.OperationKind.OPERATION_KIND_CONNECT),
        throwsStateError,
      );
      PendingClientIntent? disconnect;
      await expectLater(
        journal.submit(api.OperationKind.OPERATION_KIND_DISCONNECT, (
          intent,
        ) async {
          disconnect = intent;
          throw TimeoutException('synthetic uncertain disconnect');
        }),
        throwsA(isA<TimeoutException>()),
      );
      final reopened = ClientIntentJournal(directory);
      final retained = await reopened.pending();
      expect(retained, hasLength(4097));
      expect(
        retained
            .where(
              (intent) =>
                  intent.kind == api.OperationKind.OPERATION_KIND_DISCONNECT,
            )
            .single
            .requestId,
        disconnect!.requestId,
      );
      await expectLater(
        reopened.prepare(api.OperationKind.OPERATION_KIND_DISCONNECT),
        throwsStateError,
      );
      await reopened.acknowledge(operation(disconnect!, terminal: true));
      expect(await reopened.pending(), hasLength(4096));
      final next = await reopened.prepare(
        api.OperationKind.OPERATION_KIND_DISCONNECT,
      );
      expect(next.requestId, isNot(disconnect!.requestId));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'US-03: journal serialization does not wait for a stalled command RPC',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final connecting = journal.submit(
        api.OperationKind.OPERATION_KIND_CONNECT,
        (intent) async {
          entered.complete();
          await release.future;
          return operation(intent);
        },
      );
      try {
        await entered.future;
        final disconnect = await journal
            .submit(
              api.OperationKind.OPERATION_KIND_DISCONNECT,
              (intent) async => operation(intent),
            )
            .timeout(const Duration(seconds: 5));
        expect(
          disconnect.value.kind,
          api.OperationKind.OPERATION_KIND_DISCONNECT,
        );
        expect(await journal.pending(), hasLength(2));
        expect(release.isCompleted, isFalse);
      } finally {
        release.complete();
        await connecting;
      }
    },
  );

  test(
    'US-03: ID is persisted before send and survives uncertain acceptance',
    () async {
      String? requestId;
      await expectLater(
        journal.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          intent,
        ) async {
          requestId = intent.requestId;
          final reopened = await ClientIntentJournal(directory).pending();
          expect(reopened.single.requestId, intent.requestId);
          throw TimeoutException('synthetic transport timeout');
        }),
        throwsA(isA<TimeoutException>()),
      );
      final pending = await ClientIntentJournal(directory).pending();
      expect(pending.single.requestId, requestId);
      expect(pending.single.kind, api.OperationKind.OPERATION_KIND_CONNECT);
    },
  );

  test(
    'US-03: only matching terminal results remove pending intention',
    () async {
      final intent = await journal.prepare(
        api.OperationKind.OPERATION_KIND_CONNECT,
      );
      await expectLater(
        journal.acknowledge(operation(intent)),
        throwsStateError,
      );
      expect(await journal.pending(), hasLength(1));
      await journal.acknowledge(operation(intent, terminal: true));
      expect(await journal.pending(), isEmpty);
    },
  );

  test(
    'US-03: mismatched response does not lose the original intention',
    () async {
      await expectLater(
        journal.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          intent,
        ) async {
          return operation(
            PendingClientIntent(
              intent.requestId,
              api.OperationKind.OPERATION_KIND_DISCONNECT,
            ),
          );
        }),
        throwsFormatException,
      );
      expect(
        (await journal.pending()).single.kind,
        api.OperationKind.OPERATION_KIND_CONNECT,
      );
    },
  );

  test(
    'US-03/14: records contain only ID and kind, never command payload',
    () async {
      final intent = await journal.prepare(
        api.OperationKind.OPERATION_KIND_ENROLL,
      );
      final file = File.fromUri(
        directory.uri.resolve('${intent.requestId}.json'),
      );
      expect(
        await file.readAsString(),
        '{"request_id":"${intent.requestId}","kind":1}',
      );
    },
  );

  test(
    'US-03: truncated record fails closed without disclosing its contents',
    () async {
      final file = File.fromUri(
        directory.uri.resolve('12345678-1234-4234-8234-123456789abc.json'),
      );
      await file.writeAsString('{synthetic-sensitive-marker');
      await expectLater(
        journal.pending(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe diagnostic',
            isNot(contains('synthetic-sensitive-marker')),
          ),
        ),
      );
      var sent = false;
      await expectLater(
        journal.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          intent,
        ) async {
          sent = true;
          return operation(intent);
        }),
        throwsFormatException,
      );
      expect(sent, isFalse);
      expect(await file.exists(), isTrue);
    },
  );
}
