@Tags(['short'])
library;

import 'dart:async';
import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
  for (final scenario in [
    'read failure',
    'write failure',
    'ordered writes',
    'quit waits',
    'quit after error',
  ]) {
    testWidgets('language persistence: $scenario', (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-language-app-'),
      ))!;
      var opens = 0;
      var exits = 0;
      final connection = scenario == 'quit waits'
          ? fixtures.FakeConnection()
          : null;
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async {
          opens++;
          if (connection != null) return connection;
          throw StateError('unavailable');
        },
      );
      final pending = Completer<void>();
      final writes = <ClientLocale>[];
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          desktopIntegration: false,
          localeReadFailed: scenario == 'read failure',
          saveLocale: (locale) async {
            writes.add(locale);
            if (scenario == 'write failure') {
              throw StateError('private storage path');
            }
            if (writes.length == 1 &&
                [
                  'ordered writes',
                  'quit waits',
                  'quit after error',
                ].contains(scenario)) {
              await pending.future;
            }
          },
          onExit: () async {
            exits++;
          },
        ),
      );
      await tester.pumpAndSettle();
      if (connection != null) {
        final snapshot = fixtures.snapshot();
        snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
        connection.events.add(snapshot);
        await tester.pumpAndSettle();
      }
      Future<void> choose(ClientLocale locale) async {
        tester
            .widget<DropdownButton<ClientLocale>>(
              find.byKey(const Key('client-ui-language')),
            )
            .onChanged!(locale);
        await tester.pumpAndSettle();
      }

      if (scenario == 'read failure') {
        expect(
          find.textContaining('could not be read or saved'),
          findsOneWidget,
        );
      }
      expect(
        writes,
        isEmpty,
      ); // Startup never rewrites a missing/corrupt preference.
      await choose(ClientLocale.ru);
      expect(writes, [ClientLocale.ru]);
      if (scenario == 'write failure') {
        expect(
          find.text(
            'Не удалось прочитать или сохранить язык. Текущий выбор действует в этом запуске.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('private storage path'), findsNothing);
      } else if (scenario == 'ordered writes') {
        await choose(ClientLocale.en);
        expect(writes, [ClientLocale.ru]);
        pending.completeError(StateError('old save failed'));
        await tester.pumpAndSettle();
        expect(writes, [ClientLocale.ru, ClientLocale.en]);
        expect(find.textContaining('could not be read or saved'), findsNothing);
      } else if (scenario.startsWith('quit ')) {
        await tester.tap(find.byKey(const ValueKey('page-settings')));
        await tester.pumpAndSettle();
        final oldChoice = tester
            .widget<DropdownButton<ClientLocale>>(
              find.byKey(const Key('client-ui-language')),
            )
            .onChanged!;
        late Future<void> quitting;
        await tester.runAsync(() async {
          final quit = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Выход'))
              .onPressed!;
          quitting = (quit as Future<void> Function())();
        });
        await tester.pumpAndSettle();
        if (scenario == 'quit after error') {
          await tester.tap(find.text('Закрыть интерфейс'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(AlertDialog), findsNothing);
        expect(exits, 0);
        oldChoice(ClientLocale.en);
        expect(
          tester
              .widget<DropdownButton<ClientLocale>>(
                find.byKey(const Key('client-ui-language')),
              )
              .onChanged,
          isNull,
        );
        expect(writes, [ClientLocale.ru]);
        pending.complete();
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => quitting.timeout(const Duration(seconds: 5)),
        );
        expect(exits, 1);
      } else {
        expect(find.textContaining('Не удалось прочитать'), findsNothing);
      }
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await session.close();
        await connection?.events.close();
        await directory.delete(recursive: true);
      });
    });
  }
}
