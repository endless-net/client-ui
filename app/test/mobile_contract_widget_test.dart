import 'dart:async';

import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_connection_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_operation_details.dart';
import 'package:endlessnet/client_enrollment_panel.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reused by the native integration-test host; no desktop channel is imported.
void main() {
  testWidgets(
    'US-02: enrollment requires capability and clears token before sending',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      final calls = <(String, api.EnrollmentMode, String, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientEnrollmentPanel(
              state: state,
              enroll: (id, mode, hostname, token) async {
                calls.add((id, mode, hostname, token));
                throw StateError('must-not-display-token: $token');
              },
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'enrollment-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'enrollment-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'enrollment-test', 'revision': '1'},
            },
          },
        });
      source.add(snapshot);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('enroll-hostname')))
            .enabled,
        isFalse,
      );
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.capabilities.add(
        api.CapabilityStatus()..mergeFromProto3Json({
          'capability': 'CAPABILITY_ENROLLMENT',
          'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
        }),
      );
      source.add(snapshot);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('enroll-hostname')),
        'device-a',
      );
      await tester.pump();
      expect(
        state.snapshot!.supports(api.Capability.CAPABILITY_ENROLLMENT),
        isTrue,
      );
      expect(state.snapshot!.status.activeProfileId, 'profile-a');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('enroll-submit')));
      await tester.pump();
      expect(calls.single.$4, isNull);
      expect(calls.single.$1, 'profile-a');
      await tester.tap(find.byKey(const Key('enroll-use-token')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('enroll-token')),
        'synthetic-test-token',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('enroll-token')))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('enroll-submit')));
      await tester.pump();
      expect(calls.last.$4, 'synthetic-test-token');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('enroll-token')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('must-not-display-token'), findsNothing);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      snapshot.snapshot.status.clearActiveProfileId();
      source.add(snapshot);
      await tester.pump();
      expect(find.byKey(const Key('enroll-token')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
            .onPressed,
        isNull,
      );
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'US-02/03: browser action is refreshed, explicit and never completes operation',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      var url = 'https://example.test/old';
      var expired = false;
      var lookups = 0;
      final launched = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientRecoveryPanel(
              state: state,
              recover: () async {
                lookups++;
                return [
                  ClientOperation.fromProto(
                    api.Operation()..mergeFromProto3Json({
                      'id': 'browser',
                      'requestId': 'browser-request',
                      'kind': 'OPERATION_KIND_ENROLL',
                      'state': 'OPERATION_STATE_WAITING_FOR_USER',
                      'userAction': {
                        'kind': 'KIND_OPEN_BROWSER',
                        'browserUrl': url,
                        if (expired) 'expiresAt': '2000-01-01T00:00:00Z',
                      },
                    }),
                  ),
                ];
              },
              acknowledge: (_) async =>
                  fail('Browser launch must not acknowledge'),
              openBrowser: (uri) async {
                launched.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      source.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'browser-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'browser-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'browser-test', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(launched, isEmpty);
      url = 'https://example.test/new';
      await tester.tap(find.byKey(const Key('browser-browser-request')));
      await tester.pump();
      expect(lookups, 2);
      expect(launched, [Uri.parse(url)]);
      expect(
        find.text(
          'Browser opened. The operation is still pending; recover its result.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ack-browser-request')), findsNothing);
      for (final rejected in [
        'file:///tmp/token',
        'https://user@example.test/token',
      ]) {
        url = rejected;
        await tester.tap(find.byKey(const Key('browser-browser-request')));
        await tester.pump();
        expect(launched, hasLength(1));
        expect(find.textContaining(rejected), findsNothing);
      }
      url = 'https://example.test/expired';
      expired = true;
      await tester.tap(find.byKey(const Key('browser-browser-request')));
      await tester.pump();
      expect(launched, hasLength(1));
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'US-03/08: typed cleanup and failure keep remote and local outcomes distinct',
    (tester) async {
      for (final outcome in [
        'REMOTE_CONFIRMED',
        'REMOTE_UNCONFIRMED',
        'NOT_REGISTERED',
      ]) {
        final operation = ClientOperation.fromProto(
          api.Operation()..mergeFromProto3Json({
            'id': 'cleanup',
            'kind': 'OPERATION_KIND_FORGET_LOCAL_ENROLLMENT',
            'state': 'OPERATION_STATE_SUCCEEDED',
            'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
            'cleanup': {
              'outcome': 'CLEANUP_OUTCOME_$outcome',
              'localRegistrationRemoved': true,
              'controlRequestId': 'cleanup-correlation',
            },
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ClientOperationDetails(operation: operation)),
          ),
        );
        expect(find.text('Local registration removed.'), findsOneWidget);
        expect(
          find.text('Control request: cleanup-correlation'),
          findsOneWidget,
        );
        expect(
          find.text('Remote cleanup confirmed.'),
          outcome == 'REMOTE_CONFIRMED' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Remote cleanup NOT confirmed.'),
          outcome == 'REMOTE_UNCONFIRMED' ? findsOneWidget : findsNothing,
        );
      }
      final failure = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'failed',
          'kind': 'OPERATION_KIND_LOGOUT',
          'state': 'OPERATION_STATE_FAILED',
          'failure': {
            'code': 'ERROR_CODE_REMOTE_CLEANUP_REQUIRED',
            'reasonKey': 'do-not-render-raw-reason',
            'controlRequestId': 'failure-correlation',
          },
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ClientOperationDetails(operation: failure)),
        ),
      );
      expect(
        find.text('Failure: ERROR_CODE_REMOTE_CLEANUP_REQUIRED'),
        findsOneWidget,
      );
      expect(find.text('Control request: failure-correlation'), findsOneWidget);
      expect(find.text('do-not-render-raw-reason'), findsNothing);
      expect(find.text('Remote cleanup confirmed.'), findsNothing);
      final waiting = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'waiting',
          'kind': 'OPERATION_KIND_ENROLL',
          'state': 'OPERATION_STATE_WAITING_FOR_USER',
          'userAction': {
            'kind': 'KIND_OPEN_BROWSER',
            'browserUrl': 'https://example.test/sensitive-token',
          },
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ClientOperationDetails(operation: waiting)),
        ),
      );
      expect(find.text('Required action: KIND_OPEN_BROWSER'), findsOneWidget);
      expect(find.textContaining('sensitive-token'), findsNothing);
    },
  );
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
