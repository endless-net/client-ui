@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_cleanup_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final forget in [false, true]) {
    for (final outcome in ['unsubmitted', 'accepted', 'error']) {
      testWidgets(
        'cleanup controller replacement forget=$forget outcome=$outcome',
        (tester) async {
          final states = [ClientStateController(), ClientStateController()];
          final streams = [
            StreamController<api.WatchEventsResponse>(),
            StreamController<api.WatchEventsResponse>(),
          ];
          for (var i = 0; i < 2; i++) {
            await states[i].attach(streams[i].stream);
            final event = fixtures.snapshot(1);
            event.snapshot.runtime.capabilities.addAll([
              for (final capability in [
                api.Capability.CAPABILITY_LOGOUT,
                api.Capability.CAPABILITY_LOCAL_FORGET,
              ])
                api.CapabilityStatus(
                  capability: capability,
                  restriction: api.Restriction(
                    availability: api.Availability.AVAILABILITY_AVAILABLE,
                  ),
                ),
            ]);
            streams[i].add(event);
          }
          await tester.pump();
          expect(states[0].cacheEpoch, states[1].cacheEpoch);
          final old = Completer<ClientOperation>();
          final fresh = Completer<ClientOperation>();
          var calls = 0;
          Future<ClientOperation> submit(String profile) {
            expect(profile, 'profile-a');
            return ++calls == 1 && outcome != 'unsubmitted'
                ? old.future
                : fresh.future;
          }

          Future<void> render(int index) => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientCleanupPanel(
                  state: states[index],
                  canElevate: true,
                  logout: submit,
                  forget: submit,
                ),
              ),
            ),
          );
          final action = find.byKey(
            Key(forget ? 'client-local-forget' : 'client-logout'),
          );
          final confirmation = find.byKey(const Key('confirm-client-cleanup'));
          await render(0);
          await tester.tap(action);
          await tester.pump();
          final queued = tester.widget<TextButton>(confirmation).onPressed!;
          if (outcome != 'unsubmitted') {
            await tester.tap(confirmation);
            await tester.pump();
          }
          await render(1);
          await render(0);
          expect(confirmation, findsNothing);
          queued();
          expect(calls, outcome == 'unsubmitted' ? 0 : 1);
          expect(tester.widget<OutlinedButton>(action).onPressed, isNotNull);
          await tester.tap(action);
          await tester.pump();
          await tester.tap(confirmation);
          await tester.pump();
          final operation = ClientOperation.fromProto(
            api.Operation(
              id: 'operation',
              state: api.OperationState.OPERATION_STATE_PENDING,
              kind: forget
                  ? api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT
                  : api.OperationKind.OPERATION_KIND_LOGOUT,
            ),
          );
          if (outcome == 'error') {
            old.completeError(StateError('private old error'));
          } else {
            old.complete(operation);
          }
          await tester.pumpAndSettle();
          expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
          expect(find.textContaining('Cleanup accepted.'), findsNothing);
          expect(
            find.textContaining('Cleanup could not be confirmed.'),
            findsNothing,
          );
          fresh.complete(operation);
          await tester.pumpAndSettle();
          expect(find.textContaining('Cleanup accepted.'), findsOneWidget);
          expect(tester.widget<OutlinedButton>(action).onPressed, isNotNull);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            for (var i = 0; i < 2; i++) {
              await states[i].detach();
              await streams[i].close();
              states[i].dispose();
            }
          });
        },
      );
    }
  }
}
