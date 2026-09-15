@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(360, 640), const Size(620, 460)]) {
    for (final locale in ClientLocale.values) {
      testWidgets(
        'unconfirmed quit remains accessible at 200% in $locale at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final directory = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('en-quit-layout-'),
          ))!;
          final session = ClientSession(
            journal: ClientIntentJournal(directory),
            open: () async => throw StateError('Runtime unavailable'),
          );
          var exits = 0;
          await tester.pumpWidget(
            ClientDesktopApp(
              session: session,
              desktopIntegration: false,
              initialLocale: locale,
              onExit: () async {
                exits++;
              },
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('page-settings')));
          await tester.pumpAndSettle();
          final quit = find.text(locale == ClientLocale.ru ? 'Выход' : 'Quit');
          await tester.ensureVisible(quit);
          await tester.tap(quit);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          final stay = find.text(
            locale == ClientLocale.ru ? 'Остаться' : 'Stay',
          );
          final exit = find.text(
            locale == ClientLocale.ru ? 'Закрыть интерфейс' : 'Exit UI',
          );
          expect(stay.hitTestable(), findsOneWidget);
          expect(exit.hitTestable(), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(exits, 0);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(session.close);
          await tester.runAsync(() => directory.delete(recursive: true));
        },
      );
    }
  }
}
