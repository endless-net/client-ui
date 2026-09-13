@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_diagnostics_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:flutter/material.dart';
import 'package:endlessnet/client_recent_logs.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

api.ListRecentLogsResponse page({
  String next = '',
  int revision = 7,
  int seconds = 100,
  String message = 'safe',
}) => api.ListRecentLogsResponse()
  ..mergeFromProto3Json({
    'page': {
      'nextPageToken': next,
      'metadata': {'instanceId': 'runtime-a', 'revision': '$revision'},
    },
    'logs': [
      {
        'timestamp': DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).toIso8601String(),
        'message': message,
      },
    ],
  });

void main() {
  testWidgets('US-07: log preview is local, gated and cleared on stream loss', (
    tester,
  ) async {
    final state = ClientStateController();
    final source = StreamController<api.WatchEventsResponse>();
    await state.attach(source.stream);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientDiagnosticsPanel(
            state: state,
            load: () async => api.Diagnostics(),
            createBundle: (_) async => throw StateError('No bundle expected'),
            loadLogs: () async {
              calls++;
              return page(message: 'profile-local-record').logs;
            },
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('load-client-logs')))
          .onPressed,
      isNull,
    );
    final snapshot = api.WatchEventsResponse()
      ..mergeFromProto3Json({
        'sequence': '1',
        'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        'snapshot': {
          'runtime': {
            'protocol': api.ClientContract.protocol,
            'contractSha256': api.ClientContract.sha256,
            'instanceId': 'runtime-a',
            'callerAccess': 'ACCESS_OWNER',
            'capabilities': [
              {
                'capability': 'CAPABILITY_DIAGNOSTICS',
                'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
              },
            ],
          },
          'status': {
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'activeProfileId': 'profile-a',
          },
        },
      });
    source.add(snapshot);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('load-client-logs')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('profile-local-record'), findsOneWidget);
    source.addError(StateError('private transport detail'));
    await tester.pumpAndSettle();
    expect(find.textContaining('profile-local-record'), findsNothing);
    expect(find.textContaining('private transport detail'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('load-client-logs')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await state.detach();
      await source.close();
    });
    state.dispose();
  });
  test('US-07: bounded profile log snapshot is paged and frozen', () async {
    final requests = <api.ListRecentLogsRequest>[];
    final first = page(next: 'opaque');
    final result = await readClientRecentLogs(
      (request) async {
        requests.add(request);
        return requests.length == 1 ? first : page(seconds: 101);
      },
      instanceId: 'runtime-a',
      profileId: 'profile-a',
      minimumRevision: 7,
      checkContext: () {},
    );
    expect(requests.map((r) => r.profile.profileId), everyElement('profile-a'));
    expect(requests.map((r) => r.page.pageToken), ['', 'opaque']);
    expect(requests.map((r) => r.page.pageSize), everyElement(100));
    first.logs.first.message = 'changed';
    expect(result.first.message, 'safe');
    expect(result.length, 2);
    expect(() => result.clear(), throwsUnsupportedError);
    expect(() => result.first.message = 'changed', throwsUnsupportedError);
  });

  for (final mode in [
    'instance',
    'revision',
    'stale',
    'token-loop',
    'empty-next',
    'long-message',
    'timestamp',
    'order',
    'too-many',
  ]) {
    test('US-07: rejects $mode without returning partial logs', () async {
      var calls = 0;
      await expectLater(
        readClientRecentLogs(
          (_) async {
            calls++;
            if (calls == 1) return page(next: 'opaque');
            final response = page(seconds: 101);
            switch (mode) {
              case 'instance':
                response.page.metadata.instanceId = 'other';
              case 'revision':
                response.page.metadata.revision += 1;
              case 'stale':
                response.page.metadata.revision -= 1;
              case 'token-loop':
                response.page.nextPageToken = 'opaque';
              case 'empty-next':
                response.logs.clear();
                response.page.nextPageToken = 'next';
              case 'long-message':
                response.logs.first.message = 'x' * 4097;
              case 'timestamp':
                response.logs.first.timestamp.nanos = -1;
              case 'order':
                response.logs.first.timestamp.seconds -= 2;
              case 'too-many':
                response.logs.addAll(
                  List.generate(
                    100,
                    (_) => api.LogEntry.fromBuffer(
                      response.logs.first.writeToBuffer(),
                    ),
                  ),
                );
            }
            return response;
          },
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          minimumRevision: 7,
          checkContext: () {},
        ),
        throwsFormatException,
      );
      expect(calls, 2);
    });
  }

  test(
    'US-07: stale transport error is not retried and context stops paging',
    () async {
      var calls = 0;
      final failure = StateError('synthetic stale snapshot');
      await expectLater(
        readClientRecentLogs(
          (_) async {
            calls++;
            throw failure;
          },
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          minimumRevision: 7,
          checkContext: () {},
        ),
        throwsA(same(failure)),
      );
      expect(calls, 1);
      calls = 0;
      var changed = false;
      await expectLater(
        readClientRecentLogs(
          (_) async {
            calls++;
            changed = true;
            return page(next: 'next');
          },
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          minimumRevision: 7,
          checkContext: () {
            if (changed) throw StateError('context changed');
          },
        ),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );
}
