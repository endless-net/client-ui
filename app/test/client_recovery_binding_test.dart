@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final action in ['lookup', 'browser', 'export', 'ack']) {
    testWidgets('replacement controller revokes pending recovery $action', (
      tester,
    ) async {
      final states = [ClientStateController(), ClientStateController()];
      final events = [
        StreamController<api.WatchEventsResponse>(),
        StreamController<api.WatchEventsResponse>(),
      ];
      for (var i = 0; i < 2; i++) {
        await states[i].attach(events[i].stream);
        events[i].add(fixtures.snapshot(1));
      }
      await tester.pump();
      expect(states[0].cacheEpoch, states[1].cacheEpoch);
      final operation = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'old-operation',
          if (action != 'browser') ...{
            'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
            if (action == 'export')
              'bundle': {'bundleId': 'handle', 'sizeBytes': '32'}
            else
              'change': {'changed': true},
          },
          'requestId': 'old-request',
          'kind': action == 'export'
              ? 'OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE'
              : 'OPERATION_KIND_CONNECT',
          'state': action == 'browser'
              ? 'OPERATION_STATE_WAITING_FOR_USER'
              : 'OPERATION_STATE_SUCCEEDED',
          if (action == 'browser')
            'userAction': {
              'kind': 'KIND_OPEN_BROWSER',
              'browserUrl': 'https://example.test/old',
            },
        }),
      );
      final old = Completer<List<ClientOperation>>();
      final fresh = Completer<List<ClientOperation>>();
      var reads = 0;
      var launches = 0;
      var exports = 0;
      Future<void> render(int index) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientRecoveryPanel(
                state: states[index],
                recover: () {
                  if (index == 1) return fresh.future;
                  reads++;
                  if (reads == 1 && action != 'lookup') {
                    return Future.value([operation]);
                  }
                  return old.future;
                },
                acknowledge: (_) async {
                  await old.future;
                },
                openBrowser: (_) async {
                  launches++;
                  return true;
                },
                exportBundle: (_, check) async {
                  check();
                  exports++;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await render(0);
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pumpAndSettle();
      if (action != 'lookup') {
        final button = find.byKey(ValueKey('$action-old-request'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
      }
      await render(1);
      final refresh = find.byKey(const Key('client-recover'));
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
      expect(find.textContaining('old-operation'), findsNothing);
      await tester.tap(refresh);
      await tester.pump();
      old.complete([operation]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(refresh).onPressed,
        isNull,
        reason: 'Old completion must not clear the new lookup busy state',
      );
      expect(launches, 0);
      expect(exports, 0);
      expect(find.textContaining('old-operation'), findsNothing);
      fresh.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No pending intentions.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (var i = 0; i < 2; i++) {
          await states[i].detach();
          await events[i].close();
          states[i].dispose();
        }
      });
    });
  }
}
