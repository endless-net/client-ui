@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_create_profile_panel.dart';
import 'package:endlessnet/client_enrollment_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final enroll in [true, false]) {
    for (final fail in [true, false]) {
      testWidgets('keyed form replacement enrollment=$enroll oldError=$fail', (
        tester,
      ) async {
        final states = [ClientStateController(), ClientStateController()];
        final streams = [
          StreamController<api.WatchEventsResponse>(),
          StreamController<api.WatchEventsResponse>(),
        ];
        for (var i = 0; i < 2; i++) {
          await states[i].attach(streams[i].stream);
          final event = fixtures.snapshot(1);
          event.snapshot.runtime.capabilities.add(
            api.CapabilityStatus(
              capability: api.Capability.CAPABILITY_ENROLLMENT,
              restriction: api.Restriction(
                availability: api.Availability.AVAILABILITY_AVAILABLE,
              ),
            ),
          );
          streams[i].add(event);
        }
        await tester.pump();
        final old = Completer<ClientOperation>();
        final fresh = Completer<ClientOperation>();
        var calls = 0;
        Future<ClientOperation> submit() =>
            ++calls == 1 ? old.future : fresh.future;
        Future<void> render(int index) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: enroll
                    ? ClientEnrollmentPanel(
                        state: states[index],
                        enroll: (_, _, _, token) {
                          expect(token, calls == 0 ? 'fixture-secret' : null);
                          return submit();
                        },
                      )
                    : ClientCreateProfilePanel(
                        state: states[index],
                        create: (_, _) => submit(),
                      ),
              ),
            ),
          ),
        );
        final name = find.byKey(
          Key(enroll ? 'enroll-hostname' : 'create-profile-name'),
        );
        final button = find.byKey(
          Key(enroll ? 'enroll-submit' : 'create-profile-submit'),
        );
        Future<void> fill(String value) async {
          await tester.enterText(name, value);
          if (!enroll) {
            await tester.enterText(
              find.byKey(const Key('create-profile-origin')),
              'https://control.example',
            );
          }
          await tester.pumpAndSettle();
        }

        await render(0);
        await fill('old-name');
        if (enroll) {
          await tester.tap(find.byKey(const Key('enroll-use-token')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('enroll-token')),
            'fixture-secret',
          );
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(calls, 1);
        await render(1);
        await render(0);
        expect(tester.widget<TextField>(name).controller!.text, isEmpty);
        expect(find.byKey(const Key('enroll-token')), findsNothing);
        await fill('fresh-name');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(calls, 2);
        final result = ClientOperation.fromProto(
          api.Operation(
            id: 'operation',
            state: api.OperationState.OPERATION_STATE_PENDING,
            kind: enroll
                ? api.OperationKind.OPERATION_KIND_ENROLL
                : api.OperationKind.OPERATION_KIND_CREATE_PROFILE,
          ),
        );
        if (fail) {
          old.completeError(StateError('private old failure'));
        } else {
          old.complete(result);
        }
        await tester.pumpAndSettle();
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
        expect(tester.widget<TextField>(name).controller!.text, 'fresh-name');
        expect(find.textContaining('accepted.'), findsNothing);
        expect(find.textContaining('could not be confirmed'), findsNothing);
        fresh.complete(result);
        await tester.pumpAndSettle();
        expect(find.textContaining('accepted.'), findsOneWidget);
        expect(find.textContaining('fixture-secret'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          for (var i = 0; i < 2; i++) {
            await states[i].detach();
            await streams[i].close();
            states[i].dispose();
          }
        });
      });
    }
  }
}
