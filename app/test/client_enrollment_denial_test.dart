@Tags(['short'])
library;

import 'dart:async';

import 'package:endlessnet/client_enrollment_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';

void main() {
  for (final access in ['ACCESS_OWNER', 'ACCESS_OBSERVER']) {
    testWidgets('native enrollment $access never elevates or replays denial', (
      tester,
    ) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var submissions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientEnrollmentPanel(
              state: state,
              enroll: (profile, mode, hostname, token) async {
                submissions++;
                expect(profile, 'profile-a');
                expect(hostname, 'test-device');
                expect(token, 'synthetic-enrollment-token');
                expect(
                  tester
                      .widget<TextField>(find.byKey(const Key('enroll-token')))
                      .controller!
                      .text,
                  isEmpty,
                );
                throw GrpcError.permissionDenied('private server diagnostic');
              },
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': access,
              'capabilities': [
                {
                  'capability': 'CAPABILITY_ENROLLMENT',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      if (access == 'ACCESS_OWNER') {
        await tester.enterText(
          find.byKey(const Key('enroll-hostname')),
          'test-device',
        );
        // Use the freshly rendered input context, not the callback from before editing.
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('enroll-use-token')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('enroll-token')),
          'synthetic-enrollment-token',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('enroll-submit')));
        await tester.pumpAndSettle();
        expect(submissions, 1);
        expect(
          find.textContaining('Recover the intention before retrying'),
          findsOneWidget,
        );
        expect(find.textContaining('private server diagnostic'), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
              .onPressed,
          isNull,
        );
        await tester.pump(const Duration(seconds: 30));
        expect(submissions, 1);
      } else {
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('enroll-hostname')))
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
              .onPressed,
          isNull,
        );
        expect(submissions, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await state.detach();
        await events.close();
      });
      state.dispose();
    });
  }
}
