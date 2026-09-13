@Tags(['short'])
library;

import 'dart:async';
import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void hide(WidgetTester tester, {bool paused = false}) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  if (paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }
}

void resume(WidgetTester tester, {bool paused = false}) {
  if (paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  for (final paused in [false, true]) {
    testWidgets(
      'US-12 fresh snapshot after ${paused ? 'pause' : 'hidden'} without runtime mutation',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('en-resume-'),
        ))!;
        final first = fixtures.FakeConnection();
        final second = fixtures.FakeConnection();
        var opens = 0;
        final session = ClientSession(
          journal: ClientIntentJournal(directory),
          open: () async => ++opens == 1 ? first : second,
        );
        await tester.pumpWidget(
          ClientDesktopApp(session: session, desktopIntegration: false),
        );
        await tester.pumpAndSettle();
        first.events.add(fixtures.snapshot());
        await tester.pumpAndSettle();
        expect(session.state.link, ClientLinkState.ready);
        final oldEpoch = session.state.cacheEpoch;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(opens, 1); // Focus alone is not an interruption.
        hide(tester, paused: paused);
        expect(
          session.state.link,
          ClientLinkState.ready,
        ); // Tray retains its subscription.
        resume(tester, paused: paused);
        expect(session.state.snapshot, isNull); // Before any asynchronous work.
        expect(session.state.cacheEpoch, greaterThan(oldEpoch));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(opens, 2);
        expect(first.closed, isTrue);
        expect(session.state.link, ClientLinkState.awaitingSnapshot);
        second.events.add(
          fixtures.snapshot()..snapshot.status.accountId = 'fresh-account',
        );
        await tester.pumpAndSettle();
        expect(session.state.snapshot!.status.accountId, 'fresh-account');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(opens, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(session.close);
        hide(tester);
        resume(tester);
        expect(opens, 2); // Observer removed on dispose.
        await tester.runAsync(() => directory.delete(recursive: true));
      },
    );
  }

  testWidgets('resume while bootstrap is busy schedules one fresh connection', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('en-resume-busy-'),
    ))!;
    final opening = Completer<ClientConnection>();
    final first = fixtures.FakeConnection();
    final second = fixtures.FakeConnection();
    var opens = 0;
    final session = ClientSession(
      journal: ClientIntentJournal(directory),
      open: () => ++opens == 1 ? opening.future : Future.value(second),
    );
    await tester.pumpWidget(
      ClientDesktopApp(session: session, desktopIntegration: false),
    );
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      hide(tester);
      resume(tester);
    }
    expect(opens, 1);
    await tester.runAsync(() async {
      opening.complete(first);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(opens, 2);
    expect(first.closed, isTrue);
    expect(session.state.snapshot, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(session.close);
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  testWidgets(
    'failed resume clears old snapshot and does not retry or leak error',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-resume-fail-'),
      ))!;
      final first = fixtures.FakeConnection();
      var opens = 0;
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async {
          if (++opens == 1) return first;
          throw StateError('private endpoint');
        },
      );
      await tester.pumpWidget(
        ClientDesktopApp(session: session, desktopIntegration: false),
      );
      await tester.pumpAndSettle();
      first.events.add(fixtures.snapshot());
      await tester.pumpAndSettle();
      hide(tester);
      resume(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(session.state.snapshot, isNull);
      expect(session.state.link, ClientLinkState.unavailable);
      expect(find.textContaining('private endpoint'), findsNothing);
      expect(opens, 2);
      await tester.pumpAndSettle();
      expect(opens, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(session.close);
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}
