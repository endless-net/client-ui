import 'dart:async';

import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_connection_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reused by the native integration-test host; no desktop channel is imported.
void main() {
  testWidgets(
    'US-03: recovery acknowledges only terminal results and clears caller context',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      final pending = ClientOperation.fromProto(
        api.Operation(
          id: 'pending',
          requestId: 'request-pending',
          kind: api.OperationKind.OPERATION_KIND_CONNECT,
          state: api.OperationState.OPERATION_STATE_PENDING,
        ),
      );
      final terminal = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'done',
          'requestId': 'request-done',
          'kind': 'OPERATION_KIND_DISCONNECT',
          'state': 'OPERATION_STATE_SUCCEEDED',
          'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
          'change': {'changed': true},
        }),
      );
      var lookups = 0;
      Completer<List<ClientOperation>>? delayedLookup;
      final acknowledgements = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientRecoveryPanel(
              state: state,
              recover: () async {
                lookups++;
                if (delayedLookup != null) return delayedLookup.future;
                return [pending, terminal];
              },
              acknowledge: (op) async {
                acknowledgements.add(op.value.requestId);
              },
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'recovery-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'recovery-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'recovery-test', 'revision': '1'},
            },
          },
        });
      source.add(snapshot);
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(lookups, 1);
      expect(find.text('Still pending'), findsOneWidget);
      expect(find.byKey(const Key('ack-request-pending')), findsNothing);
      await tester.tap(find.byKey(const Key('ack-request-done')));
      await tester.pump();
      expect(acknowledgements, ['request-done']);
      expect(find.byKey(const Key('ack-request-done')), findsNothing);
      delayedLookup = Completer<List<ClientOperation>>();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(lookups, 2);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      source.add(snapshot);
      await tester.pump();
      delayedLookup.complete([pending, terminal]);
      await tester.pump();
      expect(find.byKey(const Key('ack-request-done')), findsNothing);
      expect(acknowledgements, ['request-done']);
      expect(find.text('Still pending'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('client-recover')))
            .onPressed,
        isNull,
      );
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'US-01/03: typed snapshot reaches widgets and stream loss clears it',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      final connectResult = Completer<ClientOperation>();
      var connectCalls = 0;
      var disconnectCalls = 0;
      var renewalCalls = 0;
      await state.attach(source.stream);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientConnectionPanel(
              state: state,
              renewSession: () async {
                renewalCalls++;
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'renew-operation',
                    kind: api.OperationKind.OPERATION_KIND_RENEW_SESSION,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
              connect: () {
                connectCalls++;
                return connectResult.future;
              },
              disconnect: () async {
                disconnectCalls++;
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'disconnect-op',
                    kind: api.OperationKind.OPERATION_KIND_DISCONNECT,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Waiting for runtime snapshot…'), findsOneWidget);
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'native-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'native-test',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_CONNECTION',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'metadata': {'instanceId': 'native-test', 'revision': '1'},
              'activeProfileId': 'synthetic-profile',
              'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
            },
          },
        });
      source.add(snapshot);
      await tester.pump();
      expect(find.text('Profile: synthetic-profile'), findsOneWidget);
      expect(find.text('Session expiry: Unknown'), findsOneWidget);
      expect(find.text('Credential expiry: Unknown'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('client-renew-session')),
            )
            .onPressed,
        isNull,
      );
      // US-09: the two clocks are independent and never synthesize connection
      // state. This same widget suite runs in Android/iOS native test hosts.
      snapshot.sequence += 1;
      snapshot.snapshot.status.ensureSession().mergeFromProto3Json({
        'expiresAt': '2030-01-01T00:00:00Z',
        'renewal': {'availability': 'AVAILABILITY_AVAILABLE'},
      });
      snapshot.snapshot.runtime.capabilities.add(
        api.CapabilityStatus()..mergeFromProto3Json({
          'capability': 'CAPABILITY_SESSION_RENEWAL',
          'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
        }),
      );
      snapshot.snapshot.status.ensureCredential().mergeFromProto3Json({
        'expiresAt': '2031-02-03T04:05:06Z',
      });
      source.add(snapshot);
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-renew-session')));
      await tester.pump();
      expect(renewalCalls, 1);
      snapshot.sequence += 1;
      snapshot.snapshot.status.session.state =
          api.SessionState.SESSION_STATE_RENEWING;
      source.add(snapshot);
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('client-renew-session')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Session expiry: 2030-01-01T00:00:00.000Z'),
        findsOneWidget,
      );
      expect(
        find.text('Credential expiry: 2031-02-03T04:05:06.000Z'),
        findsOneWidget,
      );
      snapshot.sequence += 1;
      snapshot.snapshot.status.session.clearExpiresAt();
      source.add(snapshot);
      await tester.pump();
      expect(find.text('Session expiry: Unknown'), findsOneWidget);
      expect(
        find.text('Credential expiry: 2031-02-03T04:05:06.000Z'),
        findsOneWidget,
      );
      expect(
        state.snapshot!.status.connectionPhase,
        api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
      );
      await tester.tap(find.byKey(const Key('client-connect')));
      await tester.pump();
      expect(connectCalls, 1);
      // Pending Connect must not prevent an explicit Disconnect.
      await tester.tap(find.byKey(const Key('client-disconnect')));
      await tester.pump();
      expect(disconnectCalls, 1);
      connectResult.complete(
        ClientOperation.fromProto(
          api.Operation(
            id: 'connect-op',
            kind: api.OperationKind.OPERATION_KIND_CONNECT,
            state: api.OperationState.OPERATION_STATE_PENDING,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
      snapshot.sequence += 1;
      snapshot.metadata.revision += 1;
      snapshot.snapshot.status.metadata.revision += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      snapshot.snapshot.status.clearActiveProfileId();
      snapshot.snapshot.status.clearSession();
      snapshot.snapshot.status.clearCredential();
      source.add(snapshot);
      await tester.pump();
      expect(find.text('Profile: synthetic-profile'), findsNothing);
      expect(find.byKey(const Key('client-session-expiry')), findsNothing);
      expect(find.byKey(const Key('client-credential-expiry')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('client-renew-session')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('client-connect')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('client-disconnect')))
            .onPressed,
        isNull,
      );
      expect(
        find.text('Command accepted. Waiting for the runtime result.'),
        findsNothing,
      );
      await source.close();
      await tester.pump();
      expect(find.text('Profile: synthetic-profile'), findsNothing);
      expect(find.text('Runtime unavailable'), findsOneWidget);
      expect(state.link, ClientLinkState.unavailable);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
