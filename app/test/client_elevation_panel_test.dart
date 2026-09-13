@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_cleanup_panel.dart';
import 'package:endlessnet/client_identity_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'owner identity elevation requires confirmation and a fresh announcement',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var loads = 0;
      var trusts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientIdentityPanel(
              state: state,
              canElevate: true,
              load: () async {
                loads++;
                return api.GetServerIdentityResponse()..mergeFromProto3Json({
                  'metadata': {'instanceId': 'runtime', 'revision': '1'},
                  'identity': {
                    'profileId': 'profile',
                    'controlOrigin': 'https://control.test',
                    'trustedKeyId': 'old',
                    'announcedKeyId': 'new',
                    'announcementId': 'a' * 64,
                    'changed': true,
                  },
                });
              },
              trust: (identity) async {
                trusts++;
                expect(identity.announcementId, 'a' * 64);
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'operation',
                    kind:
                        api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_IDENTITY_RECOVERY',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile',
              'metadata': {'instanceId': 'runtime', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('load-client-identity')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('trust-client-identity')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('compare-client-identity')));
      await tester.pump();
      expect(trusts, 0);
      await tester.tap(find.byKey(const Key('trust-client-identity')));
      await tester.pump();
      expect(loads, 2);
      expect(trusts, 1);
      await events.close();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  for (final access in ['OWNER', 'OBSERVER']) {
    testWidgets('cleanup elevation requires explicit $access confirmation', (
      tester,
    ) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientCleanupPanel(
              state: state,
              canElevate: true,
              logout: (_) async => throw StateError('No fallback'),
              forget: (id) async {
                calls++;
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'operation',
                    kind: api
                        .OperationKind
                        .OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime',
              'callerAccess': 'ACCESS_$access',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_LOCAL_FORGET',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile',
              'metadata': {'instanceId': 'runtime', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('client-local-forget')),
      );
      if (access == 'OBSERVER') {
        expect(button.onPressed, isNull);
      } else {
        await tester.tap(find.byKey(const Key('client-local-forget')));
        await tester.pump();
        expect(calls, 0);
        expect(
          find.text(
            'Confirmation will open the system administrator approval prompt.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('confirm-client-cleanup')));
        await tester.pump();
        expect(calls, 1);
      }
      await events.close();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
}
