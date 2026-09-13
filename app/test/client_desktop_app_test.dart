import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;
import 'client_privileged_session_test.dart' show ImmediateResponse;

class QuitClient extends fixtures.NoCallsClient {
  final requests = <api.NotifyLifecycleRequest>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #notifyLifecycle) {
      return super.noSuchMethod(invocation);
    }
    final request =
        invocation.positionalArguments.single as api.NotifyLifecycleRequest;
    requests.add(
      api.NotifyLifecycleRequest.fromBuffer(request.writeToBuffer()),
    );
    return ImmediateResponse<api.NotifyLifecycleResponse>(
      api.NotifyLifecycleResponse(
        operation: api.Operation(
          id: 'quit-operation',
          requestId: request.mutation.requestId,
          kind: api.OperationKind.OPERATION_KIND_NOTIFY_LIFECYCLE,
          state: api.OperationState.OPERATION_STATE_PENDING,
        ),
      ),
    );
  }
}

void main() {
  for (final observer in [false, true]) {
    testWidgets(
      'US-12: explicit quit ${observer ? 'observer sends no mutation' : 'owner journals UI_QUIT once'}',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('en-quit-'),
        ))!;
        final client = QuitClient();
        final connection = fixtures.FakeConnection()
          ..mutations = ClientMutations(client, instanceId: 'runtime-a');
        final journal = ClientIntentJournal(directory);
        final session = ClientSession(
          journal: journal,
          open: () async => connection,
        );
        var exits = 0;
        await tester.pumpWidget(
          ClientDesktopApp(
            session: session,
            desktopIntegration: false,
            onExit: () async {
              exits++;
            },
          ),
        );
        await tester.pump();
        final snapshot = fixtures.snapshot();
        snapshot.snapshot.status.activeProfileId = 'profile-a';
        if (observer) {
          snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
        }
        connection.events.add(snapshot);
        await tester.pump();
        expect(
          client.requests,
          isEmpty,
        ); // Launch is not quit or runtime start.
        final quit = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Quit'))
            .onPressed!;
        await tester.runAsync(() async {
          await (quit as Future<void> Function())().timeout(
            const Duration(seconds: 5),
          );
        });
        await tester.pump();
        expect(exits, 1);
        expect(connection.closed, isTrue);
        final intents = (await tester.runAsync(journal.pending))!;
        if (observer) {
          expect(client.requests, isEmpty);
          expect(intents, isEmpty);
        } else {
          final request = client.requests.single;
          expect(request.event, api.LifecycleEvent.LIFECYCLE_EVENT_UI_QUIT);
          expect(
            request.profile.profileId,
            snapshot.snapshot.status.activeProfileId,
          );
          expect(request.mutation.expectedInstanceId, 'runtime-a');
          expect(
            request.mutation.expectedRevision,
            snapshot.snapshot.status.metadata.revision,
          );
          expect(intents.single.requestId, request.mutation.requestId);
          expect(
            intents.single.kind,
            api.OperationKind.OPERATION_KIND_NOTIFY_LIFECYCLE,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(session.close);
        await tester.runAsync(() => directory.delete(recursive: true));
      },
    );
  }
  testWidgets('desktop entrypoint waits for a native snapshot', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('en-desktop-'),
    ))!;
    final connection = fixtures.FakeConnection();
    final session = ClientSession(
      journal: ClientIntentJournal(directory),
      open: () async => connection,
    );
    await tester.pumpWidget(
      ClientDesktopApp(session: session, desktopIntegration: false),
    );
    await tester.pump();
    expect(find.byType(ClientSessionPanel), findsOneWidget);
    expect(find.text('Runtime: awaitingSnapshot'), findsOneWidget);
    connection.events.add(fixtures.snapshot());
    await tester.pump();
    expect(find.text('Runtime: ready'), findsOneWidget);
    await connection.events.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(session.close);
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  testWidgets('desktop runtime failure stays native and sanitizes details', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('en-desktop-'),
    ))!;
    var attempts = 0;
    final session = ClientSession(
      journal: ClientIntentJournal(directory),
      open: () async {
        attempts++;
        throw StateError('private endpoint diagnostic');
      },
    );
    await tester.pumpWidget(
      ClientDesktopApp(session: session, desktopIntegration: false),
    );
    await tester.pump();
    expect(find.textContaining('No fallback was used'), findsOneWidget);
    expect(find.textContaining('private endpoint'), findsNothing);
    expect(attempts, 1);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Reconnect runtime'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.runAsync(() async {
      final reconnect = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Reconnect runtime'),
          )
          .onPressed!;
      await (reconnect as Future<void> Function())();
    });
    await tester.pump();
    expect(attempts, 2);
    await tester.tap(find.text('Quit'));
    await tester.pumpAndSettle();
    expect(
      find.text('Exit without confirmed runtime notification?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientSessionPanel), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(session.close);
    await tester.runAsync(() => directory.delete(recursive: true));
  });
}
