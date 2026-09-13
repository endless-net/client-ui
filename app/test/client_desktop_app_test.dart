import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
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
