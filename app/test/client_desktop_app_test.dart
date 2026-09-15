@Tags(['short'])
library;

import 'dart:io';
import 'dart:async';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
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
  for (final failure in [
    'none',
    'setIcon',
    'setContextMenu',
    'hide',
    'hostAbsent',
    'hostLost',
    'hostLostWhileHiding',
    'restore',
    'restoreRace',
    'restoreCleanupFailure',
  ]) {
    testWidgets('window close follows tray readiness: $failure', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-close-'),
      ))!;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final windowCalls = <String>[];
      final trayCalls = <String>[];
      const screens = MethodChannel('dev.leanflutter.plugins/screen_retriever');
      final display = {
        'id': 'test',
        'size': {'width': 1920.0, 'height': 1080.0},
        'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      };
      messenger.setMockMethodCallHandler(
        screens,
        (call) async => switch (call.method) {
          'getPrimaryDisplay' => display,
          'getAllDisplays' => {
            'displays': [display],
          },
          'getCursorScreenPoint' => {'dx': 0.0, 'dy': 0.0},
          _ => null,
        },
      );
      var closeRequested = false;
      final hiding = Completer<void>();
      var hostAvailable = failure != 'hostAbsent';
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
        call,
      ) async {
        trayCalls.add(call.method);
        if (failure == 'restoreRace' &&
            call.method == 'setIcon' &&
            trayCalls.where((c) => c == 'setIcon').length == 2) {
          hostAvailable = false;
        }
        if (call.method == failure ||
            (call.method == 'destroy' &&
                (closeRequested ||
                    (failure != 'restore' && failure != 'restoreRace')))) {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          windowCalls.add(call.method);
          if (call.method == 'hide' &&
              closeRequested &&
              failure == 'hostLostWhileHiding') {
            await hiding.future;
          }
          if (call.method == 'hide' && failure == 'hide' && closeRequested) {
            throw PlatformException(code: 'unavailable');
          }
          if (call.method == 'getBounds') {
            return {'x': 0.0, 'y': 0.0, 'width': 760.0, 'height': 560.0};
          }
          if (call.method.startsWith('is')) return false;
          return null;
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(screens, null);
        messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
      });
      final connection = fixtures.FakeConnection();
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => connection,
      );
      var exits = 0;
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          showWindow: false,
          readTrayAvailability: () async => hostAvailable,
          prepareTrayRegistration: () async => true,
          onExit: () async {
            exits++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 100 && session.state.link.name != 'awaitingSnapshot';
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(session.state.link.name, 'awaitingSnapshot');
      final snapshot = fixtures.snapshot();
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(snapshot);
      await tester.pumpAndSettle();
      if (failure == 'setIcon' ||
          failure == 'setContextMenu' ||
          failure == 'hostAbsent') {
        expect(windowCalls, contains('show'));
        expect(windowCalls, isNot(contains('hide')));
      }
      windowCalls.clear();
      if (failure.startsWith('restore')) {
        hostAvailable = false;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(windowCalls, contains('show'));
        hostAvailable = true;
        await tester.tap(find.byKey(const Key('client-restore-tray')));
        await tester.pumpAndSettle();
        expect(
          trayCalls.where((c) => c == 'setIcon').length,
          failure == 'restoreCleanupFailure' ? 1 : 2,
        );
        expect(trayCalls.where((c) => c == 'destroy').length, 1);
        if (failure != 'restoreCleanupFailure') {
          expect(
            trayCalls.indexOf('destroy'),
            lessThan(trayCalls.lastIndexOf('setIcon')),
          );
        }
        expect(windowCalls, isNot(contains('hide')));
        expect(
          find.byKey(const Key('client-restore-tray')),
          failure == 'restore' ? findsNothing : findsOneWidget,
        );
        expect(exits, 0);
        windowCalls.clear();
      }
      if (failure == 'hostLost') {
        hostAvailable = false;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(windowCalls, contains('show'));
        expect(windowCalls, isNot(contains('hide')));
        windowCalls.clear();
      }
      closeRequested = true;
      final listener =
          tester.state(find.byType(ClientDesktopApp)) as WindowListener;
      if (failure == 'hostLostWhileHiding') {
        listener.onWindowClose();
        await tester.pump();
        expect(windowCalls, contains('hide'));
        hostAvailable = false;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(windowCalls.where((c) => c == 'show').length, 1);
        hiding.complete();
        await tester.pumpAndSettle();
        expect(windowCalls.where((c) => c == 'show').length, 2);
      } else {
        await tester.runAsync(() async {
          listener.onWindowClose();
          for (var i = 0; i < 50 && failure != 'none' && exits == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
      }
      await tester.pumpAndSettle();
      if (failure == 'none' ||
          failure == 'hostLostWhileHiding' ||
          failure == 'restore') {
        expect(windowCalls, contains('hide'));
        expect(exits, 0);
        expect(connection.closed, isFalse);
      } else {
        expect(exits, 1);
        expect(connection.closed, isTrue);
        expect(windowCalls, contains('destroy'));
        expect(trayCalls, contains('destroy'));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(session.close);
      await tester.runAsync(() => directory.delete(recursive: true));
    });
  }
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
        await tester.tap(find.byKey(const ValueKey('page-settings')));
        await tester.pumpAndSettle();
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
    expect(find.text('Waiting for runtime snapshot…'), findsOneWidget);
    connection.events.add(fixtures.snapshot());
    await tester.pump();
    expect(find.text('Waiting for runtime snapshot…'), findsNothing);
    expect(find.byKey(const Key('client-runtime-state')), findsOneWidget);
    expect(
      find.byKey(const Key('client-connect')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('client-ui-notifications')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('page-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-ui-notifications')), findsOneWidget);
    expect(find.byKey(const Key('client-connect')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('page-connection')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('client-connect')).hitTestable(),
      findsOneWidget,
    );
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
    await tester.tap(find.byKey(const ValueKey('page-settings')));
    await tester.pumpAndSettle();
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
