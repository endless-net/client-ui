@Tags(['short'])
library;

import 'dart:async';

import 'package:endlessnet/client_connection_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Deliberately retain a callback to simulate queued activation from an older
// frame. This does not replace platform keyboard/hit-test acceptance.
void main() {
  testWidgets('US-03 displays typed status guidance without sensitive payload', (
    tester,
  ) async {
    final state = ClientStateController();
    final source = StreamController<api.WatchEventsResponse>();
    await state.attach(source.stream);
    var calls = 0;
    Future<ClientOperation> unexpected() async {
      calls++;
      throw StateError('Presentation must not submit');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ClientConnectionPanel(
              state: state,
              connect: unexpected,
              disconnect: unexpected,
              renewSession: unexpected,
            ),
          ),
        ),
      ),
    );
    final event = _snapshot();
    event.snapshot.status.mergeFromProto3Json({
      'serviceState': 'SERVICE_STATE_RECOVERY_BLOCKED',
      'pendingAction': {
        'kind': 'KIND_OPEN_BROWSER',
        'browserUrl': 'https://example.test/private-token',
      },
      'recovery': {
        'failure': {
          'code': 'ERROR_CODE_PERMISSION_REQUIRED',
          'actionOwner': 'ACTION_OWNER_DEVICE_ADMINISTRATOR',
          'reasonKey': 'private-recovery-reason',
        },
      },
      'failures': [
        {
          'code': 'ERROR_CODE_POLICY_BLOCKED',
          'actionOwner': 'ACTION_OWNER_ACCESS_ADMINISTRATOR',
          'reasonKey': 'private-policy-reason',
        },
      ],
    });
    source.add(event);
    await tester.pump();
    expect(
      find.text('Required action: Continue in your browser'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Recovery: Permission required. Action owner: Device administrator.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Runtime issue: Blocked by policy. Action owner: Access administrator.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private-'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    expect(calls, 0);
    final replacement = _snapshot();
    replacement.sequence *= 2;
    replacement.metadata.revision = replacement.sequence;
    replacement.snapshot.status.metadata.revision = replacement.sequence;
    source.add(replacement);
    await tester.pump();
    expect(
      find.byKey(const Key('client-status-required-action')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('client-status-recovery-failure')),
      findsNothing,
    );
    expect(find.textContaining('Runtime issue:'), findsNothing);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await state.detach();
      await source.close();
      state.dispose();
    });
  });

  testWidgets('US-09 displays independent authoritative renewal states', (
    tester,
  ) async {
    final state = ClientStateController();
    final source = StreamController<api.WatchEventsResponse>();
    await state.attach(source.stream);
    var mutationCalls = 0;
    Future<ClientOperation> unexpectedMutation() async {
      mutationCalls++;
      throw StateError('Rendering must not submit a mutation');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientConnectionPanel(
            state: state,
            connect: unexpectedMutation,
            disconnect: unexpectedMutation,
            renewSession: unexpectedMutation,
          ),
        ),
      ),
    );
    const sessionLabels = [
      'Unknown',
      'Not authenticated',
      'Active',
      'Expiring',
      'Expired',
      'Renewing',
    ];
    const credentialLabels = [
      'Unknown',
      'Absent',
      'Valid',
      'Expiring',
      'Expired',
      'Renewing',
      'Blocked',
    ];
    const renewalLabels = [
      'Unknown',
      'Available — choose Renew session',
      'Not supported',
      'Blocked by policy',
      'Permission required',
      'Temporarily unavailable',
    ];
    var sequence = 0;
    for (var session = 0; session < sessionLabels.length; session++) {
      for (
        var credential = 0;
        credential < credentialLabels.length;
        credential++
      ) {
        final event = _snapshot();
        sequence++;
        event.sequence = event.sequence * sequence;
        event.metadata.revision = event.sequence;
        event.snapshot.status.metadata.revision = event.sequence;
        event.snapshot.status.session.state = api.SessionState.valueOf(
          session,
        )!;
        event.snapshot.status.ensureCredential().state =
            api.CredentialState.valueOf(credential)!;
        event.snapshot.status.session.renewal.availability =
            api.Availability.valueOf(credential % renewalLabels.length)!;
        if (credential == 6) {
          event.snapshot.runtime.capabilities.clear();
        }
        if (credential != 0) {
          event.snapshot.status.session.mergeFromProto3Json({
            'warningAt': '2000-01-01T00:00:00Z',
          });
          event.snapshot.status.credential.mergeFromProto3Json({
            'warningAt': '2031-02-03T04:05:06Z',
          });
        }
        source.add(event);
        await tester.pump();
        expect(state.link, ClientLinkState.ready);
        expect(
          find.text('Session state: ${sessionLabels[session]}'),
          findsOneWidget,
        );
        expect(
          find.text('Credential state: ${credentialLabels[credential]}'),
          findsOneWidget,
        );
        expect(find.text('Session expiry: Unknown'), findsOneWidget);
        expect(find.text('Credential expiry: Unknown'), findsOneWidget);
        expect(
          find.text(
            'Session warning: ${credential == 0 ? 'Unknown' : '2000-01-01T00:00:00.000Z'}',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Credential warning: ${credential == 0 ? 'Unknown' : '2031-02-03T04:05:06.000Z'}',
          ),
          findsOneWidget,
        );
        final renewal = credential == 6
            ? 'Unavailable on this runtime'
            : session == 5
            ? 'In progress'
            : renewalLabels[credential];
        expect(find.text('Session renewal: $renewal'), findsOneWidget);
        expect(
          tester
                  .widget<OutlinedButton>(
                    find.byKey(const Key('client-renew-session')),
                  )
                  .onPressed !=
              null,
          credential == 1 && session != 5,
        );
      }
    }
    expect(mutationCalls, 0);
    await tester.runAsync(state.detach);
    await tester.pump();
    expect(find.byKey(const Key('client-session-state')), findsNothing);
    expect(find.byKey(const Key('client-credential-state')), findsNothing);
    expect(find.byKey(const Key('client-session-warning')), findsNothing);
    expect(find.byKey(const Key('client-credential-warning')), findsNothing);
    expect(
      find.byKey(const Key('client-session-renewal-status')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(source.close);
    state.dispose();
  });
  for (final action in ['connect', 'disconnect', 'renew-session']) {
    for (final change in [
      'profile',
      'observer',
      'capability',
      'status',
      'session',
      'detach',
      'dispose',
      'duplicate',
    ]) {
      testWidgets('US-03/09 queued $action rejects $change replacement', (
        tester,
      ) async {
        final state = ClientStateController();
        final source = StreamController<api.WatchEventsResponse>();
        await state.attach(source.stream);
        final pending = Completer<ClientOperation>();
        var calls = 0;
        Future<ClientOperation> submit() {
          calls++;
          return pending.future;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientConnectionPanel(
                state: state,
                connect: submit,
                disconnect: submit,
                renewSession: submit,
              ),
            ),
          ),
        );
        final snapshot = _snapshot();
        source.add(snapshot);
        await tester.pump();
        expect(state.link, ClientLinkState.ready);
        final queued = tester
            .widget<ButtonStyleButton>(find.byKey(Key('client-$action')))
            .onPressed!;

        if (change == 'duplicate') {
          queued();
          queued();
          expect(calls, 1);
        } else {
          if (change == 'detach') {
            await tester.runAsync(state.detach);
          } else if (change == 'dispose') {
            await tester.pumpWidget(const SizedBox());
          } else {
            final replacement = api.WatchEventsResponse.fromBuffer(
              snapshot.writeToBuffer(),
            );
            replacement.sequence += 1;
            replacement.metadata.revision += 1;
            replacement.snapshot.status.metadata.revision += 1;
            switch (change) {
              case 'profile':
                replacement.snapshot.status.activeProfileId = 'profile-b';
              case 'observer':
                replacement.snapshot.runtime.callerAccess =
                    api.Access.ACCESS_OBSERVER;
                replacement.snapshot.status.clearActiveProfileId();
                replacement.snapshot.status.clearSession();
              case 'capability':
                replacement.snapshot.runtime.capabilities.clear();
              case 'status':
                final status = replacement.snapshot.status;
                status.connectionPhase =
                    api.ConnectionPhase.CONNECTION_PHASE_CONNECTING;
                replacement.clearSnapshot();
                replacement.statusChanged = status;
              case 'session':
                replacement.clearSnapshot();
                replacement.ensureSessionChanged().state =
                    api.SessionState.SESSION_STATE_RENEWING;
            }
            source.add(replacement);
            await tester.pump();
            expect(state.link, ClientLinkState.ready);
          }
          queued();
          expect(calls, 0);
        }
        pending.complete(
          ClientOperation.fromProto(
            api.Operation(
              id: 'synthetic-operation',
              kind: api.OperationKind.OPERATION_KIND_CONNECT,
              state: api.OperationState.OPERATION_STATE_PENDING,
            ),
          ),
        );
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await state.detach();
          await source.close();
          state.dispose();
        });
        expect(tester.takeException(), isNull);
      }, timeout: const Timeout(Duration(seconds: 20)));
    }
  }
}

api.WatchEventsResponse _snapshot() =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '1',
      'metadata': {'instanceId': 'activation-test', 'revision': '1'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'activation-test',
          'callerAccess': 'ACCESS_OWNER',
          'capabilities': [
            for (final capability in [
              'CAPABILITY_CONNECTION',
              'CAPABILITY_SESSION_RENEWAL',
            ])
              {
                'capability': capability,
                'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
              },
          ],
        },
        'status': {
          'metadata': {'instanceId': 'activation-test', 'revision': '1'},
          'activeProfileId': 'profile-a',
          'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
          'session': {
            'state': 'SESSION_STATE_ACTIVE',
            'renewal': {'availability': 'AVAILABILITY_AVAILABLE'},
          },
        },
      },
    });
